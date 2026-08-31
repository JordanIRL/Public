# Exchange Online

Module `ExchangeOnlineManagement` 3.10.1 — `Connect-ExchangeOnline -UserPrincipalName admin@contoso.onmicrosoft.com -ShowBanner:$false`

## Session

### Connect
```powershell
Connect-ExchangeOnline -UserPrincipalName admin@contoso.onmicrosoft.com -ShowBanner:$false
```
Interactive MFA sign-in uses a Microsoft first-party app — no app registration needed. Requires Windows PowerShell 5.1 or PowerShell 7.6.0+ (raised from 7.4.0 in module 3.10.0).

### Load only the cmdlets you need
```powershell
Connect-ExchangeOnline -UserPrincipalName admin@contoso.onmicrosoft.com -CommandName Get-Mailbox,Set-Mailbox,Get-EXOMailbox -ShowBanner:$false
```
Cuts import time and memory; repeated connect/disconnect cycles in one session leak memory.

### Get cmdlet help working
```powershell
Connect-ExchangeOnline -UserPrincipalName admin@contoso.onmicrosoft.com -LoadCmdletHelp -ShowBanner:$false
```
Since 3.7.0 help is not loaded by default, so `Get-Help Get-Mailbox` returns nothing useful without this.

### Verify and disconnect
```powershell
Get-ConnectionInformation; Disconnect-ExchangeOnline -Confirm:$false
```
`Get-PSSession` does not see REST connections. Use `-ConnectionId <id>` on disconnect to close one of several.

### Sign in without a browser
```powershell
Connect-ExchangeOnline -UserPrincipalName admin@contoso.onmicrosoft.com -Device -ShowBanner:$false
```
Add `-DisableWAM` (3.7.2+) if the Windows broker hangs on a jump box or scheduled task.

## Recipients and mailboxes

### List every mailbox
```powershell
Get-EXOMailbox -ResultSize Unlimited | Select-Object DisplayName,PrimarySmtpAddress,RecipientTypeDetails
```
Default `ResultSize` is 1000 on every recipient cmdlet — omitting `-ResultSize Unlimited` silently truncates.

### Get a mailbox with non-default properties
```powershell
Get-EXOMailbox -Identity user@contoso.com -PropertySets Delivery,Hold -Properties WhenCreated | Format-List
```
`Get-EXO*` returns only the Minimum property set by default. Sets for `Get-EXOMailbox`: AddressList, Archive, Audit, Custom, Delivery, Hold, Moderation, Move, Policy, PublicFolder, Quota, Resource, Retention, SCL, SoftDelete, StatisticsSeed.

### Filter mailboxes server-side
```powershell
Get-EXOMailbox -ResultSize Unlimited -RecipientTypeDetails SharedMailbox -Filter "Office -eq 'London'"
```
`-Filter` is evaluated on the server; `Where-Object` pulls every object first and is far slower.

### Search by name fragment
```powershell
Get-EXOMailbox -Anr "smith" | Select-Object DisplayName,PrimarySmtpAddress
```

### List all recipient objects, not just mailboxes
```powershell
Get-EXORecipient -ResultSize Unlimited | Group-Object RecipientTypeDetails -NoElement | Sort-Object Count -Descending
```

### Mailbox size and item count
```powershell
Get-EXOMailboxStatistics -Identity user@contoso.com | Select-Object DisplayName,ItemCount,TotalItemSize,TotalDeletedItemSize
```
Only two property sets exist here: Minimum and All.

### Size report for every mailbox
```powershell
Get-EXOMailbox -ResultSize Unlimited | ForEach-Object { Get-EXOMailboxStatistics -Identity $_.PrimarySmtpAddress | Select-Object DisplayName,ItemCount,TotalItemSize } | Export-Csv ./mailbox-sizes.csv -NoTypeInformation
```
`TotalItemSize` is a formatted string; sort on `$_.TotalItemSize.Value.ToBytes()` if you need numeric order.

### Find soft-deleted mailboxes
```powershell
Get-EXOMailbox -SoftDeletedMailbox -ResultSize Unlimited -PropertySets SoftDelete | Select-Object DisplayName,PrimarySmtpAddress,WhenSoftDeleted
```
Soft-deleted mailboxes are recoverable for 30 days.

