# Setting up the Switch

This document describes the manual steps needed to setup the core switch for the lab environment.
It includes the following major steps:
1) Setting up the management pi for console access to the switch
2) Prep and Setup
3) Configure the switch for SSH-based management via Ansible
4) Write the functional configuration playbook
5) Write the security configuration playbook

See [Upgrade](upgrade.md) for additional details on how to upgrade the iOS on the switch.

# Step 1) Enable console access via the management pi

First and foremost - make sure you have a serial terminal softare installed. Common examples include `screen` and `minicom` - if you used the init script in this repository, then you should have already installed `minicom`.

Next, identify the serial device that you're using with the following command:
```
dmesg | grep ttyUSB
```

You should get output that includes something like `/dev/ttyUSB<some number>`. The command searches your system logs to find a message that has to do with the `ttyUSB` device class, which (ideally) will only pull up the log message indicating that a serial controller was attached, and which device location it's available at.

My message looked like this:
```
[<relative timestamp>] usb 1-1.1.3: FTDI USB Serial Device Converter now attached to ttyUSB<number>
```

The `<number>` in the output is the key value we're looking for. We need to pass that value to the serial terminal software so that we can connect to the switch.

If you're using minicom, your command will look like this:
```
sudo minicom -D /dev/ttyUSB<the number you saw> -b 9600
```
-D tells minicom to use the specific device to connect, and -b tells minicom the bitrate to use for the serial connection. 9600 is generally the default, but it's an important setting. Also known as the baud rate, if this number is wrong between your terminal (the management pi and the serial terminal software) and the device (the switch), you'll see garbled data, complete communication failure, system instability, or even buffer overflows. This is because serial communications rely on precise timing to synchronize data transfer: each end of the connection needs to send and receive bits at the same rate.

For the hardware-inclined folks reading this, you can check out [this article](https://www.botasys.com/post/baud-rate-guide) for more details on the baud rate, how to calculate it, how to select or evaluate a baud rate, troubleshooting steps, and best practices.

# Step 2) Prep and Setup

This step is pretty self-explanatory, but still important. Before you get too deep into the configurations and cabling, make sure you check the following:
- Do you have a USB to Serial (aka, USB-to-DB9) cable? Is it plugged into the console port on your switch?
- Does the switch have power? Does it POST correctly?

Once your switch is powered on and running, go back to your serial terminal and make sure you get a prompt for your switch.

Note: If you get a prompt that looks like `root@:RE:0%`, that means your switch didn't finish booting into the CLI. Not a problem, but you need to issue the `cli` command to boot the Junos CLI, and then you'll see a more typical switch prompt.

# 3) Configure the switch for SSH-based management via Ansible

This step is completely manual - go ahead and console into the switch using the command from step 1 above and issue the following commands.

```
configure
# Enters the JUNOS configuration prompt
edit system
# Enters the configuration block for the system
set host-name switch
# Sets the hostname of the device to switch (default is Amnesiac)
set root-authentication no-public-keys
# Disables key-based authentication for the root user
set root-authentication plain-text-password
# prompts for a password to set for the root user
set login user ansible authentication plain-text-password
# creates the user 'ansible' and prompts for a password to set
set login user ansible class super-user
# Sets the permissions for the ansible user, giving it complete access
set services ssh
# enables the default SSH configuration
set services ssh protocol-version v2
# forces the use of SSHv2
set services ssh root-login deny
# Prevents the root user from being used for SSH logins
set services netconf ssh
# Allows you to use NETCONF over SSH to configure the switch (how ansible interacts with Juniper)
up
# moves one layer out of the current edit context, in this case back to the highest level
edit vlans
# Move into the VLAN hierarchy
set mgmt vlan-id <ID>
# creates a VLAN named 'mgmt' tagged with the provided VLAN ID
set mgmt description "OOB Management"
# Sets the VLAN description to "OOB Management"
set mgmt l3-interface vlan.<ID>
# Sets the VLAN to us the layer3 interface called "irb.<your vlan ID>" which we create next
up
# return to the base hierarchy
edit interfaces vlan unit 99 family inet
# enter the interfaces hierarchy and edit the inet family of the IRB unit associated with the VLAN you just created
## same is doing:
### edit interfaces
### edit irb.<ID>
### edit family
### edit inet
set address <switch management IP>/24
# Sets the IP address for the switch on that interface; this is NOT the network or gateway
exit
# Back out to the root of the hierarchy
edit interfaces <interface id>
# Enters the edit hierarchy for the selected interface; this should match your management pi
set description "<interface description>"
# Sets the description
edit unit 0 family ethernet-switching
# Enters the hierarchy for ethernet switching on the selected port
set port-mode access vlan members mgmt
# Sets the port to access mode for management VLAN
exit
commit
# commits all staged changes to the running config; alternatively run "commit check" and you'll get a syntax check of your planned config without making any changes
```

Once you're done, make sure you set an IP address on the management Pi within the same subnet as your management VLAN so you can access it over SSH. I recommend using `sudo nmtui` to set the address on your Pi - my default installation didn't have some of the usual files in /etc/network/ that I look for on other distributions, and nmtui makes sure that the configurations get in the right spot

To test your connection, try pinging the ip address you set on the VLAN interface, and try to SSH to that same IP address using the username and password you set.
Note: If you're on older hardware, you may have to explicitly allow deprecated key exchange, key types, and cipher modes. This is okay in a home lab, but is a serious risk for any production or public-facing components.

# 4) Write the functional configuration playbook

For the first play, create tasks that affirm the configurations we placed in manually. This helps enforce idempotency - a key characteristic of ansible - and helps stabilize the configuration so that if I decide to change something in those configs later I can do it via Ansible and the existing GitOps pipelines.

Check out the current [playbook](../../ansible/playbooks/switch/configure_switch.yml) for the full functional setup.

# 5) Write the security configuration playbook

TBD - will be completed once the full infrastructure is in place
