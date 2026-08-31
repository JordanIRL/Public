# Microsoft Graph PowerShell

`Microsoft.Graph` 2.39.0 — connect with `Connect-MgGraph -Scopes "User.Read.All","Group.ReadWrite.All" -NoWelcome`.

## Mental model

- The SDK is generated from the Graph REST API. One cmdlet = one endpoint: `Get-MgUser` is `GET /users`, `New-MgGroupMemberByRef` is `POST /groups/{id}/members/$ref`, `Get-MgUserLicenseDetail` is `GET /users/{id}/licenseDetails`.
- `Microsoft.Graph` is a meta-module of ~40 submodules. `Microsoft.Graph.Authentication` is always required; the rest load on demand (`Microsoft.Graph.Users`, `.Groups`, `.Identity.DirectoryManagement`, `.Identity.SignIns`, `.Applications`, `.Reports`, `.Identity.Governance`).
- `Get-MgUser` returns the API's default `$select` set only (id, displayName, mail, UPN, jobTitle, a few more). Everything else — `AssignedLicenses`, `SignInActivity`, `OnPremisesSyncEnabled`, `CreatedDateTime` — comes back `$null` until you ask for it with `-Property`.
- Beta endpoints live in the separate `Microsoft.Graph.Beta` module with `Get-MgBeta*` naming. There is no `Get-MgProfile` / `Select-MgProfile` in v2 — that was v1.x.
- Scopes are consent, not authorization: you still need the matching Entra role (User Administrator, Groups Administrator, Security Reader, Global Reader…) for the call to succeed.
- `Connect-MgGraph` has **no** `-Interactive` switch — browser sign-in is the default.

## Connection

### Connect with the scopes you need
```powershell
Connect-MgGraph -Scopes "User.ReadWrite.All","Group.ReadWrite.All","Organization.Read.All" -NoWelcome
```
Scopes are accretive: re-running with new `-Scopes` adds to what is already consented, it does not replace.

### Verify the connection and see the scopes you actually have
```powershell
Get-MgContext | Select-Object Account,TenantId,Scopes
```

### Sign in on a machine with no browser
```powershell
Connect-MgGraph -Scopes "User.Read.All" -UseDeviceCode -NoWelcome
```

### Disconnect
```powershell
Disconnect-MgGraph
```

### Work around a hanging WAM sign-in on Windows
```powershell
Connect-MgGraph -UseDeviceCode
```
WAM is on by default on Windows and **cannot be disabled** — `Set-MgGraphOption -DisableLoginByWAM` no longer has any effect. Device code is the fallback.

## Discovery

### Find the cmdlet that calls a given API URI
```powershell
Find-MgGraphCommand -Uri "/users/{id}/licenseDetails" -Method GET | Select-Object Command,Module,Permissions
```

### Find the URI and permissions behind a cmdlet
```powershell
Find-MgGraphCommand -Command Get-MgAuditLogSignIn | Select-Object -ExpandProperty Permissions
```

### Find the permission that grants an operation
```powershell
Find-MgGraphPermission "AuditLog" -PermissionType Delegated | Select-Object Name,Description
```

### Use a beta endpoint
```powershell
Get-MgBetaUser -UserId user@contoso.com -Property DisplayName,EmployeeLeaveDateTime
```
Beta is subject to change without notice; keep it out of scheduled jobs where a v1.0 equivalent exists.

## Querying properly

### Return every object instead of the first page
```powershell
Get-MgUser -All -Property Id,DisplayName,UserPrincipalName,AccountEnabled
```
Without `-All` you get one page (100 objects) and no warning.

### Get properties that are null by default
```powershell
Get-MgUser -UserId user@contoso.com -Property Id,DisplayName,UsageLocation,AssignedLicenses,OnPremisesSyncEnabled,CreatedDateTime
```
`-Property` has the alias `-Select`; `-ExpandProperty` is `-Expand`, `-Sort` is `-OrderBy`, `-Top` is `-Limit`.

