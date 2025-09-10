# Setting up the Management Pi

## Components

- Raspberry Pi 4 - I used the [CanaKit Raspberry Pi 4 4GB Starter Kit Pro](https://www.amazon.com/dp/B07V5JTMV9?ref=ppx_yo2ov_dt_b_fed_asin_title&th=1)
  - This kit comes with a case, SD Card, power cord, power switch, heat sinks, fan, mini-HDMI cable, and even an adapter to plug your SD Card into another computer to update the OS. It's really everything you need to get started with a Raspberry Pi
- (Optional) USB-C to USB-A Data Cable - I used [this](https://www.amazon.com/dp/B01GGKYR2O?ref=ppx_yo2ov_dt_b_fed_asin_title&th=1) Amazon Basics cable rated for 10Gbps data transfer 
	-  A data-rated cable is useful for a number of things; namely allowing you to pass data from the Pi to a workstation powering it and back. However, I wasn't able to get it to work in my deployment, so this cable became optionAL. I still used it instead of the provided wall plug power supply, so that way everything can run through my tower and I didn't have to get under my desk to plug more stuff in.

## High Level Process:

1. Flash the OS
2. Cable and test
- Includes setting console font size
3. Download dependencies
4. Setup Ansible
5. Ansibilize the Management Node Setup

# Step 1) Flash the OS

The kit comes pre-installed with the latest version of Raspbian Buster - it's a fork of Debian 10 Buster specifically designed for Raspberry Pi. It's compatible with all Raspberry Pi models, but it's not the most recent version. Bullseye (the current legacy OS) and Bookworm (the current recommended OS) are both available for free on the [Raspberry Pi Site](https://www.raspberrypi.com/software/operating-systems/)

You'll also need the [Raspberry Pi Imager](https://downloads.raspberrypi.org/imager/imager_latest.exe) to install the OS.

Follow the prompts and accept the agreement to install the imager, launch it and you'll be able to select your Pi model (4), and your desired OS.

In my deployment, I went with a headless approach to preserve storage, so I scrolled down to "Raspberry Pi OS (other)" and selected the (at the time) top option - Raspberry Pi OS Lite (64-bit). It's really small - only 400Mb - and headless, which is perfect for a use case that doesn't require a graphical interface.

The last option is to choose storage - you should select the SD card that you inserted, and the one that you'll use to run the Pi.

I also recommend setting up a username and password via the OS Settings Customization options. You can also pre-set a hostname, enable SSH, and other things. I didn't enable SSH or Wi-Fi, as those weren't necessary under the console access model and my home lab only uses ethernet for admin functions.

It'll take a few minutes to download and install everything, and then let you know when it's done. Make sure you safely eject the SD card before removing it.

# Step 2) Cable and Test

Make sure that you insert the SD Card first, then plug in the power supply. Pi's don't have an external power button, so they will automatically power on as soon as they get power.
Give it 30-60 seconds to boot, and then once your keyboard and monitor are plugged in you should be presented with the login prompt.

If you're on a monitor with a high resolution (mine are all 27" class and 4K capable) you'll notice that the font size is super tiny.

Log in with the credentials you set in Pi Imager, and then run `sudo nano /etc/default/console-setup` to edit your console settings.

There are two lines here:
- FONTFACE: sets the font; you can find a list of default compatible fonts at `/usr/share/consolefonts`
- FONTSIZE: sets the size of the font; sizes are recorded in WidthxHeight format, where each number represents the number of pixels
	- So 16x32 (my setting), sets each character to be 16 pixels wide and 32 pixels tall. On a 1920/1080p monitor, that comes out to 120 characters across and 33 lines down before stuff starts going over the top.
	

# Step 3) Download dependencies

First and foremost, make sure you have the most up to date patches.
```
## Update local package repositories; ensures the local cache of application versions is up to date with the external repositories
sudo apt update
## Trigger an upgrade for any packages that have newer versions out There
sudo apt full-upgrade -y
```

Next, let's get some of the key dependencies for the management node
`sudo apt install -y python3-pip git curl gnupg software-properties-common`
- python3-pip: Package installer for Python3; used to install ansible later
- git: version control system
- curl: useful for fetching remote scripts, keys, or files; not explicitly necessary but good to have
- gnupg: GNU Privacy Guard; used for encryption, signing, and GPG key management, and required for verifying downloads using Ansible Vault with GPG
- software-properties-common: optional at this stage, but provides the `add-apt-repository` command and other related scripts that manage software sources

# Step 4) Install Ansible

This is a bit nuanced... the default Debian repos that ship with Raspberry Pi are generally several versions behind the most current version of ansible. As of July 2025, ansible-core was at 2.18, but apt could only find version 2.14 by default.

Fortunately, Ansible is python based, and python package installers like pip and pipx can get the cutting edge of ansible. This guide will focus on installing with pipx - a pip variation that installs every downloaded package into it's own virtual environment. Python virtual environments allow you to segment packages from the main system, supporting code portability and explicit identification of dependencies.

```
sudo apt install pipx
# Installs the pipx binaries
pipx ensurepath
# Ensures the pipx binaries are in your path
pipx install ansible-core
# Installs ansible into a new venv specifically for it
# Note: This specifically installs (and makes available) the core components of ansible, like ansible-playbook, ansible-vault, etc.
# It doesn't install any packages; but in keeping with the principle of least functionality, it allows us to manage the modules that we need to use more discreetly
ansible --version
# confirms ansible is installed and in your path
pipx inject ansible-core ncclient lxml jxmlease
# Injects dependencies that make working with Juniper switches easier
```

# Step 5) Create Initial Ansible Resources

Specifically, a folder structure, initialization play for the management node, and inventory. In this environment, we went with the wrapper playbook model

Folder Structure:
```
ansible/
└── run_init_mgmt_pi.yml
├── tasks/
    ├── mgmt-pi/
        └── init_mgmt_pi.yml
├── inventory/
    └──inventory.ini
├── group_vars/
├── host_vars/
```

inventory.ini
```
[local]
localhost ansible_connection=local
```

For the full YAMLs, refer to the git repo.
