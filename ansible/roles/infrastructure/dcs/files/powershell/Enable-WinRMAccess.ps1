<#
@file Enable-WinRMAccess.ps1

@brief Idempotently enables WinRM access for a specified account or group

@note designed to run ONCE, not as part of a loop in ansible
@note if looped, the last item will be the only one that remains
@note will avoid changing the default permissions for NTAUTH\INTERACTIVE, BUILTIN\Administrators, and BUILTIN\Remote Management Users, but will only reset them to default if they are changed. will not recreate if deleted

@param[in] group_name the name of the group to allow to access the machine via WinRM
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [string]$group_name
)

# ----------------- Helpers ---------- #

function Compare-ACE
{
  param(
    [System.Security.AccessControl.CommonAce]$ace,
    [System.Security.Principal.SecurityIdentifier]$sid,
    [System.Security.AccessControl.AceType]$type,
    [System.Int32]$mask,
    [System.Security.AccessControl.InheritanceFlags]$inheritance,
    [System.Security.AccessControl.PropagationFlags]$propagation
  )
  $equal = $true

  if ($ace.SecurityIdentifier -ne $sid) { $equal = $false }
  if ($ace.AceType -ne $type) { $equal = $false }
  if ($ace.AccessMask -ne $mask) { $equal = $false }
  if ($ace.InheritanceFlags -ne $inheritance) { $equal = $false }
  if ($ace.PropagationFlags -ne $propagation) { $equal = $false }

  return $equal
}

# ---------------- Main -------------- #

$object = Get-PSSessionConfiguration -Name Microsoft.PowerShell
$sd = New-Object System.Security.AccessControl.CommonSecurityDescriptor $false, $false, $object.SecurityDescriptorSddl

$sid = (New-Object System.Security.Principal.NTAccount($group_name)).Translate([System.Security.Principal.SecurityIdentifier])
# These fields are the same for our goal ACE and the default ACEs
$target_type = [System.Security.AccessControl.AceType]::AccessAllowed
$target_mask = 0x10000000
$target_inheritance = [System.Security.AccessControl.InheritanceFlags]::None
$target_propagation = [System.Security.AccessControl.PropagationFlags]::None

$basic_sids = @(
  (New-Object System.Security.Principal.NTAccount("NT AUTHORITY\INTERACTIVE")).Translate([System.Security.Principal.SecurityIdentifier]).Value
  (New-Object System.Security.Principal.NTAccount("BUILTIN\Administrators")).Translate([System.Security.Principal.SecurityIdentifier]).Value
  (New-Object System.Security.Principal.NTAccount("BUILTIN\Remote Management Users")).Translate([System.Security.Principal.SecurityIdentifier]).Value
)

# Have to copy the ACL to allow us to change the ACL dynamically
$loop_acl = @($sd.DiscretionaryAcl)
$changed = $false
$needed = $true
foreach ($ace in $loop_acl)
{
# Parse the existing ACEs and ensure they are:
## a) default, or
## b) the one we're trying to set
  if ($ace.SecurityIdentifier -eq $sid)
  {
    $needed = $false
    # This ACE is for the group we're working on
    if ( Compare-ACE -ace $ace -sid $sid -type $target_type -mask $target_mask -inheritance $target_inheritance -propagation $target_propagation )
    {
      # This ACE matches, so we have nothing to do
      continue
    }
    else
    {
      # ace doesnt match, so we have to delete and recreate it
      $sd.DiscretionaryAcl.RemoveAce($ace)
      $sd.DiscretionaryAcl.AddAccess($target_type,$sid,$target_mask,$target_inheritance,$target_propagation)
      $changed = $true
    }
  }
  elseif ($ace.SecurityIdentifier.Value -notin $basic_sids)
  {
    $changed = $true
    # This ACE is not one of the default ACEs
    $sd.DiscretionaryAcl.RemoveAce($ace)
  }
  else
  {
  # This is one of the default ACEs, need to make sure they werent modified
    foreach($basic in $basic_sids)
    {
    # quick loop to find the matching SID
      if ($ace.SecurityIdentifier -eq $basic)
      {
      # compare the ACEs to see if they match
	if ( -not (Compare-ACE -ace $ace -sid $basic -type $target_type -mask $target_mask -inheritance $target_inheritance -propagation $target_propagation))
        {
          $sd.DiscretionaryAcl.RemoveAce($ace)
          $sd.DiscretionaryAcl.AddAccess($target_type,$sid,$target_mask,$target_inheritance,$target_propagation)
          $changed = $true	  
        }
      }
    }
  }
}

if ($needed)
{
# we didnt fix an existing ACE, so we need to create one
  $sd.DiscretionaryAcl.AddAccess(
    [System.Security.AccessControl.AccessControlType]::Allow,
    $sid,
    0x1, # Maps to the Execute permission
    [System.Security.AccessControl.InheritanceFlags]::None,
    [System.Security.AccessControl.PropagationFlags]::None
  )
  $changed = $true
}

if ($changed)
{
# if we changed anything, save the updated ACL
## TODO - SDDL formation creates an error condition
  $newSDDL = $sd.GetSddlForm([System.Security.AccessControl.AccessControlSections]::All)
  Set-PSSessionConfiguration -Name Microsoft.PowerShell -SecurityDescriptorSddl $newSddl -Force
}

return [pscustomobject]@{ changed=$changed; sddl=$newSDDL }