### Filter server-side
```powershell
Get-MgUser -All -Filter "department eq 'Finance' and accountEnabled eq true" -Property DisplayName,UserPrincipalName,Department
```

### Run an advanced query (endsWith, not, ne, empty collections)
```powershell
Get-MgUser -All -Filter "endsWith(mail,'@contoso.com')" -ConsistencyLevel eventual -CountVariable c -Property DisplayName,Mail
```
`endsWith`, `not`, `ne`, `$search`, `$count` and filters on `signInActivity`/`extensionAttributes` all require **both** `-ConsistencyLevel eventual` and `-CountVariable`. Omit either and the filter is silently ignored or errors.

### Search across display name and mail
```powershell
Get-MgUser -Search '"displayName:Sales" OR "mail:Sales"' -ConsistencyLevel eventual -CountVariable c -All
```
The search value needs inner double quotes inside outer single quotes.

### Cap results
```powershell
Get-MgAuditLogSignIn -Top 25
```
`/auditLogs/signIns` supports only `$top`, `$filter` and `$skiptoken` — `-Sort` is silently ignored, but records already come back newest-first.

### Expand a relationship in one call
```powershell
Get-MgGroup -GroupId $groupId -ExpandProperty Members | Select-Object -ExpandProperty Members
```
`$expand` on a directory relationship returns **at most 20** objects and does not page — use `Get-MgGroupMember -All` for the real membership.

### Tune the page size for large pulls
```powershell
Get-MgUser -All -PageSize 999 -Property Id,UserPrincipalName,AssignedLicenses
```

### Escape a quote inside a filter
```powershell
Get-MgUser -Filter "displayName eq 'O''Brien, Sean'"
```
Double the single quote; do not backslash it.

## Users

### Get a user with the properties you care about
```powershell
Get-MgUser -UserId user@contoso.com -Property DisplayName,UserPrincipalName,JobTitle,Department,UsageLocation,AccountEnabled
```

### Create a user
```powershell
$pw = -join ((48..57)+(65..90)+(97..122) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
New-MgUser -DisplayName "Sean O'Brien" -UserPrincipalName user@contoso.com -MailNickname "user" -UsageLocation "GB" -AccountEnabled -PasswordProfile @{ Password = $pw; ForceChangePasswordNextSignIn = $true }
```
`-UsageLocation` must be set before any license can be assigned.

### Update user attributes
```powershell
Update-MgUser -UserId user@contoso.com -JobTitle "Financial Analyst" -Department "Finance" -OfficeLocation "London"
```

### Block sign-in and kill existing sessions
```powershell
Update-MgUser -UserId user@contoso.com -AccountEnabled:$false; Revoke-MgUserSignInSession -UserId user@contoso.com
```
Disabling alone leaves issued access tokens valid for their remaining lifetime — 60–90 minutes by default, up to 24–28 hours for CAE-capable clients — so always revoke too.

### Reset a password and force a change at next sign-in
```powershell
$pw = -join ((48..57)+(65..90)+(97..122) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
Update-MgUser -UserId user@contoso.com -PasswordProfile @{ Password = $pw; ForceChangePasswordNextSignIn = $true }
```
Needs `User-PasswordProfile.ReadWrite.All`; it fails against anyone holding a privileged role unless you hold one too.

### Set the manager
```powershell
Set-MgUserManagerByRef -UserId user@contoso.com -OdataId "https://graph.microsoft.com/v1.0/users/admin@contoso.com"
```

### Read the manager
```powershell
(Get-MgUserManager -UserId user@contoso.com).AdditionalProperties['userPrincipalName']
```

### Set and get the profile photo
```powershell
Set-MgUserPhotoContent -UserId user@contoso.com -InFile ./photo.jpg; Get-MgUserPhotoContent -UserId user@contoso.com -OutFile ./current.jpg
```

### Delete a user
```powershell
Remove-MgUser -UserId user@contoso.com
```

