# PowerShell Cheatsheet — Entra ID · Intune · Microsoft 365

PowerShell 7+ recommended for all modules. Examples use `contoso.com` / `contoso.onmicrosoft.com`.

---

## 1. Modules

`AzureAD`, `AzureADPreview`, and `MSOnline` are **retired** (MSOnline retired May 2025, AzureAD retired Q3 2025) and no longer function. Use the modules below.

| Area | Module | Notes |
|---|---|---|
| Graph (everything) | `Microsoft.Graph` | v1.0 cmdlets. Meta-module — install sub-modules to stay lean. |
| Graph beta | `Microsoft.Graph.Beta` | `*-MgBeta*` cmdlets, `/beta` surface. |
| Entra ID (scenario-focused) | `Microsoft.Entra` | GA. Built on Graph SDK, side-by-side compatible. `Connect-Entra`, `Get-EntraUser`. |
| Entra ID beta | `Microsoft.Entra.Beta` | `Get-EntraBetaUser`, etc. |
| Exchange Online | `ExchangeOnlineManagement` | v3.7+ needed for `*V2` message-trace cmdlets. |
| Teams | `MicrosoftTeams` | Includes voice/`Cs*` cmdlets. |
| SharePoint / OneDrive | `PnP.PowerShell` | Requires your own Entra app (`-ClientId`); the shared multi-tenant app was retired. |
| SharePoint admin | `Microsoft.Online.SharePoint.PowerShell` | `Connect-SPOService`, `Get-SPOSite`. |

```powershell
Install-Module Microsoft.Graph        -Scope CurrentUser
Install-Module Microsoft.Graph.Beta   -Scope CurrentUser
Install-Module Microsoft.Entra        -Scope CurrentUser
Install-Module ExchangeOnlineManagement -Scope CurrentUser
Install-Module MicrosoftTeams         -Scope CurrentUser
Install-Module PnP.PowerShell         -Scope CurrentUser

# Lean Graph install — auth + only what you need
Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Users, `
               Microsoft.Graph.Groups, Microsoft.Graph.DeviceManagement -Scope CurrentUser

Get-InstalledModule Microsoft.Graph*          # check versions
Update-Module Microsoft.Graph                 # update (does NOT remove old versions)
Get-InstalledModule Microsoft.Graph -AllVersions | Sort Version   # spot stale copies
```

---

## 2. Connecting & authentication

### Microsoft Graph
```powershell
# Interactive (delegated)
Connect-MgGraph -Scopes "User.Read.All","Group.Read.All","DeviceManagementManagedDevices.Read.All" -NoWelcome

# App-only with certificate (unattended / runbooks)
Connect-MgGraph -ClientId $appId -TenantId $tenantId -CertificateThumbprint $thumb -NoWelcome

# Managed identity (Azure Automation / Azure VM)
Connect-MgGraph -Identity -NoWelcome

# Device code (no browser on host)
Connect-MgGraph -Scopes "User.Read.All" -UseDeviceCode

Get-MgContext                      # current connection
(Get-MgContext).Scopes             # granted scopes this session
Disconnect-MgGraph
```

```powershell
# Dual-mode connect (runbook vs interactive) — Connect-MgGraph -Identity fails interactively
if ($env:AUTOMATION_ASSET_ACCOUNTID) {
    Connect-MgGraph -Identity -NoWelcome
} else {
    Connect-MgGraph -Scopes "User.Read.All" -NoWelcome
}
```

### Entra PowerShell
```powershell
Connect-Entra -Scopes "User.Read.All"
Connect-Entra -ClientId $appId -TenantId $tenantId -CertificateThumbprint $thumb   # app-only
Disconnect-Entra
```

### Exchange Online & Security/Compliance
```powershell
Connect-ExchangeOnline -UserPrincipalName admin@contoso.com
Connect-ExchangeOnline -AppId $appId -CertificateThumbprint $thumb -Organization contoso.onmicrosoft.com
Connect-IPPSSession                      # Security & Compliance Center
Disconnect-ExchangeOnline -Confirm:$false
```

### Teams / SharePoint
```powershell
Connect-MicrosoftTeams
Connect-SPOService -Url https://contoso-admin.sharepoint.com
Connect-PnPOnline -Url https://contoso.sharepoint.com/sites/Team -ClientId $appId -Interactive
Connect-PnPOnline -Url https://contoso.sharepoint.com/sites/Team -ClientId $appId -Thumbprint $thumb -Tenant contoso.onmicrosoft.com
```

---

## 3. Graph SDK essentials

```powershell
# Map a Graph endpoint to the SDK cmdlet
Find-MgGraphCommand -Uri '/users/{id}/manager' -Method GET
Find-MgGraphCommand -Command Get-MgUser | Select -ExpandProperty Permissions   # scopes a cmdlet needs

