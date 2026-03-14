# Storage Ecosystem — MVP Build Runbook

**Subsystem:** sn | **Component:** tnas | **Version:** v1.0 | **Scope:** MVP (VM)

---

## Overview

This runbook documents the manual build procedure for the TrueNAS SCALE MVP storage VM. The MVP validates iSCSI block and SMB file storage primitives to unblock the Kubernetes epic. S3 object storage is deferred to the Kubernetes epic and will be deployed as a containerized workload backed by a TrueNAS PVC.

The full solution will replace this VM with a dedicated PowerEdge running TrueNAS SCALE baremetal. This runbook applies to both the MVP and the full solution unless otherwise noted.

> **NOTE:** Automation via Ansible is intentionally deferred. TrueNAS SCALE 25.x uses a JSON-RPC 2.0 over WebSocket API that is incompatible with `ansible.builtin.uri`. No community collection covers sufficient surface area to justify a mixed automation model. Full IaC coverage is backlog pending a viable Ansible collection or custom WebSocket wrapper. This runbook serves as the configuration source of truth until that work is completed.

---

## Architecture

### VM Specification

> **NOTE:** VM creation uses the existing Proxmox VM creation playbook. The following spec is the input to that playbook.

| Setting | Value |
| --- | --- |
| CPU Type | `host` — required for container workloads; exposes full host CPU instruction set |
| Machine Type | q35 |
| BIOS | OVMF (UEFI) — Secure Boot disabled, Pre-Enroll Keys unchecked |
| Display | VirtIO |
| Sockets | 1 |
| Cores | 4 |
| Memory | 16 GB |
| OS Disk | 100 GB, SATA bus, Write Through cache |
| Data Disk | varies — see pool configuration; SCSI bus, VirtIO SCSI controller, Write Through cache, serial number required |
| NIC 1 | Services VLAN (VLAN 20) |
| NIC 2 | Storage VLAN (VLAN 50) |

**WARNING:** Virtual disks passed to TrueNAS must have a serial number set. Proxmox does not assign serial numbers to SCSI disks by default. Set via CLI:

> ``` shell
> qm set <vmid> --scsi1 <disk-config>,serial=tnas-data-01
> ```

**WARNING:** Write Through cache is required for ZFS integrity on virtual disks. Write Back (Unsafe) will undermine ZFS write guarantees and risks pool corruption on unclean shutdown.

---

### Network Configuration

> **NOTE:** VLAN configuration is limited to the core switch and Proxmox bridge interfaces. The storage VLAN has no default gateway and no EWFW presence — isolation is enforced by the absence of routing infrastructure, not firewall rules.

| VLAN | Purpose |
| --- | --- |
| VLAN 20 — Services | NFS, SMB, S3 (future), AD integration, management UI |
| VLAN 50 — Storage | iSCSI only. Flat L2 segment. No gateway. No EWFW. |
| VLAN 50 members | Core switch (trunk), Proxmox nodes (bridge), TrueNAS VM, K8s nodes (future), database servers (future) |

---

### Storage Primitives

| Primitive | Protocol | Notes |
| --- | --- | --- |
| iSCSI (block) | TCP/3260 — Storage VLAN only | Consumers: K8s nodes, database servers. Dual-homed required. |
| SMB (file) | TCP/445 — Services VLAN | Consumers: Windows workstations and servers via EWFW. |
| S3 (object) | TCP/443 — Services VLAN | Deferred to K8s epic. Containerized workload backed by TrueNAS PVC. |

---

### Data Flows

| ID | Port/Proto | Description | Controls |
| --- | --- | --- | --- |
| 1 | 3260/TCP | iSCSI block storage — Storage VLAN consumers only | Host-based firewall restricting access to ICMP and 3260/TCP on same L2 segment only. IQN whitelisting for explicitly authorized initiators. Note: no protocol-level signing equivalent exists for iSCSI. Network isolation and IQN whitelisting are the compensating controls. |
| 2 | 2049/TCP | NFS file shares — NFSv4 only | AD group-based access via Kerberos. IP-based export restrictions. sec=krb5 enforced at export level. |
| 3 | 445/TCP | SMB file shares — AD-backed | AD group-based access via Kerberos. SMB signing enforced (Transport Encryption: Required). SMB guest access disabled. |
| 4 | 443/TCP | S3 object storage (future) | MinIO IAM policies scoped per access key. TLS enforced. Deferred to K8s epic. |
| 5 | 389/TCP, 636/TCP | AD integration — domain join and Kerberos | Domain join uses narrowly scoped account with delegated Create Computer Objects permission on target OU only. Post-join auth via Kerberos computer account. No persistent bind account required. |

