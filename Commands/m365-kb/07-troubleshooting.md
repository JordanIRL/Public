# Troubleshooting & Gotchas

Covers all five modules: `ExchangeOnlineManagement` 3.10.1 (`Connect-ExchangeOnline`, `Connect-IPPSSession`), `MicrosoftTeams` 7.9.0 (`Connect-MicrosoftTeams`), `PnP.PowerShell` 3.4.1 (`Connect-PnPOnline`), `Microsoft.Online.SharePoint.PowerShell` 16.0.27515.12000 (`Connect-SPOService`), `Microsoft.Graph` 2.39.0 (`Connect-MgGraph`).

## Connection failures

### Fix "Connect-ExchangeOnline is not recognized"
```powershell
Get-Module ExchangeOnlineManagement -ListAvailable | Select-Object Name,Version,Path
```
The module is missing or was never imported. `Install-Module ExchangeOnlineManagement -Scope CurrentUser`, then reopen PowerShell.

### Fix "Get-Mailbox is not recognized" after a successful connect
```powershell
Get-ConnectionInformation | Format-List State,UserPrincipalName,TokenStatus,ModulePrefix
```
Workload cmdlets are generated at connect time — if `State` is not `Connected` you are not connected, and if you used `-Prefix Contoso` the cmdlet is `Get-ContosoMailbox`.

### Find side-by-side module versions that break Connect-MgGraph
```powershell
Get-InstalledModule Microsoft.Graph.Authentication -AllVersions | Select-Object Name,Version,InstalledLocation
```
Two versions of `Microsoft.Graph.Authentication` produce a misleading "Authentication needed. Please call Connect-MgGraph." on later cmdlets. Uninstall the extras.

### Remove an extra module version
```powershell
Uninstall-Module Microsoft.Graph.Authentication -RequiredVersion 2.25.0 -Force
```
Never run `Update-Module` on a module already imported in the session — close and reopen PowerShell first.

### Check the PowerShell version floor for the module you are loading
```powershell
$PSVersionTable.PSVersion; (Get-Module PnP.PowerShell -ListAvailable).PowerShellVersion
```
Floors differ: PnP 3.x needs PS 7.4+ (5.1 unsupported); EXO 3.10.x needs Windows PowerShell 5.1 or PS 7.6+; Teams needs 5.1 or PS 7.2+; SPO Management Shell is Windows PowerShell 5.1 on Windows only.

### Load the Windows-only SPO module from PowerShell 7
```powershell
Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell
```
It cannot be installed on macOS or Linux at all; use PnP.PowerShell or Graph there. It also fails to load if the SharePoint Client Components SDK is on the same machine — uninstall the SDK.

### Stop chasing WinRM and Basic auth errors
```powershell
Get-Command -Module ExchangeOnlineManagement -Name Connect-ExchangeOnline | Select-Object -ExpandProperty Parameters | ForEach-Object { $_.Keys -contains 'UseRPSSession' }
```
Remote PowerShell is retired: `-UseRPSSession` is gone in 3.10.x, `New-PSSession`/`Import-PSSession` against outlook.office365.com no longer works, and enabling WinRM Basic auth does nothing.

### Work around a WAM sign-in hang on Windows
```powershell
Connect-ExchangeOnline -UserPrincipalName admin@contoso.onmicrosoft.com -ShowBanner:$false -DisableWAM
```
Graph equivalent persists across sessions: `Set-MgGraphOption -DisableLoginByWAM $true`. Teams has `-DisableWAM` only in 7.8.1-preview and later.

### Sign in on a machine with no browser
```powershell
Connect-MgGraph -Scopes "User.Read.All" -UseDeviceCode -NoWelcome
```
Per-module switches, not interchangeable: `Connect-ExchangeOnline -Device`, `Connect-MicrosoftTeams -UseDeviceAuthentication`, `Connect-PnPOnline -DeviceLogin -ClientId <id>`. `Connect-IPPSSession` and `Connect-SPOService` have no device-code option.

### Fix PowerShell Gallery failures behind a proxy or old TLS
```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
```
Windows PowerShell 5.1 only; PS 7 already negotiates TLS 1.2+. Allow TCP 443 to `cdn.powershellgallery.com` and `cdn.oneget.org`, and set `$env:HTTPS_PROXY` if your proxy is not the system one.