# Search the permission catalogue
Find-MgGraphPermission user.read

# Discover cmdlets
Get-Command -Module Microsoft.Graph* -Noun *user*

# Raw Graph call (anything the SDK lacks, or full Intune beta surface)
Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/users?$top=5'
Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/beta/deviceManagement/managedDevices'
$body = @{ displayName = "New Group"; mailEnabled = $false; securityEnabled = $true; mailNickname = "newgrp" }
Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/groups' -Body $body
```

**Querying patterns**
```powershell
Get-MgUser -All                                       # paginate fully (default returns first page only)
Get-MgUser -Filter "accountEnabled eq false" -All     # OData filter
Get-MgUser -Filter "startsWith(displayName,'Jane')" -All
Get-MgUser -Select id,displayName,signInActivity -All # trim returned properties
Get-MgUser -ExpandProperty manager                    # expand a relationship

# Advanced queries need ConsistencyLevel eventual + a count variable
Get-MgUser -Search '"displayName:Smith"' -ConsistencyLevel eventual -CountVariable c -All
Get-MgUser -Filter 'assignedLicenses/$count eq 0' -ConsistencyLevel eventual -CountVariable c -All
Get-MgGroup -Filter "NOT(groupTypes/any(t:t eq 'Unified'))" -ConsistencyLevel eventual -CountVariable c -All
```

---

## 4. Entra ID — Users

```powershell
Get-MgUser -UserId user@contoso.com
Get-MgUser -All | Select Id,DisplayName,UserPrincipalName,AccountEnabled
Get-MgUser -Filter "userType eq 'Guest'" -All

# Create
$pw = @{ Password = 'Tr4ns!ent-Pa55'; ForceChangePasswordNextSignIn = $true }
New-MgUser -DisplayName "Jane Doe" -UserPrincipalName "jane@contoso.com" `
           -MailNickname "janed" -AccountEnabled -PasswordProfile $pw -UsageLocation "IE"

Update-MgUser -UserId jane@contoso.com -Department "IT" -JobTitle "Engineer"
Update-MgUser -UserId jane@contoso.com -AccountEnabled:$false        # disable
Get-MgUserManager -UserId jane@contoso.com
Set-MgUserManagerByRef -UserId jane@contoso.com -BodyParameter @{ "@odata.id" = "https://graph.microsoft.com/v1.0/users/$mgrId" }

Remove-MgUser -UserId jane@contoso.com                                # DESTRUCTIVE (soft-delete)
Get-MgDirectoryDeletedItemAsUser -All                                # recycle bin
Restore-MgDirectoryDeletedItem -DirectoryObjectId $deletedId
```

---

## 5. Entra ID — Groups & membership