### Find inactive (on-hold, licence-removed) mailboxes
```powershell
Get-EXOMailbox -InactiveMailboxOnly -ResultSize Unlimited | Select-Object DisplayName,PrimarySmtpAddress
```
Add `-IncludeInactiveMailbox` to a normal query to see active and inactive together.

## Mailbox settings

### Add an alias
```powershell
Set-Mailbox -Identity user@contoso.com -EmailAddresses @{Add="alias@contoso.com"}
```
`@{Add=}` / `@{Remove=}` edits the multivalued property in place; passing a bare list replaces every address.

### List all proxy addresses
```powershell
Get-EXOMailbox -Identity user@contoso.com | Select-Object -ExpandProperty EmailAddresses
```
Uppercase `SMTP:` is the primary; lowercase `smtp:` are aliases.

### Change the primary SMTP address
```powershell
Set-Mailbox -Identity user@contoso.com -WindowsEmailAddress newname@contoso.com
```
The previous primary is kept as an alias so mail to it still delivers.

### Change display name and alias
```powershell
Set-Mailbox -Identity user@contoso.com -DisplayName "Jane Smith" -Alias jsmith
```

### Hide from the address list
```powershell
Set-Mailbox -Identity user@contoso.com -HiddenFromAddressListsEnabled $true
```
Can take a few hours to propagate to Outlook's cached offline address book.

### Set language and time zone
```powershell
Set-MailboxRegionalConfiguration -Identity user@contoso.com -Language en-GB -TimeZone "GMT Standard Time" -LocalizeDefaultFolderName
```
Without `-LocalizeDefaultFolderName` the default folders keep their old-language names.

### Enable the archive mailbox
```powershell
Enable-Mailbox -Identity user@contoso.com -Archive
```

### Enable archives for everyone who lacks one
```powershell
Get-Mailbox -ResultSize Unlimited -Filter "ArchiveStatus -eq 'None' -and RecipientTypeDetails -eq 'UserMailbox'" | Enable-Mailbox -Archive
```

### Turn on auto-expanding archiving
```powershell
Set-OrganizationConfig -AutoExpandingArchive
```
Irreversible, org-wide, and it blocks recovery/restore of any mailbox that later becomes inactive. `Enable-Mailbox -AutoExpandingArchive` does one user and adds 10 GB of interim quota.

### Check auto-expanding archive state
```powershell
Get-OrganizationConfig | Format-List AutoExpandingArchiveEnabled
```

### Put a mailbox on litigation hold
```powershell
Set-Mailbox -Identity user@contoso.com -LitigationHoldEnabled $true -LitigationHoldDuration 2555
```
Duration is in days; omit it for an indefinite hold. Needs an Exchange Online Plan 2 (or equivalent) licence.

### Report all holds
```powershell
Get-EXOMailbox -ResultSize Unlimited -PropertySets Hold | Where-Object {$_.LitigationHoldEnabled -or $_.InPlaceHolds} | Select-Object PrimarySmtpAddress,LitigationHoldEnabled,LitigationHoldDate,InPlaceHolds
```

### Set retention hold during a leave of absence
```powershell
Set-Mailbox -Identity user@contoso.com -RetentionHoldEnabled $true -EndDateForRetentionHold (Get-Date).AddMonths(3)
```
Retention hold pauses the Managed Folder Assistant; it does not preserve deleted items — that is litigation hold.

## Permissions

### Grant Full Access
```powershell
Add-MailboxPermission -Identity shared@contoso.com -User user@contoso.com -AccessRights FullAccess -InheritanceType All -AutoMapping:$false
```
`-AutoMapping:$false` keeps the mailbox out of the user's Outlook profile automatically; changing it later requires removing and re-adding the permission.

### Remove Full Access
```powershell
Remove-MailboxPermission -Identity shared@contoso.com -User user@contoso.com -AccessRights FullAccess -Confirm:$false
```

### Grant Send As
```powershell
Add-RecipientPermission -Identity shared@contoso.com -Trustee user@contoso.com -AccessRights SendAs -Confirm:$false
```
Send As lives on the recipient, not the mailbox — `Add-MailboxPermission` cannot grant it.

### Grant Send on Behalf
```powershell
Set-Mailbox -Identity shared@contoso.com -GrantSendOnBehalfTo @{Add="user@contoso.com"}
```

