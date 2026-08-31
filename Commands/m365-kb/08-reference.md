# Quick Reference

Lookup tables for the whole KB. Nothing here runs without a connection first — see the module table below.

## Modules

| Module (version) | Manages | Connect | Disconnect / verify |
| --- | --- | --- | --- |
| ExchangeOnlineManagement 3.10.1 | Exchange Online, mailboxes, transport, EOP | `Connect-ExchangeOnline -UserPrincipalName admin@contoso.onmicrosoft.com -ShowBanner:$false` | `Disconnect-ExchangeOnline -Confirm:$false` / `Get-ConnectionInformation` |
| ExchangeOnlineManagement 3.10.1 (same package) | Purview: labels, DLP, retention, eDiscovery | `Connect-IPPSSession -UserPrincipalName admin@contoso.onmicrosoft.com` | `Disconnect-ExchangeOnline -Confirm:$false` / `Get-ConnectionInformation` |
| MicrosoftTeams 7.9.0 | Teams, Teams Phone, all `Cs*` cmdlets | `Connect-MicrosoftTeams` | `Disconnect-MicrosoftTeams` / `Get-CsTenant` |
| Microsoft.Online.SharePoint.PowerShell 16.0.27515.12000 | SPO/OneDrive tenant + sites (Windows only) | `Connect-SPOService -Url https://contoso-admin.sharepoint.com` | `Disconnect-SPOService` / `Get-SPOTenant` |
| PnP.PowerShell 3.4.1 | Site content: lists, files, permissions | `Connect-PnPOnline -Url "https://contoso.sharepoint.com" -Interactive -ClientId <your-app-client-id>` | `Disconnect-PnPOnline` / `Get-PnPConnection` |
| Microsoft.Graph 2.39.0 | Entra ID, users, groups, licences, reports | `Connect-MgGraph -Scopes "User.Read.All","Group.ReadWrite.All" -NoWelcome` | `Disconnect-MgGraph` / `Get-MgContext` |

PnP is the only one that requires your own Entra app registration. `Connect-MgGraph` has no `-Interactive` switch — browser sign-in is the default. Beta Graph cmdlets live in `Microsoft.Graph.Beta` as `Get-MgBeta*`.

## Cmdlet noun map — Exchange Online

| I want to… | Look at |
| --- | --- |
| List mailboxes in bulk | `Get-EXOMailbox` (`Get-Mailbox` for writes/rare properties) |
| See size, item count, last logon | `Get-EXOMailboxStatistics` |
| Find any recipient type at once | `Get-EXORecipient`, `Get-Recipient` |
| Check who has access to a mailbox | `Get-EXOMailboxPermission`, `Get-EXORecipientPermission` (SendAs), `Get-EXOMailboxFolderPermission` |
| Grant access | `Add-MailboxPermission`, `Add-RecipientPermission`, `Set-Mailbox -GrantSendOnBehalfTo` |
| Convert to shared, set forwarding, litigation hold | `Set-Mailbox` |
| Distribution groups / M365 group mailboxes | `Get-DistributionGroup`, `Get-DistributionGroupMember`, `Get-UnifiedGroup`, `Get-UnifiedGroupLinks` |
| Rooms and equipment | `Get-Mailbox -RecipientTypeDetails RoomMailbox,EquipmentMailbox`, `Get-CalendarProcessing`, `Get-Place` |
| Trace a message | `Get-MessageTraceV2`, then `Get-MessageTraceDetailV2` (90 days of data, max 10 days per query — page the range); older than 90 days: `Start-HistoricalSearch` |
| Mail flow rules and connectors | `Get-TransportRule`, `Get-InboundConnector`, `Get-OutboundConnector`, `Get-AcceptedDomain`, `Get-RemoteDomain` |
| Anti-spam / anti-phish / Safe Links | `Get-HostedContentFilterPolicy`, `Get-AntiPhishPolicy`, `Get-SafeLinksPolicy`, `Get-QuarantineMessage` |
| Suspicious inbox rules | `Get-InboxRule -Mailbox user@contoso.com` |
| Protocols, OWA/ActiveSync, mobile devices | `Get-CASMailbox`, `Get-MobileDevice`, `Get-MobileDeviceStatistics` |
| Tenant-wide settings | `Get-OrganizationConfig`, `Set-OrganizationConfig` |
| Search the unified audit log | `Search-UnifiedAuditLog` (EXO, not Purview) |

## Cmdlet noun map — Purview (Connect-IPPSSession)

