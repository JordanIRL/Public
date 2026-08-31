# Cross-Workload Recipes

Spans five modules — `ExchangeOnlineManagement` 3.10.1 (`Connect-ExchangeOnline -UserPrincipalName admin@contoso.onmicrosoft.com -ShowBanner:$false`), `Microsoft.Graph` 2.39.0 (`Connect-MgGraph -Scopes "User.ReadWrite.All","Group.ReadWrite.All","Organization.Read.All" -NoWelcome`), `MicrosoftTeams` 7.9.0 (`Connect-MicrosoftTeams`), `PnP.PowerShell` 3.4.1 (`Connect-PnPOnline -Url "https://contoso.sharepoint.com" -Interactive -ClientId <your-app-client-id>`), `Microsoft.Online.SharePoint.PowerShell` 16.0.27515.12000 (`Connect-SPOService -Url https://contoso-admin.sharepoint.com`, Windows only) — each with its own disconnect: `Disconnect-ExchangeOnline -Confirm:$false`, `Disconnect-MgGraph`, `Disconnect-MicrosoftTeams`, `Disconnect-PnPOnline`, `Disconnect-SPOService`.

## New-hire provisioning

### Create the user account
```powershell
$pw = ((33..126) | Get-Random -Count 20 | ForEach-Object { [char]$_ }) -join ''
New-MgUser -DisplayName "Ada Lovelace" -UserPrincipalName user@contoso.com -MailNickname ada -AccountEnabled -UsageLocation GB -PasswordProfile @{ Password = $pw; ForceChangePasswordNextSignIn = $true }
```
Set `UsageLocation` at creation — licensing fails without it. Hand `$pw` to the new hire out of band; never commit it.

### Assign a licence
```powershell
$sku = Get-MgSubscribedSku -All | Where-Object SkuPartNumber -eq 'SPE_E3'
Set-MgUserLicense -UserId user@contoso.com -AddLicenses @{ SkuId = $sku.SkuId } -RemoveLicenses @()
```
`-RemoveLicenses @()` is mandatory even when removing nothing. Prefer group-based licensing where you have it and skip this entirely.

### Set the manager
```powershell
Set-MgUserManagerByRef -UserId user@contoso.com -OdataId "https://graph.microsoft.com/v1.0/users/$((Get-MgUser -UserId manager@contoso.com).Id)"
```

### Add to a group
```powershell
New-MgGroupMember -GroupId (Get-MgGroup -Filter "displayName eq 'Sales Team'").Id -DirectoryObjectId (Get-MgUser -UserId user@contoso.com).Id
```

### Add to a team
```powershell
Add-TeamUser -GroupId (Get-Team -DisplayName "Sales Team").GroupId -User user@contoso.com
```
`Get-Team -DisplayName` is a case-sensitive *filter*, not an exact match — check it returned one team before piping.

### Pre-provision OneDrive
```powershell
Request-PnPPersonalSite -UserEmails "user@contoso.com"
```
Connect PnP to the admin URL (`https://contoso-admin.sharepoint.com`) first. Otherwise OneDrive is created lazily on the user's first visit.

## Leaver / offboarding

### Offboard a leaver — order matters
```powershell
Set-Mailbox user@contoso.com -LitigationHoldEnabled $true
Update-MgUser -UserId user@contoso.com -AccountEnabled:$false
Revoke-MgUserSignInSession -UserId user@contoso.com
Set-MailboxAutoReplyConfiguration user@contoso.com -AutoReplyState Enabled -ExternalAudience All -InternalMessage "Ada has left Contoso. Please contact sales@contoso.com." -ExternalMessage "Ada has left Contoso. Please contact sales@contoso.com."
Set-Mailbox user@contoso.com -DeliverToMailboxAndForward $true -ForwardingSmtpAddress manager@contoso.com
Add-MailboxPermission user@contoso.com -User manager@contoso.com -AccessRights FullAccess -InheritanceType All -AutoMapping $false
Set-Mailbox user@contoso.com -Type Shared
Set-MgUserLicense -UserId user@contoso.com -RemoveLicenses (Get-MgUserLicenseDetail -UserId user@contoso.com).SkuId -AddLicenses @()
```
Hold first, licence removal last — but the last two lines are mutually exclusive endings, pick one:
- **Keep the account** as a shared-mailbox anchor (`Set-Mailbox -Type Shared`): you must **keep an Exchange Online Plan 2 licence**. A shared mailbox on litigation hold is not licence-free, so drop the `Set-MgUserLicense` line.
- **Delete the account** (`Remove-MgUser -UserId user@contoso.com`) once the hold is on: the held mailbox becomes an *inactive mailbox*, needs no licence, and is retained for the hold's duration.