### Read an AADSTS code instead of guessing
| Code | Meaning | Fix |
| --- | --- | --- |
| AADSTS50076 / 50074 | MFA required or not satisfied | Complete the MFA prompt; do not script around it |
| AADSTS53003 | Blocked by Conditional Access | Exclude the module's app from the policy or sign in from a compliant device |
| AADSTS530035 | Blocked by security defaults | Legacy/unsafe auth path — use interactive modern auth |
| AADSTS65001 | Consent not granted for this app | Have an admin consent to the requested scopes |
| AADSTS50058 / 50173 | Stale or revoked session | Disconnect, close PowerShell, sign in again |

Conditional Access sees each module as its own app ("Microsoft Graph Command Line Tools" for Graph, your own app registration for PnP) — the CA exclusion has to name the right one.

### Capture a connection log when EXO sign-in fails silently
```powershell
Connect-ExchangeOnline -UserPrincipalName admin@contoso.onmicrosoft.com -ShowBanner:$false -EnableErrorReporting -LogDirectoryPath ~/EXOLogs -LogLevel All
```

## PnP.PowerShell app registration

### Fix "ClientId is required" / no app to sign in with
```powershell
Register-PnPEntraIDAppForInteractiveLogin -ApplicationName "PnP PowerShell" -Tenant contoso.onmicrosoft.com
```
The shared PnP Management Shell app was removed on 9 September 2024, so every admin must register their own. This creates a public client with an `http://localhost` redirect and prints the Application (client) ID — save it. Add `-DeviceLogin` to register without a local browser.

### Stop passing -ClientId on every connect
```powershell
$env:ENTRAID_APP_ID = "<your-app-client-id>"
```
With `ENTRAID_APP_ID` (or `ENTRAID_CLIENT_ID`) set, `Connect-PnPOnline -Url https://contoso.sharepoint.com -Interactive` works without `-ClientId`. Put it in your profile.

### Do not use the wrong registration cmdlet
```powershell
Get-Command Register-PnPEntraIDApp*, Register-PnPAzureADApp -ErrorAction SilentlyContinue | Select-Object Name
```
`Register-PnPEntraIDApp` (alias `Register-PnPAzureADApp`) creates a **certificate-based app-only** app — not the interactive-login one.

### Fix "connected to the wrong place" in PnP
```powershell
Get-PnPConnection | Format-List Url,ClientId,ConnectionType
```
`-Url` takes the site or tenant root (`https://contoso.sharepoint.com/sites/Marketing`), never the `-admin` URL; `Connect-SPOService` takes `https://contoso-admin.sharepoint.com`. Tenant-level PnP cmdlets use the separate `-TenantAdminUrl`.

## Graph consent and scopes

### See exactly what you are connected as
```powershell
Get-MgContext | Format-List Account,TenantId,AppName,ClientId,Scopes
```

### Find the cmdlet and permission an API needs
```powershell
Find-MgGraphCommand -Uri "/users/{id}/licenseDetails" -Method GET | Select-Object -First 1 -ExpandProperty Permissions
```

### Look up a permission by name before requesting it
```powershell
Find-MgGraphPermission "Group.ReadWrite" -PermissionType Delegated
```

### Fix "Insufficient privileges to complete the operation"
```powershell
Connect-MgGraph -Scopes "User.ReadWrite.All","Directory.ReadWrite.All" -NoWelcome
```
Scopes are consent, not authorization. Adding the scope fixes a *consent* gap; if it still fails you are missing the Entra directory role (User Administrator, Exchange Administrator, etc.). Scopes are accretive — reconnecting adds to what you already consented to.

### Fix a stale token after a role was granted
```powershell
Disconnect-MgGraph; Connect-MgGraph -Scopes "User.ReadWrite.All" -NoWelcome
```
New role assignments are not in the token you already hold. Same for Exchange RBAC: `Disconnect-ExchangeOnline -Confirm:$false` then reconnect.

### Fix "admin consent required" on first use
Ask a Global Administrator or Privileged Role Administrator to consent to "Microsoft Graph Command Line Tools" for the requested scopes — the delegated scope cannot be granted by a non-admin when it is an admin-level permission.

## Throttling

### Slow down an Exchange Online bulk loop
```powershell
Get-EXOMailbox -ResultSize Unlimited | ForEach-Object { Get-EXOMailboxStatistics -Identity $_.ExternalDirectoryObjectId; Start-Sleep -Milliseconds 200 }
```
EXO throttles on resource usage, not a fixed count. A 100-200 ms micro-delay plus batches of ~1,000 is the practical fix; there is no cmdlet to raise the limit.

