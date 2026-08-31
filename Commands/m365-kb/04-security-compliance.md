# Security & Compliance (Purview)

`ExchangeOnlineManagement` 3.10.1 — `Connect-IPPSSession -UserPrincipalName admin@contoso.onmicrosoft.com`

## Connecting

### Connect to Security & Compliance PowerShell
```powershell
Connect-IPPSSession -UserPrincipalName admin@contoso.onmicrosoft.com
```
Same module and same package as Exchange Online, but a separate endpoint: `Connect-ExchangeOnline` does not give you `Get-Label`, `New-ComplianceSearch` or `Get-DlpCompliancePolicy`.

### Connect for content search, eDiscovery and purge cmdlets
```powershell
Connect-IPPSSession -UserPrincipalName admin@contoso.onmicrosoft.com -EnableSearchOnlySession
```
Required (module 3.9.0+) for `*-ComplianceSearch`, `*-ComplianceSearchAction -Purge`, `*-ComplianceCase`. Without it those cmdlets fail or are missing.

### Connect to Exchange Online and Purview in the same session
```powershell
Connect-ExchangeOnline -UserPrincipalName admin@contoso.onmicrosoft.com -ShowBanner:$false; Connect-IPPSSession -UserPrincipalName admin@contoso.onmicrosoft.com -Prefix SCC
```
`-Prefix SCC` renames the imported SCC cmdlets to `Get-SCCLabel`, `Get-SCCComplianceSearch` and so on, so they can't silently collide with Exchange cmdlets of the same name.

### See which connections are open
```powershell
Get-ConnectionInformation | Format-Table ConnectionId,ConnectionUri,UserPrincipalName,ModulePrefix,TokenStatus
```

### Disconnect
```powershell
Disconnect-ExchangeOnline -Confirm:$false
```
There is no `Disconnect-IPPSSession`. Add `-ConnectionId <id>` from `Get-ConnectionInformation` to drop only the SCC connection.

## Audit log search

`Search-UnifiedAuditLog` is **not deprecated** — it is still the documented cmdlet, but it lives in **Exchange Online** PowerShell, so connect with `Connect-ExchangeOnline`, not `Connect-IPPSSession`.

### Search the audit log for one user
```powershell
Search-UnifiedAuditLog -StartDate (Get-Date).AddDays(-7) -EndDate (Get-Date) -UserIds user@contoso.com -ResultSize 5000
```
Dates are UTC. Default `-ResultSize` is 100, maximum 5000 in a single non-paged call.

### Filter by record type and operation
```powershell
Search-UnifiedAuditLog -StartDate "2026-08-01" -EndDate "2026-08-26" -RecordType ExchangeAdmin -Operations "Set-Mailbox","Add-MailboxPermission" -Formatted
```
`-Formatted` turns integer RecordType/Operation values into strings and makes AuditData readable.

### Page through a large result set
```powershell
$sid = [guid]::NewGuid().ToString(); $all = @()
do {
  $page = Search-UnifiedAuditLog -StartDate (Get-Date).AddDays(-30) -EndDate (Get-Date) -RecordType SharePointFileOperation -SessionId $sid -SessionCommand ReturnLargeSet -ResultSize 5000
  $all += $page
} while ($page.Count -gt 0)
$all = $all | Sort-Object Identity -Unique
```
`ReturnLargeSet` caps at 50,000 records per session and returns unsorted, duplicate-prone pages — always de-duplicate. Never mix `ReturnLargeSet` and `ReturnNextPreviewPage` on one SessionId or you are capped at 10,000.

### Expand the AuditData JSON
```powershell
$all | ForEach-Object { $_.AuditData | ConvertFrom-Json } | Select-Object CreationTime,UserId,Operation,ClientIP,ObjectId
```
Everything interesting (IP, target object, result status) is inside `AuditData`; the top-level columns are just an index.

