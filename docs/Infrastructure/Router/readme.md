# North–South Firewall (NSFW)

Occasionally referred to as the "external router".

## Purpose and Role

The Protectli Vault running pfSense serves as the north–south firewall, enforcing policy at the edge between the home-lab environment and the external network. Its mission is to:

- Shape egress (outbound) traffic per VLAN so that future SIEM analysis can surface noisy or exfiltrating clients.
- Ensure all inbound traffic terminates in the DMZ VLAN (30), never directly into service VLANs.
- Provide a clean default-deny boundary that can be tuned incrementally as detection and monitoring mature.

This design keeps the NSFW opinionated but coarse-grained. East–west traffic control and microsegmentation are delegated to the Proxmox vFW cluster inside the lab.

## Key Design Decisions

### Management Plane

The firewall is managed (via GUI or SSH) from the inside of the transit VLAN. There is no separate connection to the MGMT VLAN, ensuring adequate segmentation of the OOB segment and matching enterprise design paradigms.

SSH is restricted to the ansible automation user with scoped sudo privileges; no root login.

pfSense GUI is treated as read-only; all changes flow through Git → CI/CD → Ansible → pfSense.

### Interfaces and Routing

WAN is configured first, with “block private/bogons” disabled only if the upstream handoff is RFC1918.

Internal VLAN interfaces are defined for DMZ (30), Users (40), Services (20), Protected Services (21), and Management (99).

Default route points upstream via WAN; no additional static routes were required beyond this baseline for external access. Static routes traversing the transit VLAN to the internal VLANs were created.

### NAT

pfSense remains in Automatic Outbound NAT mode for simplicity.

All internal RFC1918 nets are translated to the WAN address automatically.

Inbound NAT (port forwards) is not configured until services are published via the DMZ. NAT reflection remains disabled; split-horizon DNS will be used internally.

### Firewall Rule Framework

Rule order and grouping are enforced with START/END separators and a cursor anchor to preserve YAML list order.

Egress-first focus: outbound HTTPS/DNS/NTP per VLAN, default-deny otherwise. More granular allowlists will follow once SIEM telemetry is available.

Inbound WAN: default deny; no publishes until DMZ services are stood up.

DMZ → Inside: no pinholes yet; reserved for future reverse-proxy to backend flows.

### Backups and Recovery

Config is pulled (config.xml) via Ansible fetch before any play modifies anything.

A restore path is documented: copy back a known-good config.xml and reboot (“nuclear option”).

## Mental Model

The NSFW is not a deeply stateful application firewall; it is a boundary shaper. Its job is to:

- Enforce the shape of flows (everything egresses WAN; everything inbound must land in DMZ).
- Provide observability hooks (logs with provenance) so the SIEM and detection stack can characterize traffic.
- Act as the incident brake pedal (nuclear block switch).

Fine-grained service policy belongs closer to the workloads (E–W vFW, SIEM rules, application configs). The NSFW simply guarantees that every flow crossing the edge is shaped, visible, and can be clamped instantly.
