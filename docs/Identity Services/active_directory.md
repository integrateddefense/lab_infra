## IN PROGRESS

# Step 1) VM prep

Cloned the Windows Server 2022 Core template into VLAN21 (Protected-Services).

Gave it CPU/RAM/disk in Proxmox, but had to console in because no guest agent/cloud-init.

# Step 2) Local Configurations
## Networking
Used Get-NetAdapter + New-NetIPAddress to set a static IP, prefix, and gateway.

Set DNS to itself (10.0.21.10) plus an external fallback resolver.

Verified with Get-NetIPAddress and Resolve-DnsName.

```
Get-NetAdapter
Remove-NetIPAddress -InterfaceAlias "Ethernet" -Confirm:$false
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 10.0.21.10 -PrefixLength 24 -DefaultGateway 10.0.21.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses ("10.0.21.10","1.1.1.1")
Get-NetIPAddress -InterfaceAlias "Ethernet"
```

## WinRM HTTPS listener

Created a self-signed cert for the host FQDN.

```
# Make a cert with the right names
$fqdn = "<host fqdn>"
$cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME,$fqdn `
  -CertStoreLocation Cert:\LocalMachine\My
$thumb = $cert.Thumbprint
```

Added a WinRM HTTPS listener bound to that cert.

```
# Remove any existing HTTPS listener (ignore errors)
Remove-Item -Path WSMan:\Localhost\Listener\Listener* -Recurse -Force -ErrorAction SilentlyContinue `
  | Where-Object { $_.Keys -match 'Transport=HTTPS' }

# Create the HTTPS listener
New-Item -Path WSMan:\LocalHost\Listener `
  -Transport HTTPS -Address * -Hostname $fqdn -CertificateThumbprint $thumb
```

Locked WinRM service config (no Basic, no unencrypted).

```
# Lock service settings
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $false
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $false
Restart-Service WinRM
```

## Firewall

Since Server Core didn’t ship with an HTTPS rule, created a custom inbound rule for TCP/5986.

```
New-NetFirewallRule -Name "WINRM-HTTPS-In-TCP" `
  -DisplayName "Windows Remote Management (HTTPS-In)" `
  -Enabled True -Direction Inbound -Protocol TCP -LocalPort 5986 `
  -Action Allow
```

Checked QEMU guest agent was installed and set to Automatic.

Set NTP source and restarted w32time.

# Step 3) Connectivity testing
## Basic
Verified with Test-WSMan -UseSSL inside the guest.

```
# Verify
winrm enumerate winrm/config/Listener
Test-WSMan -ComputerName $fqdn -UseSSL
```

From the Mgmt Pi: confirmed TCP/5986 open with nc.
## Authentication

Installed pywinrm + requests-ntlm on the controller.

## Ansible Connectivity

```
ansible all -i '10.0.21.10,' -m win_ping --ask-pass \
  -e ansible_connection=winrm \
  -e ansible_winrm_transport=ntlm \
  -e ansible_winrm_scheme=https \
  -e ansible_port=5986 \
  -e ansible_winrm_server_cert_validation=ignore \
  -e ansible_user='.\\Administrator'
```
Pong indicates success.
