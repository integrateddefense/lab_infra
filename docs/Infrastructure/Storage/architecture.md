
# Storage Ecosystem Architecture Decision Record

IN PROGRESS

**Subsystem:** sn | **Version:** v0.1 (TBD) | **Scope:** Storage Ecosystem Architectural Decisions

---

## Overview

This document records the architectural decisions made during the design and MVP implementation of the Storage Ecosystem. Decisions are grouped by domain. Each entry records the decision, the alternatives considered, and the rationale. Where a decision represents a known tradeoff or accepted limitation, that is noted explicitly.

---

## Storage Platform

### End-State Platform: TrueNAS SCALE Baremetal on Dedicated PowerEdge

**Decision:** The full solution will run TrueNAS SCALE on a dedicated Dell PowerEdge as a baremetal storage appliance.

**Alternatives considered:**

| Option | Description | Rejected Reason |
| --- | --- | --- |
| NetApp FAS/AFF | Industry-standard enterprise NAS | License tied to controller serial number — used hardware requires separate ONTAP license purchase (~$45K). High cost for lab use. |
| Dell PowerStore | Full-featured block/file/object array with first-party CSI driver | Higher cost than PowerVault. PowerStore CSI is the stronger enterprise story but cost prohibitive for lab. |
| Dell PowerVault ME5 | Block-only SAN array, no license requirement | Block-only — no native NFS or S3. Would require supplemental solution for file and object primitives. |
| Pure Storage FlashArray | Strong K8s-native storage, Evergreen support model | No free lab tier. Essentially no used market. Entry price $50K+. |
| Ceph via Rook | K8s-native converged storage | Minimum 3 OSD nodes — incompatible with 2-node R720 topology without compromising bootstrap node role. Operationally heavy ongoing management cost. |
| TrueNAS VM (MVP only) | VM on existing Proxmox cluster | Correct for MVP. Not the end state — ZFS on virtualized storage undermines integrity guarantees. |

**Rationale:** Dell PowerEdge hardware provides enterprise administration reps (iDRAC, RAID, drive management) while TrueNAS SCALE provides a production-grade open source storage OS with no license cost. The combination is operationally honest — enterprise hardware, fully managed software layer. Used PowerEdge hardware is available at reasonable refurb prices and 30U of available rack space accommodates it. TrueNAS SCALE is deployed commercially by iXsystems on their own appliances, confirming the architecture is production-grade.

**Hardware selection** is deferred to a future epic. The MVP VM bridges to the end state without blocking K8s.

---

### CSI Driver: democratic-csi (Permanent)

**Decision:** democratic-csi is the permanent K8s CSI driver. It is not a stepping stone to a vendor driver.

**Alternatives considered:**

| Option | Rejected Reason |
| --- | --- |
| Longhorn | Explicitly rejected. Migration from Longhorn to democratic-csi would impose an unacceptable migration tax on existing PVCs. No interim solutions by design principle. |
| NetApp Trident | Correct driver for NetApp arrays. Not applicable given platform decision. |
| Dell PowerStore CSI / Container Storage Modules | Correct driver for PowerStore. Not applicable given platform decision. |

**Rationale:** democratic-csi supports TrueNAS natively for iSCSI, NFS, and S3 via the TrueNAS API. It is the standard community driver for TrueNAS + K8s integrations. Selecting it as the permanent driver eliminates migration risk. The "no interim solutions" principle established during this decision applies across the architecture — a stepping-stone CSI driver creates migration tax that is treated as unacceptable design debt.

---

### Storage Architecture: Disaggregated

**Decision:** Storage is a separate dedicated system from compute. K8s and Proxmox consume storage over the network from TrueNAS.

**Alternatives considered:**

| Option | Rejected Reason |
| --- | --- |
| Converged (Ceph/Rook on K8s nodes) | Requires 3+ OSD nodes. Operational complexity. Failure domain overlap between compute and storage. |
| Local storage only | No persistent volumes for K8s stateful workloads. No shared storage for scheduleable VMs. |

**Rationale:** Disaggregated storage maintains clean separation of concerns and independent failure domains. A storage outage does not affect compute scheduling for VMs on local storage. Enterprise environments treat storage as a separate infrastructure layer — this decision mirrors that model.

---

## Network Architecture

### Storage VLAN Isolation Model

**Decision:** The storage VLAN (VLAN 50) is a flat L2 segment with no default gateway and no EWFW presence. Security is enforced by the absence of routing infrastructure.

**Rationale:** iSCSI is designed to run on a dedicated L2 segment. Routing iSCSI traffic through a firewall adds latency and overhead to every disk I/O operation and introduces a routing path that creates unnecessary attack surface. The correct security model for iSCSI is to make the segment unreachable by design — no gateway means no route injection, no inter-VLAN traversal, no firewall rules to misconfigure. This is the universal vendor recommendation (Dell, VMware, NetApp) and is distinct from compensating with firewall rules.

