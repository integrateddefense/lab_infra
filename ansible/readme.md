# Ansible IaC Repository

## Directory Structure

ansible/
- tasks/
  - mgmt-pi/ - collects tasks specific to the management pi, with the hostname `mgmt-pi`
  - switch/ - collects tasks specific to the core switch, with the hostname `switch`
- group_vars/ - collects group-specific variables for the environment
- host_vars/ - collects host-specific variables for the environment
- inventory/ - collects the inventory files for the environment, which identify hosts and map them to groups
- run_* - wrapper playbooks for using group_ and host_vars correctly

## Naming Convention
The naming convention for this repository mirrors the folder structure of the tasks repository and the wrapper playbooks.

For example:
- The wrapper playbook that configures the core switch is called `run_switch_configure.yml`. Wrapper playbooks always begin with a key verb that describes what they do, generally `run`, followed by the system or group that the playbook targets (`switch` referring to the core switch), and the action being conducted (`configure` for the initial configuration).
- That trend mirrors through the directory structure - the tasks file is located at `tasks/switch/` with the filename `configure.yml`.