### Batch around the 15-minute REST timeout
```powershell
Update-DistributionGroupMember -Identity "Sales Team" -Members $members[0..4999] -Confirm:$false
$members[5000..($members.Count-1)] | ForEach-Object { Add-DistributionGroupMember -Identity "Sales Team" -Member $_ }
```
REST cmdlets time out server-side after 15 minutes, so one call over thousands of objects fails regardless of your network. `Update-DistributionGroupMember` **replaces** the whole membership on every call — never loop it over chunks or you keep only the last one; seed with one call, then add the rest individually.

### Handle a Graph 429
```powershell
try { Get-MgUser -All } catch { $_.Exception.Response.Headers }
```
`Retry-After` only comes back on the 429 itself, so it is empty on a successful paged call. The SDK already retries and honours it. If you still get throttled, lower `-PageSize`, stop polling in loops, and never fire parallel calls at the same resource.

### Handle a SharePoint 429/503
SharePoint returns 429 or 503 with `Retry-After`; PnP retries automatically. Mitigation is fewer concurrent requests, no request spikes, and running large scans off-peak — ignoring `Retry-After` gets the whole client blocked.

### Use Teams batch cmdlets instead of a per-user loop
```powershell
New-CsBatchPolicyAssignmentOperation -PolicyType TeamsMeetingPolicy -PolicyName "Kiosk" -Identity $upns -OperationName "Kiosk rollout"
```
Max 5,000 users per batch, and only a few batches in flight at once. Track with `Get-CsBatchPolicyAssignmentOperation -OperationId <id>`.

## Results silently truncated

### Get all mailboxes, not the first 1,000
```powershell
Get-EXOMailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox
```
Every Exchange `Get-*` cmdlet defaults to `-ResultSize 1000` and prints no warning when it stops.

### Get all Graph objects, not the first page
```powershell
Get-MgUser -All -Property Id,DisplayName,UserPrincipalName
```
Without `-All` you get one page (100 for most collections). `-Top` caps the total; it is not paging.

### Get all sites, not the default page
```powershell
Get-SPOSite -Limit All -IncludePersonalSite $true
```
PnP equivalent: `Get-PnPTenantSite -IncludeOneDriveSites`. Note `Get-SPOSite` never returns sites in the recycle bin.

### Page a large audit log search
```powershell
$sid = [guid]::NewGuid().ToString()
$all = [System.Collections.Generic.List[object]]::new()
do {
    $page = Search-UnifiedAuditLog -StartDate (Get-Date).AddDays(-7) -EndDate (Get-Date) -SessionId $sid -SessionCommand ReturnLargeSet -ResultSize 5000
    $all.AddRange([object[]]$page)
} while ($page.Count -gt 0)
$all | Sort-Object Identity -Unique | Sort-Object CreationDate | Export-Csv ~/audit.csv -NoTypeInformation
```
Default is 100 records. `ReturnLargeSet` reaches 50,000 but returns unsorted data with duplicates; `ReturnNextPreviewPage` is sorted but caps at 5,000. Never mix the two on one `SessionId`. Past 50,000, split the date range.

### Page large SharePoint lists
```powershell
Get-PnPListItem -List "Documents" -PageSize 2000 -Fields "Title","FileLeafRef"
```
Without `-PageSize` a big list will time out rather than truncate.

## Property is empty or null

### Ask Graph for the property you actually want
```powershell
Get-MgUser -UserId user@contoso.com -Property Id,DisplayName,Department,AccountEnabled,SignInActivity | Select-Object Department,AccountEnabled
```
Graph returns a limited default property set and silently omits the rest; `-Property` is aliased `-Select`. `signInActivity` is GA in v1.0 but needs the `AuditLog.Read.All` scope and an Entra ID P1/P2 licence, and selecting it caps the page size at 500.

### Ask EXO for the property you actually want
```powershell
Get-EXOMailbox -Identity user@contoso.com -Properties LitigationHoldEnabled,ArchiveStatus,ForwardingSmtpAddress
```
`Get-EXO*` cmdlets return the Minimum property set by default. Use `-Properties` for named fields; avoid `-PropertySets All`, which pulls everything and is slow.

