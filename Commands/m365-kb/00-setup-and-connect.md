# Setup & Connecting

Five modules, five sign-ins: `ExchangeOnlineManagement` 3.10.1 (`Connect-ExchangeOnline`, `Connect-IPPSSession`), `MicrosoftTeams` 7.9.0 (`Connect-MicrosoftTeams`), `Microsoft.Online.SharePoint.PowerShell` 16.0.27515.12000 (`Connect-SPOService`), `PnP.PowerShell` 3.4.1 (`Connect-PnPOnline`), `Microsoft.Graph` 2.39.0 (`Connect-MgGraph`).

## Prerequisites

### Check your PowerShell version
```powershell
$PSVersionTable.PSVersion
```
Floors differ per module: PnP.PowerShell 3.x needs PS 7.4+ (no 5.1 at all); ExchangeOnlineManagement 3.10.x needs PS 7.6+ or Windows PowerShell 5.1; MicrosoftTeams needs 5.1 or 7.2+; the SPO module is Windows PowerShell 5.1 only.

### Set the execution policy (Windows)
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```
Without this the EXO and Graph modules fail to load with "running scripts is disabled on this system".

### Force TLS 1.2 before installing (Windows PowerShell 5.1 only)
```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
```
PowerShell 7 already negotiates TLS 1.2+; only old Windows boxes need this to reach the PowerShell Gallery.

### Load the SPO module inside PowerShell 7 on Windows
```powershell
Import-Module Microsoft.Online.SharePoint.PowerShell -UseWindowsPowerShell
```
The module is Windows-only and cannot be installed on macOS or Linux at all — use PnP.PowerShell or Graph there.

## Installing and updating

### Install everything, current user, no elevation
```powershell
Install-Module ExchangeOnlineManagement,MicrosoftTeams,PnP.PowerShell,Microsoft.Graph -Scope CurrentUser
```
Add `Microsoft.Online.SharePoint.PowerShell` on Windows. `Microsoft.Graph` is a ~40-submodule meta-module and is slow; install only the submodules you use plus `Microsoft.Graph.Authentication` if you care about install time.

### Install just the Graph submodules you actually use
```powershell
Install-Module Microsoft.Graph.Authentication,Microsoft.Graph.Users,Microsoft.Graph.Groups -Scope CurrentUser
```

### See what is installed and where
```powershell
Get-Module -ListAvailable ExchangeOnlineManagement,MicrosoftTeams,PnP.PowerShell,Microsoft.Graph.Authentication | Select-Object Name,Version,ModuleBase
```

### Find side-by-side duplicate versions
```powershell
Get-Module -ListAvailable | Group-Object Name | Where-Object Count -gt 1 | Select-Object Name,Count
```
Two versions of `Microsoft.Graph.Authentication` is the classic cause of "Authentication needed. Please call Connect-MgGraph." on cmdlets that run after a successful connect.

### Remove the stale version
```powershell
Uninstall-Module Microsoft.Graph.Authentication -RequiredVersion 2.25.0
```

### Update a module
```powershell
Update-Module ExchangeOnlineManagement
```
Never run this while the module is imported in the current session — close PowerShell and reopen first.

### Uninstall every version of a module
```powershell
Uninstall-Module MicrosoftTeams -AllVersions
```

## Connecting (interactive MFA)

### Connect to Exchange Online
```powershell
Connect-ExchangeOnline -UserPrincipalName admin@contoso.onmicrosoft.com -ShowBanner:$false
```
No app registration needed — a Microsoft first-party app handles interactive MFA. Omit `-ExchangeEnvironmentName`; `O365Default` is correct for commercial and GCC.

### Connect to Exchange Online with cmdlet help loaded
```powershell
Connect-ExchangeOnline -UserPrincipalName admin@contoso.onmicrosoft.com -LoadCmdletHelp -ShowBanner:$false
```
Since module 3.7.0 help is not loaded by default, so `Get-Help Get-Mailbox` returns nothing useful without this.

### Import only the cmdlets you need (faster, less memory)
```powershell
Connect-ExchangeOnline -UserPrincipalName admin@contoso.onmicrosoft.com -CommandName Get-Mailbox,Set-Mailbox,Get-EXOMailbox -ShowBanner:$false
```

### Connect to Security & Compliance (Microsoft Purview)
```powershell
Connect-IPPSSession -UserPrincipalName admin@contoso.onmicrosoft.com
```
Same module as Exchange Online, but **not available in PowerShell 7 on macOS or Linux** — Windows only. RBAC comes from Purview role groups, not Exchange RBAC.

### Connect to Security & Compliance for eDiscovery search cmdlets
```powershell
Connect-IPPSSession -UserPrincipalName admin@contoso.onmicrosoft.com -EnableSearchOnlySession
```
Added in 3.9.0; needed for eDiscovery cmdlets that reach out to other Microsoft 365 services.

### Connect to Microsoft Teams
```powershell
Connect-MicrosoftTeams
```
Takes no parameters in the normal admin case; the sign-in prompt appears on its own. Add `-TenantId contoso.onmicrosoft.com` if your account exists in more than one tenant.

### Connect to SharePoint Online (SPO module, Windows)
```powershell
Connect-SPOService -Url https://contoso-admin.sharepoint.com
```
Must be the `-admin` URL, and must have no `-Credential` — passing credentials is the legacy non-MFA path. Requires the SharePoint Administrator role.

### Register your own Entra ID app for PnP (one time, mandatory)
```powershell
Register-PnPEntraIDAppForInteractiveLogin -ApplicationName "PnP PowerShell" -Tenant contoso.onmicrosoft.com
```
The shared "PnP Management Shell" app was removed 9 September 2024, so PnP 3.x will not connect without your own app. This creates a public client with an `http://localhost` redirect and requests delegated `AllSites.FullControl`, `Group.ReadWrite.All`, `User.ReadWrite.All`, `TermStore.ReadWrite.All`. **Save the Application (client) ID it prints.**