```powershell
Get-MgGroup -All
Get-MgGroup -Filter "displayName eq 'Sales'"
New-MgGroup -DisplayName "Sales" -MailEnabled:$false -MailNickname "sales" -SecurityEnabled
New-MgGroup -DisplayName "Sales M365" -GroupTypes "Unified" -MailEnabled -MailNickname "salesm365" -SecurityEnabled:$false

# Membership
Get-MgGroupMember -GroupId $gid -All
New-MgGroupMember -GroupId $gid -DirectoryObjectId $userId
Remove-MgGroupMemberByRef -GroupId $gid -DirectoryObjectId $userId

# Owners
Get-MgGroupOwner -GroupId $gid -All
New-MgGroupOwner -GroupId $gid -DirectoryObjectId $userId

# Dynamic membership rule
New-MgGroup -DisplayName "Dyn-IT" -MailNickname "dynit" -SecurityEnabled -MailEnabled:$false `
            -GroupTypes "DynamicMembership" `
            -MembershipRule '(user.department -eq "IT")' -MembershipRuleProcessingState "On"
```

---

## 6. Entra ID — Roles, PIM, apps & service principals

### Directory roles & unified RBAC
```powershell
Get-MgDirectoryRole -All                                  # currently activated roles
Get-MgDirectoryRoleMember -DirectoryRoleId $rid
Get-MgDirectoryRoleTemplate -All                          # all assignable role templates

Get-MgRoleManagementDirectoryRoleDefinition -All | Select DisplayName,Id,IsBuiltIn
Get-MgRoleManagementDirectoryRoleAssignment -All -ExpandProperty Principal
New-MgRoleManagementDirectoryRoleAssignment -RoleDefinitionId $roleDefId -PrincipalId $userId -DirectoryScopeId "/"
```

### PIM — eligible & active assignments
```powershell
# Read eligibility / active schedules
Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance -All -ExpandProperty Principal,RoleDefinition
Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance  -All -ExpandProperty Principal,RoleDefinition

# Admin assigns an eligible role (8h example; use "noExpiration" / "P365D" for standing eligibility)
$params = @{
    action           = "adminAssign"
    principalId      = $userId
    roleDefinitionId = $roleDefId
    directoryScopeId = "/"
    scheduleInfo     = @{
        startDateTime = (Get-Date)
        expiration    = @{ type = "afterDuration"; duration = "PT8H" }
    }
}
New-MgRoleManagementDirectoryRoleEligibilityScheduleRequest -BodyParameter $params

# User self-activates an eligible role (principalId must be the signed-in user)
$activate = @{
    action           = "selfActivate"
    principalId      = (Get-MgContext).Account   # or the user's object id
    roleDefinitionId = $roleDefId
    directoryScopeId = "/"
    justification    = "On-call incident response"
    scheduleInfo     = @{
        startDateTime = (Get-Date)
        expiration    = @{ type = "afterDuration"; duration = "PT8H" }
    }
}
New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -BodyParameter $activate
```

### App registrations & service principals
```powershell
Get-MgApplication -All
Get-MgApplication -Filter "displayName eq 'My API Client'"
New-MgApplication -DisplayName "My API Client"

# Add a client secret / view credentials
Add-MgApplicationPassword -ApplicationId $appObjectId `
    -PasswordCredential @{ displayName = "cli-secret"; endDateTime = (Get-Date).AddMonths(6) }

Get-MgServicePrincipal -All
Get-MgServicePrincipal -Filter "appId eq '$appId'"
New-MgServicePrincipal -AppId $appId

# Grant an APPLICATION permission (app role) to a service principal
New-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $clientSpId `
    -BodyParameter @{ principalId = $clientSpId; resourceId = $resourceSpId; appRoleId = $appRoleId }

# Grant DELEGATED admin consent
New-MgOauth2PermissionGrant -BodyParameter @{
    clientId = $clientSpId; consentType = "AllPrincipals"; resourceId = $graphSpId; scope = "User.Read Group.Read.All"
}
```

---

## 7. Entra ID — Conditional Access, logs, licensing

### Conditional Access
```powershell
Get-MgIdentityConditionalAccessPolicy -All | Select DisplayName,State,Id
Get-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $id
Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $id -State "enabledForReportingButNotEnforced"
Get-MgIdentityConditionalAccessNamedLocation -All
```