### Stop values being cut off with "..."
```powershell
Get-EXOMailbox -Identity user@contoso.com -Properties EmailAddresses | Format-List
```
`Format-Table` truncates to console width — that is a display artifact, not missing data. Never pipe `Format-*` into `Export-Csv`.

### Flatten a collection property for CSV
```powershell
Get-MgGroup -GroupId $id -Property Id,DisplayName,ProxyAddresses | Select-Object DisplayName,@{n='ProxyAddresses';e={$_.ProxyAddresses -join ';'}}
```
Without this, arrays export as `System.String[]`. `Select-Object -ExpandProperty` gets one collection out; a calculated property keeps the other columns.

### Know when SPO omits properties on purpose
Using `-Limit` or `-Filter` on `Get-SPOSite` leaves sharing and policy properties (SharingCapability, SensitivityLabel, ConditionalAccessPolicy, DenyAddAndCustomizePages, …) at default values. Re-query the single site by `-Identity` to read them.

## Slow scripts

### Filter server-side, not in PowerShell
```powershell
Get-EXOMailbox -Filter "RecipientTypeDetails -eq 'SharedMailbox'" -ResultSize Unlimited
```
`Get-EXOMailbox -ResultSize Unlimited | Where-Object {...}` downloads every mailbox first — minutes versus seconds in a large tenant. `-Filter` supports only a subset of properties; check before assuming.

### Filter Graph server-side
```powershell
Get-MgUser -Filter "accountEnabled eq false and userType eq 'Member'" -All -Property Id,UserPrincipalName
```
For `endsWith`, `$search`, or `$count`, add `-ConsistencyLevel eventual -CountVariable total`.

### Replace a per-user cmdlet call in a loop with one bulk read
```powershell
$stats = Get-EXOMailbox -ResultSize Unlimited -Properties ArchiveStatus | Group-Object ArchiveStatus -AsHashTable
```
One call returning 5,000 objects beats 5,000 calls returning one, every time.

### Stop growing arrays with +=
```powershell
$results = [System.Collections.Generic.List[object]]::new(); Get-EXOMailbox -ResultSize Unlimited | ForEach-Object { $results.Add($_) }
```
`$a += $x` rebuilds the whole array each iteration — quadratic. Better still, let the pipeline produce the output and assign it directly.

## Propagation delays

### Wait for a new object to be readable
```powershell
do { Start-Sleep -Seconds 15; $u = Get-MgUser -UserId user@contoso.com -ErrorAction SilentlyContinue } until ($u)
```
Directory writes replicate asynchronously — a read immediately after `New-MgUser` can legitimately return 404.

### Wait for a mailbox to exist after licensing
```powershell
do { Start-Sleep -Seconds 30; $mbx = Get-EXOMailbox -Identity user@contoso.com -ErrorAction SilentlyContinue } until ($mbx)
```
Mailbox provisioning after a license assignment commonly takes several minutes. Group-connected SharePoint sites and Teams can take longer still; restoring a Microsoft 365 group can take up to 48 hours to bring back all content.

## Deleted objects and restore

| Object | Window | Restore with |
| --- | --- | --- |
| Entra user | 30 days | `Restore-MgDirectoryDeletedItem` |
| Microsoft 365 / cloud security group | 30 days | `Restore-MgDirectoryDeletedItem` |
| Mailbox (soft-deleted) | 30 days | `Undo-SoftDeletedMailbox` |
| SharePoint site | 93 days | `Restore-SPODeletedSite` / `Restore-PnPTenantRecycleBinItem` |
| Site content (recycle bin) | 93 days total, second stage included | `Restore-PnPRecycleBinItem` |
| Mailbox items (Recoverable Items) | 14 days default, 30 max | `Restore-RecoverableItems` |

### List and restore a deleted user
```powershell
Get-MgDirectoryDeletedItemAsUser -All | Select-Object Id,UserPrincipalName,DeletedDateTime
```
Then `Restore-MgDirectoryDeletedItem -DirectoryObjectId <id>`. Needs `User.ReadWrite.All` plus a role that can restore users.

### List and restore a deleted group
```powershell
Get-MgDirectoryDeletedItemAsGroup -All | Select-Object Id,DisplayName,DeletedDateTime
```
Then `Restore-MgDirectoryDeletedItem -DirectoryObjectId <id>`. Distribution groups have no soft-delete — they are gone immediately.