### Register the PnP app from a machine with no browser
```powershell
Register-PnPEntraIDAppForInteractiveLogin -ApplicationName "PnP PowerShell" -Tenant contoso.onmicrosoft.com -DeviceLogin
```
Do not confuse this cmdlet with `Register-PnPEntraIDApp` — that one builds a certificate-based app for unattended app-only access.

### Request narrower PnP permissions
```powershell
Register-PnPEntraIDAppForInteractiveLogin -ApplicationName "PnP PowerShell" -Tenant contoso.onmicrosoft.com -SharePointDelegatePermissions "AllSites.FullControl" -GraphDelegatePermissions "Group.Read.All"
```

### Connect with PnP.PowerShell
```powershell
Connect-PnPOnline -Url "https://contoso.sharepoint.com" -Interactive -ClientId <your-app-client-id>
```
`-Url` is the site or tenant root URL, never the `-admin` URL; `-TenantAdminUrl` is a separate optional parameter for tenant-level cmdlets.

### Connect PnP to a specific site
```powershell
Connect-PnPOnline -Url "https://contoso.sharepoint.com/sites/Marketing" -Interactive -ClientId <your-app-client-id>
```

### Stop typing -ClientId on every PnP connect
```powershell
$env:ENTRAID_CLIENT_ID = "<your-app-client-id>"
```
`ENTRAID_APP_ID` works too. With either set, `Connect-PnPOnline -Interactive` needs no `-ClientId`. Set it permanently in your PowerShell profile or as a user environment variable.

### Cache the PnP sign-in / force a fresh one
```powershell
Connect-PnPOnline -Url "https://contoso.sharepoint.com" -Interactive -ClientId <your-app-client-id> -PersistLogin
```
`-ForceAuthentication` does the opposite and discards the cached token; `Disconnect-PnPOnline -ClearPersistedLogin` clears a persisted one.