### List soft-deleted users
```powershell
Get-MgDirectoryDeletedItemAsUser -All | Select-Object DisplayName,UserPrincipalName,DeletedDateTime
```
Deleted directory objects are recoverable for 30 days.

### Restore a deleted user
```powershell
Restore-MgDirectoryDeletedItem -DirectoryObjectId $deletedUserId
```

### Bulk-create users from CSV
```powershell
Import-Csv ./newusers.csv | ForEach-Object {
  $pw = -join ((48..57)+(65..90)+(97..122) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
  New-MgUser -DisplayName $_.DisplayName -UserPrincipalName $_.UserPrincipalName -MailNickname $_.MailNickname `
    -UsageLocation $_.UsageLocation -AccountEnabled -PasswordProfile @{ Password = $pw; ForceChangePasswordNextSignIn = $true }
}
```
CSV headers: DisplayName, UserPrincipalName, MailNickname, UsageLocation.

### Find users who have not signed in for 90 days
```powershell
Get-MgUser -All -Property DisplayName,UserPrincipalName,SignInActivity -Filter "signInActivity/lastSignInDateTime le $((Get-Date).AddDays(-90).ToString('yyyy-MM-ddTHH:mm:ssZ'))" -ConsistencyLevel eventual -CountVariable c
```
Requires Entra ID P1/P2 and `AuditLog.Read.All`. Misses accounts that have **never** signed in (blank `lastSignInDateTime`) — catch those with a second pass filtering on `-not $_.SignInActivity.LastSignInDateTime`. `signInActivity` cannot be combined with any other filterable property, and `-Top` is capped at 500 when you select it.

## Groups

### Create a Microsoft 365 group
```powershell
New-MgGroup -DisplayName "Sales Team" -MailNickname "salesteam" -MailEnabled -SecurityEnabled:$false -GroupTypes "Unified"
```

### Create a security group
```powershell
New-MgGroup -DisplayName "Sales Team" -MailNickname "salesteam" -SecurityEnabled -MailEnabled:$false -GroupTypes @()
```

### Add a member
```powershell
New-MgGroupMemberByRef -GroupId $groupId -OdataId "https://graph.microsoft.com/v1.0/directoryObjects/$userId"
```

### Remove a member
```powershell
Remove-MgGroupMemberByRef -GroupId $groupId -DirectoryObjectId $userId
```

### Add and list owners
```powershell
New-MgGroupOwnerByRef -GroupId $groupId -OdataId "https://graph.microsoft.com/v1.0/users/admin@contoso.com"; Get-MgGroupOwnerAsUser -GroupId $groupId -All | Select-Object DisplayName,UserPrincipalName
```

### Create a dynamic membership group
```powershell
New-MgGroup -DisplayName "Sales Team" -MailNickname "salesteam" -MailEnabled -SecurityEnabled:$false `
  -GroupTypes "Unified","DynamicMembership" -MembershipRule '(user.department -eq "Sales")' -MembershipRuleProcessingState "On"
```
Dynamic membership needs an Entra ID P1 licence per member.

### List members including nested groups
```powershell
Get-MgGroupTransitiveMember -GroupId $groupId -All | Select-Object Id,@{n='Type';e={$_.AdditionalProperties['@odata.type']}},@{n='Name';e={$_.AdditionalProperties['displayName']}}
```
`Get-MgGroupMember` returns direct members only.

### List the groups a user is in, transitively
```powershell
Get-MgUserTransitiveMemberOf -UserId user@contoso.com -All | Select-Object -ExpandProperty AdditionalProperties | Select-Object displayName,'@odata.type'
```

### Find empty groups
```powershell
Get-MgGroup -All -Property Id,DisplayName | Where-Object { -not (Get-MgGroupMember -GroupId $_.Id -Top 1) } | Select-Object DisplayName,Id
```

### Find ownerless groups
```powershell
Get-MgGroup -All -Property Id,DisplayName | Where-Object { -not (Get-MgGroupOwner -GroupId $_.Id -Top 1) } | Select-Object DisplayName,Id
```