**Implication:** Any host that requires iSCSI access must be physically or virtually dual-homed onto the storage VLAN. Hosts that are not dual-homed cannot reach iSCSI targets — by design, not by policy.

---

### TrueNAS Dual-Homed Network Model

**Decision:** TrueNAS is dual-homed with dedicated interfaces on two VLANs serving different protocol sets.

| Interface | VLAN | Protocols |
| --- | --- | --- |
| NIC 1 | Services (VLAN 20) | NFS, SMB, S3 (future), AD integration, management UI |
| NIC 2 | Storage (VLAN 50) | iSCSI only |

**Rationale:** iSCSI must remain on the isolated L2 segment. File and object protocols (NFS, SMB, S3) are routable and must be reachable by consumers on other VLANs via normal inter-VLAN routing through the EWFW. A single interface cannot satisfy both requirements. Dual-homing is the standard pattern for storage appliances serving multiple protocol tiers.

**DMZ hosts never appear on the storage VLAN.** A DMZ host on the storage VLAN would have L2 adjacency to internal compute infrastructure, bypassing the EWFW entirely. DMZ persistent storage needs are served via local VM disk or routed NFS/S3 through the EWFW.

---

### iSCSI Dual-Homed Consumer Requirement

**Decision:** Any host consuming iSCSI must be dual-homed — one IP on its service VLAN, one IP on the storage VLAN.

**Consumers:** Proxmox hosts, K8s nodes, database servers.

**Non-consumers:** Client machines, DMZ hosts, any host that does not require block storage.

**Rationale:** iSCSI consumers need a direct L2 path to TrueNAS's storage VLAN interface. There is no routing path onto the storage VLAN by design. Dual-homing is the accepted enterprise standard confirmed across Dell, VMware, and NetApp implementation guides.

---

## Protocol Decisions

### NFS Version: NFSv4 Only

**Decision:** NFSv4 only. Port 111 (portmapper, NFSv3 requirement) is not opened.

**Rationale:** No legacy consumers exist in the environment that require NFSv3. NFSv4 requires only TCP/2049, simplifying firewall rules and reducing attack surface. NFSv3 can be re-enabled if a specific use case requires it.

---

### File Sharing: SMB Single-Protocol

**Decision:** The general-purpose file share is SMB only. No dual-protocol NFS/SMB share is implemented.

**Alternatives considered:**

| Option | Rejected Reason |
| --- | --- |
| Dual-protocol NFS+SMB | Requires POSIX-to-ACL permission mapping. Added complexity. No Linux workstation use case to justify it. |
| NFS only | Windows clients cannot map NFS shares natively without additional software. |

**Rationale:** No Linux workstation or Linux server use case requires persistent access to a general-purpose file share. Linux infrastructure nodes communicate via Ansible or S3. Windows clients use SMB natively. File transfers for Linux servers are handled via Ansible templates or S3. Dual-protocol complexity is not justified without a concrete use case.

---

### iSCSI Security: No Protocol-Level Signing

**Decision:** CHAP authentication is not implemented. Network isolation and IQN whitelisting are the compensating controls.

**Rationale:** iSCSI has no modern equivalent to SMB signing. CHAP is the only native iSCSI authentication mechanism and is considered weak — it provides minimal additional protection when the threat model is already addressed by network controls. The compensating controls are:

1. Storage VLAN has no default gateway — unauthorized hosts cannot reach iSCSI targets by routing
2. Only explicitly dual-homed hosts can be on the storage VLAN — controlled via Proxmox bridge and core switch VLAN trunk configuration
3. IQN whitelisting on TrueNAS targets — only authorized initiators can connect even if they reach the portal

These three layers together provide a stronger security posture than CHAP would add. iSCSI over IPsec would provide encryption and mutual authentication at the network layer but introduces meaningful complexity and computational overhead not justified by the current compliance requirements.

---

### S3: Deferred to Kubernetes Epic

**Decision:** S3 object storage is not implemented as a TrueNAS-native service. It is deferred to the Kubernetes epic and will run as a containerized workload backed by a TrueNAS PVC.

**Context:** MinIO Community Edition stripped LDAP, user administration, and most admin features in early 2025. Docker image publication ceased in October 2025. MinIO Enterprise (AIStor) starts at ~$96,000 annually. SeaweedFS and RustFS are the primary community-recommended replacements.

**Rationale:** S3 is an application-layer service, not a storage primitive. Running it as a K8s workload is architecturally cleaner — TrueNAS provides the underlying block/file storage, K8s manages the service lifecycle. The `s3` dataset is created and reserved on TrueNAS during the MVP build. S3 tooling selection and deployment is a K8s epic deliverable.

