# SharePoint Online & OneDrive

PnP.PowerShell 3.4.1 — `Connect-PnPOnline -Url "https://contoso.sharepoint.com/sites/Marketing" -Interactive -ClientId <your-app-client-id>` · Microsoft.Online.SharePoint.PowerShell 16.0.27515.12000 — `Connect-SPOService -Url https://contoso-admin.sharepoint.com`

**Which module**: PnP for everything inside a site (lists, files, permissions, pages, templates, term store) and for cross-platform work — it is the only option on macOS/Linux. SPO Management Shell for tenant-wide settings and site lifecycle only; it is Windows PowerShell 5.1 on Windows only. PnP also carries `*-PnPTenant*` cmdlets that cover most of what SPO does, so a non-Windows admin rarely needs SPO at all.

## Connect

### Register the Entra ID app PnP requires (one time)
```powershell
Register-PnPEntraIDAppForInteractiveLogin -ApplicationName "PnP PowerShell" -Tenant contoso.onmicrosoft.com
```
Mandatory since 9 Sep 2024 — the shared PnP Management Shell app was removed. Save the printed client ID, or put it in `ENTRAID_APP_ID` so `-Interactive` works without `-ClientId`.

### Connect PnP to a site, and to tenant admin cmdlets
```powershell
Connect-PnPOnline -Url "https://contoso.sharepoint.com/sites/Marketing" -Interactive -ClientId <your-app-client-id>
```
`-Url` is the site or tenant root, never the `-admin` URL. Tenant cmdlets (`Get-PnPTenantSite`) work from a normal site connection; add `-TenantAdminUrl https://contoso-admin.sharepoint.com` if PnP cannot infer it.

### Connect the SPO Management Shell (Windows only)
```powershell
Connect-SPOService -Url https://contoso-admin.sharepoint.com
```
No `-Credential` — omitting it gives the MFA browser prompt. From PowerShell 7 on Windows: `Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell`.

### Verify and disconnect
```powershell
Get-PnPConnection; Disconnect-PnPOnline; Disconnect-SPOService
```

## Tenant administration

### Read all tenant-level settings
```powershell
Get-PnPTenant | Format-List
```
SPO equivalent: `Get-SPOTenant`.

### Set org-wide external sharing
```powershell
Set-SPOTenant -SharingCapability ExternalUserAndGuestSharing -DefaultSharingLinkType Internal -DefaultLinkPermission View
```
Values: `Disabled`, `ExistingExternalUserSharingOnly`, `ExternalUserSharingOnly`, `ExternalUserAndGuestSharing`. PnP: `Set-PnPTenant -SharingCapability ...`. A site can never be more permissive than the tenant.

### Restrict sharing to specific domains
```powershell
Set-SPOTenant -SharingDomainRestrictionMode AllowList -SharingAllowedDomainList "contoso.com fabrikam.com"
```
Space-delimited string, not an array.

### Set external sharing on one site
```powershell
Set-PnPTenantSite -Identity "https://contoso.sharepoint.com/sites/Marketing" -SharingCapability Disabled
```

### List every site
```powershell
Get-SPOSite -Limit All | Select-Object Url,Owner,Template,StorageUsageCurrent,LastContentModifiedDate
```
`-Limit All` is required; the default returns only the first 200. PnP: `Get-PnPTenantSite -Detailed`.

### Set storage quota on a site
```powershell
Set-SPOSite -Identity https://contoso.sharepoint.com/sites/Marketing -StorageQuota 10240 -StorageQuotaWarningLevel 9216
```
Megabytes. Fails silently-ish with a generic error if tenant storage management is set to automatic — switch it to manual first.

### Create a site
```powershell
New-SPOSite -Url https://contoso.sharepoint.com/sites/Marketing -Owner admin@contoso.com -Template STS#3 -StorageQuota 10240 -Title "Marketing"
```
`STS#3` modern team site (no group), `SITEPAGEPUBLISHING#0` communication site. Use PnP `New-PnPSite` for group-connected sites.

### Delete a site and empty it from the recycle bin
```powershell
Remove-PnPTenantSite -Url "https://contoso.sharepoint.com/sites/Marketing" -Force -SkipRecycleBin
```
Drop `-SkipRecycleBin` to keep the 93-day restore window; `-FromRecycleBin` purges one already-deleted site.