| I want to… | Look at |
| --- | --- |
| Content search end to end | `New-ComplianceSearch`, `Start-ComplianceSearch`, `Get-ComplianceSearch`, `New-ComplianceSearchAction` |
| eDiscovery cases and holds | `Get-ComplianceCase`, `New-CaseHoldPolicy`, `New-CaseHoldRule` |
| Retention | `Get-RetentionCompliancePolicy`, `Get-RetentionComplianceRule` |
| Sensitivity labels | `Get-Label`, `Get-LabelPolicy` |
| DLP | `Get-DlpCompliancePolicy`, `Get-DlpComplianceRule`, `Get-DlpSensitiveInformationType` |
| Purview RBAC | `Get-RoleGroup`, `Add-RoleGroupMember` |

## Cmdlet noun map — Teams

| I want to… | Look at |
| --- | --- |
| List teams, members, channels | `Get-Team`, `Get-TeamUser`, `Get-TeamChannel` |
| Per-user voice/licence/policy state | `Get-CsOnlineUser` |
| Policies and assignment | `Get-CsTeamsMeetingPolicy`, `Get-CsTeamsMessagingPolicy`, `Get-CsTeamsCallingPolicy`, `Grant-Cs*Policy -Identity user@contoso.com` |
| Phone numbers | `Get-CsPhoneNumberAssignment`, `Set-CsPhoneNumberAssignment`, `Remove-CsPhoneNumberAssignment` |
| Voice routing (Direct Routing) | `Get-CsOnlineVoiceRoutingPolicy`, `Get-CsOnlinePSTNGateway`, `Get-CsOnlineVoiceRoute` |
| Auto attendants and call queues | `Get-CsAutoAttendant`, `Get-CsCallQueue`, `Get-CsOnlineApplicationInstance` |
| Federation / external access | `Get-CsTenantFederationConfiguration`, `Get-CsExternalAccessPolicy` |
| Confirm the tenant you are in | `Get-CsTenant` |

## Cmdlet noun map — SharePoint / OneDrive

| I want to… | Look at (SPO) | Look at (PnP) |
| --- | --- | --- |
| List sites | `Get-SPOSite -Limit All` | `Get-PnPTenantSite` |
| Site storage / quota / sharing | `Get-SPOSite`, `Set-SPOSite` | `Set-PnPTenantSite` |
| Site collection admins | `Set-SPOUser -IsSiteCollectionAdmin $true` | `Get-PnPSiteCollectionAdmin`, `Add-PnPSiteCollectionAdmin` |
| OneDrive sites | `Get-SPOSite -IncludePersonalSite $true -Limit All -Filter "Url -like '-my.sharepoint.com/personal/'"` | `Get-PnPTenantSite -IncludeOneDriveSites` |
| Tenant sharing policy | `Get-SPOTenant`, `Set-SPOTenant` | `Get-PnPTenant`, `Set-PnPTenant` |
| Lists, libraries, items, files | — | `Get-PnPList`, `Get-PnPListItem`, `Get-PnPFile`, `Get-PnPFolder` |
| Permissions on a site/web | `Get-SPOUser`, `Get-SPOSiteGroup` | `Get-PnPGroup`, `Get-PnPGroupMember` |
| Deleted sites and recycle bin | `Get-SPODeletedSite`, `Restore-SPODeletedSite` | `Get-PnPRecycleBinItem` |
| External users | `Get-SPOExternalUser` | `Get-PnPExternalUser` |

## Cmdlet noun map — Entra / Graph

| I want to… | Look at |
| --- | --- |
| Users | `Get-MgUser`, `New-MgUser`, `Update-MgUser`, `Remove-MgUser` |
| Groups and membership | `Get-MgGroup`, `Get-MgGroupMember`, `New-MgGroupMember`, `Get-MgGroupOwner` |
| A user's group/role memberships | `Get-MgUserMemberOf`, `Get-MgUserTransitiveMemberOf` |
| Licences | `Get-MgSubscribedSku`, `Get-MgUserLicenseDetail`, `Set-MgUserLicense` |
| Directory roles | `Get-MgDirectoryRole`, `Get-MgDirectoryRoleMember` |
| Sign-in and audit logs | `Get-MgAuditLogSignIn`, `Get-MgAuditLogDirectoryAudit` |
| MFA / auth method registration | `Get-MgUserAuthenticationMethod`, `Get-MgReportAuthenticationMethodUserRegistrationDetail` |
| Conditional Access | `Get-MgIdentityConditionalAccessPolicy` |
| Apps and service principals | `Get-MgApplication`, `Get-MgServicePrincipal` |
| Devices | `Get-MgDevice` |
| Usage reports | `Get-MgReportOffice365ActiveUserDetail` and the other `Get-MgReport*` |
| Kill a user's sessions | `Revoke-MgUserSignInSession` |
| Tenant and domains | `Get-MgOrganization`, `Get-MgDomain` |

