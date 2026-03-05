# GPO as Code

## Overview

This document summarizes a sustained attempt to implement Group Policy Objects (GPOs) as fully declarative Infrastructure-as-Code artifacts, with Git serving as the authoritative source of truth.

### Design Goals

- No GUI usage
- No manual edits
- Fully deterministic enforcement
- Extensible support for new policy types
- No per-policy “seed and mutate” hacks
- Clean Git → domain pipeline

The effort achieved partial success. It also surfaced structural constraints within the Windows GPO engine that prevent a pure “compile from files” declarative model using only supported APIs.

This write-up focuses on the technical journey and failure patterns encountered.

---

# The Core Friction

GPOs appear file-based, but they are not.

They consist of:

- SYSVOL file structures
- Active Directory metadata objects
- Client Side Extension (CSE) GUID registration
- Version counters
- Backup container semantics
- Link metadata
- Internal stamping and activation state

The working assumption at the start was:

> If we can generate the correct files and push them to SYSVOL, AD will recognize and process the policy.

That assumption proved false.

---

# Major Troubleshooting Storylines

## 1. The “SYSVOL Is Authoritative” Assumption

### Approach

- Generate complete GPO directory structure in Git
- Write directly to SYSVOL
- Use `Import-GPO` to align AD metadata

### Observed Behavior

- Existing settings updated correctly
- Version counters incremented
- GPO appeared structurally valid
- New policy types (new CSE classes) were silently ignored
- No activation of new extension types occurred

### Key Diagnostic Signal

The files were present and correct, but AD did not process new policy classes.

This established:

> SYSVOL is not the structural source of truth for policy activation.

---

## 2. The `backup.xml` Hypothesis

After discovering that file presence was insufficient, attention shifted to backup container metadata.

### Hypothesis

If `backup.xml` accurately reflects the new policy types, AD may activate them upon import.

### Approach

- Template `backup.xml`
- Manually adjust:
  - Extension GUID lists
  - Version counters
  - Policy halves
  - Stamping semantics

### Result

- Extremely fragile
- Behavior inconsistent across runs
- Minor misalignment caused silent failures
- Required undocumented internal knowledge
- Not safely extensible

### Key Realization

`backup.xml` is a manifest of state, not a compiler input.

AD does not derive structural activation purely from this file.

---

## 3. Import vs Restore

To isolate behavior differences:

### Import-GPO

- Applies settings to an existing GPO
- Assumes structural validity
- Does not reinitialize extension registration
- Does not “compile” from files

### Restore-GPO

- Replaces a GPO from a backup container
- Correctly handles versioning and stamping
- Requires fully valid backup structure

Neither command functions as a declarative compiler.

Both assume pre-existing structural correctness.

---

## 4. The CSE Activation Barrier

When introducing new policy types (e.g., Preferences → Local Users and Groups):

The following must align:

- Correct CSE GUID registration
- AD attributes reflecting activation
- Proper extension pair formatting
- Matching version counters
- Both policy halves enabled
- Correct stamping in AD-side attributes

Troubleshooting revealed:

- File-level changes alone do not activate CSEs
- AD metadata must reflect structural registration
- No supported API exposes low-level CSE activation directly

This was the structural wall.

---

## 5. GPMC COM Automation Limits

The GPMC COM model was evaluated as a potential structured authoring path.

It exposes:

- GPO creation
- Import / restore
- Linking
- Enable/disable halves
- Reporting

It does not expose:

- Arbitrary preference item creation
- Direct manipulation of extension lists
- Explicit CSE GUID registration
- Low-level structural activation

COM automation mirrors GUI workflows.

It does not function as a declarative compiler surface.

---

# What Actually Works

## Model 1 – Managed Lifecycle (Enterprise Pattern)

This model treats backup containers as compiled artifacts.

Process:

- Create or modify GPO via supported interfaces
- Use `Backup-GPO` to generate valid containers
- Store backup artifacts in Git
- Use `Import-GPO` or `Restore-GPO` for deployment

This preserves structural integrity and avoids internal activation issues.

---

## Model 2 – Hybrid Authority

Accept that AD is the structural authority.

Use IaC for:

- GPO creation
- Linking
- Permissions
- Drift detection
- Structural validation
- SYSVOL integrity checks

Use supported tools for policy authoring.

---

# Patterns Observed During Troubleshooting

- Presence of files ≠ activation of policy types
- Version counter increments ≠ structural recognition
- AD silently ignores structurally invalid CSE combinations
- `Import-GPO` does not recompile structure
- `Restore-GPO` assumes valid compiled backup
- Some policy types are fully API-addressable; others are not
- GPO state is distributed between file system and directory metadata

The friction is architectural, not operational.

---

# Final Architectural Position

A fully native, Linux-style declarative “GPO as Code” model is not feasible using supported interfaces.

Achieving full parity would require:

- Undocumented CSE stamping manipulation
- Per-policy seeding hacks
- Reverse-engineering internal activation semantics
- Or writing a custom GPO compiler

None of these are stable, portable, or enterprise-safe.

---

# Practical Outcome

- Use supported interfaces for structural creation
- Treat backup containers as compiled artifacts
- Maintain Git as specification authority
- Implement drift detection where full enforcement is not possible
- Avoid direct SYSVOL mutation for structural changes

---

# Lessons Learned

- GPO is not a flat configuration object
- SYSVOL is not authoritative
- `backup.xml` is not a source-of-truth compiler input
- Import operations are not compilation passes
- Activation logic is stateful and directory-backed
- Not all policy types are equally automatable

Understanding these limits is more valuable than fighting them.

---

# Reflection

The effort exposed the internal coupling between:

- AD metadata
- SYSVOL structure
- CSE registration
- Backup container semantics

The Windows GPO engine is stateful and activation-driven.

Declarative Git authority can coexist with it — but it cannot fully replace it.

Recognizing that boundary prevents fragile architectures and long-term maintenance debt.
