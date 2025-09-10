# Router Documentation

This folder collects all of the documentation for configuring and managing the edge router.

In this environment we're using a Protectli Vault to provide the external routing and north-south firewall. We'll follow the below steps for the initial setup and configuration.

Step 1) Cable
Step 2) Manual Setup
Step 3) Ansible Configuration
Step 4) Ansible Hardening

# Step 1) Cable

This step is pretty self-explanatory - make sure the router is cabled. You should cable three ports:
- A data port that will handle traffic coming from the outside-in on your external VLAN
- A data port for out-of-band management
- A data port for connection to the ISP

If you're building this in the same order, be sure to update your switch configuration and cabling diagrams for the new connection if you missed it in the original design.

# Step 2) Manual Setup

This step focuses on all of the manual pieces you need to implement before you can configure the router automatically via ansible. 

# Step 3) Ansible Configuration

# Step 4) Ansible Hardening

TBD - will be implemented once the rest of the infrastructure has been stood up.