### List and restore deleted sites
```powershell
Get-SPODeletedSite -IncludePersonalSite | Format-Table Url,DeletionTime,DaysRemaining
Restore-SPODeletedSite -Identity https://contoso.sharepoint.com/sites/Marketing
```
PnP: `Get-PnPTenantDeletedSite` / `Restore-PnPTenantSite`.

### Lock a site
```powershell
Set-PnPTenantSite -Identity "https://contoso.sharepoint.com/sites/Marketing" -LockState NoAccess
```
`Unlock`, `ReadOnly`, `NoAccess`. Pair with `Set-PnPTenant -NoAccessRedirectUrl "https://contoso.com"`.

## Sites via PnP

### Create a communication site
```powershell
New-PnPSite -Type CommunicationSite -Title "Marketing" -Url "https://contoso.sharepoint.com/sites/Marketing" -Owner admin@contoso.com -Wait
```

### Create a group-connected team site
```powershell
New-PnPSite -Type TeamSite -Title "Sales Team" -Alias salesteam -Owners "admin@contoso.com" -IsPublic
```
`-Alias` drives the URL and the Microsoft 365 group mail nickname. Omit `-IsPublic` for a private group.

### Read site and web properties
```powershell
Get-PnPSite -Includes Usage,RootWeb; Get-PnPWeb | Select-Object Title,Url,Created,Language
```

### Register a hub site and associate a site to it
```powershell
Register-PnPHubSite -Site "https://contoso.sharepoint.com/sites/Marketing"
Add-PnPHubSiteAssociation -Site "https://contoso.sharepoint.com/sites/Sales" -HubSite "https://contoso.sharepoint.com/sites/Marketing"
```
List hubs with `Get-PnPHubSite`; detach with `Remove-PnPHubSiteAssociation -Site <url>`; `Unregister-PnPHubSite` demotes the hub itself.

### Create a site script and site design
```powershell
$id = (Add-PnPSiteScript -Title "Marketing baseline" -Content (Get-Content .\script.json -Raw)).Id
Add-PnPSiteDesign -Title "Marketing" -SiteScriptIds $id -WebTemplate TeamSite
```

### Apply a site design to an existing site
```powershell
Invoke-PnPSiteDesign -Identity 5c73382d-9643-4aa0-9160-d0cba35e40fd -WebUrl "https://contoso.sharepoint.com/sites/Marketing"
```

### Export a site as a PnP template and apply it elsewhere
```powershell
Get-PnPSiteTemplate -Out .\marketing.pnp -Handlers Lists,Fields,ContentTypes,Navigation
Invoke-PnPSiteTemplate -Path .\marketing.pnp
```
`Invoke-PnPSiteTemplate` applies to the currently connected site unless you pass a target; `-Handlers` keeps the extract small and fast.

## Permissions

### List and add site collection administrators
```powershell
Get-PnPSiteCollectionAdmin; Add-PnPSiteCollectionAdmin -Owners "user@contoso.com"
```
SPO equivalent: `Set-SPOUser -Site https://contoso.sharepoint.com/sites/Marketing -LoginName user@contoso.com -IsSiteCollectionAdmin $true`.

### List SharePoint groups and their members
```powershell
Get-PnPGroup | ForEach-Object { [pscustomobject]@{ Group = $_.Title; Members = (Get-PnPGroupMember -Group $_.Title).Title -join "; " } }
```

### Create a group, grant it a permission level, add a member
```powershell
New-PnPGroup -Title "Sales Team"; Set-PnPGroupPermissions -Identity "Sales Team" -AddRole "Contribute"; Add-PnPGroupMember -Group "Sales Team" -LoginName user@contoso.com
```

### Grant or remove a direct permission on the web
```powershell
Set-PnPWebPermission -User "user@contoso.com" -AddRole "Read"
```
`-RemoveRole "Read"` revokes it; `-Group` targets a SharePoint group instead of a user.

### Break inheritance on a list
```powershell
Set-PnPList -Identity "Documents" -BreakRoleInheritance -CopyRoleAssignments
```
Without `-CopyRoleAssignments` the list starts with no assignments at all except site admins. `-ResetRoleInheritance` puts it back.

