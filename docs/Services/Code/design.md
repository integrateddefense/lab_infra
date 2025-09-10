# IN PROGRESS

[Diagram](../../../diagrams/Subsystems/Code.pdf)

# Components

- Git (public and private repositories)
- TBD

## Git

### Purpose and Scope

- Provide a minimal, reliable, policy-enforcing source of truth for automation content during early bring-up:
- A place the Management Pi can push to and pull from, before workstations and larger tools exist.
- Server-side enforcement of “no secrets in Git.”
- A controlled path to publish a sanitized subset of content to the public repository.
- A clean hand-off to GitLab later without rearchitecting Source Code Management (SCM).

### Target Architecture (Ideal End State)

#### Center of gravity
GitLab is the primary hub where contributors push their work. GitLab runs over HTTPS (443) for both UI and Git operations (SSH optional). GitLab’s CI publishes public-safe content to GitHub over HTTPS (443) using an org-scoped token or GitHub App.

#### Hot backup & local ops
The Bootstrap Git service remains online in parallel as a bare Git over SSH (22) endpoint. GitLab push-mirrors (or CI-pushes) to this internal repo so that the Management Pi can continue to operate and recover against a local, low-dependency remote even if GitLab is unavailable.

#### Policy at boundaries
- Inbound to Bootstrap: a pre-receive hook rejects pushes that introduce sensitive paths or key material.
- Outbound to GitHub: GitLab CI applies an allow-list (playbooks/roles/docs only). Inventories, group/host vars, vaults, and keys are never published.

Most teams point everything at GitLab and call it a day. Here, we're specifically implementing a two-tiered approach to SCM: GitLab for collaboration + an internal, lightweight Git remote that is always present for operations and recovery. It trades a little complexity for resilience and a clearer separation between authoring (GitLab) and operating (Bootstrap + Pi).

### Service Shape

#### Bootstrap Git (aka gitstrap)

- Transport: SSH only; no web UI, no HTTP backend. The attack surface is limited to sshd + git.
- Account model: a dedicated git service user with git-shell as the login shell (permits Git upload/receive, denies interactive shells).
- Auth: key-only. The Management Pi and (later) GitLab each have their own deploy key. Keys are scoped to this service and rotated independently.
- Network exposure: reachable from the Management VLAN today and the GitLab host later. Broader east–west exposure is not required.

This “no-frills” shape aligns with the intent for the internal git remote: authoritative, small, and predictable.

#### GitLab

TBD

### Use Cases

Who can push where (steady state):
- Developers → GitLab (HTTPS/SSH): normal day-to-day.
- GitLab → Bootstrap (SSH): one-way mirror so Bootstrap stays current.
- Management Pi → Bootstrap (SSH): operations and recovery continue to work locally.
- GitLab → GitHub (HTTPS): via CI job that filters out non-public files.
- Management Pi → GitHub (HTTPS): via makefile that filters out non-public files.

Keys & identities: distinct keys for Pi and GitLab; no password auth; no shared credentials.

Enforcement: server-side policy on Bootstrap (hook) and pipeline policy in GitLab CI (allow-list). Users don’t have to remember special client-side rules; the servers enforce them.

### Repository Policy

Default branch: main. New clones from either remote land on main by default.

History safety: non-fast-forward updates to protected branches are discouraged (and can be disallowed) on the internal service; formal branch protections are applied in GitLab.

“No secrets in Git” (always on): the Bootstrap service’s pre-receive hook rejects pushes that add any of the following:
- group_vars/** and host_vars/**
- files or paths containing vaulted artifacts
- private key material (.key, .pem, .pfx, etc.)

Publication stance (always on): public repos contain only reusable content (playbooks, roles, and optionally docs). Inventories and environment-specific materials never appear in public.

### Publish Policy & Mechanics

Pre-GitLab (bootstrap phase): The Management Pi runs a make publish target that copies an allow-listed subset (playbooks/roles/docs) into a local clone of the public repo and pushes over HTTPS (443). This is a deliberate action with a dry-run option and defensive excludes—aligned with the diagram’s “public path is filtered.”

Post-GitLab (steady state): GitLab CI becomes the policy gateway:

On merge to main, a small job copies only allowed roots and pushes to GitHub.

The allow-list lives as code (shared with the Makefile), so the policy is uniform whether publishing is done by the Pi (early) or GitLab (later).

This ensures that publishing is explicit, filtered, and automated—and that inventories/vars never leave the private side.

### Key Differences vs. a Vanilla GitLab-Only Deployment

Two remotes by design. An internal Git remote exists in parallel with GitLab to support operations/recovery without depending on the app tier.

Server-enforced policies. A pre-receive hook on the internal service blocks secrets before they enter history; GitLab CI enforces a publish allow-list. Users don’t carry the burden of remembering special client rules.

Publish is a filter, not a mirror. Only playbooks/roles/docs are exported; inventories and environment-specific config never leave the private side.

No web stack on the internal service. The internal remote is SSH-only and intentionally spartan to minimize surface area and operational drift.