### Restore a soft-deleted mailbox
```powershell
Get-EXOMailbox -SoftDeletedMailbox -ResultSize Unlimited | Select-Object DisplayName,PrimarySmtpAddress,ExternalDirectoryObjectId
```
If the user object still exists, restore the **user** first (that reconnects the mailbox); use `Undo-SoftDeletedMailbox` only when the account was deleted too.

### Restore a deleted site
```powershell
Get-SPODeletedSite -IncludePersonalSite | Where-Object Url -like "*Marketing*" | Restore-SPODeletedSite
```
PnP equivalent: `Get-PnPTenantRecycleBinItem` then `Restore-PnPTenantRecycleBinItem -Url https://contoso.sharepoint.com/sites/Marketing`. Restoring a group-connected site restores the group, but only within the group's 30 days.

## Long-running scripts

### Guard against session expiry mid-script
```powershell
if ((Get-ConnectionInformation).State -ne 'Connected') { Connect-ExchangeOnline -UserPrincipalName admin@contoso.onmicrosoft.com -ShowBanner:$false }
```
Check `TokenExpiryTimeUTC` and `TokenStatus` on the same object. Graph equivalent: `if (-not (Get-MgContext)) { Connect-MgGraph -Scopes "User.Read.All" -NoWelcome }`.

### Do not reconnect in a loop
```powershell
Connect-ExchangeOnline -UserPrincipalName admin@contoso.onmicrosoft.com -ShowBanner:$false -CommandName Get-Mailbox,Set-Mailbox
```
Repeated `Connect`/`Disconnect` inside one session leaks memory. Import only the cmdlets you need with `-CommandName`.

### Close one connection out of several
```powershell
Disconnect-ExchangeOnline -ConnectionId (Get-ConnectionInformation | Where-Object IsEopSession -eq $true).ConnectionId -Confirm:$false
```
`Disconnect-ExchangeOnline` covers both `Connect-ExchangeOnline` and `Connect-IPPSSession`; use `-Prefix` at connect time when you hold both.

## Encoding and CSV

### Export CSV that Excel opens correctly
```powershell
Get-EXOMailbox -ResultSize Unlimited | Select-Object DisplayName,PrimarySmtpAddress | Export-Csv ~/mailboxes.csv -NoTypeInformation -Encoding utf8BOM
```
`utf8BOM` is PowerShell 7; in Windows PowerShell 5.1 use `-Encoding UTF8` (which already writes a BOM). Without the BOM, accented names arrive as mojibake in Excel.

### Read a CSV whose encoding is not the default
```powershell
Import-Csv ~/users.csv -Encoding utf8 -Delimiter ";"
```
On a machine with a comma decimal separator, Excel writes `;` — `Import-Csv` still defaults to `,` and gives you one column.

### Stop Format-* from poisoning an export
Pipe objects, never `Format-Table`/`Format-List`, into `Export-Csv` or `ConvertTo-Json`; format objects serialize as `Microsoft.PowerShell.Commands.Internal.Format.*` rows.

## Deprecated cmdlets

| Retired | Replacement |
| --- | --- |
| `Connect-MsolService` | `Connect-MgGraph` |
| `Get-MsolUser` / `New-MsolUser` / `Set-MsolUser` | `Get-MgUser` / `New-MgUser` / `Update-MgUser` |
| `Set-MsolUserLicense` + `New-MsolLicenseOptions` | `Set-MgUserLicense` |
| `Get-MsolGroup` / `Get-MsolGroupMember` | `Get-MgGroup` / `Get-MgGroupMember` |
| `Get-MsolRole` / `Get-MsolRoleMember` | `Get-MgDirectoryRole` / `Get-MgDirectoryRoleMember` |
| `Connect-AzureAD` / `Get-AzureADUser` | `Connect-MgGraph` / `Get-MgUser` |
| `Connect-EXOPSSession` | `Connect-ExchangeOnline` |
| `New-PSSession` + `Import-PSSession` (EXO) | `Connect-ExchangeOnline` (REST) |
| `Get-PSSession` | `Get-ConnectionInformation` |
| `Remove-PSSession` | `Disconnect-ExchangeOnline` |
| `-UseRPSSession` | removed in 3.10.x; REST is the only transport |
| `New-CsOnlineSession` | `Connect-MicrosoftTeams` |
| `Get-UserAnalyticsConfig` / `Set-UserAnalyticsConfig` | `Get-MyAnalyticsFeatureConfig` / `Set-MyAnalyticsFeatureConfig` |
| `Get-VivaFeatureCategory` | deprecated in module 3.8.0, no direct replacement |

