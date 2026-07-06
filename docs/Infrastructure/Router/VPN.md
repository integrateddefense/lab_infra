# WireGuard Remote Access — Runbook

This Runbook describes the process for setting up the VPN server and configuring a client. It combines some ansibilized components, as well as some manual components where first-class ansible modules were not available.

---

## Why WireGuard

- Minimal attack surface: silent by default. An unauthenticated probe against the listen port gets no response at all — no banner, no error, nothing to fingerprint.
- No PKI/certificate management overhead compared to IPsec or OpenVPN — just keypairs.
- Kernel-level implementation on pfSense (FreeBSD), low overhead, simple peer model.
- Single mechanism covers both site-to-site and road-warrior/remote-access use cases — the only difference is what's declared in a peer's Allowed IPs (a full remote subnet vs. a single `/32`).

## How It Works, Conceptually

- **Tunnel** = pfSense's own local side: its own keypair, its own interface address, listen port.
- **Peer** = a remote endpoint pfSense expects to hear from: the peer's public key (never its private key) and an Allowed IPs value that both authorizes and restricts what source IP that peer may claim.
- Address assignment is static and manual on both sides — WireGuard has no DHCP-equivalent. The client's own `Address` field is self-declared (like a static IP), and is **not** what enforces anything. The actual enforcement is pfSense's per-peer Allowed IPs: after decrypting a packet, pfSense checks the plaintext source IP against that peer's Allowed IPs and drops anything that doesn't match. Client and firewall configs must simply agree.
- Handshake authenticates the peer; Allowed IPs authorizes the address it's claiming. Two independent checks.

## Data Flow

```text
Internet
  → pfSense WAN (encrypted UDP/51820 accepted, decrypted by WG kernel module)
  → VLAN250 tunnel interface (10.0.250.0/24)
  → routed via VLAN10 (transit-DMZ)
  → EWFW (destination/service policy enforcement)
  → VLAN20 (Services/Core) — GitLab, ArgoCD, etc.
```

**Two-firewall responsibility split** (consistent with the rest of the architecture):

- **pfSense (NSFW)**: coarse admission only — "should this encrypted traffic be let in and decrypted at all." Also owns the WireGuard-interface rule tab, which is likewise kept broad/permissive — its job is just "let traffic that made it through the handshake continue downstream," not re-implement destination policy.
- **EWFW**: fine-grained destination policy — "given this is now legitimate decrypted traffic, what can it specifically reach." This is where VLAN20 scoping and per-service ports actually live.

VLAN20 is treated as an "on-prem equivalent access" trust tier — VPN clients get the same breadth of access a physically-present device on VLAN20 would get, scoped by service/port rather than by destination host. Any future sensitive-data workloads (HIPAA, CMMC, etc.) get their own dedicated VLAN/segment rather than a carve-out in this rule — segmentation-by-trust-tier, not ACL exceptions.

VLAN99 (MGMT) is explicitly excluded — no direct kubectl/admin access via VPN; that stays with the MGMT PI's automated pipeline.

---

## 1. Package Install (Ansible)

```yaml
- name: Install WireGuard package
  ansible.builtin.package:
    name: pfSense-pkg-WireGuard
    state: present
```

No reboot/restart required — confirmed on pfSense CE 2.8.0.

## 2. Enable WireGuard Service (Manual — one-time gotcha)

Package install does **not** start the service. Package install just makes tunnel creation possible — WireGuard won't actually run until this is done explicitly:

> VPN > WireGuard > Settings > check **Enable WireGuard** > Save

## 3. Tunnel Creation (Manual runbook — no pfsensible.core module covers WireGuard objects)