### Show who has access to one mailbox
```powershell
Get-EXOMailboxPermission -Identity shared@contoso.com | Where-Object {$_.User -like '*@*'}; Get-EXORecipientPermission -Identity shared@contoso.com | Where-Object {$_.Trustee -like '*@*'}
```
Filtering on `*@*` drops the NT AUTHORITY\SELF and SYSTEM noise rows.

### Audit every delegated mailbox in the tenant
```powershell
Get-EXOMailbox -ResultSize Unlimited | ForEach-Object { Get-EXOMailboxPermission -Identity $_.PrimarySmtpAddress | Where-Object {$_.User -like '*@*' -and $_.AccessRights -contains 'FullAccess'} } | Export-Csv ./fullaccess.csv -NoTypeInformation
```
Slow on large tenants — expect throttling; batch it by department or run overnight.

### Folder-level permissions
```powershell
Get-EXOMailboxFolderPermission -Identity user@contoso.com:\Calendar
```
Identity is `mailbox:\FolderPath`; the folder name is localised, so use `Get-EXOMailboxFolderStatistics` to find the real path on non-English mailboxes.

### Give someone access to one folder
```powershell
Add-MailboxFolderPermission -Identity user@contoso.com:\Inbox -User admin@contoso.com -AccessRights Reviewer
```
Use `Set-MailboxFolderPermission` if a permission for that user already exists — `Add-` fails with "an existing permission entry was found".

### Remove a folder permission
```powershell
Remove-MailboxFolderPermission -Identity user@contoso.com:\Calendar -User admin@contoso.com -Confirm:$false
```

## Shared, room and equipment mailboxes

### Create a shared mailbox
```powershell
New-Mailbox -Shared -Name "Support" -DisplayName "Support" -PrimarySmtpAddress support@contoso.com
```
Unlicensed up to 50 GB; needs a licence beyond that or for archive/litigation hold.

### Convert between user and shared
```powershell
Set-Mailbox -Identity user@contoso.com -Type Shared
```
`-Type Regular` converts back. Remove the licence only after the conversion completes.

### Create a room and an equipment mailbox
```powershell
New-Mailbox -Room -Name "Conf Room 01"; New-Mailbox -Equipment -Name "Projector 01"
```

### Make a room auto-accept bookings
```powershell
Set-CalendarProcessing -Identity "Conf Room 01" -AutomateProcessing AutoAccept -AllowConflicts $false -BookingWindowInDays 180 -DeleteComments $false -DeleteSubject $false -AddOrganizerToSubject $false
```
New resource mailboxes default to `AutomateProcessing AutoAccept`, but the default settings strip the subject and body from the booking.

### Require delegate approval for a room
```powershell
Set-CalendarProcessing -Identity "Conf Room 01" -AutomateProcessing AutoAccept -AllBookInPolicy $false -AllRequestInPolicy $true -ResourceDelegates "admin@contoso.com"
```

### Set capacity and room metadata
```powershell
Set-Mailbox -Identity "Conf Room 01" -ResourceCapacity 12; Set-Place -Identity "Conf Room 01" -Building "HQ" -Floor 3 -City London -Capacity 12
```
`Get-Place -Type Room` lists rooms with their metadata; Room Finder relies on Building/Floor/City being populated.

### Create a room list
```powershell
New-DistributionGroup -Name "London Rooms" -RoomList; Add-DistributionGroupMember -Identity "London Rooms" -Member "Conf Room 01"
```
Only room lists (not ordinary DGs) appear in Outlook's Room Finder. List them with `Get-DistributionGroup -RecipientTypeDetails RoomList`.

## Calendar

### Set default calendar visibility for one mailbox
```powershell
Set-MailboxFolderPermission -Identity user@contoso.com:\Calendar -User Default -AccessRights LimitedDetails
```
Common values: `AvailabilityOnly`, `LimitedDetails`, `Reviewer`, `Editor`.

### Set it for every mailbox
```powershell
Get-EXOMailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox | ForEach-Object { Set-MailboxFolderPermission -Identity "$($_.PrimarySmtpAddress):\Calendar" -User Default -AccessRights LimitedDetails }
```

### Add a calendar delegate
```powershell
Add-MailboxFolderPermission -Identity user@contoso.com:\Calendar -User admin@contoso.com -AccessRights Editor -SharingPermissionFlags Delegate
```
`-SharingPermissionFlags` is only valid with `-AccessRights Editor`; without it you get a plain folder permission, not a delegate.