### Set item-level permissions
```powershell
Set-PnPListItemPermission -List "Documents" -Identity 42 -User "user@contoso.com" -AddRole "Read" -ClearExisting
```
Breaks inheritance on the item automatically. `-InheritPermissions` restores it. `-ClearExisting` wipes every other assignment on that item — check first with `Get-PnPListItemPermission -List "Documents" -Identity 42`.

### Find broken permission inheritance in a library
```powershell
Measure-PnPList "Documents" -BrokenPermissions -ItemLevel
```

### Inventory sharing links in a library
```powershell
Get-PnPListItem -List "Documents" -PageSize 500 | Get-PnPFileSharingLink
```
Returns link type, scope, expiry and grantees per file. Folder links: `Get-PnPFolderSharingLink -Folder "/sites/Marketing/Shared Documents/Projects"`.

### Delete a sharing link
```powershell
Remove-PnPFileSharingLink -FileUrl "/sites/Marketing/Shared Documents/Budget.xlsx" -Identity <link-id> -Force
```
Get the id from `Get-PnPFileSharingLink -Identity "/sites/Marketing/Shared Documents/Budget.xlsx"`. **Omitting `-Identity` here removes every sharing link on the file.**

### Check pending guest invitations for one address on a site
```powershell
Get-PnPSiteUserInvitations -Site "https://contoso.sharepoint.com/sites/Marketing" -EmailAddress guest@fabrikam.com
```
Revoke with `Remove-PnPSiteUserInvitations -Site <url> -EmailAddress <address>`.

### List external users in the tenant
```powershell
0,50,100 | ForEach-Object { Get-PnPExternalUser -Position $_ -PageSize 50 } | Select-Object DisplayName,AcceptedAs,WhenCreated
```
Paged, max 50 per call — loop the `-Position` offset until it returns nothing. SPO: `Get-SPOExternalUser -Position 0 -PageSize 50`.

### Audit "Everyone except external users" on a site
```powershell
Get-PnPUser -WithRightsAssigned | Where-Object LoginName -like "*spo-grid-all-users*"
```
That claim is EEEU; plain "Everyone" is `c:0(.s|true`. Turn the claims off tenant-wide with `Set-PnPTenant -ShowEveryoneExceptExternalUsersClaim $false -ShowAllUsersClaim $false`.

## Lists & libraries

### Create a list and a document library
```powershell
New-PnPList -Title "Project Tracker" -Template GenericList -OnQuickLaunch; New-PnPList -Title "Contracts" -Template DocumentLibrary -EnableVersioning
```

### List all lists with item counts
```powershell
Get-PnPList | Select-Object Title,BaseTemplate,ItemCount,EnableVersioning,Hidden
```

### Read items from a large list
```powershell
Get-PnPListItem -List "Project Tracker" -Fields "Title","Status","Modified" -PageSize 2000
```
Always set `-PageSize` on lists over 5,000 items — it pages under the list view threshold instead of throwing.

### Query items with CAML
```powershell
Get-PnPListItem -List "Project Tracker" -Query "<View><Query><Where><Eq><FieldRef Name='Status'/><Value Type='Text'>Active</Value></Eq></Where></Query><RowLimit>500</RowLimit></View>"
```
Filtered columns must be indexed once the list passes 5,000 items.

### Add, update and delete items
```powershell
Add-PnPListItem -List "Project Tracker" -Values @{ Title = "Q3 rollout"; Status = "Active" }
Set-PnPListItem -List "Project Tracker" -Identity 42 -Values @{ Status = "Closed" }
Remove-PnPListItem -List "Project Tracker" -Identity 42 -Recycle -Force
```

### Bulk-update items in one round trip
```powershell
$b = New-PnPBatch; 1..500 | ForEach-Object { Set-PnPListItem -List "Project Tracker" -Identity $_ -Values @{ Status = "Closed" } -Batch $b }; Invoke-PnPBatch -Batch $b
```
Batching is the difference between minutes and hours, and it is the main defence against throttling.

### Add a field
```powershell
Add-PnPField -List "Project Tracker" -DisplayName "Region" -InternalName "Region" -Type Choice -Choices "EMEA","AMER","APAC" -AddToDefaultView
```

