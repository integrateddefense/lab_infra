# Default Domain Controllers Group Policy Object
This is the template GPO for the Integrated Defense Lab.

Object Name: Default Domain Controllers Policy
Targets:
- Read-Write Domain Controllers
- Read-Only Domain Controllers

The sysvol directory includes a 1:1 copy of the object as stored in sysvol.
The metadata.yml is a yml-formatted ansible variables file defining non-SYSVOL components of the object.

## Purpose
This GPO supplants the default "Default Domain Controllers Policy" GPO to apply domain specific settings.

Some example settings include:
- WinRM Configurations
- Scheduled Tasks to purge sensitive credentials

## Computer Settings
ScheduledTasks

## User Settings
None