### List delegates
```powershell
Get-EXOMailboxFolderPermission -Identity user@contoso.com:\Calendar | Where-Object {$_.SharingPermissionFlags -match 'Delegate'}
```

### Inspect external calendar sharing policy
```powershell
Get-SharingPolicy | Format-List Name,Domains,Enabled,Default
```
`Set-SharingPolicy -Identity "Default Sharing Policy" -Domains '*:CalendarSharingFreeBusySimple'` limits external **federated** organisations to free/busy; anonymous sharing needs a separate `Anonymous:` entry, and `-Domains` replaces the whole list.

## Auto-replies (OOF)

### Read a user's automatic reply state
```powershell
Get-MailboxAutoReplyConfiguration -Identity user@contoso.com | Format-List AutoReplyState,StartTime,EndTime,ExternalAudience,InternalMessage
```

### Set an auto-reply
```powershell
Set-MailboxAutoReplyConfiguration -Identity user@contoso.com -AutoReplyState Enabled -InternalMessage "On leave, contact support@contoso.com." -ExternalMessage "Out of office." -ExternalAudience All
```
`-ExternalAudience` values: `None`, `Known` (contacts only), `All`.

### Schedule an auto-reply
```powershell
Set-MailboxAutoReplyConfiguration -Identity user@contoso.com -AutoReplyState Scheduled -StartTime "2026-09-01 09:00" -EndTime "2026-09-14 17:00" -InternalMessage "Back on the 15th."
```
`StartTime`/`EndTime` are only honoured when `AutoReplyState` is `Scheduled`.

### Turn it off
```powershell
Set-MailboxAutoReplyConfiguration -Identity user@contoso.com -AutoReplyState Disabled
```

## Forwarding

### Set SMTP forwarding to an external address
```powershell
Set-Mailbox -Identity user@contoso.com -ForwardingSmtpAddress forward@fabrikam.com -DeliverToMailboxAndForward $true
```
`ForwardingSmtpAddress` takes any SMTP address and is user-settable from OWA; `ForwardingAddress` takes an internal recipient object and is admin-only. If both are set, `ForwardingSmtpAddress` is **ignored** and mail goes only to `ForwardingAddress`.

### Clear forwarding
```powershell
Set-Mailbox -Identity user@contoso.com -ForwardingSmtpAddress $null -ForwardingAddress $null -DeliverToMailboxAndForward $false
```

### Find every mailbox with forwarding configured
```powershell
Get-EXOMailbox -ResultSize Unlimited -PropertySets Delivery | Where-Object {$_.ForwardingSmtpAddress -or $_.ForwardingAddress} | Select-Object PrimarySmtpAddress,ForwardingAddress,ForwardingSmtpAddress,DeliverToMailboxAndForward
```
The standard compromise-check. Mailbox forwarding is only half the story — also check inbox rules below.

### Find inbox rules that forward or redirect
```powershell
Get-EXOMailbox -ResultSize Unlimited | ForEach-Object { Get-InboxRule -Mailbox $_.PrimarySmtpAddress | Where-Object {$_.ForwardTo -or $_.ForwardAsAttachmentTo -or $_.RedirectTo} | Select-Object @{n='Mailbox';e={$_.MailboxOwnerId}},Name,Enabled,ForwardTo,RedirectTo }
```
Attackers hide exfiltration rules with a blank or single-character name; check `Enabled` and `Name` too.

### Block external auto-forwarding tenant-wide
```powershell
Set-HostedOutboundSpamFilterPolicy -Identity Default -AutoForwardingMode Off
```
Values are `Automatic`, `On`, `Off`. `Automatic` behaves differently in old vs new tenants — set it explicitly.

## Groups

### Create a distribution group
```powershell
New-DistributionGroup -Name "Sales Team" -PrimarySmtpAddress sales@contoso.com -Members user@contoso.com -ManagedBy admin@contoso.com
```

### Create a mail-enabled security group
```powershell
New-DistributionGroup -Name "Sales Team" -Type Security -PrimarySmtpAddress sales@contoso.com
```
The type cannot be changed after creation.

### Allow external senders
```powershell
Set-DistributionGroup -Identity "Sales Team" -RequireSenderAuthenticationEnabled $false
```
Default is `$true`, which silently NDRs every external sender — the most common "the group doesn't receive mail" ticket.

