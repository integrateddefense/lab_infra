# Overview

## IN PROGRESS

Active Directory (AD) provides the backbone of identity for the InDef lab. The design prioritizes infrastructure-as-code (IaC) enforcement, security by segmentation, and a clear split between read/write domain controllers (RWDCs) and read-only domain controllers (RODCs).

This split allows the environment to reflect real enterprise tradeoffs: protecting Tier-0 identities while still delivering directory services broadly across VLANs and sites.

It also provides a real-world implementation of the [Restricted Access Domain Controllers](radcs.yml) concept, providing tiered access to protected credentials without interrupting typical use cases that require access to writeable domain controllers (domain joins, password resets, dynamic DNS).

## RWDC and RODC Roles

RWDC (Read/Write Domain Controller)

- Hosts the authoritative copy of the directory.
- Lives only in the Protected Services VLAN (21).
- Used for must-write operations: domain joins, gMSA credential retrieval, schema changes, FSMO roles.
- Protected behind stricter firewall policies and site preferences.

RODCs (Read-Only Domain Controllers)

- Provide authentication, DNS, and GPO distribution across the Services VLAN (20) and DMZ VLAN (30).
- Do not store Tier-0 credentials (controlled via Password Replication Policy).
- Intercept most client operations, then refer must-writes back to the RWDC.
- Preferred in SRV records and site locator to minimize unnecessary RWDC exposure.

## Site Architecture

Each physical site generally includes three AD sites to further support the separation of roles and responsibilities among RODCs and RWDCs.

| Site | VLAN | DC Type | Purpose |
| Protected | 21 | RWDC | Anchor for Tier-0 operations, FSMO roles, and must-write use cases |
| Services | 20 | RODC | Direct integration with users and services for non-write use cases |
| DMZ | 30 | RODC | Provides read-only services to high-risk DMZ workloads |

The Protected AD Site in each location is generally hosted on the bootstrap node - a dedicated physical server that supports exclusively management and recovery functions.

## Mental Models Driving the Design

### OOB Management Principle

RWDCs are kept strictly behind VLAN boundaries. Admin access flows through the management Pi or designated jump hosts; normal services never talk directly to the RWDC.

### Restricted Access Domain Controllers (aka Least Privilege by Topology)

RODCs absorb almost all read traffic, providing additional “speed bumps” for attackers. Even if compromised, cached credentials are limited by PRP.

### IaC Enforcement

Every element (sites, subnets, OU tree, groups, PRP) is defined in Ansible and idempotently enforced. DC placement is checked via PowerShell and corrected only if drift is found.

### Operational Hygiene

Built-in high-privilege groups (Enterprise Admins, Schema Admins, GPO Creator Owners) are intentionally kept empty. Downstream groups is used instead, nested into built-in groups for permissions.

### Isolation of Trust Zones

DMZ identity needs are served by RODCs only, with no direct write path. This matches the “Integrated Defense” model: integration where needed, isolation where critical.