A mailbox only becomes inactive when the account or mailbox is **deleted** — disabling and converting to shared never does. An unheld mailbox is purged 30 days after delicensing.

### Grant the manager access to the leaver's OneDrive
```powershell
Connect-PnPOnline -Url ("https://contoso-my.sharepoint.com/personal/" + ("user@contoso.com" -replace '[.@]','_')) -Interactive -ClientId <your-app-client-id>
Add-PnPSiteCollectionAdmin -Owners manager@contoso.com
```
`Add-PnPSiteCollectionAdmin` acts on the currently connected site — there is no `-Url` on it.

### Remove the leaver from every team
```powershell
Get-Team -User user@contoso.com | ForEach-Object { Remove-TeamUser -GroupId $_.GroupId -User user@contoso.com }
```
Fails silently-ish on teams where they are the last owner; add another owner first.

### Remove the leaver from every group
```powershell
$id = (Get-MgUser -UserId user@contoso.com).Id
Get-MgUserMemberOf -UserId $id -All | Where-Object { $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.group' } | ForEach-Object { Remove-MgGroupMemberDirectoryObjectByRef -GroupId $_.Id -DirectoryObjectId $id }
```
Dynamic groups and on-cloud mail-enabled security groups reject this — expect errors on those rows and ignore them.

### Confirm the conversion and that the hold stuck
```powershell
Get-EXOMailbox -Identity user@contoso.com -PropertySets Minimum,Hold | Select-Object RecipientTypeDetails,LitigationHoldEnabled,LitigationHoldDate
```

### List inactive mailboxes (the delete-the-account path only)
```powershell
Get-EXOMailbox -InactiveMailboxOnly -ResultSize Unlimited -Properties WhenSoftDeleted | Select-Object DisplayName,PrimarySmtpAddress,WhenSoftDeleted
```
`WhenSoftDeleted` is outside the default Minimum property set — request it explicitly or the column comes back empty.

## Licence inventory and waste

### Report purchased vs consumed per SKU
```powershell
Get-MgSubscribedSku -All | Select-Object SkuPartNumber,ConsumedUnits,@{n='Purchased';e={$_.PrepaidUnits.Enabled}},@{n='Unused';e={$_.PrepaidUnits.Enabled - $_.ConsumedUnits}} | Sort-Object Unused -Descending
```

### Find licensed users who have not signed in for 90 days
```powershell
Get-MgUser -All -Property Id,DisplayName,UserPrincipalName,AssignedLicenses,SignInActivity | Where-Object { $_.AssignedLicenses.Count -gt 0 -and ($null -eq $_.SignInActivity.LastSignInDateTime -or $_.SignInActivity.LastSignInDateTime -lt (Get-Date).AddDays(-90)) } | Select-Object DisplayName,UserPrincipalName,@{n='LastSignIn';e={$_.SignInActivity.LastSignInDateTime}}
```
`signInActivity` is never returned by default, needs the `AuditLog.Read.All` scope and an Entra ID P1 licence, and is blank for accounts that never attempted a sign-in.

### Find disabled users still holding licences
```powershell
Get-MgUser -All -Filter 'accountEnabled eq false' -Property Id,DisplayName,UserPrincipalName,AssignedLicenses | Where-Object { $_.AssignedLicenses.Count -gt 0 } | Select-Object DisplayName,UserPrincipalName
```