### Connect to Microsoft Graph
```powershell
Connect-MgGraph -Scopes "User.Read.All","Group.ReadWrite.All" -NoWelcome
```
There is **no `-Interactive` switch** — browser sign-in is already the default. No app registration is needed in a commercial tenant; the SDK uses the first-party "Microsoft Graph Command Line Tools" app (`14d82eec-204b-4c2f-b7e8-296a70dab67e`), and an admin must consent to admin-level scopes on first use.

### Keep the Graph sign-in across PowerShell sessions
```powershell
Connect-MgGraph -Scopes "User.Read.All" -NoWelcome
```
Interactive sign-in already defaults to `CurrentUser`, so the token is cached and survives new shells. Use `-ContextScope Process` to confine it to this shell (app-only and managed-identity connects default to `Process`).

### Use Graph beta cmdlets
```powershell
Install-Module Microsoft.Graph.Beta -Scope CurrentUser; Get-MgBetaUser -UserId user@contoso.com
```
Beta lives in a separate module with `Get-MgBeta*` naming — there is no profile switch. **Beta APIs are preview and can change without notice.**

### Sign in on a machine with no browser
```powershell
Connect-ExchangeOnline -UserPrincipalName admin@contoso.onmicrosoft.com -Device
Connect-MgGraph -Scopes "User.Read.All" -UseDeviceCode -NoWelcome
Connect-MicrosoftTeams -UseDeviceAuthentication
Connect-PnPOnline -Url "https://contoso.sharepoint.com" -DeviceLogin -ClientId <your-app-client-id>
```
`Connect-IPPSSession` and `Connect-SPOService` have no device-code option at all.

### Work around WAM hangs on Windows
```powershell
Connect-ExchangeOnline -UserPrincipalName admin@contoso.onmicrosoft.com -DisableWAM -ShowBanner:$false
Set-MgGraphOption -DisableLoginByWAM $true
```
`Connect-IPPSSession -DisableWAM` and `Connect-MicrosoftTeams -DisableWAM` (7.8.1-preview+, explicitly temporary) exist too. The Graph option persists across sessions.

## Graph scopes and permissions

### See what you are actually consented to
```powershell
Get-MgContext | Select-Object -ExpandProperty Scopes
```

### Find the scope a cmdlet needs
```powershell
Find-MgGraphCommand -Command Get-MgUser | Select-Object -First 1 -ExpandProperty Permissions
```

### Find the cmdlet behind a Graph URL
```powershell
Find-MgGraphCommand -Uri '/users/{id}' -Method GET -ApiVersion beta
```

### Search permissions by name
```powershell
Find-MgGraphPermission mail.read -PermissionType Delegated
```

### Add a scope you forgot, without losing the ones you have
```powershell
Connect-MgGraph -Scopes "Directory.Read.All" -NoWelcome
```
Scopes are accretive — re-connecting adds to what you already consented to rather than replacing it.

## Verifying and disconnecting

### Check what you are connected as
```powershell
Get-ConnectionInformation | Select-Object UserPrincipalName,ConnectionUri,ModulePrefix,ConnectionId,State
Get-MgContext | Select-Object Account,TenantId,AuthType,ContextScope
Get-PnPConnection | Select-Object Url,ClientId,ConnectionType
Get-CsTenant | Select-Object DisplayName,TenantId
Get-SPOTenant
```
`Get-PSSession` sees none of these — REST connections are invisible to it.

### Disconnect everything cleanly
```powershell
Disconnect-ExchangeOnline -Confirm:$false; Disconnect-MicrosoftTeams; Disconnect-PnPOnline; Disconnect-SPOService; Disconnect-MgGraph
```
`Disconnect-ExchangeOnline` covers both `Connect-ExchangeOnline` and `Connect-IPPSSession`. Leaving EXO sessions open burns your per-user connection quota until they time out.

## Multiple connections in one shell