### Add a content type to a library and make it the default
```powershell
Set-PnPList -Identity "Contracts" -EnableContentTypes $true; Add-PnPContentTypeToList -List "Contracts" -ContentType "Project Document" -DefaultContentType
```

### Create a view
```powershell
Add-PnPView -List "Project Tracker" -Title "Active" -Fields "Title","Status","Modified" -Query "<Where><Eq><FieldRef Name='Status'/><Value Type='Text'>Active</Value></Eq></Where>" -RowLimit 100 -Paged
```

### Set versioning on a library
```powershell
Set-PnPList -Identity "Contracts" -EnableVersioning $true -EnableMinorVersions $true -MajorVersions 100 -MinorVersions 10
```

### Set the version expiration policy on a library
```powershell
Set-PnPListVersionPolicy -Identity "Contracts" -EnableAutoExpirationVersionTrim $false -ExpireVersionsAfterDays 180 -MajorVersionLimit 100
```
`-EnableAutoExpirationVersionTrim $true` hands version trimming to SharePoint's own algorithm and ignores the count limits. Site-wide default: `Get-PnPSiteVersionPolicy` / `Set-PnPSiteVersionPolicy`.

## Files & folders

### Upload and download a file
```powershell
Add-PnPFile -Path .\Budget.xlsx -Folder "Shared Documents/Finance"
Get-PnPFile -Url "/sites/Marketing/Shared Documents/Finance/Budget.xlsx" -Path C:\Temp -Filename Budget.xlsx -AsFile
```

### Create a folder
```powershell
Add-PnPFolder -Name "Finance" -Folder "Shared Documents"
```

### Copy or move a file between sites
```powershell
Copy-PnPFile -SourceUrl "/sites/Marketing/Shared Documents/Budget.xlsx" -TargetUrl "/sites/Sales/Shared Documents" -Overwrite
Move-PnPFile -SourceUrl "Shared Documents/Budget.xlsx" -TargetUrl "Archive" -Overwrite
```
Cross-site copies run as a server-side job; add `-NoWait` and poll with `Receive-PnPCopyMoveJobStatus` for large sets. `-IgnoreVersionHistory` copies only the latest version and is far faster.

### List folder contents recursively
```powershell
Get-PnPFolderItem -FolderSiteRelativeUrl "Shared Documents" -ItemType File -Recursive | Select-Object Name,ServerRelativeUrl,TimeLastModified
```

### Find files by name pattern
```powershell
Find-PnPFile -List "Documents" -Match "*.pdf"
```

### Find large files in a library
```powershell
Get-PnPListItem -List "Documents" -Fields "FileRef","File_x0020_Size" -PageSize 500 | Where-Object { [int64]$_.FieldValues.File_x0020_Size -gt 100MB } | Select-Object @{n="Url";e={$_.FieldValues.FileRef}},@{n="MB";e={[math]::Round($_.FieldValues.File_x0020_Size/1MB,1)}}
```

### Storage used by a library, or per folder
```powershell
Get-PnPFolderStorageMetric -List "Documents" | Select-Object TotalSize,TotalFileCount,LastModified
```
That is one aggregate for the library root. For a per-folder breakdown, iterate `Get-PnPFolderItem -FolderSiteRelativeUrl "Shared Documents" -ItemType Folder | ForEach-Object { Get-PnPFolderStorageMetric -Identity $_ }`.

### Find and release checked-out files
```powershell
Get-PnPFileCheckedOut -List "Documents"
Set-PnPFileCheckedIn -Url "/sites/Marketing/Shared Documents/Budget.xlsx" -CheckinType MajorCheckIn -Comment "Admin check-in"
```
`Undo-PnPFileCheckedOut -Url <url>` discards the checkout instead of committing it.

### List and restore file versions
```powershell
Get-PnPFileVersion -Url "Shared Documents/Budget.xlsx"; Restore-PnPFileVersion -Url "Shared Documents/Budget.xlsx" -Identity 512 -Force
```

### Restore items from the site recycle bin
```powershell
Get-PnPRecycleBinItem -FirstStage -RowLimit 5000 | Where-Object LeafName -like "*.docx" | Restore-PnPRecycleBinItem -Force
```
First stage = user recycle bin (93 days), second stage = site collection recycle bin. `Clear-PnPRecycleBinItem -All -Force` permanently deletes everything.

## OneDrive