### Export audit results to CSV
```powershell
$all | Select-Object CreationDate,UserIds,Operations,RecordType,AuditData | Export-Csv C:\Temp\audit.csv -NoTypeInformation -Encoding UTF8
```
The record property is `CreationDate`; `CreationTime` exists only inside the nested `AuditData` JSON.

### Run an audit search through the Purview Audit Search Graph API instead
```powershell
Connect-MgGraph -Scopes "AuditLogsQuery.Read.All" -NoWelcome
$q = New-MgBetaSecurityAuditLogQuery -DisplayName "Phish IR" -FilterStartDateTime (Get-Date).AddDays(-7) -FilterEndDateTime (Get-Date) -UserPrincipalNameFilters "user@contoso.com"
Get-MgBetaSecurityAuditLogQuery -AuditLogQueryId $q.Id | Select-Object Status
Get-MgBetaSecurityAuditLogQueryRecord -AuditLogQueryId $q.Id -All
```
**Beta only**: the Graph PowerShell SDK ships these solely in `Microsoft.Graph.Beta.Security` — there is no v1.0 `Get-MgSecurityAuditLogQuery`. Asynchronous: poll `Status` until `succeeded` before reading records.

## Content search and purge

Classic Content Search and classic eDiscovery (Standard/Premium) in the portal retired 31 August 2025. The `*-ComplianceSearch` cmdlets still work for search-and-purge; `-Preview` and `-Export` search actions are no longer functional in the cloud.

### List content searches and their status
```powershell
Get-ComplianceSearch | Format-Table Name,Status,ItemCount,Size -AutoSize
```

### Create a search for a phishing message across all mailboxes
```powershell
New-ComplianceSearch -Name "Remove Phishing Message" -ExchangeLocation All -ContentMatchQuery '(Received:8/25/2026..8/26/2026) AND (Subject:"Update your account information")'
```
KQL only; the query must not include SharePoint or OneDrive locations or the purge action later fails.

### Run the search and wait for it
```powershell
Start-ComplianceSearch -Identity "Remove Phishing Message"; do { Start-Sleep 10; $s = Get-ComplianceSearch "Remove Phishing Message" } until ($s.Status -eq "Completed"); $s | Format-List ItemCount,Size,Status
```

### See per-mailbox hit counts
```powershell
(Get-ComplianceSearch "Remove Phishing Message").SuccessResults -split "`r`n" | Where-Object { $_ -notmatch "Item count: 0" }
```

### Purge the message from every mailbox (recoverable)
```powershell
New-ComplianceSearchAction -SearchName "Remove Phishing Message" -Purge -PurgeType SoftDelete
```
Maximum **10 items per mailbox** and 50,000 mailboxes per search — this is an incident-response tool, not mailbox cleanup. Re-run the search and confirm `ItemCount` before purging.

### Purge permanently
```powershell
New-ComplianceSearchAction -SearchName "Remove Phishing Message" -Purge -PurgeType HardDelete -Confirm:$false
```
Items go to Purges and are unrecoverable by the user; with single item recovery on they survive until the deleted item retention period expires.

### Track the purge
```powershell
Get-ComplianceSearchAction -Identity "Remove Phishing Message_Purge" -Details | Format-List Status,Results
```
The action object is always named `<SearchName>_Purge`.

### Purge more than 10 items per location
Use the Graph eDiscovery API `ediscoverySearch: purgeData` (100 items per location) — `Clear-MgSecurityCaseEdiscoveryCaseSearchData` in the `Microsoft.Graph.Security` module.

### Delete a search when the incident is closed
```powershell
Remove-ComplianceSearch -Identity "Remove Phishing Message" -Confirm:$false
```

## eDiscovery cases and holds

### List cases
```powershell
Get-ComplianceCase | Format-Table Name,CaseType,Status,CreatedDateTime -AutoSize
```