### Find the cmdlet and permission for any Graph API
```powershell
Find-MgGraphCommand -Uri '/users/{id}/licenseDetails' -Method GET | Select-Object -First 1 Command,Permissions
```
`Find-MgGraphPermission mailbox -PermissionType Delegated` goes the other way, from keyword to scope name.

## Graph delegated scopes by task

Scopes are consent only. You also need the Entra role in the third column, or the call still returns 403.

| Task | Least-privilege delegated scope | Entra role usually needed |
| --- | --- | --- |
| Read user objects | `User.Read.All` | Directory Readers / Global Reader |
| Create, update, disable users | `User.ReadWrite.All` | User Administrator |
| Reset a password | `User-PasswordProfile.ReadWrite.All` | Helpdesk / Password Administrator |
| Read groups | `Group.Read.All` | Directory Readers |
| Change group membership | `GroupMember.ReadWrite.All` | Groups Administrator |
| Create / delete groups | `Group.ReadWrite.All` | Groups Administrator |
| Read tenant SKUs and licence assignments | `LicenseAssignment.Read.All` (or `Organization.Read.All`) | Global Reader / Directory Readers |
| Assign or remove licences | `LicenseAssignment.ReadWrite.All` | License Administrator |
| Read sign-in and directory audit logs | `AuditLog.Read.All` | Reports Reader / Security Reader |
| Read usage reports | `Reports.Read.All` | Reports Reader |
| Read Conditional Access policies | `Policy.Read.All` | Global Reader / Security Reader |
| Write Conditional Access policies | `Policy.ReadWrite.ConditionalAccess` | Conditional Access Administrator |
| Read role assignments | `RoleManagement.Read.Directory` | Global Reader |
| Assign directory roles | `RoleManagement.ReadWrite.Directory` | Privileged Role Administrator |
| Read auth method registration | `AuditLog.Read.All` (report) or `UserAuthenticationMethod.Read.All` (per user) | Authentication Administrator |
| Read apps / service principals | `Application.Read.All` | Global Reader |
| Read devices | `Device.Read.All` | Global Reader |
| Read SharePoint sites via Graph | `Sites.Read.All` | SharePoint Administrator |

## Admin roles by workload

| Workload | Role that actually works | Read-only equivalent |
| --- | --- | --- |
| Exchange Online, EOP | Exchange Administrator (Graph name: Exchange Service Administrator) | Global Reader (Exchange Recipient Administrator is write, not read-only) |
| Purview / compliance | Compliance Administrator, Compliance Data Administrator; plus a Purview role group (eDiscovery Manager, Organization Management) | Global Reader |
| Teams | Teams Administrator; Teams Communications Administrator for voice only | Teams Communications Support Specialist, Global Reader |
| SharePoint / OneDrive | SharePoint Administrator | Global Reader |
| Users, groups, licences | User Administrator; License Administrator for licences only; Groups Administrator for groups | Directory Readers, Global Reader |
| Sign-in / audit / reports | Reports Reader, Security Reader | same |
| Conditional Access, auth methods | Conditional Access Administrator, Authentication Policy Administrator | Global Reader |
| Role assignments, PIM | Privileged Role Administrator | Global Reader |

## Licence SKUs

`SkuPartNumber` is the string you see in PowerShell; `SkuId` is the GUID Graph wants.

