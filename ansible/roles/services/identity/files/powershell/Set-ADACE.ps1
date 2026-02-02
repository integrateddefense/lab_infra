<# 
@file Set-ADACE.ps1
@brief Sets a single Active Directory Access Control Entry based on provided specifications

@param[in] principal the group or user to set the ACE for
@param[in] ou the OU to apply the ACE on
@param[in] right the right to grant or deny
@param[in] extendedRight (optional) used when right=ExtendedRight, the extended right to grant
@param[in] object_class the object class the right applies to
@param[in] access allow or deny
@param[in] inheritance None or Descendents; does this ACE apply to the OU or to the OUs descendents
@param[in] inherited_object_class (optional) used when inheritance!=None; the object class the inherited ACE applies to (i.e., computer, user, group)
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [string]$principal,
  [string]$ou,
  [string]$right,
  [string]$object_class,
  [string]$inheritance,
  [string]$access,
  [string]$extendedRight,
  [string]$inherited_object_class
)

Import-Module ActiveDirectory -ErrorAction Stop

# ------------ Helper Functions -------------------#
## Get all of the ACEs applied to the provided OU
function Get-OUACEs {
  param([Parameter(Mandatory=$true)][string]$ou)
  $path = "AD:$ou"
  $acl = Get-Acl -Path $path
  return @{ Path=$path; Rules=$acl.Access; acl=$acl }
}

## Resolve provided identity into a SID
function Resolve-Sid {
  param([Parameter(Mandatory=$true)][string]$trustee)
  $nt = New-Object System.Security.Principal.NTAccount($trustee)
  return $nt.Translate([System.Security.Principal.SecurityIdentifier]).Value
}

## Resolves a Schema/Object Class into its GUID reference
function Get-SchemaClassGuid {
  param([Parameter(Mandatory=$true)][string]$displayname)
  $root = [ADSI]"LDAP://RootDSE"
  $schemaNC = $root.schemaNamingContext

  # Build a DirectorySearcher object, apply the search root, filter, and make sure it also gets the GUID of anything it finds
  $ds = New-Object System.DirectoryServices.DirectorySearcher
  $ds.SearchRoot = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$schemaNC")
  $ds.Filter = "(&(objectClass=classSchema)(lDAPDisplayName=$displayname))"
  $ds.PropertiesToLoad.Add("schemaIDGUID") | Out-Null
  # Tell the DirectorySearcher object to find a single matching entry
  $res = $ds.FindOne()

  # Error check
  if ( -not $res) { throw "Could not resolve schema class GUID for lDAPDisplayName='$displayname'" }

  # convert the raw byte string to a GUID object
  $bytes = $res.Properties["schemaidguid"][0]
  return New-Object Guid(,$bytes)
}

## Resolves an ExtendedRight into it's GUID reference
function Get-ExtendedRightGuid {
  param([Parameter(Mandatory=$true)][string]$displayname)
  $root = [ADSI]"LDAP://RootDSE"
  $configNC = $root.configurationNamingContext
  $extRightsDN = "CN=Extended-Rights,$configNC"

  # Build a DirectorySearcher object to find the object we want
  $ds = New-Object System.DirectoryServices.DirectorySearcher
  $ds.SearchRoot = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$extRightsDN")
  $ds.Filter = "(&(objectClass=controlAccessRight)(displayName=$displayname))"
  $ds.PropertiesToLoad.Add("rightsGuid") | Out-Null
  # Tell the DirectorySearcher object to find a single matching entry
  $res = $ds.FindOne()

  # Error check
  if ( -not $res) { throw "Could not resolve extended right GUID for displayname='$displayname'" }

  # Convert the GUID String into a GUID object and return
  $guidStr = [string]$res.Properties["rightsguid"][0]
  return [Guid]$guidStr
}