---

### Access Control Model

| Account/Group | Role |
| --- | --- |
| `truenas_admin` | Built-in local account. Break-glass use only. Strong unique password vaulted in Ansible vault pending Vault/PKI epic. Never used for day-to-day access. |
| `OPS-TNAS-Users` (AD group) | Controls SMB share access. Referenced in share and filesystem ACLs. Full control on the SMB share. |
| Ansible service account | Deferred — no automation in MVP. Create when viable Ansible collection or WebSocket wrapper is available. |

> **NOTE:** AD groups `OPS-TNAS-Admins` and `OPS-Admins-Servers` have no valid use in TrueNAS — admin privileges cannot be assigned to AD groups. These groups are not created for TrueNAS. `OPS-TNAS-Users` is the only AD group with a functional role.

---

## Step 1 — Web UI Hardening

Complete all items before proceeding to Step 2.

### System > General Settings > GUI

- SSL Certificate: `truenas_default` (self-signed). Replace with PKI-issued cert when Vault/PKI epic completes.
- Web Interface HTTPS Port: 443
- Web Interface HTTP → HTTPS Redirect: enabled
- Web Interface Address: bind to Services VLAN IP only — not `0.0.0.0`
- Usage collection and error reporting: disabled

> **NOTE:** IPv6 cannot be disabled via the TrueNAS GUI. Known gap — accepted risk, consistent with outstanding IPv6 disable item on the Windows baseline.

### System > General Settings > Localization

- Timezone: America/New_York (or local timezone)

### System > Advanced Settings > NTP Servers

- Add RWDC IP as NTP server with IBurst enabled
- IBurst is correct for NTP clients. Burst and Prefer are not required.
- Confirm UDP/123 is allowed outbound from TrueNAS services VLAN IP through EWFW before saving

### System > Network > Network Configuration

- Service Announcements (mDNS, NetBIOS, WSD): disabled — DNS handles discovery in a managed environment
- Outbound Network Activity: disabled — prevents automatic update checks and telemetry. Manual update process required.

### System > Services

- iSCSI: set to start automatically
- SMB: set to start automatically
- SSH: stopped and disabled — Proxmox console is the emergency shell access path
- All other services: confirm stopped and disabled unless explicitly required

---

## Step 2 — Active Directory Integration

> **WARNING:** Complete NTP configuration and confirm time sync before starting domain join. A time skew greater than 5 minutes will cause Kerberos pre-authentication failure.

### Pre-Join Checklist

- Confirm UDP/123 outbound from TrueNAS to RWDC is allowed through EWFW
- Confirm the following ports are allowed from TrueNAS services VLAN IP to RODC through EWFW: 53/TCP-UDP, 88/TCP-UDP, 389/TCP-UDP, 445/TCP, 636/TCP
- Confirm target OU exists: `OU=Storage,OU=Linux,OU=Servers,DC=ops,DC=indef,DC=space`
- Confirm domain join account is a member of the delegated join group with Create Computer Objects permission on target OU
- Confirm no stale computer object exists in target OU from a previous failed join attempt

### Directory Services > Active Directory

- Domain: `ops.indef.space`
- Account: domain join account (scoped to target OU only)
- Computer Account OU: `OU=Storage,OU=Linux,OU=Servers,DC=ops,DC=indef,DC=space`
- Kerberos Principal: select or leave default

**NOTE:** If the join fails with `WERR_NERR_DEFAULTJOINREQUIRED`, retry once before troubleshooting. A Kerberos ticket cache issue on the join account is the most common cause and a second attempt often succeeds. If it fails a second time, invalidate the join account ticket by toggling `SmartcardLogonRequired` on and off, then retry immediately:

> ```powershell
> Set-ADUser -Identity <joinaccount> -SmartcardLogonRequired $true
> Set-ADUser -Identity <joinaccount> -SmartcardLogonRequired $false
> ```