- VPN > WireGuard > Tunnels > Add Tunnel
- Description: cosmetic only, shows up in Tunnels list and peer-add dropdown — no downstream code consumes it
- Listen Port: **51820** (default kept deliberately — WireGuard's silence-by-default to unauthenticated probes makes port obscurity add little; a nonstandard port would only add a value to keep consistent across every client config for negligible benefit)
- Interface Keys: **Generate** via GUI — firewall owns its own private key for now (acceptable until Vault is in place; Ansible-generating it offers no security benefit while the key would still need to live somewhere before Vault exists)
- **Interface Addresses field**: only present for *unassigned* tunnels. Must note the tunnel's intended address here before moving to interface assignment — once assigned to an interface, this field disappears and the address must be re-entered at the interface level (see Step 4).

## 4. Interface Assignment (Ansible — `pfsensible.core.pfsense_interface`)

- Interfaces > Assignments > add `tun_wg0` as available network port (one-time manual step to expose it, then Ansible-managed going forward)
- **Critical config**: IPv4 Configuration Type must be set to **Static IPv4**, with the VPN clients subnet network address entered directly on the interface — not left as `None`. (The "address lives on the tunnel, leave interface as None" pattern described in generic WireGuard/pfSense documentation did **not** hold for this package/version — the interface itself needs the static address, or the connected route for the subnet never populates and traffic silently fails past the handshake stage.)

## 5. Peer Creation (Manual runbook — deliberate, not automated)

No pfsensible.core module exists for WireGuard peer objects; config lives under `installedpackages/wireguard` in `config.xml`, outside pfsensible's supported object types.

Per peer:

- Public key only (never the private key — generated client-side, public key copied out)
- Allowed IPs: `/32` per peer (e.g. `1.1.1.69/32`)
- Preshared Key: **skipped** — judgment call; PSK protects against a future break of the elliptic-curve handshake (quantum-resistance stopgap), which is disproportionate to this environment's realistic threat model (same reasoning applied to rejecting a hardware-token approach for key rotation)

## 6. Firewall Rules

### WAN (Ansible — `pfsense_rule`)

- Allow UDP/51820 inbound, direction `in`
- No floating rule needed — no cross-cutting concern; a normal interface-tab rule is sufficient

### WireGuard interface tab (Ansible — `pfsense_rule`)

- Broad allow: source `10.0.250.0/24`, destination any
- Deliberately permissive — this rule's only job is admission past the handshake; destination policy is EWFW's responsibility, not duplicated here

### EWFW (nft, via Ansible)

Standard rules from the DMZ Transit VLAN interface to the other VLAN interfaces as necessary, with an `ip saddr` filter to ensure the rule only applies to hosts in the VPN clients subnet, and no others.

```text
add rule inet filter fwd_v{{ vlans.transit.dmz.id }} ip saddr {{ vlans.vpn_clients.cidr }} oifname "{{ trunk_iface }}.{{ vlans.core.id }}" tcp dport { 443 } accept
```

Plus additional accepted ports for VLAN20, added incrementally as needs become concrete:

- `88 TCP/UDP` — Kerberos (future domain-joined client support)
- `53 UDP` — DNS (UDP only, not TCP, per existing Identity Services read-only data flow)
- `445 TCP` — SMB
- `123 UDP` — NTP

GitLab's SSH service (used by Ansible, not by end users) is intentionally **not** opened to VPN clients, same as it isn't opened to the on-prem User VLAN.

Rule ordering note: new accept rules must be inserted before the default-drop rule on the transit-DMZ chain, or they're never evaluated.

## 7. Client Setup (Manual, Windows — laptop + tower)

- Install official client: wireguard.com/install
- Add Tunnel > **Add empty tunnel** — generates keypair locally; private key never leaves the device
- Copy the generated **public key** only → into that peer's pfSense config (Step 5)

**`[Interface]`**

```text
PrivateKey = <generated locally, never shared>
Address = <reserved address for this specific client>/24
DNS = <RODC internal address>   # required for split-DNS; *.primary.ops.indef.space
                                  # will not resolve otherwise, and the tunnel will
                                  # appear to work while internal services silently fail
```

**`[Peer]`**

```text
PublicKey = <pfSense tunnel public key>
Endpoint = <public IP or DDNS>:51820
AllowedIPs = 10.0.0.0/8          # split tunnel — covers all sites/VLANs;
                                  # general internet traffic stays local
PersistentKeepalive = 25          # required for NAT traversal on travel networks
                                  # (hotel wifi, phone hotspot, etc.) — without it,
                                  # idle NAT mappings expire and pfSense loses the
                                  # ability to reach back to the client
```

## 8. Verification

- Confirm handshake timestamp populates on both client and pfSense side (Status > WireGuard) before assuming connectivity — "tunnel up" alone only means the interface/service is active, not that a handshake occurred.
- **Never test from the same LAN as pfSense** — hairpin NAT on the home router can produce false negatives/positives that look identical to real connectivity problems. Always test from a genuinely external network.
- Full dress rehearsal from an external network (phone hotspot) is a fixed pre-departure checkpoint, independent of Splunk/Caddy work pacing.

---

## Troubleshooting

| Symptom | Cause / Check |
| --- | --- |
| Tunnel shows "up," no actual connectivity | "Up" only reflects interface/service state, not handshake success. Check the Latest Handshake timestamp on both ends. |
| Handshake succeeds, RX/TX look fine, but internal hosts unreachable | Check for a default-deny on the WireGuard interface's own rule tab — pfSense auto-creates one for every newly assigned interface, separate from EWFW/nft rules. |
| Interface assigned, shows up, but "no IP assigned" | Tunnel's Interface Addresses field only applies to *unassigned* tunnels. Once assigned, the address must be set directly on the interface (Static IPv4), not left as None. |
| No connected route for `10.0.250.0/24` appears in pfSense's routing table | Same root cause as above — once the interface has its static IP, the connected route populates automatically. No static route should be needed for a directly-connected subnet. |
| Testing from the same LAN as pfSense gives inconsistent/confusing results | Hairpin NAT. Always verify from a genuinely external network (phone hotspot), not same-LAN. |
| EWFW rule appears correct but traffic still dropped | Check rule ordering — new accept rules must be inserted before the existing default-drop on that chain, not appended after. |