### Find every user's OneDrive URL
```powershell
Get-SPOSite -IncludePersonalSite $true -Limit All -Filter "Url -like '-my.sharepoint.com/personal/'" | Select-Object Url,Owner,StorageUsageCurrent,LastContentModifiedDate
```
PnP alternative: `Get-PnPTenantSite -IncludeOneDriveSites | Where-Object Url -like "*-my.sharepoint.com/personal/*"`.

### Find one user's OneDrive URL
```powershell
Get-PnPUserOneDriveLocation -UserPrincipalName user@contoso.com
```
Or `Get-PnPUserProfileProperty -Account user@contoso.com | Select-Object PersonalUrl`.

### Provision a OneDrive before the user signs in
```powershell
Request-PnPPersonalSite -UserEmails "user@contoso.com"
```
Asynchronous, takes minutes to hours. `New-PnPPersonalSite -Email @("user@contoso.com")` is the older synchronous-ish equivalent.

### Grant yourself access to a leaver's OneDrive
```powershell
Set-SPOUser -Site https://contoso-my.sharepoint.com/personal/user_contoso_com -LoginName admin@contoso.com -IsSiteCollectionAdmin $true
```
PnP: connect to that OneDrive URL and run `Add-PnPSiteCollectionAdmin -Owners "admin@contoso.com"`. Remember to remove the grant afterwards — it is auditable but not self-expiring.

### OneDrive storage report
```powershell
Get-SPOSite -IncludePersonalSite $true -Limit All -Filter "Url -like '-my.sharepoint.com/personal/'" | Select-Object Owner,@{n="UsedGB";e={[math]::Round($_.StorageUsageCurrent/1024,2)}},StorageQuota | Sort-Object UsedGB -Descending
```
`StorageUsageCurrent` is in MB, `StorageQuota` in MB.

### Read and set a user's OneDrive quota
```powershell
Get-PnPUserOneDriveQuota -Account user@contoso.com; Set-PnPUserOneDriveQuota -Account user@contoso.com -Quota 5368709120 -QuotaWarning 4831838208
```
Bytes here, unlike `Set-SPOSite -StorageQuota` which is MB. `Reset-PnPUserOneDriveQuotaToDefault -Account <upn>` returns it to the tenant default.

### Restore a deleted OneDrive
```powershell
Get-SPODeletedSite -IncludeOnlyPersonalSite | Format-Table Url,DaysRemaining; Restore-SPODeletedSite -Identity https://contoso-my.sharepoint.com/personal/user_contoso_com
```
The OneDrive stays deleted-recoverable for the tenant retention period (default 30 days after the user object is deleted, then 93 days in the site recycle bin).

## Search & reporting

### Cross-tenant search query
```powershell
Submit-PnPSearchQuery -Query "ContentTypeId:0x0101* AND Author:'user@contoso.com'" -SelectProperties "Title","Path","LastModifiedTime","SiteTitle" -All
```
`-All` pages through the whole result set; without it you get 500 rows max and must page with `-StartRow`/`-MaxResults`. Search results honour the caller's permissions — a Global Admin does not see everything.

### Report every site with size, owner and last activity
```powershell
Get-SPOSite -Limit All | Select-Object Url,Title,Owner,Template,@{n="GB";e={[math]::Round($_.StorageUsageCurrent/1024,2)}},LastContentModifiedDate,LockState | Export-Csv .\sites.csv -NoTypeInformation
```
`SharingCapability` is deliberately left unpopulated whenever `-Limit` or `-Filter` is used, so it would report a wrong value for every row — read it with `Get-PnPTenantSite -Detailed` instead.

### Export permissions for one user across a site
```powershell
Export-PnPUserInfo -LoginName user@contoso.com -Site "https://contoso.sharepoint.com/sites/Marketing" | Export-Csv .\user-access.csv -NoTypeInformation
```

### Site usage analytics
```powershell
Get-PnPSiteAnalyticsData -LastSevenDays
```