## Licensing

### List subscriptions and free units
```powershell
Get-MgSubscribedSku -All | Select-Object SkuPartNumber,SkuId,@{n='Enabled';e={$_.PrepaidUnits.Enabled}},ConsumedUnits
```
`SkuPartNumber` (e.g. `SPE_E3`, `ENTERPRISEPACK`) is the friendly-ish name; Microsoft publishes the product-name mapping in the "Product names and service plan identifiers" article.

### Assign a licence
```powershell
Set-MgUserLicense -UserId user@contoso.com -AddLicenses @{ SkuId = (Get-MgSubscribedSku -All | Where-Object SkuPartNumber -eq 'SPE_E3').SkuId } -RemoveLicenses @()
```
`-RemoveLicenses @()` is mandatory even when you are only adding.

### Remove a licence
```powershell
Set-MgUserLicense -UserId user@contoso.com -AddLicenses @() -RemoveLicenses @((Get-MgSubscribedSku -All | Where-Object SkuPartNumber -eq 'SPE_E3').SkuId)
```

### Disable one service plan inside a SKU
```powershell
$sku = Get-MgSubscribedSku -All | Where-Object SkuPartNumber -eq 'SPE_E3'
$off = $sku.ServicePlans | Where-Object ServicePlanName -in ('YAMMER_ENTERPRISE','SWAY') | Select-Object -ExpandProperty ServicePlanId
Set-MgUserLicense -UserId user@contoso.com -AddLicenses @(@{ SkuId = $sku.SkuId; DisabledPlans = $off }) -RemoveLicenses @()
```
`DisabledPlans` is absolute: any plan you omit is re-enabled, so merge with the user's existing disabled plans first if you are only adding one.

### See what a user is licensed for and where it came from
```powershell
Get-MgUserLicenseDetail -UserId user@contoso.com | Select-Object SkuPartNumber; (Get-MgUser -UserId user@contoso.com -Property LicenseAssignmentStates).LicenseAssignmentStates | Select-Object SkuId,AssignedByGroup,State,Error
```
A non-null `AssignedByGroup` means group-based licensing — removing it directly will fail.

### Inspect group-based licensing
```powershell
Get-MgGroup -All -Property Id,DisplayName,AssignedLicenses | Where-Object { $_.AssignedLicenses } | Select-Object DisplayName,@{n='Skus';e={$_.AssignedLicenses.SkuId -join ','}}
```

### Export a licence report for every user
```powershell
$skus = Get-MgSubscribedSku -All
Get-MgUser -All -PageSize 999 -Property DisplayName,UserPrincipalName,AccountEnabled,AssignedLicenses |
  Select-Object DisplayName,UserPrincipalName,AccountEnabled,
    @{n='Licenses';e={ ($_.AssignedLicenses.SkuId | ForEach-Object { $id = $_; ($skus | Where-Object SkuId -eq $id).SkuPartNumber }) -join ';' }} |
  Export-Csv ./license-report.csv -NoTypeInformation
```

## Devices

### List devices
```powershell
Get-MgDevice -All -Property DisplayName,OperatingSystem,OperatingSystemVersion,TrustType,ApproximateLastSignInDateTime,AccountEnabled
```

### Find stale devices
```powershell
Get-MgDevice -All -ConsistencyLevel eventual -CountVariable c -Filter "approximateLastSignInDateTime le $((Get-Date).AddDays(-180).ToString('yyyy-MM-ddTHH:mm:ssZ'))" -Property DisplayName,OperatingSystem,ApproximateLastSignInDateTime
```

### List devices registered to a user
```powershell
Get-MgUserRegisteredDevice -UserId user@contoso.com -All | Select-Object -ExpandProperty AdditionalProperties | Select-Object displayName,operatingSystem
```

