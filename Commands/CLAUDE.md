# Microsoft 365 PowerShell KB

Task-oriented cookbook for administering a cloud-only M365 tenant from PowerShell. Files live in [m365-kb/](m365-kb/).

Format throughout: `### Imperative task` → one-liner in a `powershell` fence → at most one note line. Grep the task headings first; they are phrased as the thing you want to do.

## When to read which file

| File | Read it for |
|---|---|
| [00-setup-and-connect.md](m365-kb/00-setup-and-connect.md) | Installing/updating modules, the connect one-liner for any workload, Graph scopes, PnP app registration, multi-tenant sessions |
| [01-exchange-online.md](m365-kb/01-exchange-online.md) | Mailboxes, permissions, shared/room mailboxes, calendars, forwarding, distribution groups, mail flow, message trace, quarantine |
| [02-teams.md](m365-kb/02-teams.md) | Teams and channels, membership, policy assignment (incl. batch), guest/external access, Teams Phone |
| [03-sharepoint-onedrive.md](m365-kb/03-sharepoint-onedrive.md) | Sites, permissions and sharing, lists/libraries, files, OneDrive, tenant settings, reporting |
| [04-security-compliance.md](m365-kb/04-security-compliance.md) | Audit log search, content search and purge, eDiscovery holds, retention, sensitivity labels, DLP |
| [05-microsoft-graph.md](m365-kb/05-microsoft-graph.md) | Users, groups, licensing, devices, sign-in logs, app registrations, directory roles, raw Graph calls |
| [06-recipes.md](m365-kb/06-recipes.md) | Multi-module jobs: onboarding, offboarding, licence waste, permission audits, bulk-from-CSV |
| [07-troubleshooting.md](m365-kb/07-troubleshooting.md) | Symptom → cause → fix: auth errors, throttling, truncated results, empty properties, slow scripts |
| [08-reference.md](m365-kb/08-reference.md) | Lookup tables: scope-per-task, admin roles, licence SKUs, OData operators, KQL, RecordTypes |

Rule of thumb: identity, licensing and reporting → Graph (05). Mailbox and mail-flow configuration → Exchange (01). Site contents → PnP (03). Anything spanning two workloads → check 06 first.

## Conventions in every file

- **Auth is interactive admin + MFA.** No stored credentials, no app-only certificate flows except where called out.
- Placeholders: tenant `contoso`, users `user@contoso.com` / `admin@contoso.com`, sites `https://contoso.sharepoint.com/sites/Marketing`. **`fabrikam.com` always means an external party** (external sender, federation partner, forwarding target).
- Preview/beta cmdlets are marked as such.
- MSOnline and AzureAD are retired and appear only as "replace with X".

## Platform constraints (this machine is macOS)

Two things in this KB **cannot run on macOS or Linux** — they need Windows:

- `Connect-IPPSSession`, and therefore everything in 04-security-compliance.md.
- `Microsoft.Online.SharePoint.PowerShell` (`*-SPO*` cmdlets) — it will not install at all. Use the PnP equivalents in 03 instead; `*-PnPTenant*` covers most of what the SPO module does.

Exchange Online, Teams, PnP and Graph are all fine cross-platform. `ExchangeOnlineManagement` 3.10+ requires PowerShell 7.6+, PnP 3.x requires 7.4+.

## Maintaining the KB

Cmdlet and parameter names are verified mechanically rather than by eye. To re-verify after edits: parse every fenced block with `[System.Management.Automation.Language.Parser]::ParseInput`, resolve each command against installed module manifests, and check parameters for non-installed modules against `https://learn.microsoft.com/en-us/powershell/module/{exchange|microsoftteams|sharepoint-online}/{cmdlet}` (the `id="-paramname"` anchors on those pages are the full parameter list).

That catches names and syntax but not meaning. The errors it misses, and which a review of new content should look for: a `-Filter` that returns the wrong set, a property selected that the cmdlet never returns (Graph `-Select`, `Get-EXOMailbox -Properties`, `Get-SPOSite`/`Get-PnPTenantSite -Detailed`), a cmdlet that replaces rather than appends, and limits or retention windows quoted from memory.