### Hide a group from the GAL
```powershell
Set-DistributionGroup -Identity "Sales Team" -HiddenFromAddressListsEnabled $true
```

### Manage members
```powershell
Add-DistributionGroupMember -Identity "Sales Team" -Member user@contoso.com; Get-DistributionGroupMember -Identity "Sales Team" -ResultSize Unlimited
```
`Update-DistributionGroupMember -Members` replaces the whole membership — batch it, REST calls time out at 15 minutes.

### Create a dynamic distribution group
```powershell
New-DynamicDistributionGroup -Name "All London" -PrimarySmtpAddress all-london@contoso.com -RecipientFilter "RecipientTypeDetails -eq 'UserMailbox' -and Office -eq 'London'"
```
Membership is evaluated at send time; preview it with `Get-DynamicDistributionGroupMember -Identity "All London"`.

### Microsoft 365 group mail settings
```powershell
Set-UnifiedGroup -Identity "Sales Team" -RequireSenderAuthenticationEnabled $false -HiddenFromAddressListsEnabled $true -HiddenFromExchangeClientsEnabled $true -AutoSubscribeNewMembers $true
```
`HiddenFromExchangeClientsEnabled` is what actually hides a Microsoft 365 group from Outlook; the GAL flag alone is not enough.

### Manage Microsoft 365 group membership
```powershell
Add-UnifiedGroupLinks -Identity "Sales Team" -LinkType Members -Links user@contoso.com; Get-UnifiedGroupLinks -Identity "Sales Team" -LinkType Owners
```
`LinkType` values: `Members`, `Owners`, `Subscribers`. An owner must also be a member.

## Mail flow

### List accepted domains
```powershell
Get-AcceptedDomain | Select-Object Name,DomainName,DomainType,Default
```

### List connectors
```powershell
Get-InboundConnector | Select-Object Name,Enabled,SenderDomains,SenderIPAddresses; Get-OutboundConnector | Select-Object Name,Enabled,RecipientDomains,SmartHosts
```

### Inspect remote domain settings
```powershell
Get-RemoteDomain | Select-Object Name,DomainName,AutoForwardEnabled,AutoReplyEnabled,AllowedOOFType
```
The `Default` remote domain (`*`) governs OOF and auto-forward behaviour to every external domain.

### List transport rules
```powershell
Get-TransportRule | Select-Object Name,State,Priority,Mode | Sort-Object Priority
```

### Read one rule in full
```powershell
Get-TransportRule -Identity "Block executables" | Format-List Name,State,Priority,Description
```
`Description` is the human-readable rendering of the conditions and actions — far easier to read than the raw parameters.

### Create a rule that adds an external-sender warning
```powershell
New-TransportRule -Name "External banner" -FromScope NotInOrganization -SentToScope InOrganization -ApplyHtmlDisclaimerLocation Prepend -ApplyHtmlDisclaimerText "<p>External sender.</p>" -ApplyHtmlDisclaimerFallbackAction Wrap
```

### Disable a rule without deleting it
```powershell
Disable-TransportRule -Identity "External banner" -Confirm:$false
```

## Message trace

### Trace recent messages
```powershell
Get-MessageTraceV2 -SenderAddress user@contoso.com -StartDate (Get-Date).AddDays(-2) -EndDate (Get-Date) -ResultSize 5000
```
`Get-MessageTraceV2` is the current cmdlet (module 3.7.0+); `Get-MessageTrace` still works but Microsoft has marked it for eventual deprecation. Searches back 90 days, max 10 days per query, 1000 results by default and 5000 maximum, 100 queries per 5 minutes per tenant.

### Page past the 5000-result cap
```powershell
Get-MessageTraceV2 -StartDate "2026-08-01T00:00:00Z" -EndDate $last.Received -StartingRecipientAddress $last.RecipientAddress -ResultSize 5000
```
There is no `-Page` on V2. Feed the `Received` and `RecipientAddress` of the last row of the previous batch back in as `-EndDate` and `-StartingRecipientAddress`.

### See the delivery detail for one message
```powershell
Get-MessageTraceV2 -MessageId "<abc123@contoso.com>" -StartDate (Get-Date).AddDays(-5) -EndDate (Get-Date) | Get-MessageTraceDetailV2
```