### Export every licence assignment with the SKU name resolved
```powershell
$skuName = @{}; Get-MgSubscribedSku -All | ForEach-Object { $skuName[$_.SkuId] = $_.SkuPartNumber }
Get-MgUser -All -Property Id,UserPrincipalName,AccountEnabled,AssignedLicenses | ForEach-Object { $u = $_; $u.AssignedLicenses | ForEach-Object { [pscustomobject]@{ UserPrincipalName = $u.UserPrincipalName; Enabled = $u.AccountEnabled; Sku = $skuName[$_.SkuId] } } } | Export-Csv ./licences.csv -NoTypeInformation
```
Pivot the CSV on `Sku` + `Enabled` for the spend-on-disabled-accounts number.

## Tenant-wide permission audit

### Export every explicit mailbox delegate
```powershell
Get-EXOMailboxPermission -ResultSize Unlimited | Where-Object { $_.User -notlike 'NT AUTHORITY\*' -and -not $_.IsInherited } | Select-Object Identity,User,AccessRights | Export-Csv ./fullaccess.csv -NoTypeInformation
```
With no `-Identity` this runs across the whole tenant in one call — do not loop `Get-EXOMailbox` into it.

### Export every Send As permission
```powershell
Get-EXORecipientPermission -ResultSize Unlimited | Where-Object Trustee -ne 'NT AUTHORITY\SELF' | Select-Object Identity,Trustee,AccessRights | Export-Csv ./sendas.csv -NoTypeInformation
```

### Find calendars shared with Default or Anonymous
```powershell
Get-EXOMailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox | ForEach-Object { Get-EXOMailboxFolderPermission -Identity "$($_.PrimarySmtpAddress):\Calendar" -ErrorAction SilentlyContinue } | Where-Object { $_.User.ToString() -in 'Default','Anonymous' -and $_.AccessRights -notcontains 'None' }
```
The folder name is localised — this misses mailboxes whose Calendar folder is named in another language.

### List every guest account
```powershell
Get-MgUser -All -Filter "userType eq 'Guest'" -Property Id,DisplayName,Mail,CreatedDateTime,ExternalUserState,AccountEnabled | Select-Object DisplayName,Mail,ExternalUserState,CreatedDateTime | Export-Csv ./guests.csv -NoTypeInformation
```
`ExternalUserState` of `PendingAcceptance` means the invitation was never redeemed — usually safe to clean up.

### Map every guest to what they can reach
```powershell
Get-MgUser -All -Filter "userType eq 'Guest'" | ForEach-Object { $g = $_; Get-MgUserMemberOf -UserId $g.Id -All | ForEach-Object { [pscustomobject]@{ Guest = $g.Mail; Resource = $_.AdditionalProperties['displayName']; Type = $_.AdditionalProperties['@odata.type'] } } } | Export-Csv ./guest-access.csv -NoTypeInformation
```
Covers group and team membership only; per-site and per-file shares need the SharePoint recipes below.

### List external users known to SharePoint
```powershell
Get-PnPExternalUser -PageSize 50
```
Returns 50 at a time — page with `-Position`, or scope to one site with `-SiteUrl "https://contoso.sharepoint.com/sites/Marketing"`.

### List sites where external sharing is on
```powershell
Get-PnPTenantSite -Detailed | Where-Object SharingCapability -ne 'Disabled' | Select-Object Url,SharingCapability,Template
```
Without `-Detailed`, `SharingCapability` is a default placeholder rather than the site's real setting. Add `-IncludeOneDriveSites` to pull personal sites in too.

### Find sharing links created in the last 30 days
```powershell
Search-UnifiedAuditLog -StartDate (Get-Date).AddDays(-30) -EndDate (Get-Date) -Operations SharingSet,AnonymousLinkCreated,SharingInvitationCreated -SessionId "sharing-audit" -SessionCommand ReturnLargeSet -ResultSize 5000
```
Re-run the identical command with the same `SessionId` until it returns zero rows; results are unsorted and can contain duplicates.