### Namespace a second Exchange-family connection
```powershell
Connect-IPPSSession -UserPrincipalName admin@contoso.onmicrosoft.com -Prefix SCC
```
Now `Get-SCCLabel` instead of `Get-Label`, so Purview cmdlets cannot silently collide with Exchange ones.

### Connect two tenants side by side
```powershell
Connect-ExchangeOnline -UserPrincipalName admin@contoso.onmicrosoft.com -Prefix C1 -ShowBanner:$false
Connect-ExchangeOnline -UserPrincipalName admin@fabrikam.onmicrosoft.com -Prefix C2 -ShowBanner:$false
Get-C1Mailbox -ResultSize 10; Get-C2Mailbox -ResultSize 10
```

### Close one connection, not all of them
```powershell
Get-ConnectionInformation | Where-Object ModulePrefix -eq 'C2' | Disconnect-ExchangeOnline -Confirm:$false
```
`Disconnect-ExchangeOnline -ModulePrefix C2` does the same thing directly.

### Hold two PnP connections in variables
```powershell
$mkt = Connect-PnPOnline -Url "https://contoso.sharepoint.com/sites/Marketing" -Interactive -ClientId <your-app-client-id> -ReturnConnection
Get-PnPList -Connection $mkt
```
`-ReturnConnection` keeps the connection out of the ambient session so `-Connection` targets it explicitly.

### Connect to everything
```powershell
$upn = 'admin@contoso.onmicrosoft.com'
Connect-ExchangeOnline -UserPrincipalName $upn -ShowBanner:$false
Connect-IPPSSession -UserPrincipalName $upn -Prefix SCC          # Windows only
Connect-MicrosoftTeams
Connect-SPOService -Url https://contoso-admin.sharepoint.com     # Windows only
Connect-PnPOnline -Url "https://contoso.sharepoint.com" -Interactive -ClientId $env:ENTRAID_CLIENT_ID
Connect-MgGraph -Scopes "User.Read.All","Group.ReadWrite.All","Directory.Read.All" -NoWelcome
```
Expect five or six separate MFA prompts — there is no single sign-on across the workloads.

## Gotchas

- No unified sign-in: every workload needs its own `Connect-*` and its own `Disconnect-*` in the same shell.
- Only PnP.PowerShell forces you to register your own Entra ID app. Do not copy `-ClientId` onto EXO, Teams, SPO, or Graph connects.
- `Connect-MgGraph -Interactive` is not a thing; interactive is the default. `-UseDeviceCode` is the headless option.
- Graph scopes are consent, not authorization — you still need the matching Entra role (Exchange Administrator, SharePoint Administrator, etc.) or the call fails with 403 despite a valid token.
- Two versions of `Microsoft.Graph.Authentication` produce misleading "Authentication needed. Please call Connect-MgGraph." errors on cmdlets after a successful connect. Keep exactly one.
- `Connect-SPOService` allows one connection per session per geo and silently replaces the previous one when run again.
- The SPO module fails to load if the SharePoint Client Components SDK is on the same machine; uninstall the SDK.
- `Get-PSSession`, `New-PSSession`, `Import-PSSession`, `Remove-PSSession` and `Invoke-Command` are all dead against Exchange Online and Purview — REST connections replaced remote PowerShell, and `-UseRPSSession` is gone from module 3.10.x.
- On macOS/Linux you cannot reach Security & Compliance PowerShell or the SPO module at all — use PnP/Graph for SharePoint and run Purview work from Windows.
- Repeated `Connect-ExchangeOnline`/`Disconnect-ExchangeOnline` cycles in one session leak memory; use `-CommandName` to limit what gets imported.
- MSOnline (`Connect-MsolService`) and AzureAD (`Connect-AzureAD`) are retired and unlisted on the Gallery — replace with Microsoft.Graph or Microsoft.Entra (`Connect-Entra` is an alias for `Connect-MgGraph`).
- Never run `Update-Module` on a module already imported in the session; reopen PowerShell first.