| Friendly name | SkuPartNumber | SkuId (GUID) |
| --- | --- | --- |
| Microsoft 365 E3 | `SPE_E3` | `05e9a617-0261-4cee-bb44-138d3ef5d965` |
| Microsoft 365 E5 | `SPE_E5` | `06ebc4ee-1bb5-47dd-8120-11324bc54e06` |
| Office 365 E3 | `ENTERPRISEPACK` | `6fd2c87f-b296-42f0-b197-1e91e994b900` |
| Office 365 E5 | `ENTERPRISEPREMIUM` | `c7df2760-2c81-4ef7-b578-5b5392b571df` |
| Microsoft 365 Business Premium | `SPB` | `cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46` |
| Microsoft 365 F3 | `SPE_F1` | `66b55226-6b4f-492c-910c-a3b7a3c9d993` |
| Office 365 F3 | `DESKLESSPACK` | `4b585984-651b-448a-9e53-3b10f069cf7f` |
| Exchange Online (Plan 1) | `EXCHANGESTANDARD` | `4b9405b0-7788-4568-add1-99614e613b69` |
| Exchange Online (Plan 2) | `EXCHANGEENTERPRISE` | `19ec0d23-8335-4cbd-94ac-6050e30712fa` |
| Microsoft Teams Phone Standard | `MCOEV` | `e43b5b99-8dfb-405f-9987-dc307f34bcbd` |
| Power BI Pro | `POWER_BI_PRO` | `f8a1db68-be16-40ed-86d5-cb42ce701560` |
| Microsoft Entra ID P1 | `AAD_PREMIUM` | `078d2b04-f1bd-4111-bbd4-b4b1b354cef4` |
| Microsoft Entra ID P2 | `AAD_PREMIUM_P2` | `84a661c4-e949-4bd2-a560-ed7766fcaf2b` |

Common service plans inside them: `EXCHANGE_S_ENTERPRISE`, `SHAREPOINTENTERPRISE`, `TEAMS1`, `OFFICESUBSCRIPTION`, `AAD_PREMIUM`, `MCOEV`, `BI_AZURE_P2`, `INTUNE_A`.

### Resolve the SKUs in your own tenant
```powershell
Get-MgSubscribedSku -All | Select-Object SkuPartNumber,SkuId,ConsumedUnits,@{n='Enabled';e={$_.PrepaidUnits.Enabled}}
```

### List the service plans inside one SKU
```powershell
(Get-MgSubscribedSku -All | Where-Object SkuPartNumber -eq 'SPE_E3').ServicePlans | Select-Object ServicePlanName,ServicePlanId
```

## Search-UnifiedAuditLog: RecordType values

| RecordType | Id | Covers |
| --- | --- | --- |
| `ExchangeAdmin` | 1 | Exchange admin cmdlets (Operation = the cmdlet name) |
| `ExchangeItem` | 2 | Single-item mailbox actions |
| `ExchangeItemGroup` | 3 | Multi-item mailbox actions (move, delete) |
| `SharePoint` | 4 | SharePoint non-file events |
| `SharePointFileOperation` | 6 | File access, edit, delete, download |
| `OneDrive` | 7 | OneDrive events |
| `AzureActiveDirectory` | 8 | Directory changes |
| `AzureActiveDirectoryStsLogon` | 15 | Sign-in (STS) events |
| `SharePointSharingOperation` | 14 | Sharing links and invitations |
| `SecurityComplianceCenterEOPCmdlet` | 18 | Defender/EOP admin cmdlets |
| `ExchangeAggregatedOperation` | 19 | Aggregated mailbox auditing |
| `PowerBIAudit` | 20 | Power BI |
| `Discovery` | 24 | Content search / eDiscovery activity |
| `MicrosoftTeams` | 25 | Teams |
| `ThreatIntelligence` | 28 | Phish and malware (Defender for Office 365) |
| `ComplianceDLPSharePoint` / `ComplianceDLPExchange` | 11 / 13 | DLP matches |

## Operations worth knowing

| Area | Operation values |
| --- | --- |
| Mailbox access | `MailItemsAccessed`, `FolderBind`, `AttachmentAccess`, `MailboxLogin`, `Send`, `SendAs`, `SendOnBehalf` |
| Mailbox delegation | `Add-MailboxPermission`, `AddFolderPermissions`, `ModifyFolderPermissions`, `UpdateCalendarDelegation` |
| Inbox rules (BEC signal) | `New-InboxRule`, `Set-InboxRule`, `UpdateInboxRules` |
| Files | `FileAccessed`, `FileModified`, `FileDownloaded`, `FileDeleted`, `FileRecycled`, `FileRenamed`, `FileCopied` |
| Sharing | `SharingSet`, `SharingInvitationCreated`, `AnonymousLinkCreated`, `AnonymousLinkUsed`, `SecureLinkCreated`, `SharingRevoked` |
| Entra | `Add member to group`, `Update user`, `Add service principal`, `Consent to application`, `UserLoggedIn` |
| Teams | `TeamCreated`, `MemberAdded`, `MemberRemoved`, `TeamSettingChanged`, `MessageDeleted` |