## Storage reports

### Export mailbox sizes
```powershell
Get-EXOMailbox -ResultSize Unlimited | ForEach-Object { Get-EXOMailboxStatistics -Identity $_.Identity -Properties DisplayName,TotalItemSize,ItemCount } | Select-Object DisplayName,TotalItemSize,ItemCount | Export-Csv ./mailbox-sizes.csv -NoTypeInformation
```
`TotalItemSize` is a formatted string, not a number — sort on `TotalItemSize.Value.ToBytes()` if you need real ordering.

### Export mailbox and site storage from the usage reports
```powershell
Get-MgReportMailboxUsageDetail -Period D30 -OutFile ./mailbox-usage.csv
Get-MgReportSharePointSiteUsageDetail -Period D30 -OutFile ./site-usage.csv
```
`-OutFile` is mandatory; these write CSV directly rather than emitting objects. Names come back as GUIDs unless report anonymisation is turned off in the M365 admin centre.

## Governance reports

### Find ownerless groups and teams
```powershell
Get-MgGroup -All -Filter "groupTypes/any(c:c eq 'Unified')" -Property Id,DisplayName,Mail,ResourceProvisioningOptions | Where-Object { -not (Get-MgGroupOwner -GroupId $_.Id -Top 1) } | Select-Object DisplayName,Mail,@{n='IsTeam';e={ $_.AdditionalProperties['resourceProvisioningOptions'] -contains 'Team' }}
```
One `Get-MgGroupOwner` call per group — expect this to be slow and throttled on a large tenant.

### Export authentication method registration
```powershell
Get-MgReportAuthenticationMethodUserRegistrationDetail -All | Select-Object UserPrincipalName,IsAdmin,IsMfaRegistered,IsMfaCapable,IsPasswordlessCapable,@{n='Methods';e={$_.MethodsRegistered -join ';'}} | Export-Csv ./mfa-registration.csv -NoTypeInformation
```
Needs `AuditLog.Read.All`. `IsMfaCapable` (a registered method usable for MFA) is the number to report on, not `IsMfaRegistered`.

### List admins without a strong method
```powershell
Get-MgReportAuthenticationMethodUserRegistrationDetail -All | Where-Object { $_.IsAdmin -and -not $_.IsMfaCapable } | Select-Object UserPrincipalName,@{n='Methods';e={$_.MethodsRegistered -join ';'}}
```

## Export patterns

### Write a report to CSV
```powershell
Get-EXOMailbox -ResultSize Unlimited -PropertySets Minimum | Export-Csv ./mailboxes.csv -NoTypeInformation -Encoding utf8
```
`-NoTypeInformation` is the default in PowerShell 7 but not in Windows PowerShell 5.1 — always pass it so the file is the same either way.

### Join data from two modules with a hashtable lookup
```powershell
$dept = @{}; Get-MgUser -All -Property UserPrincipalName,Department | ForEach-Object { $dept[$_.UserPrincipalName] = $_.Department }
Get-EXOMailbox -ResultSize Unlimited | Select-Object DisplayName,PrimarySmtpAddress,@{n='Department';e={ $dept[$_.PrimarySmtpAddress] }} | Export-Csv ./mailboxes-by-dept.csv -NoTypeInformation
```
One pass per source instead of a `Where-Object` inside a loop. Key on UPN only when UPN and primary SMTP actually match in your tenant.

### Collect rows without `+=`
```powershell
$rows = foreach ($m in Get-EXOMailbox -ResultSize Unlimited) { [pscustomobject]@{ Name = $m.DisplayName; Smtp = $m.PrimarySmtpAddress } }
```
`$rows += $row` rebuilds the entire array on every iteration — quadratic, and the usual reason a 20,000-mailbox script never finishes. Capture the loop's output as above, or use `[System.Collections.Generic.List[object]]::new()` and `.Add()` when you must append conditionally.