**NOTE:** After a hard VM reset or snapshot restore, the machine account password may fall out of sync with AD. Symptom: Directory Services status shows FAULTED with `SECRETS/MACHINE_PASSWORD/OPS` error. Fix: leave the domain, remove the stale computer object from AD, and rejoin. Retry the join twice if the first attempt shows a failure.

### Post-Join Validation

- Directory Services status shows healthy
- Confirm TrueNAS can resolve domain users and groups
- Confirm `OPS-TNAS-Users` group is visible for share ACL assignment

---

## Step 3 — Storage Pool Configuration

> **NOTE:** MVP uses a single ZFS pool with no redundancy. ZFS redundancy is handled at the hypervisor/RAID layer for the MVP VM. Full solution will use RAIDZ2 per pool. Hardware RAID controllers should be flashed to IT mode (passthrough) for the full baremetal solution so ZFS owns drives directly.

### Storage > Create Pool

- Pool name: `tank` (or site-appropriate name)
- Topology: Stripe (single disk, MVP only)
- Disk: select the data disk — confirm serial number matches `tnas-data-01` to avoid selecting the OS disk

### Create Datasets

Create three datasets within the pool. Share Type must be set correctly at creation — changing it later requires recreating the dataset.

| Dataset | Share Type | Purpose |
| --- | --- | --- |
| `iscsi` | Generic | iSCSI block storage backing |
| `smb` | SMB | SMB file share backing — sets correct ACL type for Windows permissions |
| `s3` | Generic | S3 object storage backing (future — deferred to K8s epic) |

> **NOTE:** Compression: lz4 (default). No deduplication. No quotas for MVP.

---

## Step 4 — iSCSI Configuration

### Shares > iSCSI > Portals

- Add portal bound to Storage VLAN IP only — not `0.0.0.0`
- Port: 3260

### Shares > iSCSI > Initiators

- For MVP: allow all initiators until K8s node IQNs are known
- For full solution: whitelist each authorized initiator IQN explicitly — K8s nodes and database servers only

> **NOTE:** IQN whitelisting is the primary access control for iSCSI. There is no protocol-level signing equivalent. Network isolation (L2 segment, no gateway, no EWFW) and IQN whitelisting together are the compensating controls documented in the architecture.

### Shares > iSCSI > Wizard

- Target name: set per naming convention — becomes part of the IQN
- Portal: select portal created above
- Initiator: select initiator group created above
- Extent — Device: select `iscsi` dataset
- Extent — Size: 25 GB (MVP) — adjust for full solution
- Extent — Sharing Platform: Modern OS (4K block size) — correct for Linux/K8s consumers

### Confirm iSCSI

- Services > iSCSI: confirm Running

---

## Step 5 — SMB Configuration

### Shares > Windows (SMB) > Add Share

- Path: select `smb` dataset
- Name: set share name (appears as `\\<truenas-ip>\<sharename>` to Windows clients)
- Purpose: Default share parameters
- Access Based Share Enumeration: enabled — users only see shares they have access to
- Transport Encryption Behavior: Required — enforces SMB signing/encryption. Incompatible with SMB1.
- Guest Account: leave as `nobody` — do not grant `nobody` permissions in ACLs
- Administrators Group: leave unset — no delegated share admin use case

### Share ACL

- `OPS-TNAS-Users`: Full Control
- Remove or restrict any default built-in entries as appropriate

### Filesystem ACL

- Set dataset owner and permissions to allow `OPS-TNAS-Users` full control at root
- Confirm permissions inherit to subdirectories and files

> **NOTE:** Both the Share ACL and the Filesystem ACL must permit access. Share ACL is the network gate; Filesystem ACL is the data gate. A user blocked at either layer will be denied.

### Confirm SMB

- Services > SMB: confirm Running

### EWFW Rules Required

- TCP/445 from Services VLAN to TrueNAS Services VLAN IP
- TCP/445 from Protected Services VLAN to TrueNAS Services VLAN IP
- TCP/445 from User VLAN to TrueNAS Services VLAN IP
- TCP/445 from Management VLAN to TrueNAS Services VLAN IP (admin/testing use)

---

## Step 6 — S3 Configuration (Deferred)