### Tenant oversharing reports (SharePoint Advanced Management licence required)
```powershell
Start-SPODataAccessGovernanceInsight -ReportEntity EveryoneExceptExternalUsers -ReportType Snapshot
Get-SPODataAccessGovernanceInsight -ReportEntity EveryoneExceptExternalUsers
Export-SPODataAccessGovernanceInsight -ReportID <report-guid> -DownloadPath .\dag
```
Other entities: `SharingLinks_Anyone`, `SharingLinks_PeopleInYourOrg`, `SharingLinks_Guests`, `PermissionedUsers`, `SensitivityLabelForFiles`. Reports are asynchronous — the first `PermissionedUsers` snapshot can take five days.

## Term store

### Browse the term store
```powershell
Get-PnPTermGroup; Get-PnPTermSet -TermGroup "Corporate"; Get-PnPTerm -TermSet "Departments" -TermGroup "Corporate" -Recursive
```

### Create a group, term set and term
```powershell
New-PnPTermGroup -GroupName "Corporate"; New-PnPTermSet -Name "Departments" -TermGroup "Corporate"; New-PnPTerm -Name "Finance" -TermSet "Departments" -TermGroup "Corporate"
```

### Back up a term group to XML
```powershell
Export-PnPTermGroupToXml -Identity "Corporate" -Out .\corporate-terms.xml
```
Restore with `Import-PnPTermGroupFromXml -Path .\corporate-terms.xml`.

### Set a default managed metadata value on a library
```powershell
Set-PnPDefaultColumnValues -List "Documents" -Field TaxKeyword -Value "Corporate|Departments|Finance"
```

## Pages

### List, create and publish a modern page
```powershell
Get-PnPListItem -List "Site Pages" | Select-Object @{n="Name";e={$_.FieldValues.FileLeafRef}},@{n="Modified";e={$_.FieldValues.Modified}}
Add-PnPPage -Name "Announcements" -Title "Announcements" -LayoutType Article -Publish
```

### Add content to a page
```powershell
Add-PnPPageTextPart -Page "Announcements" -Text "<h2>Q3 update</h2><p>Rollout begins Monday.</p>"
```
`Add-PnPPageWebPart` adds a first-party or custom web part; `Get-PnPAvailablePageComponents -Page <name>` lists what can be added.

### Promote a page as news
```powershell
Set-PnPPage -Identity "Announcements" -PromoteAs NewsArticle -Publish
```

## Gotchas
- SPO Management Shell is Windows PowerShell 5.1 on Windows only — it will not install on macOS or Linux. Use PnP or Graph there.
- PnP.PowerShell 3.x needs PowerShell 7.4+ and your own Entra ID app. The other M365 modules need neither — do not copy `-ClientId` onto them.
- `Get-SPOSite` returns only 200 sites without `-Limit All`, and using `-Limit` or `-Filter` leaves ~20 properties (including `SharingCapability` and `DenyAddAndCustomizePages`) unpopulated with default values. Re-query the single site by `-Identity` to read those.
- `Get-PnPListItem` without `-PageSize` throws on lists over the 5,000-item list view threshold; filtered columns must be indexed.
- Loops of single-item PnP writes get throttled (HTTP 429) fast. Use `New-PnPBatch`/`Invoke-PnPBatch`, and for many-site reporting use certificate-based app-only auth so retries are not tied to an interactive token.
- `Get-PnPSite` / `Get-PnPWeb` return a lazy CSOM object — properties you did not ask for are null, not absent. Use `-Includes` or `Get-PnPProperty` to load them.
- `Set-PnPListItemPermission -ClearExisting` and `Set-PnPList -BreakRoleInheritance` without `-CopyRoleAssignments` both silently strip every existing assignment.
- Only one `Connect-SPOService` connection exists per session per geo; a second call replaces the first without warning. PnP keeps one current connection too — pass `-Connection` to target another.
- Deleting a site sends it to the tenant recycle bin for 93 days and the URL stays reserved; you cannot recreate the same URL until it is purged with `Remove-PnPTenantSite -FromRecycleBin`.
- A site's sharing setting can never exceed the tenant setting — `Set-PnPTenantSite -SharingCapability` appears to succeed but has no effect above the tenant ceiling.
- ACS app-only auth (client id + secret via appinv.aspx) retires 2 April 2026, and legacy IDCRL sign-in (`Connect-SPOService -Credential`) is fully retired 1 May 2026. Move automation to certificate-based Entra ID apps.
- Each workload disconnects separately: `Disconnect-PnPOnline`, `Disconnect-SPOService`. There is no single sign-out.