### Bulk change from a CSV with a dry run and per-row error capture
```powershell
$failures = [System.Collections.Generic.List[object]]::new()
foreach ($r in Import-Csv ./users.csv) {
  try   { Update-MgUser -UserId $r.UserPrincipalName -Department $r.Department -JobTitle $r.JobTitle -ErrorAction Stop -WhatIf }
  catch { $failures.Add([pscustomobject]@{ Row = $r.UserPrincipalName; Error = $_.Exception.Message }) }
}
$failures | Export-Csv ./failures.csv -NoTypeInformation
```
Drop `-WhatIf` to run for real. `-ErrorAction Stop` is what makes `catch` fire at all — without it most cmdlets emit a non-terminating error and the loop sails past. `Add-TeamUser` and `Remove-TeamUser` have no `-WhatIf`; dry-run those by printing the intended change instead.

## Scheduling and unattended runs

None of this runs on a timer as written. Interactive MFA sign-in requires a human and a browser, and cached tokens expire, so a scheduled task or runbook using `Connect-ExchangeOnline -UserPrincipalName ...` or a bare `Connect-MgGraph` will hang or fail. The supported answer is app-only authentication: register an Entra ID application, give it a certificate and the application permissions (or Exchange/SharePoint admin roles) the job needs, and connect with `-AppId`/`-ClientId`, `-CertificateThumbprint` and `-Organization`/`-TenantId`. Every one of these five modules supports that path; managed identity is the equivalent when the job runs in Azure Automation.

## Gotchas

- No single sign-in: each workload needs its own `Connect-*` in the same session, and its own disconnect. `Get-PSSession` sees none of them — use `Get-ConnectionInformation`, `Get-MgContext`, `Get-PnPConnection`, `Get-CsTenant`, `Get-SPOTenant`.
- Graph `-Scopes` is consent, not authorisation. You still need the matching Entra role (User Administrator, Exchange Administrator, SharePoint Administrator, Teams Administrator) or the call fails with 403 despite the scope.
- Exchange Online REST calls time out server-side at 15 minutes. Batch anything tenant-wide and re-connect between batches rather than one giant pipeline.
- Exchange cmdlets default to `-ResultSize 1000`. Forgetting `-ResultSize Unlimited` silently truncates a report to the first thousand rows with no warning.
- `Get-MgUser` returns a small default property set and only the first 100 objects. Always pass `-All`, and name what you need in `-Property` — `Department`, `SignInActivity`, `AssignedLicenses` are all absent by default.
- Prefer `Get-EXO*` over `Get-Mailbox`/`Get-Recipient` for bulk reads and control output with `-Properties`; never use `-PropertySets All`.
- Throttling shows up as slow calls, not errors. Per-object loops (`Get-MgGroupOwner` per group, `Get-EXOMailboxStatistics` per mailbox) are the usual culprit — cache into a hashtable and reuse.
- Delegate audits miss folder-level rights. `Get-EXOMailboxPermission` covers Full Access only; calendar and inbox delegates live in `Get-EXOMailboxFolderPermission`.
- `Set-Mailbox -Type Shared` on a mailbox over 50 GB, one with an archive, or one on litigation hold still needs a licence (Plan 2 for the hold) — check all three before delicensing.
- Graph usage reports return anonymised GUIDs for user and site names unless an admin disables concealment in the M365 admin centre; the report cmdlets give no hint that this happened.
- `Connect-IPPSSession` (Purview) does not work in PowerShell 7 on macOS or Linux, and `Microsoft.Online.SharePoint.PowerShell` cannot be installed there at all. Reach SharePoint via PnP or Graph, and run compliance work from Windows.
- MSOnline and AzureAD are retired and unlisted on the Gallery. Anything you inherit that calls `Get-MsolUser` or `Connect-AzureAD` must move to `Microsoft.Graph` or `Microsoft.Entra`.