### Sign-in & audit logs
```powershell
Get-MgAuditLogSignIn -Top 50
Get-MgAuditLogSignIn -Filter "userPrincipalName eq 'jane@contoso.com'" -All
Get-MgAuditLogSignIn -Filter "status/errorCode ne 0" -Top 100        # failures
Get-MgAuditLogDirectoryAudit -Filter "activityDisplayName eq 'Add member to role'" -Top 50
```

### Licensing
```powershell
Get-MgSubscribedSku -All |
    Select SkuPartNumber, SkuId, ConsumedUnits, @{n='Enabled';e={$_.PrepaidUnits.Enabled}}

Update-MgUser -UserId jane@contoso.com -UsageLocation "IE"          # required before assigning
Set-MgUserLicense -UserId jane@contoso.com -AddLicenses @{ SkuId = $skuId } -RemoveLicenses @()
Set-MgUserLicense -UserId jane@contoso.com -AddLicenses @() -RemoveLicenses @($skuId)

Get-MgUserLicenseDetail -UserId jane@contoso.com
```

---

## 8. Intune / Device management

Intune lives under `deviceManagement` / `deviceAppManagement`. The **beta** Graph surface exposes the full device-management API — prefer `/beta` for Intune raw calls.

```powershell
# Managed devices (SDK)
Get-MgDeviceManagementManagedDevice -All
Get-MgDeviceManagementManagedDevice -Filter "operatingSystem eq 'iOS'" -All
Get-MgDeviceManagementManagedDevice -ManagedDeviceId $id
Get-MgBetaDeviceManagementManagedDevice -All                          # beta cmdlet variant

# Sync a device — raw Graph (beta) is the reliable path
Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$id/syncDevice"
# SDK equivalent: Sync-MgDeviceManagementManagedDevice -ManagedDeviceId $id

# Compliance & configuration
Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies'
Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations'
Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies'   # settings catalog

# Apps
Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps'

# Autopilot
Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities'

# Detected apps on a device
Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$id/detectedApps"
```

**Destructive device actions — guard with `SupportsShouldProcess` / `-WhatIf` in scripts**
```powershell
Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$id/retire"
Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$id/wipe"
Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$id/rebootNow"
```

**Pull all pages from a raw Graph list**
```powershell
$uri  = 'https://graph.microsoft.com/beta/deviceManagement/managedDevices'
$all  = @()
do {
    $resp = Invoke-MgGraphRequest -Method GET -Uri $uri
    $all += $resp.value
    $uri  = $resp.'@odata.nextLink'
} while ($uri)
```

---

## 9. Exchange Online

```powershell
Get-EXOMailbox -ResultSize Unlimited                       # fast REST-based
Get-Mailbox -Identity user@contoso.com
Get-EXOMailboxStatistics -Identity user@contoso.com
Set-Mailbox -Identity user@contoso.com -LitigationHoldEnabled $true
Set-Mailbox -Identity user@contoso.com -Type Shared

# Permissions
Add-MailboxPermission   -Identity room@contoso.com   -User jane@contoso.com -AccessRights FullAccess -AutoMapping $true
Add-RecipientPermission -Identity shared@contoso.com -Trustee jane@contoso.com -AccessRights SendAs -Confirm:$false

# Groups
Get-DistributionGroup
Get-DistributionGroupMember -Identity dl@contoso.com
Get-UnifiedGroup                                           # M365 groups

# Message trace (V2 — legacy Get-MessageTrace deprecated Sep 2025; needs module v3.7+)
Get-MessageTraceV2 -StartDate (Get-Date).AddDays(-2) -EndDate (Get-Date) -SenderAddress jane@contoso.com
Get-MessageTraceV2 -StartDate (Get-Date).AddDays(-7) -EndDate (Get-Date) -Status Failed
Get-MessageTraceDetailV2 -MessageTraceId $id -RecipientAddress recipient@contoso.com

# Transport rules & connectors
Get-TransportRule
Get-OutboundConnector
```