### Retrieve a BitLocker recovery key
```powershell
Get-MgInformationProtectionBitlockerRecoveryKey -All | Select-Object Id,DeviceId,CreatedDateTime
Get-MgInformationProtectionBitlockerRecoveryKey -BitlockerRecoveryKeyId $keyId -Property "key"
```
The key value is only returned when you explicitly `-Property "key"`; needs `BitlockerKey.Read.All` and Global/Cloud Device/Intune Administrator or Helpdesk Administrator.

## Sign-in and audit logs

### Read recent sign-ins
```powershell
Get-MgAuditLogSignIn -Filter "createdDateTime ge $((Get-Date).AddDays(-1).ToString('yyyy-MM-ddTHH:mm:ssZ'))" -Top 50 | Select-Object CreatedDateTime,UserPrincipalName,AppDisplayName,IPAddress,@{n='Error';e={$_.Status.ErrorCode}}
```

### List failed sign-ins for one user
```powershell
Get-MgAuditLogSignIn -Filter "userPrincipalName eq 'user@contoso.com' and status/errorCode ne 0" -Top 50 | Select-Object CreatedDateTime,AppDisplayName,IPAddress,@{n='Reason';e={$_.Status.FailureReason}}
```

### Search the directory audit log
```powershell
Get-MgAuditLogDirectoryAudit -All -Filter "activityDisplayName eq 'Add member to group' and activityDateTime ge $((Get-Date).AddDays(-7).ToString('yyyy-MM-ddTHH:mm:ssZ'))" | Select-Object ActivityDateTime,ActivityDisplayName,@{n='By';e={$_.InitiatedBy.User.UserPrincipalName}}
```

### List risky users
```powershell
Get-MgRiskyUser -All -Filter "riskLevel eq 'high' and riskState ne 'dismissed'" | Select-Object UserPrincipalName,RiskLevel,RiskState,RiskLastUpdatedDateTime
```
Needs `IdentityRiskyUser.Read.All` and Entra ID P2.

## Applications and service principals

### List app registrations
```powershell
Get-MgApplication -All -Property DisplayName,AppId,Id,SignInAudience,CreatedDateTime | Sort-Object DisplayName
```

### Find secrets and certificates expiring in the next 60 days
```powershell
Get-MgApplication -All -Property DisplayName,AppId,PasswordCredentials,KeyCredentials |
  ForEach-Object { $a = $_; @($a.PasswordCredentials) + @($a.KeyCredentials) |
    Where-Object { $_ -and $_.EndDateTime -lt (Get-Date).ToUniversalTime().AddDays(60) -and $_.EndDateTime -gt (Get-Date).ToUniversalTime() } |
    Select-Object @{n='App';e={$a.DisplayName}},@{n='AppId';e={$a.AppId}},DisplayName,EndDateTime } |
  Sort-Object EndDateTime
```

### List enterprise apps with admin-consented delegated permissions
```powershell
Get-MgServicePrincipal -All -Filter "servicePrincipalType eq 'Application'" -Property Id,DisplayName,AppId | ForEach-Object { $sp = $_; Get-MgServicePrincipalOauth2PermissionGrant -ServicePrincipalId $sp.Id -All | Where-Object ConsentType -eq 'AllPrincipals' | Select-Object @{n='App';e={$sp.DisplayName}},ConsentType,Scope }
```

### List application (app-only) permissions granted to a service principal
```powershell
Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $spId -All | Select-Object ResourceDisplayName,AppRoleId,CreatedDateTime
```

## Directory roles

### List activated roles
```powershell
Get-MgDirectoryRole -All | Select-Object DisplayName,Id,RoleTemplateId | Sort-Object DisplayName
```
Only roles that have ever had a member are activated and returned here.

### List every Global Administrator
```powershell
Get-MgDirectoryRoleMemberAsUser -DirectoryRoleId (Get-MgDirectoryRoleByRoleTemplateId -RoleTemplateId "62e90394-69f5-4237-9190-012177145e10").Id -All | Select-Object DisplayName,UserPrincipalName
```