S3 object storage is deferred to the Kubernetes epic. The S3 service will run as a containerized workload on K8s, backed by a TrueNAS PVC pointing at the `s3` dataset created in Step 3.

**Rationale:** MinIO Community Edition stripped LDAP, user administration, and most admin features in early 2025 and ceased publishing Docker images in October 2025. S3 as a K8s workload is architecturally cleaner — TrueNAS provides the storage primitive, K8s manages the service lifecycle.

> **NOTE:** The `s3` dataset created in Step 3 is intentionally left idle until the K8s epic. Do not delete it.

---

## Step 7 — Validation

### iSCSI Validation

**TBD** — no iSCSI consumer available in MVP. Validate when K8s nodes are provisioned in the Kubernetes epic. At that point:

- Confirm K8s node can discover and mount the iSCSI target
- Confirm IQN appears in initiator log
- Update initiator group whitelist with confirmed IQN

### SMB Validation

- From a domain-joined Windows machine, map a network drive to `\\<truenas-ip>\<sharename>`
- Authenticate with a domain account that is a member of `OPS-TNAS-Users`
- Confirm read and write operations succeed
- Confirm a domain account NOT in `OPS-TNAS-Users` is denied access
- Confirm guest/anonymous access is denied

### AD Integration Validation

- Directory Services status: healthy
- Domain users and groups resolve correctly in share ACL editor
- `OPS-TNAS-Users` membership is enforced correctly on the SMB share

---

## Known Issues and Operational Notes

### Machine Account Password Sync

After a hard VM reset, snapshot restore, or CPU configuration change, TrueNAS may lose sync with its AD machine account password. Symptom: Directory Services shows FAULTED with `SECRETS/MACHINE_PASSWORD/OPS` error. Resolution: leave domain, remove computer object from AD, rejoin. Retry the join twice — a second attempt after an apparent failure often succeeds.

### Domain Join Ticket Cache

The domain join account's Kerberos ticket can become stale between join attempts. If the join fails with a credential error after a previous successful-looking attempt, invalidate the join account ticket before retrying:

```powershell
Set-ADUser -Identity <joinaccount> -SmartcardLogonRequired $true
Set-ADUser -Identity <joinaccount> -SmartcardLogonRequired $false
```

Then retry the join immediately.

### CPU Type Requirement for Containers

The TrueNAS VM CPU type must be set to `host` for any container workloads (Apps). The default Proxmox CPU type (`kvm64`/`qemu64`) does not expose x86-64-v2 instructions required by modern container images. This setting makes the VM non-portable across hosts with different CPU generations — acceptable for a single-site lab.

### Admin Access Limitation

TrueNAS SCALE 25.x does not support AD-backed admin privileges. Admin access is local only via the `truenas_admin` break-glass account. This is consistent with the enterprise pattern of not assigning personal accounts to storage appliances. Break-glass credential is stored in Ansible vault pending the Vault/PKI epic.

### IPv6

IPv6 cannot be disabled via the TrueNAS GUI. Accepted risk — consistent with the outstanding IPv6 disable item on the Windows baseline. Revisit in the Baselines epic.

### Automation Coverage

Full IaC automation is backlog. TrueNAS SCALE 25.x uses JSON-RPC 2.0 over WebSocket exclusively — REST endpoints are removed. `ansible.builtin.uri` is incompatible. No community collection covers sufficient surface area. A custom Ansible collection wrapping the iXsystems Python WebSocket client is the correct long-term solution and is tracked as a backlog item.

---

## Open Items for Full Solution

- Replace OS and data disk bus configuration: SATA for OS disk, SCSI for data disks
- Flash R720 RAID controller to IT mode (passthrough) — allows ZFS to own drives directly
- Implement RAIDZ2 pool topology per pool for the full baremetal solution
- Implement tiered pool design: hot (SSD), warm, cold
- Replace self-signed TLS cert with PKI-issued cert when Vault/PKI epic completes
- Update iSCSI initiator group with K8s node IQNs when Kubernetes epic provisions nodes
- Add democratic-csi API key generation to Kubernetes epic runbook
- Evaluate S3 container options for Kubernetes epic: SeaweedFS, RustFS as MinIO replacements
- Implement IaC automation when viable Ansible collection or WebSocket wrapper is available