### Create an eDiscovery Premium case
```powershell
New-ComplianceCase -Name "Coho-2026-08" -CaseType AdvancedEdiscovery -ExternalId "SaraDavis v. Coho Winery"
```
Omit `-CaseType` for an eDiscovery Standard case. Avoid spaces in `-Name` if you will attach searches with `New-ComplianceSearch -Case`.

### List case hold policies with real distribution status
```powershell
Get-CaseHoldPolicy -Case "Coho-2026-08" -DistributionDetail | Format-List Name,Enabled,DistributionStatus,ExchangeLocation,SharePointLocation
```
Without `-DistributionDetail` the location and status properties come back empty.

### Add several mailboxes to an existing hold
```powershell
Set-CaseHoldPolicy -Identity "Coho Hold" -AddExchangeLocation "user@contoso.com","admin@contoso.com"
```
One call with all users — repeating `Set-CaseHoldPolicy` in a loop triggers a full policy sync each time and causes distribution errors.

### Retry a hold stuck in Pending
```powershell
Set-CaseHoldPolicy -Identity "Coho Hold" -RetryDistribution
```

### Find every hold on a mailbox or a site
```powershell
Invoke-HoldRemovalAction -Action GetHolds -ExchangeLocation user@contoso.com
```
Swap for `-SharePointLocation https://contoso.sharepoint.com/sites/Marketing` for sites. `-Action RemoveHold -HoldId <id>` removes one; only Compliance Administrator can.

### Check mailbox-level and org-wide holds (Exchange Online session)
```powershell
Get-Mailbox user@contoso.com | Format-List LitigationHoldEnabled,InPlaceHolds,ComplianceTagHoldApplied,DelayHoldApplied,DelayReleaseHoldApplied
Get-OrganizationConfig | Select-Object -ExpandProperty InPlaceHolds
```
Prefixes: `mbx` = mailbox retention policy (also Teams 1:N chats), `grp` = M365 group (also Teams channel messages), `skp` = Skype for Business conversations, `UniH` = eDiscovery hold, `cld` = In-Place Hold (a bare GUID with no prefix is one too), `-mbx` = excluded from an org-wide policy.

### Resolve an InPlaceHolds GUID to a policy name
```powershell
Get-RetentionCompliancePolicy -Identity 7cfb30345d454ac0a989ab3041051209 | Format-List Name,Mode
```
Strip the `mbx`/`skp`/`grp` prefix and the `:1`/`:2`/`:3` action suffix first.

## Retention

### List retention policies with the locations they actually cover
```powershell
Get-RetentionCompliancePolicy -DistributionDetail | Format-List Name,Enabled,Mode,DistributionStatus,ExchangeLocation,SharePointLocation
```
Without `-DistributionDetail` the `Workload` column lists every workload regardless of what the policy targets, and Location is empty.

### Show the rule (duration and action) behind a policy
```powershell
Get-RetentionComplianceRule -Policy "Regulation 123 Compliance" | Format-List Name,RetentionDuration,RetentionComplianceAction,ExpirationDateOption
```

### Create a retention policy and its rule
```powershell
New-RetentionCompliancePolicy -Name "Finance 7yr" -ExchangeLocation All -SharePointLocation "https://contoso.sharepoint.com/sites/Marketing" -Enabled $true
New-RetentionComplianceRule -Name "Finance 7yr rule" -Policy "Finance 7yr" -RetentionDuration 2555 -RetentionComplianceAction KeepAndDelete
```
A policy does nothing until a rule is attached, and a retention policy accepts exactly one rule.

### List retention labels
```powershell
Get-ComplianceTag | Format-Table Name,RetentionDuration,RetentionAction,IsRecordLabel,Policy -AutoSize
```