### Assign a role
```powershell
New-MgDirectoryRoleMemberByRef -DirectoryRoleId $roleId -OdataId "https://graph.microsoft.com/v1.0/directoryObjects/$userId"
```

### Remove a role assignment
```powershell
Remove-MgDirectoryRoleMemberDirectoryObjectByRef -DirectoryRoleId $roleId -DirectoryObjectId $userId
```

### Read PIM eligible role assignments
```powershell
Get-MgRoleManagementDirectoryRoleEligibilitySchedule -All -ExpandProperty "principal,roleDefinition" | Select-Object @{n='Who';e={$_.Principal.AdditionalProperties['displayName']}},@{n='Role';e={$_.RoleDefinition.DisplayName}},Status
```
Requires `RoleEligibilitySchedule.Read.Directory` and Entra ID P2.

## Conditional Access

### Inventory the policies
```powershell
Get-MgIdentityConditionalAccessPolicy -All | Select-Object DisplayName,State,Id,ModifiedDateTime | Sort-Object State,DisplayName
```
Needs `Policy.Read.All`.

### Export one policy as JSON for review or diffing
```powershell
Get-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $policyId | ConvertTo-Json -Depth 10 | Set-Content ./ca-policy.json
```

### List named locations
```powershell
Get-MgIdentityConditionalAccessNamedLocation -All | Select-Object DisplayName,Id,@{n='Type';e={$_.AdditionalProperties['@odata.type']}}
```

## Mail and calendar

### Send mail as a user
```powershell
Send-MgUserMail -UserId user@contoso.com -SaveToSentItems -Message @{ Subject = "Maintenance window"; Body = @{ ContentType = "Text"; Content = "Patching starts at 22:00 UTC." }; ToRecipients = @(@{ EmailAddress = @{ Address = "admin@contoso.com" } }) }
```
Delegated `Mail.Send` only lets you send as yourself; sending as somebody else needs application permission plus an application access policy.

### Read the newest messages in a mailbox
```powershell
Get-MgUserMessage -UserId user@contoso.com -Top 10 -Sort "receivedDateTime DESC" -Property Subject,ReceivedDateTime,From,IsRead
```

### Read calendar events in a window
```powershell
Get-MgUserCalendarView -UserId user@contoso.com -StartDateTime "2026-09-01T00:00:00Z" -EndDateTime "2026-09-30T23:59:59Z" -All | Select-Object Subject,Start,End,Organizer
```
For mailbox configuration — quotas, permissions, forwarding, litigation hold, retention, transport rules — use Exchange Online cmdlets instead; Graph exposes item data, not mailbox administration.

## Raw requests

### Call an endpoint that has no cmdlet
```powershell
Invoke-MgGraphRequest -Method GET -Uri "v1.0/users/user@contoso.com/mailboxSettings" -OutputType PSObject
```
Default `-OutputType` is a hashtable; `PSObject` gives you dotted property access.

### Page a raw request manually
```powershell
$uri = "v1.0/users?`$select=displayName,userPrincipalName&`$top=999"
while ($uri) { $r = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject; $r.value; $uri = $r.'@odata.nextLink' }
```
`Invoke-MgGraphRequest` does not follow `@odata.nextLink` for you.

