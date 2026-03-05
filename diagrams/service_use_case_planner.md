| Service Area       | Component            | Keep? | Realism    | Load   | Deployment Notes                                     |
|--------------------|----------------------|-------|------------|--------|------------------------------------------------------|
| **Core Infrastructure** | Proxmox               | ✅     | Production | High   | Clustered, main hypervisor layer                    |
|                    | AD/DNS/DHCP/NTP       | ✅     | Production | Low    | Windows Server-based, VLAN-aware                    |

| **Security Stack** | Splunk (Dev License)  | ✅     | Production | Medium–High | Primary SIEM with Elastic mirror                    |
|                    | Elastic Stack         | ✅     | Production | Medium | Translates Splunk detections                        |
|                    | Zeek/Suricata         | ✅     | Production | Medium | Custom sensor VM builds                             |
|                    | Vulnerability Scanning| ✅     | Production | Medium | Tool TBD (e.g. OpenVAS)                             |
|                    | OpenRMF (Compliance)  | ✅     | Production | Medium | Demonstrate SIEM-feedback loop                      |
|                    | Osquery / Falco       | ✅     | Security   | Light  | Osquery in Phase 1, Falco optional Phase 2          |

| **Automation & Ops** | Git (Internal)        | ✅     | Production | High   | Central to GitOps + CaC                             |
|                    | Ansible               | ✅     | Production | Low    | CLI only for now, Tower deferred                    |
|                    | ArgoCD / GitOps       | ✅     | Production | High   | Core automation + K8s syncing                       |
|                    | Prometheus / Grafana  | 🟡     | Security   | Medium | Add only if SIEM can't cover observability needs    |
|                    | Central Logging       | ✅     | Production | High   | Syslog-ng, WEC, SIEM-forwarding                     |

| **App & Dev Stack** | Kubernetes            | ✅     | Production | Medium | 1–3 node cluster, for deployment tests              |
|                    | Container Registry    | 🟡     | Production | Medium | Add Harbor or GitLab registry later                 |
|                    | GitLab / Jenkins      | ✅     | Production | Medium | CI/CD core; may consolidate tools                   |
|                    | Sample App Stacks     | 🟡     | Production | Light  | Ghost, WordPress, Flask as test cases              |