MSOnline and AzureAD/AzureADPreview are retired and unlisted on the PowerShell Gallery; the underlying Azure AD Graph API (graph.windows.net) is gone, which is why they fail rather than warn. Replace with `Microsoft.Graph` or `Microsoft.Entra`. Not deprecated despite the rumour: `Microsoft.Online.SharePoint.PowerShell`, still shipping monthly.

## Service health

### Check whether it is you or Microsoft
```powershell
Get-MgServiceAnnouncementHealthOverview -All | Where-Object Status -ne 'serviceOperational' | Select-Object Service,Status
```
Needs `ServiceHealth.Read.All`. Drill in with `Get-MgServiceAnnouncementHealthOverviewIssue -ServiceHealthId "Exchange Online"`.

### Read the advisories behind an incident
```powershell
Get-MgServiceAnnouncementIssue -Filter "status ne 'serviceRestored'" | Select-Object Id,Title,Service,StartDateTime
```

## Diagnostics one-liners

### Show PowerShell and all admin module versions
```powershell
$PSVersionTable.PSVersion; Get-Module ExchangeOnlineManagement,MicrosoftTeams,PnP.PowerShell,Microsoft.Graph.Authentication,Microsoft.Online.SharePoint.PowerShell -ListAvailable | Select-Object Name,Version
```

### Show every live connection at once
```powershell
Get-ConnectionInformation; Get-MgContext; Get-PnPConnection; Get-CsTenant | Select-Object DisplayName,TenantId
```
Run only the lines for workloads you actually connected to; each errors harmlessly when not connected.

### Test network reachability to the endpoints
```powershell
'login.microsoftonline.com','graph.microsoft.com','outlook.office365.com','contoso.sharepoint.com' | ForEach-Object { Test-Connection $_ -TcpPort 443 -Count 1 }
```
PowerShell 7 syntax; on Windows PowerShell 5.1 use `Test-NetConnection <host> -Port 443`.

### Show the proxy PowerShell will actually use
```powershell
[System.Net.WebRequest]::DefaultWebProxy.GetProxy("https://graph.microsoft.com"); $env:HTTPS_PROXY
```

### Re-enable Get-Help for Exchange cmdlets
```powershell
Connect-ExchangeOnline -UserPrincipalName admin@contoso.onmicrosoft.com -ShowBanner:$false -LoadCmdletHelp
```
Since module 3.7.0 cmdlet help is not loaded by default, so `Get-Help Get-Mailbox` returns nothing useful.

## Gotchas

- Every Exchange `Get-*` cmdlet stops at 1,000 objects with no warning — `-ResultSize Unlimited` or your report is wrong, not short.
- `Get-MgUser` without `-All` returns one page and without `-Property` returns a trimmed object; both fail silently.
- Graph `-Scopes` is consent only — you still need the matching Entra role, and a role added after you connected needs a reconnect.
- PnP.PowerShell 3.x is the only module here that requires your own Entra app registration; do not copy `-ClientId` onto the other four.
- `Connect-SPOService` takes the `-admin` URL, `Connect-PnPOnline -Url` takes the site URL; swapping them fails with an unhelpful message.
- Only one `Connect-SPOService` connection exists per session per geo — reconnecting silently replaces the previous one.
- `Get-PSSession` sees nothing: EXO and S&C are REST, so use `Get-ConnectionInformation`.
- Two versions of `Microsoft.Graph.Authentication` produce "Authentication needed. Please call Connect-MgGraph." on cmdlets that ran fine yesterday.
- `Connect-IPPSSession` does not exist in PowerShell 7 on macOS/Linux, and `Microsoft.Online.SharePoint.PowerShell` cannot be installed there at all.
- REST cmdlets time out after 15 minutes server-side; a single bulk call over thousands of objects fails no matter how fast your link is.
- `Search-UnifiedAuditLog` returns 100 records by default and caps at 50,000 per session — mixing `ReturnLargeSet` and `ReturnNextPreviewPage` on one SessionId caps you at 10,000.
- `Format-Table` truncation looks exactly like missing data; never pipe `Format-*` into `Export-Csv`.
- `$array += $item` in a loop over thousands of objects is the single most common reason an M365 script "hangs".
- Soft-delete windows differ: 30 days for users, groups and mailboxes, 93 days for SharePoint sites — restore the user before the mailbox.