---

## 10. Teams / SharePoint

```powershell
# Teams
Get-Team -DisplayName "Marketing"
Get-TeamUser -GroupId $gid
Add-TeamUser -GroupId $gid -User jane@contoso.com -Role Member
Get-CsOnlineUser -Identity jane@contoso.com                # voice / calling
Get-CsTeamsMeetingPolicy

# SharePoint admin (SPO)
Get-SPOSite -Limit All
Get-SPOSite -Identity https://contoso.sharepoint.com/sites/Team | Select Url,StorageQuota,Owner

# SharePoint content (PnP)
Get-PnPList
Get-PnPListItem -List "Documents" -PageSize 500
Get-PnPSite
```

---

## 11. Reusable patterns & gotchas

### Error handling
```powershell
try {
    Get-MgUser -UserId nope@contoso.com -ErrorAction Stop
} catch {
    Write-Warning "Lookup failed: $($_.Exception.Message)"
}
```

### Export to CSV
```powershell
Get-MgUser -All -Property DisplayName,UserPrincipalName,AccountEnabled |
    Select DisplayName,UserPrincipalName,AccountEnabled |
    Export-Csv -Path .\users.csv -NoTypeInformation -Encoding UTF8
```

### Destructive bulk op with safe-preview
```powershell
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param([string[]]$DeviceIds)

foreach ($d in $DeviceIds) {
    if ($PSCmdlet.ShouldProcess($d, "Retire device")) {
        Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$d/retire"
    }
}
# Run with -WhatIf to preview, -Confirm to approve each.
```

### Null-safe Graph dates
```powershell
# Fields like lastSyncDateTime / enrolledDateTime can be $null — [datetime]::Parse throws on null.
$last = if ($device.lastSyncDateTime) { [datetime]$device.lastSyncDateTime } else { $null }
```

### Common traps
- **Pagination:** SDK list cmdlets return only the first page (~100). Add `-All` or follow `@odata.nextLink`.
- **Advanced queries:** `$search`, `$count`, `endsWith`, `NOT`, `ne` need `-ConsistencyLevel eventual` **and** `-CountVariable`.
- **OData `$` in URIs:** use single-quoted strings (`'...$top=5'`) or backtick-escape (`` `$top ``) so PowerShell doesn't treat it as a variable.
- **Licensing:** `Set-MgUserLicense` fails until `UsageLocation` is set on the user.
- **Intune surface:** many device-management properties exist only on `/beta`. `/v1.0` will silently omit them.
- **App-only vs delegated:** application context has no signed-in user — `selfActivate` PIM, `/me`, and sign-in-as-user calls won't work.
- **Cmdlet confusions:** `Get-Tpm` reports TPM state, **not** BitLocker status (use `Get-BitLockerVolume`); `Get-SecureBootUEFI` returns a variable object, not a boolean.
- **Legacy modules:** `Connect-AzureAD` → `Connect-Entra` / `Connect-MgGraph`; `Get-AzureADUser` / `Get-MsolUser` → `Get-EntraUser` / `Get-MgUser`; `Set-MsolUserLicense` → `Set-MgUserLicense`.

---

## 12. Reusable script header

```powershell
<#
.TITLE       Short descriptive title
.SYNOPSIS    One-line summary
.DESCRIPTION What it does, inputs/outputs, scope
.TAGS        Intune, Graph, Reporting
.PLATFORM    Windows / iOS / Android / Cross-platform
.PERMISSIONS DeviceManagementManagedDevices.Read.All   # real Graph scopes only
.AUTHOR      <name>
.VERSION     1.0.0
.CHANGELOG   1.0.0 - Initial version
.LASTUPDATE  YYYY-MM-DD
.EXAMPLE     .\Get-DeviceComplianceReport.ps1 -Os iOS
.NOTES       Assumptions, throttling notes, dependencies
#>
```