### Search older than 10 days
```powershell
Start-HistoricalSearch -ReportTitle "Phish investigation" -ReportType MessageTrace -StartDate (Get-Date).AddDays(-45) -EndDate (Get-Date) -SenderAddress user@contoso.com -NotifyAddress admin@contoso.com
```
Asynchronous CSV job covering 90 days; check with `Get-HistoricalSearch`. Limits: 250 searches per 24 hours, 100,000 rows per file.

## Protection (EOP and Defender)

### Review anti-spam, anti-phish and malware policies
```powershell
Get-HostedContentFilterPolicy | Select-Object Name,SpamAction,HighConfidenceSpamAction,BulkThreshold,QuarantineRetentionPeriod; Get-AntiPhishPolicy | Select-Object Name,Enabled,EnableSpoofIntelligence,EnableMailboxIntelligence; Get-MalwareFilterPolicy | Select-Object Name,EnableFileFilter,ZapEnabled
```
Policies do nothing until a rule binds them to recipients — check `Get-HostedContentFilterRule` / `Get-AntiPhishRule` / `Get-MalwareFilterRule` for `State` and `Priority`.

### Review Safe Links and Safe Attachments
```powershell
Get-SafeLinksPolicy | Select-Object Name,EnableSafeLinksForEmail,EnableSafeLinksForTeams,TrackClicks; Get-SafeAttachmentPolicy | Select-Object Name,Enable,Action
```
Defender for Office 365 licence required; these cmdlets are absent in an EOP-only tenant.

### List quarantined messages
```powershell
Get-QuarantineMessage -StartReceivedDate (Get-Date).AddDays(-7) -EndReceivedDate (Get-Date) -PageSize 1000 | Select-Object ReceivedTime,SenderAddress,RecipientAddress,Subject,QuarantineTypes,ReleaseStatus
```
Defaults to the last 16 days; 30 days is the maximum lookback. `-PageSize` maxes at 1000, so page with `-Page`.

### Preview and release a quarantined message
```powershell
Get-QuarantineMessage -MessageId "<abc123@contoso.com>" | Preview-QuarantineMessage; Get-QuarantineMessage -MessageId "<abc123@contoso.com>" | Release-QuarantineMessage -ReleaseToAll
```
`-User user@contoso.com` releases to one original recipient instead of all.

### Block a sender or URL tenant-wide
```powershell
New-TenantAllowBlockListItems -ListType Sender -Block -Entries "spammer@fabrikam.com" -NoExpiration -Notes "Ticket 4821"
```
`-ListType` values: `Sender`, `Url`, `FileHash`, `IP`. Without `-NoExpiration` or `-ExpirationDate` the entry expires in 30 days (90 days maximum).

### Review the Tenant Allow/Block List
```powershell
Get-TenantAllowBlockListItems -ListType Sender | Select-Object Value,Action,ExpirationDate,LastUsedDate,Notes
```
Remove with `Remove-TenantAllowBlockListItems -ListType Sender -Entries "spammer@fabrikam.com"`.

## Auditing and reporting

### Confirm mailbox auditing is on
```powershell
Get-OrganizationConfig | Format-List AuditDisabled
```
`False` means org-wide mailbox auditing is on, which overrides `AuditEnabled` on individual mailboxes.

### See which actions a mailbox audits
```powershell
Get-EXOMailbox -Identity user@contoso.com -PropertySets Audit | Format-List AuditEnabled,DefaultAuditSet,AuditOwner,AuditDelegate,AuditAdmin
```
A blank `DefaultAuditSet` means someone overrode the Microsoft-managed action list for that mailbox.

### Exclude a service account from mailbox auditing
```powershell
Set-MailboxAuditBypassAssociation -Identity svc-scanner@contoso.com -AuditByPassEnabled $true
```
The only way to suppress auditing per-user now that it is on by default. `AuditLogAgeLimit` no longer governs retention — that is a Purview audit retention policy.

### Folder-level item counts and sizes
```powershell
Get-EXOMailboxFolderStatistics -Identity user@contoso.com | Select-Object FolderPath,ItemsInFolder,FolderAndSubfolderSize | Sort-Object FolderAndSubfolderSize -Descending
```
Add `-FolderScope RecoverableItems` to see whether the dumpster is what filled a mailbox.

