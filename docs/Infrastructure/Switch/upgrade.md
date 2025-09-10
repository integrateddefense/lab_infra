# Upgrading your Switch OS

Keeping your hardware up to date is important - newer versions provide security fixes, bug and stability fixes, and new features that can improve your architecture. Patch and upgrade management are also foundational aspects of good security hygiene, which makes it all the more frustrating when upgrades to critical infrastructure (like core switches) aren't intuitive.

A lot of times, security practitioners don't understand the ins-and-outs of actually applying patches and the availability risks involved, while administrators don't understand the confidentiality and integrity risks associated with delaying patching activities.

Network equipment can be especially fickle; when a workstation fails to come back up after a patch cycle, you can just switch out the workstation with another and get the user back up and running. But when network equipment fails the effects are far reaching, and not always as simple as replacing the hardware device.

So - let's jump into one way to upgrade your switch. As is standard for this repo, this guide is intended to be a helpful resource but is not all-inclusive, and is limited to only the hardware I have on hand.

We'll use the following high-level process:
Step 1) Identify the target image
Step 2) Boot the switch into ROMMON mode
Step 3) Transfer the image to the switch
Step 4) Set the boot variable and save the config
Step 5) Reboot and confirm the upgrade
Optional) Clean up old images

## Note
This process focuses on transferring the image via the serial connection. It is slow - about 7-10KB/s. There are other, faster, options out there, but this was the most secure approach as a solo-developer. It allows me to continue to deny access to these kinds of functions over the network - reducing the switch's attack surface.

## TBD

The rest of this document is under still under construction; the switch currently in use is already at it's highest support version without a Cisco contract, a feature that is DEFINITELY not needed for a home lab setup.