### List retention label (publishing) policies
```powershell
Get-RetentionCompliancePolicy -DistributionDetail -RetentionRuleTypes | Where-Object { -not $_.RetentionRuleTypes } | Format-Table Name,Enabled
Get-AppRetentionCompliancePolicy -DistributionDetail | Format-Table Name,Enabled,Mode -AutoSize
```
Use the `*-AppRetentionCompliance*` cmdlets for adaptive scopes and for Teams chats, Teams channels, Viva Engage and Copilot locations; `*-RetentionCompliance*` covers Exchange and SharePoint.

### Confirm retention label storage is enabled
```powershell
Get-ComplianceTagStorage | Format-List Enabled,DistributionStatus
```
`Enabled: True` / `DistributionStatus: Success` means `Enable-ComplianceTagStorage` has already been run — it is a one-time tenant operation.

## Sensitivity labels

### List labels
```powershell
Get-Label | Format-Table DisplayName,Name,Priority,ContentType,Disabled -AutoSize
```
On tenants with more than ~1000 labels add `-SkipValidations` or the call times out.

### Show every setting on one label
```powershell
Get-Label -Identity "Confidential" | Format-List DisplayName,Priority,Tooltip,ContentType,EncryptionEnabled,LabelActions,Settings
```

### List label policies and the labels each publishes
```powershell
Get-LabelPolicy | Select-Object Name,Enabled,@{n="Labels";e={$_.Labels -join ", "}},ExchangeLocation
```

### Publish a new label policy
```powershell
New-LabelPolicy -Name "Sales" -Labels "Confidential","Confidential\Internal" -ExchangeLocation "Sales Team"
```
There is no separate publish step — creating the policy publishes it.

### Add a label to an already published policy
```powershell
Set-LabelPolicy -Identity "Sales" -AddLabels "Highly Confidential"
```
Never pipe a list into `Set-LabelPolicy` with `ForEach-Object` when adding or removing locations; pass all values in one call.

## DLP

### List DLP policies
```powershell
Get-DlpCompliancePolicy | Format-Table Name,Mode,Enabled,ExchangeLocation,SharePointLocation -AutoSize
```

### Show the rules inside one policy
```powershell
Get-DlpComplianceRule -Policy "Credit card data" | Format-List Name,Disabled,BlockAccess,NotifyUser,ContentContainsSensitiveInformation
```

### List sensitive information types
```powershell
Get-DlpSensitiveInformationType | Sort-Object Publisher,Name | Format-Table Name,Id,Publisher,RecommendedConfidence -AutoSize
```

### Inspect one sensitive information type in detail
```powershell
Get-DlpSensitiveInformationType -Identity "Credit Card Number" -IncludeDetails | Format-List
```

### Export DLP rule matches from Activity Explorer
```powershell
Export-ActivityExplorerData -StartTime (Get-Date).AddDays(-7) -EndTime (Get-Date) -Filter1 @("Activity","DLPRuleMatch") -Filter2 @("Workload","Exchange") -PageSize 5000 -OutputFormat Csv
```
Activity Explorer holds only 30 days. Filters combine as OR within one `-FilterN` and AND across them.

### Page through Activity Explorer results
```powershell
$r = Export-ActivityExplorerData -StartTime (Get-Date).AddDays(-7) -EndTime (Get-Date) -PageSize 5000 -OutputFormat Json
$data = $r.ResultData
while (-not $r.LastPage) {
  $r = Export-ActivityExplorerData -StartTime (Get-Date).AddDays(-7) -EndTime (Get-Date) -PageSize 5000 -OutputFormat Json -PageCookie $r.WaterMark
  $data += $r.ResultData
}
```
The `WaterMark` page cookie expires after 120 seconds — keep the loop tight and the time window small.

## Information barriers

### List IB policies and segments
```powershell
Get-InformationBarrierPolicy | Format-Table Name,State,AssignedSegment,SegmentsAllowed,SegmentsBlocked -AutoSize
Get-OrganizationSegment | Format-Table Name,UserGroupFilter,Guid -AutoSize
```