## Generate a normalized key reference for a given rule
function Create-RuleKey
{
  param(
    [Parameter(Mandatory=$true)]$rule,
    [Parameter(Mandatory=$true)]$SidValue
  )

  # Normalize empty GUIDs
  $objType = if ($rule.ObjectType -and $rule.ObjectType -ne [Guid]::Empty) { $rule.ObjectType } else { [Guid]::Empty }
  $inherited_objType = if ($rule.InheritedObjectType -and $rule.InheritedObjectType -ne [Guid]::Empty) { $rule.InheritedObjectType } else { [Guid]::Empty }
  # Normalize string forms to upper case for stable comparisons
  $rights = $rule.ActiveDirectoryRights.ToString().ToUpperInvariant()
  $access_control_type = $rule.AccessControlType.ToString().ToUpperInvariant()
  $inheritance_type = $rule.InheritanceType.ToString().ToUpperInvariant()

  # return string form
  return "$SidValue|$access_control_type|$rights|$objType|$inheritance_type|$inherited_objType"
}

# -------------------------- Main ---------------------#

## Resolve all of the inputs and check to make sure we have everything we need
$principalSid = Resolve-Sid -trustee $principal
if (($right -eq "ExtendedRight") -and ( -not $extendedRight))
{
  throw { "Must provide an extendedRight when setting right to 'ExtendedRight'" }
}
elseif ($right -eq "ExtendedRight")
{
  $extendedRightGUID = Get-ExtendedRightGuid -displayname $extendedRight
}

if (($right -ne "ExtendedRight") -and (-not $object_class))
{
  throw { "Must provide an object_class when not setting extended rights" }
}
elseif ($right -ne "ExtendedRight")
{
  $objectGUID = Get-SchemaClassGuid -displayname $object_class
}

if ($access -eq "Allow")
{
  $a = [System.Security.AccessControl.AccessControlType]::Allow  
}
elseif ($access -eq "Deny")
{
  $a = [System.Security.AccessControl.AccessControlType]::Deny
}
else
{
  throw { "Unrecognized value for access; must be either 'Allow' or 'Deny'"}
}

if (($inheritance -ne "None") -and ( -not $inherited_object_class))
{
  throw { "Must provide an object class when applying inherited ACE" }
}
elseif ($inheritance -ne "None")
{
  $inherited_object_guid = Get-SchemaClassGuid -displayname $inherited_object_class
}

$r = [System.DirectoryServices.ActiveDirectoryRights]::None
foreach ($token in ($right -split '\s*,\s*'))
{
  $r = $r -bor ([System.DirectoryServices.ActiveDirectoryRights]::$token)
}

#$r = [System.DirectoryServices.ActiveDirectoryRights]($right.split(", "))
$i = [System.DirectoryServices.ActiveDirectorySecurityInheritance]::$inheritance

# Build the ACE object
$p = New-Object System.Security.Principal.NTAccount($principal)
if ((($right -eq "ExtendedRight") -and ($inheritance -eq "None")) -or ($right -ne "ExtendedRight"))
{
# ExtendedRights with inheritence, or standard rights
  $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($p,$r,$a,$objectGUID,$i)
}
elseif (($right -eq "ExtendedRight") -and ($inheritance -ne "None"))
{
# ExtendedRights without inheritance
  $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($p,$r,$a,$extendedRightGUID,$i,$inherited_object_guid)
}
else
{
  throw { "Unknown combination of right type and inheritance" }
}

# Generate a normalized key that refers to the rule we want to ensure exists
$key = Create-RuleKey -rule $ace -SidValue $principalSid
#write-host $key
# Search the current set of rules to see if an existing rule matches
$state = Get-OUACEs -ou $ou
foreach ($rule in $state.Rules)
{
  # Normalize the rule
  $sid = $null
  try
  {
    $sid = (New-Object System.Security.Principal.NTAccount($rule.IdentityReference.Value)).Translate([System.Security.Principal.SecurityIdentifier]).Value
  } catch { continue }
  $normalized = Create-RuleKey -rule $rule -SidValue $sid

  # Compare
  #write-host $normalized
  if ($key -eq $normalized)
  {
    $rc = [pscustomobject]@{
      ou = $ou
      principal = $principal
      right = $right
      extended_right = $extendedRight
      inheritance = $inheritance
      access = $access
      changed = $false
    }
    return $rc 
  }
}

# If we get to this point, the rule doesn't exist
$state.acl.AddAccessRule($ace)
Set-Acl -Path "AD:$ou" -AclObject $state.acl

$rc = [pscustomobject]@{
  ou = $ou
  principal = $principal
  right = $right
  extended_right = $extendedRight
  inheritance = $inheritance
  access = $access
  changed = $true
}
return $rc 