---

## VM Classification

### Locked vs Scheduleable VMs

**Decision:** VMs are classified along two independent axes: compute pinning and storage dependency.

| Axis | Locked | Scheduleable |
| --- | --- | --- |
| Compute | Pinned to specific node. Survives loss of other nodes. | Can migrate across nodes. Requires HA-compatible configuration. |
| Storage | Local storage. Survives storage outages. | Networked storage (TrueNAS). Freezes or crashes if TrueNAS is unavailable. |

**Key principle:** Scheduleable VMs implicitly require networked storage to be scheduleable — local storage cannot follow a VM across nodes. Committing a VM to the scheduleable bucket commits it to TrueNAS dependency.

**Examples:**

| VM | Classification | Rationale |
| --- | --- | --- |
| Domain Controllers | Locked + Local | Identity infrastructure must survive storage outages |
| vFW (EWFW) | Locked + Local | Network infrastructure must survive storage outages |
| GitLab | Scheduleable + Networked | Survives compute node loss; acceptable to go down during storage outage |
| Splunk | Scheduleable + Networked | Same rationale |
| K8s control plane | Locked + Local | etcd and control plane must survive storage outages |

**Implication for graceful degradation:** Anything in the scheduleable bucket goes down simultaneously during a TrueNAS outage. The scheduleable bucket must be designed so that no VM in it is required to recover TrueNAS itself — a circular dependency would make storage outage recovery impossible.

---

## Automation

### TrueNAS Configuration Model: Runbook (Not Playbook)

**Decision:** TrueNAS configuration is managed as a structured runbook, not an Ansible playbook. This is an accepted-branch pattern, not a gap.

**Context:** TrueNAS SCALE 25.x replaced the REST API with JSON-RPC 2.0 over WebSocket. `ansible.builtin.uri` is incompatible. The `arensb.truenas` community collection covers insufficient surface area and uses `midclt` or a Python WebSocket client under the hood. SSH is disabled on TrueNAS — `midclt` over SSH is not available.

**Alternatives considered:**

| Option | Rejected Reason |
| --- | --- |
| `ansible.builtin.uri` | Incompatible with JSON-RPC 2.0 over WebSocket |
| `arensb.truenas` collection | Insufficient coverage; would result in inconsistent mix of collection modules and raw fallbacks |
| `midclt` over SSH via `ansible.builtin.command` | SSH disabled by design. Per-invocation overhead significant. |
| Custom Ansible collection wrapping iXsystems Python WebSocket client | Correct long-term solution. Engineering time disproportionate to MVP need. Backlog. |

**Rationale:** TrueNAS is configured once at build time and rarely modified after. The operational value of idempotent repeated execution — the primary benefit of Ansible — is minimal for a mostly-static appliance. This follows the same accepted-branch pattern as GPO-as-code: where a system's architecture is fundamentally incompatible with declarative automation, a well-documented runbook is the correct answer. Full IaC coverage remains a backlog item.

---

### TrueNAS Admin Access: Local Break-Glass Only

**Decision:** TrueNAS admin access uses a single local break-glass account (`truenas_admin`). No personal admin accounts. No AD-backed admin privileges.

**Context:** TrueNAS SCALE 25.x does not support assigning admin privileges to AD groups or AD users. Admin privilege assignment is local-only via the Privileges system.

**Rationale:** This is consistent with the enterprise pattern for storage appliances — nobody has a personal account on a NetApp or Pure array in production. Admin access is mediated through privileged access management tooling (HashiCorp Vault in the future). The local break-glass account credential is stored in Ansible vault pending the Vault/PKI epic. `OPS-TNAS-Admins` and `OPS-Admins-Servers` AD groups have no valid role in TrueNAS and are not created for this subsystem.

---

## Open Decisions

| Decision | Status | Notes |
| --- | --- | --- |
| End-state hardware selection | Deferred | Separate future epic. 30U available in rack. Budget TBD. |
| S3 tooling selection | Deferred | K8s epic deliverable. SeaweedFS and RustFS are leading candidates. |
| TrueNAS IaC automation | Backlog | Requires custom Ansible collection wrapping iXsystems Python WebSocket client. |
| RAIDZ2 pool topology | Deferred | Full solution design. Dependent on drive count and hardware selection. |
| Tiered pool design (hot/warm/cold) | Deferred | Full solution design. |
| IT mode RAID controller flash | Deferred | Required for baremetal end state. R720 controller model TBD. |
| PKI-issued TLS cert for TrueNAS | Deferred | Vault/PKI epic dependency. Self-signed cert acceptable for MVP. |