### Check the barrier between two users
```powershell
Get-ExoInformationBarrierRelationship -RecipientId1 user@contoso.com -RecipientId2 admin@contoso.com
```
This is the Exchange Online cmdlet and the one to use in non-legacy IB mode; `Get-InformationBarrierRecipientStatus` in the SCC session only works in legacy mode.

### Apply pending IB changes and check progress
```powershell
Start-InformationBarrierPoliciesApplication; Get-InformationBarrierPoliciesApplicationStatus
```
Application is user-by-user and takes roughly an hour per 5,000 accounts.

## Alerts

### List alert policies
```powershell
Get-ProtectionAlert | Format-Table Name,Category,Severity,Disabled,ThreatType,NotifyUser -AutoSize
```

### Show one alert policy in full
```powershell
Get-ProtectionAlert -Identity "Content search deleted" | Format-List
```

### Disable a custom alert policy
```powershell
Set-ProtectionAlert -Identity "Mass download by a single user" -Disabled $true
```
`Set-ProtectionAlert` only works on policies created with `New-ProtectionAlert`; built-in default alert policies cannot be edited from PowerShell.

## Exporting results

### Export any Purview object list to CSV
```powershell
Get-DlpCompliancePolicy | Select-Object Name,Mode,Enabled,WhenCreatedUTC,WhenChangedUTC | Export-Csv C:\Temp\dlp-policies.csv -NoTypeInformation -Encoding UTF8
```

### Flatten multi-valued properties before exporting
```powershell
Get-RetentionCompliancePolicy -DistributionDetail | Select-Object Name,Enabled,Mode,@{n="Exchange";e={$_.ExchangeLocation -join ";"}},@{n="SharePoint";e={$_.SharePointLocation -join ";"}} | Export-Csv C:\Temp\retention.csv -NoTypeInformation
```
Multi-valued properties export as `System.Object[]` unless you join them yourself.

## Gotchas

- `Connect-IPPSSession` does **not** work in PowerShell 7 on macOS or Linux — Windows PowerShell 5.1 or PowerShell 7 on Windows only. It also has no `-Device` device-code switch.
- SCC cmdlets do not exist until you connect; you cannot inspect them with `Get-Command` offline, and `Get-Help` is empty unless you connect Exchange Online with `-LoadCmdletHelp`.
- Purview RBAC is separate from Exchange RBAC. Being in Exchange **Organization Management** does not grant Search And Purge — the symptom is `A parameter can't be found that matches parameter name 'Purge'`.
- Forgetting `-EnableSearchOnlySession` makes `New-ComplianceSearch`, `New-ComplianceCase` and purge actions fail with confusing "cmdlet not found" style errors.
- `Search-UnifiedAuditLog` is an Exchange Online cmdlet, not an SCC one, and audit records take 60–90 minutes to appear. Its `ReturnLargeSet` pages are unsorted and contain duplicates.
- Audit search dates without a time component default to 00:00 UTC, so a same-day StartDate and EndDate returns nothing.
- `-DistributionDetail` is mandatory for truthful output from `Get-RetentionCompliancePolicy`, `Get-AppRetentionCompliancePolicy` and `Get-CaseHoldPolicy`; without it Location is empty and DistributionStatus is stale.
- Purge removes at most 10 items per mailbox, skips unindexed items, skips Teams messages, and does nothing useful on a mailbox under litigation hold.
- `Get-CaseHoldRule` with no parameters times out in large tenants; scope it with `-Policy`.
- Policy changes (retention, labels, DLP, IB) distribute asynchronously — expect up to 24 hours before `Get-*` reflects reality in a client.
- `Get-Label` and `Get-CaseHoldPolicy` truncate multi-valued properties in table output; pipe to `Format-List` or `Select-Object -ExpandProperty`.
- Repeated single-item `Set-CaseHoldPolicy` / `Set-LabelPolicy` calls in a loop each trigger a full sync and get throttled; batch the values into one call.