### POST a body
```powershell
Invoke-MgGraphRequest -Method POST -Uri "v1.0/groups/$groupId/members/`$ref" -Body @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$userId" }
```

### Combine calls with JSON batching
```powershell
$body = @{ requests = @(
  @{ id = "1"; method = "GET"; url = "/users/user@contoso.com?`$select=displayName,usageLocation" },
  @{ id = "2"; method = "GET"; url = "/users/user@contoso.com/licenseDetails" }
) }
(Invoke-MgGraphRequest -Method POST -Uri "v1.0/`$batch" -Body $body -OutputType PSObject).responses | Select-Object id,status
```
Max 20 requests per batch; each is throttled individually and the batch itself still returns 200 when members fail.

## Errors, throttling, permissions

### Raise the SDK's automatic retry behaviour
```powershell
Set-MgRequestContext -MaxRetry 10 -RetryDelay 5 -RetriesTimeLimit 300
```
Applies to 429 and 5xx; check current values with `Get-MgRequestContext`.

### See the real error message from a failed call
```powershell
try { Get-MgUser -UserId nobody@contoso.com -ErrorAction Stop } catch { $_.Exception.Message; $_.ErrorDetails.Message }
```
`$_.ErrorDetails.Message` holds the Graph JSON error body — that is where the useful `code` and `message` live.

### Fix a "Insufficient privileges" / consent error
```powershell
Get-MgContext | Select-Object -ExpandProperty Scopes; Find-MgGraphCommand -Command Get-MgAuditLogSignIn | Select-Object -ExpandProperty Permissions
```
Compare the two, then reconnect with the missing scope added. If consent itself is refused, a Global Administrator has to approve the "Microsoft Graph Command Line Tools" app (id `14d82eec-204b-4c2f-b7e8-296a70dab67e`).

### Throttle bulk writes yourself
```powershell
Import-Csv ./users.csv | ForEach-Object { Update-MgUser -UserId $_.UserPrincipalName -Department $_.Department; Start-Sleep -Milliseconds 200 }
```

## Gotchas

- No `-All` means one page (100 objects) and no warning that there is more.
- `Get-MgUser` silently returns `$null` for anything outside the default property set — `AssignedLicenses`, `SignInActivity`, `CreatedDateTime`, `OnPremisesSyncEnabled` all need `-Property`.
- Advanced filters (`endsWith`, `not`, `ne`, `$search`, `$count`, `signInActivity`, `extensionAttributes`) need `-ConsistencyLevel eventual` **and** `-CountVariable` together; supply only one and the query fails or quietly ignores the filter.
- Filters are OData, not PowerShell: `-Filter "displayName eq 'Sales'"`, single quotes doubled to escape, ISO 8601 UTC timestamps, and `-Filter` is case-sensitive on values.
- `Connect-MgGraph -Interactive` is not a thing. Browser sign-in is the default parameter set.
- Scopes are consent, not permission. Having `User.ReadWrite.All` consented still fails without the User Administrator (or higher) role.
- Two versions of `Microsoft.Graph.Authentication` side by side produce bogus "Authentication needed. Please call Connect-MgGraph." errors on later cmdlets — keep exactly one (`Get-InstalledModule Microsoft.Graph.Authentication -AllVersions`).
- `Set-MgUserLicense -AddLicenses`/`-RemoveLicenses` are both mandatory; pass `@()` for the one you are not using.
- `DisabledPlans` replaces the whole disabled set — omitting a plan silently re-enables it.
- Licences assigned through a group cannot be removed from the user directly; check `LicenseAssignmentStates.AssignedByGroup` first.
- `Get-MgGroupMember` is direct members only. Nested groups need `Get-MgGroupTransitiveMember`.
- Directory-object cmdlets return a `DirectoryObject` whose real fields sit in `.AdditionalProperties` — `Select-Object DisplayName` on `Get-MgGroupMember` output returns blanks. Use the `*AsUser` / `*AsGroup` variants instead.
- `Get-MgDirectoryRole` lists only activated roles; a role nobody has ever held will not appear. Use `Get-MgDirectoryRoleByRoleTemplateId` when you need one by template.
- `Invoke-MgGraphRequest` does not follow `@odata.nextLink`, and `$` in the URI must be backtick-escaped in double-quoted PowerShell strings.
- 429s are retried automatically but only `MaxRetry` times; bulk loops still need pacing, and batched requests are never auto-retried.
- Graph is eventually consistent: a user or group created a second ago may not appear in a filtered list yet.
- Beta cmdlets (`Get-MgBeta*`) come from a separate module and can change without notice — do not build scheduled jobs on them if v1.0 covers the call.
- Disconnect with `Disconnect-MgGraph`; it does not affect Exchange, Teams, PnP or SPO sessions, which each need their own disconnect.
