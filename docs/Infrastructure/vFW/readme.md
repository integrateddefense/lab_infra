# Virtual Firewall (vFW) Design Documentation

IN PROGRESS

## Purpose & Principles

Goal: Make east–west traffic enforceable, reproducible, and easy to evolve without host restarts.
Split of duties:

- vFW (Linux, nftables + keepalived) = inter-VLAN contracts (zone/subsystem granularity).
- SDN (OVS) = same-VLAN microsegmentation (component/host granularity); handled in a different epic and set of documentation

Posture: default-deny, fail-closed, policy-as-code, minimal blast radius.

HA: VRRP per VLAN with non-preemptive failover.

## Topology

vFW nodes: two AlmaLinux VMs, single trunk vNIC (eth0) with subinterfaces (eth0.{10,20,21,30,40}), plus mgmt vNIC (eth1) for OOB.

Gateways: VRRP VIP .1 on each VLAN (node IPs .2/.3); preemption off.

## Inter-VLAN Pathing (north/south & east/west)

Internal host → external: VLAN→vFW (VIP) → Transit VLAN → pfSense → WAN.

Return traffic: pfSense static routes for {99,20,21,30,40} pointing to Transit VIP.

pfSense mgmt: via Transit IP (no direct leg into MGMT VLAN for routing).

## Enforcement Model

vFW (nftables): small, auditable zone→zone “contracts.”

Per-VLAN ingress fan-out (iifname → fwd_vXX sub-chains)

Contracts like:

- Mgmt(99) → {20,21,30,40}: {22,443}
- Users(40) → DMZ(30): {80,443}
- Services(20) → Identity(21): Kerberos/LDAP/NTP/GC

Default drop with tagged logging (prefix per VLAN/chain).

SDN (OVS): component-level doors and same-VLAN isolation.

Examples: mgmt_pi → gitstrap:22 only; Users→gitlab:443; deny lateral by default.

When higher assurance is needed, we allow dual enforcement (coarse at vFW + precise at SDN) for crown-jewel flows.

## HA & Availability Choices

VRRP (keepalived): v3, unicast peerings, nopreempt, advert_int 1s, GARP tuning to refresh ARP quickly on failover.

Failure semantics: Stateful at vFW (conntrack) but no state sync—acceptable for lab; brief session resets on failover are fine.

Gateway mapping: VRID == VLAN ID for human-readable ops.

## Policy-as-Code Structure

nftables as files (no YAML-to-nft translation):

- baseline file defines table/hooks, per-VLAN sub-chains, sets, defaults.
- Small per-VLAN baseline files and optional subsystem packs using add rule … (no chain redefinitions).

Ansible role:

- Creates subinterfaces from a staged list; templates keepalived instances per VLAN; deploys nft packs; validates with nft -c and reload handlers.
- Sysctl baseline: redirect/ICMP hygiene, ip_forward=1, rp_filter=0.

## Routing & NAT Responsibilities

vFW: routing between internal VLANs + forwarding to Transit; no NAT.

pfSense: NAT at WAN, policy/rules on Transit to allow the path; static routes back via Transit VIP.

## Observability Hooks (lightweight, ready for sensors later)

Drop logs in nft with distinct prefixes (per VLAN/chain) for quick grep.

TAPs/mirrors reserved in SDN design; sensors to be added in a later epic.

## Why

Resilient & simple: explicit inter-VLAN chokepoint + per-VLAN VIPs with HA.

Composable: vFW rule count stays tiny; SDN carries frequent per-component changes.

Auditable: contracts read like the architecture diagram; file-per-pack diffs are tiny.