### Check what a licence actually enabled
```powershell
Get-EXOMailbox -Identity user@contoso.com -Properties ProhibitSendReceiveQuota,IssueWarningQuota,RecoverableItemsQuota | Format-List *Quota
```

## Bulk operations from CSV

### Apply settings from a CSV
```powershell
Import-Csv ./users.csv | ForEach-Object { Set-Mailbox -Identity $_.UPN -CustomAttribute1 $_.Department -HiddenFromAddressListsEnabled ([bool]::Parse($_.Hidden)) }
```
CSV columns here are `UPN,Department,Hidden`. Test with `-WhatIf` appended to the `Set-Mailbox` call first.

### Bulk-grant Full Access from CSV
```powershell
Import-Csv ./access.csv | ForEach-Object { Add-MailboxPermission -Identity $_.Mailbox -User $_.Trustee -AccessRights FullAccess -InheritanceType All -AutoMapping:$false }
```

### Batch a long-running bulk job
```powershell
$all = Get-EXOMailbox -ResultSize Unlimited; for ($i=0; $i -lt $all.Count; $i+=500) { $all[$i..([Math]::Min($i+499,$all.Count-1))] | ForEach-Object { Set-Mailbox -Identity $_.PrimarySmtpAddress -RetainDeletedItemsFor 30 } }
```
REST cmdlets have a 15-minute server-side timeout — anything touching thousands of objects must be chunked.

## Exchange cmdlets vs Microsoft Graph

- Mailbox configuration (quotas, forwarding, holds, permissions, calendar processing, transport rules, connectors) exists **only** in Exchange PowerShell. Graph has no equivalent.
- Directory attributes (UPN, licences, account enabled, manager, group membership for security/M365 groups) belong to Graph. `Set-Mailbox` cannot change a UPN or assign a licence.
- Both cmdlet families see Microsoft 365 groups: `Set-UnifiedGroup` controls the mail behaviour, `Update-MgGroup` controls the directory object. Changes made in one are visible in the other after a short delay.
- Usage reporting (mailbox usage, activity, storage trends) is a Graph reports API job (`Get-MgReportMailboxUsageDetail`), not an Exchange cmdlet.
- Exchange RBAC (`Get-ManagementRoleAssignment`) is separate from Entra directory roles; holding Exchange Administrator in Entra is what grants the Exchange role group membership.

## Gotchas

- Default `-ResultSize` is 1000 on every recipient cmdlet. Always pass `-ResultSize Unlimited` for inventories.
- `Get-EXO*` cmdlets return only the Minimum property set — a property you did not ask for comes back empty, not missing, which reads as "not configured". Use `-PropertySets` / `-Properties`; avoid `-PropertySets All`.
- Prefer server-side `-Filter` over `Where-Object`; the latter enumerates the whole tenant first and is a throttling magnet.
- REST cmdlets time out server-side at 15 minutes. Chunk bulk work into batches of a few hundred.
- `Update-DistributionGroupMember -Members` replaces the entire membership; `Add-DistributionGroupMember` appends. Mixing them up empties groups silently.
- Passing a bare list to `-EmailAddresses` overwrites all proxy addresses including the primary. Use `@{Add=}` / `@{Remove=}`.
- `RequireSenderAuthenticationEnabled $true` (the default on new groups) NDRs every external sender.
- `-AutoMapping` can only be changed by removing and re-adding the Full Access permission.
- Folder identities like `user@contoso.com:\Calendar` use the *localised* folder name; resolve the real path with `Get-EXOMailboxFolderStatistics` on non-English mailboxes.
- Mailbox forwarding and inbox-rule forwarding are separate settings. A forwarding audit that checks only `ForwardingSmtpAddress` misses the rules attackers actually use.
- `Get-MessageTraceV2` has no pagination — use `-StartingRecipientAddress` plus a rolling `-EndDate`, and stay under 100 queries per 5 minutes.
- Anti-spam/anti-phish/Safe Links policies are inert until a matching rule binds them to recipients; check the rule's `State` and `Priority`, not just the policy.
- Auto-expanding archiving cannot be turned off once enabled, and it blocks recovery of mailboxes that later become inactive.
- `Get-PSSession` never shows Exchange Online connections — use `Get-ConnectionInformation`.
- Connecting to Exchange Online and Security & Compliance in one session collides on shared cmdlet names; namespace one of them with `-Prefix`.
