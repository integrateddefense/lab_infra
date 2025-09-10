# Compute Nodes

This document covers the manual steps necessary to instantiate the compute nodes, including iDRAC and ProxMox installation.

We'll follow the below high-level steps:
1) Design
2) Power and Data Cabling
3) iDRAC Configuration
4) Manual ProxMox Installation
5) Cluster Configuration

# Step 1) Design

This is probably the most important step to get right if you don't want to have to do a bunch of recabling later on.

Figure out what you've got, where you'd like to it to go, and make sure that you have all of the materials you need.

Pay particular attention to the following considerations:
- Does your hardware have dedicated iDRAC ports? If so, do you need (and have) a license to use it?
  - If not, don't cable the dedicated iDRAC, and make sure you carve out a specific NIC to use for the iDRAC functionality.
  - In either case, make sure the associated switch ports are assigned to your management VLAN.
- Identify a specific NIC to serve as your proxmox management interface.
  - This isn't strictly necessary on all hypervisors; ESXi in particular doesn't need it.
  - Make sure the associated switch ports are also assigned to your management VLAN.

# Step 2) Power and Data Cabling

Self explanatory - make sure everything is powered and cabled in line with your design.

# Step 3) iDRAC Configuration

This step will vary greatly depending on your hardware and BIOS, but generally follows the same pattern.
1) Boot your hardware with a KVM attached
2) Interrupt the normal boot cycle to enter the BIOS configuration options. This could look like hitting F11 or F12, or booting into what some older Dell hardware calls the Lifecycle Controller
3) Once in the configuration menu, look for networking settings or iDRAC settings, and follow the prompts to configure it.
- This is where it's important to know if you have (and can use) a dedicated iDRAC, or if you have to dedicate one of your regular NICs.
4) Make sure you save the config and reboot when you're done.

# Step 4) Manual ProxMox Installation

This step is self-explanatory - just follow the prompts and you're good to go.

Make sure you select the right interface for your management interface as well; this is different from the iDRAC interface, but important for making sure you can access the management interface.

# Step 5) Ansible Configuration

Now that you have proxmox installed and you can access it via SSH, everything else can be done via ansible.