## Graph OData filter cheat sheet

Advanced query = add `-ConsistencyLevel eventual -CountVariable c` (the header plus `$count=true`).

| Pattern | Example | Advanced? |
| --- | --- | --- |
| `eq` | `-Filter "accountEnabled eq false"` | no |
| `in` | `-Filter "department in ('Sales','Legal')"` | no |
| `startsWith` | `-Filter "startsWith(displayName,'Sv')"` | no |
| `lt gt le ge` on dates | `-Filter "createdDateTime ge 2026-01-01T00:00:00Z"` | no |
| `any` lambda | `-Filter "assignedLicenses/any(x:x/skuId eq 05e9a617-0261-4cee-bb44-138d3ef5d965)"` | no |
| `ne` | `-Filter "companyName ne null"` | yes |
| `not(...)` | `-Filter "not(startsWith(displayName,'Svc'))"` | yes |
| `endsWith` (only mail, otherMails, userPrincipalName, proxyAddresses) | `-Filter "endsWith(userPrincipalName,'#EXT#@contoso.com')"` | yes |
| Empty / single-item collections | `-Filter 'assignedLicenses/$count eq 0'` | yes |
| `-Search` | `-Search '"displayName:Sales"'` | yes (header only, no `$count`) |

### Run an advanced query
```powershell
Get-MgUser -Filter "endsWith(userPrincipalName,'#EXT#@contoso.com')" -ConsistencyLevel eventual -CountVariable guestCount -All -Property Id,UserPrincipalName,CreatedDateTime
```
Inside double quotes, escape `$count` with a **backtick** (`` `$count ``) — a backslash is not a PowerShell escape and leaves `assignedLicenses/\ eq 0`. Single-quoting the whole filter is safer.

## KQL for content search

Mail properties: `subject`, `from`, `to`, `cc`, `bcc`, `participants`, `recipients`, `sent`, `received`, `kind`, `hasattachment`, `attachmentnames`, `itemclass`, `size`, `category`.
Site properties: `filename`, `fileextension`, `title`, `author`, `createdby`, `modifiedby`, `created`, `lastmodifiedtime`, `contenttype`, `documentlink`, `size`, `sharedwithusersowsuser`, `viewablebyexternalusers`, `sensitivetype`, `mipsensitivelabel`, `detectedlanguage`.

| Goal | KQL |
| --- | --- |
| Mail to or from one person in a window | `participants:user@contoso.com AND sent>=2026-01-01 AND sent<=2026-01-31` |
| Teams chat and IM only | `kind:microsoftteams OR kind:im` |
| Subject phrase plus attachment | `subject:"budget Q1" AND hasattachment:true` |
| One file type in a folder tree | `documentlink:"https://contoso.sharepoint.com/sites/Marketing/Shared Documents/*" AND fileextension:xlsx` |
| Externally shared documents | `viewablebyexternalusers:true AND contenttype:document NOT fileextension:aspx` |
| Documents holding card numbers | `SensitiveType:"Credit Card Number|5.."` |
| Documents with a sensitivity label | `MipSensitiveLabel=<label-guid>` |
| Exclude a sender | `-from:"Sara Davis"` |

Values are prefix-match only (`cat*` works, `*cat` does not); a bare space between terms means OR; `subject:budget Q1` is not the same as `subject:"budget Q1"`.

## PowerShell idioms this KB relies on

### Filter server-side, not client-side
```powershell
Get-EXOMailbox -Filter "RecipientTypeDetails -eq 'SharedMailbox'" -ResultSize Unlimited
```
`-Filter` runs on the server and is the difference between 4 seconds and 4 minutes; `Where-Object` is the fallback for properties `-Filter` will not accept.

### Flatten a property to plain strings
```powershell
Get-MgGroupMember -GroupId $groupId -All | Select-Object @{n='UPN';e={$_.AdditionalProperties['userPrincipalName']}}
```
`AdditionalProperties` is a dictionary, so `Select-Object userPrincipalName` on it yields blanks — index the key in a calculated property.

### Calculated properties for nested or renamed values
```powershell
Get-EXOMailbox -ResultSize Unlimited -Properties ArchiveStatus | Select-Object DisplayName,@{n='SMTP';e={$_.PrimarySmtpAddress}},@{n='Aliases';e={$_.EmailAddresses -join ';'}}
```
Join collections yourself — anything left as an array exports to CSV as `System.String[]`.

### Export a report
```powershell
Get-EXOMailboxStatistics -Identity user@contoso.com | Select-Object DisplayName,ItemCount,TotalItemSize | Export-Csv ~/mbx.csv -NoTypeInformation -Encoding UTF8
```

### Page a large Graph result
```powershell
Get-MgUser -All -Property Id,DisplayName,UserPrincipalName,AccountEnabled | Select-Object DisplayName,UserPrincipalName,AccountEnabled
```
Without `-All` you get one page (100 objects); without `-Property` you get the default subset and everything else is null.

### Batch, don't parallelise
```powershell
Get-Content ~/users.txt | ForEach-Object { Set-Mailbox -Identity $_ -LitigationHoldEnabled $true; Start-Sleep -Milliseconds 200 }
```
`ForEach-Object -Parallel` starts each iteration in a fresh runspace that has neither the module import nor your `Connect-*` session, so EXO, Teams, PnP and SPO cmdlets fail or trigger a re-auth per thread. Split the work into serial batches instead.

## Docs

| Topic | Link |
| --- | --- |
| Exchange Online PowerShell | https://learn.microsoft.com/powershell/exchange/exchange-online-powershell |
| Exchange cmdlet reference | https://learn.microsoft.com/powershell/module/exchangepowershell/ |
| Security & Compliance PowerShell | https://learn.microsoft.com/powershell/exchange/scc-powershell |
| Teams PowerShell | https://learn.microsoft.com/powershell/module/microsoftteams/ |
| SharePoint Online Management Shell | https://learn.microsoft.com/powershell/module/sharepoint-online/ |
| PnP PowerShell | https://pnp.github.io/powershell/ |
| Microsoft Graph PowerShell SDK | https://learn.microsoft.com/powershell/microsoftgraph/overview |
| Graph permissions reference | https://learn.microsoft.com/graph/permissions-reference |
| Graph advanced queries | https://learn.microsoft.com/graph/aad-advanced-queries |
| Entra built-in roles | https://learn.microsoft.com/entra/identity/role-based-access-control/permissions-reference |
| Least-privileged role per task | https://learn.microsoft.com/entra/identity/role-based-access-control/delegate-by-task |
| SKU / service plan identifiers | https://learn.microsoft.com/entra/identity/users/licensing-service-plan-reference |
| Audit log activities | https://learn.microsoft.com/purview/audit-log-activities |
| RecordType enum (Management Activity API) | https://learn.microsoft.com/office/office-365-management-api/office-365-management-activity-api-schema |
| KQL mailbox properties | https://learn.microsoft.com/purview/edisc-search-mailboxes |
| KQL site properties | https://learn.microsoft.com/purview/edisc-search-sites |

## Gotchas

- SKU GUIDs and part numbers change as Microsoft renames products — resolve them live with `Get-MgSubscribedSku` before hardcoding, and treat the table above as a starting point.
- `Get-Mailbox` and friends default to `-ResultSize 1000`; add `-ResultSize Unlimited` or you will silently report on a subset.
- `Search-UnifiedAuditLog` returns 100 records by default, caps at 5,000 per call and 50,000 per paged session — page with `-SessionId`/`-SessionCommand ReturnLargeSet` and narrow the date range.
- Audit `Operation` names are workload-specific and the interesting detail is inside the JSON `AuditData` blob, not the top-level columns: `$_.AuditData | ConvertFrom-Json`.
- Graph `-Filter` support varies per property; `ne`, `not`, `endsWith` and `$count` filters return an error unless you add `-ConsistencyLevel eventual -CountVariable`.
- Consent is not authorisation: `Connect-MgGraph -Scopes` only decides what the app may ask for — you still need the Entra role, and `-Scopes` is accretive across sessions.
- `Get-EXOMailbox` returns the Minimum property set; anything you did not name in `-Properties`/`-PropertySets` comes back empty rather than erroring.
- Arrays exported straight to CSV become `System.String[]`; `-join` them in a calculated property first.
- One SPO service connection per session per geo — a second `Connect-SPOService` silently replaces the first.
- `Connect-IPPSSession` does not work in PowerShell 7 on macOS or Linux, and `Microsoft.Online.SharePoint.PowerShell` will not install there at all.
- EXO REST calls time out server-side at 15 minutes, so bulk loops must be batched; repeated connect/disconnect in one session leaks memory.
- `Get-Help` for Exchange cmdlets is empty unless you connected with `Connect-ExchangeOnline -LoadCmdletHelp` (module 3.7.0+).
