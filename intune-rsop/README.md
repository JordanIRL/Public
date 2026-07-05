# 🔍 Intune Lens — `Get-IntuneResultantSettings.ps1` (v2)

*Resultant settings (RSOP) + cause-finding for Intune-managed Windows devices.*

**The questions this answers:**

1. *"What are ALL the settings that actually apply to this device?"* — across Settings Catalog, Endpoint Security (ASR, AV, Firewall, BitLocker, EDR, App Control…), Security Baselines, classic templates (incl. custom OMA-URI), ADMX, Compliance, Windows Update profiles, platform scripts (including their **decoded script bodies**), and **app assignments** (policy type **Apps**, one entry per assignment intent — intent is a secondary field, so Uninstall assignments are first-class without polluting the type list).
2. *"WHAT is causing this problem on this device?"* — the report's **🔎 Investigate** tab turns a plain-language complaint (*"usb blocked"*, *"copilot uninstalls itself"*) into a ranked list of suspect policies, with the matching settings and the assignment path that delivers them.

## Quick start

```powershell
cd intune-rsop
./Get-IntuneResultantSettings.ps1          # ← no flags = guided menu
```

```
  🔍 Intune Lens v2.5.1
  Tenant 29vvx0.onmicrosoft.com  |  signed in as you@tenant.com
  Policy corpus: 21 policies (16 assigned), 3 filters, pulled 09:14

  What do you want to look up?
   [1] Device(s) by serial number
   [2] Device(s) by name
   [3] All devices in an Entra group
   [4] Policies assigned directly to a group  (fast, no device math)
   [5] Devices matching an assignment filter
   [6] Tenant-wide settings inventory  (every policy + every setting; optional group/filter scope)
   [R] Refresh policy cache      [Q] Quit
```

Every query writes an interactive HTML report (offers to open it) and can optionally write a CSV. All the flags from v1 still work for scripting:

```powershell
./Get-IntuneResultantSettings.ps1 -SerialNumber 5CD1234XYZ,PF2ABCDE
./Get-IntuneResultantSettings.ps1 -Group "Sales Laptops"
./Get-IntuneResultantSettings.ps1 -Group "Pilot Ring 1" -GroupAssignedOnly
./Get-IntuneResultantSettings.ps1 -AssignmentFilter "Corp Windows 11"
./Get-IntuneResultantSettings.ps1 -All -ExportCsv tenant-inventory.csv   # whole-tenant documentation
./Get-IntuneResultantSettings.ps1 -All -ScopeGroup "Sales Laptops"       # what applies to this group?
./Get-IntuneResultantSettings.ps1 -All -ScopeFilter "Corp Windows 11"    # which policies use this filter?
```

### Scoped tenant export (`-All -ScopeGroup / -ScopeFilter`)

`-All` alone documents everything. Add `-ScopeGroup` (group name or id) and/or `-ScopeFilter` (assignment filter name or id) to answer *"what policies apply to this scope?"*:

- A policy is **in scope** when an assignment targets the scope group **directly**, via a **parent group** (the scope group's transitive `memberOf`), or via **All devices / All users** — or, for `-ScopeFilter`, when an assignment carries that filter.
- Each kept policy's *Assigned / applies via* starts with `Scope: …` spelling out **why** (`assigned to group 'X' [include filter: Y]`, `EXCLUDED via group 'X'`, `uses include filter 'F' on All devices`), followed by the full assignment summary.
- Policies that only **exclude** the scope stay visible with status `Excluded`; their settings land in the shadow set so Investigate can rule them in or out. Everything else is dropped from the report.
- Both scopes together must **both** match (AND).

**Files**: keep `report-template.html` next to the script (it's the rich report layout; without it a basic built-in layout is used).

## Prerequisites

- PowerShell 7+ · `Install-Module Microsoft.Graph.Authentication -Scope CurrentUser`
- Read-only scopes: `DeviceManagementConfiguration.Read.All`, `DeviceManagementManagedDevices.Read.All`, `Directory.Read.All`, plus `DeviceManagementApps.Read.All` for app assignments (skip the scope with `-SkipApps`) and `DeviceManagementScripts.Read.All` for platform-script bodies (skip with `-SkipScripts` — Graph gates the script endpoint behind this dedicated scope, so expect one extra consent prompt the first time)
- The tool never writes to the tenant.

## How applicability is computed

1. Transitive Entra group membership of the **device object** and the **primary user**, plus **All devices / All users** targets, minus **group exclusions**. Exclusions are kind-aware per the [Intune support matrix](https://learn.microsoft.com/intune/device-configuration/assign-device-profile#support-matrix): a device-group exclusion beats device-targeted includes, a user-group exclusion beats user-targeted includes, but cross-kind exclusions (e.g. user group excluded from an *All devices* assignment) are **not** applied by Intune — the report surfaces them as notes instead of wrongly flipping the status.
2. **Assignment filters** — three layers, in order:
   - a **local rule-language evaluator** parses the filter rule (`-eq/-ne/-in/-startsWith/-contains/and/or/not/…` over `device.*` properties, incl. `operatingSystemSKU` via `skuNumber`, `deviceTrustType`, `$null` literals and bare operators) and evaluates it against the device's live inventory record — the server-side preview report lags enrollment and pages at 100 rows, so live data decides whenever the rule is locally decidable;
   - for rules the local evaluator can't decide (e.g. `cpuArchitecture`, extension attributes), server-side `evaluateAssignmentFilter` (what the portal's filter preview uses), trying several request shapes because the endpoint is picky across tenants — a device *found* there counts as a match, and *absence* only counts as a non-match when the fully-paged result set is complete;
   - only if all of that fails does a policy show `Unknown` — and the exact error appears in the report's **Run diagnostics** panel.
3. Platform gating (iOS/Android/macOS profiles are not evaluated against Windows devices).
4. Prediction is cross-checked against the device's own check-in report (`getConfigurationPoliciesReportForDevice`); policies the device reported that weren't predicted show as `ReportedOnly`.

## The HTML report

- **Overview** — clickable stat cards (each jumps to the matching filtered view), a settings-per-policy-type table, conflict preview, a **Run diagnostics** panel (every Graph call that failed and what the tool did about it — no more silent gaps), and a **Find the cause of a problem** chip row that jumps straight into Investigate. The left panel adapts to the query: a **per-device report** shows the device identity + group memberships; a **tenant-wide or group inventory** shows a **scope + status breakdown** instead (assigned / not-assigned / excluded / unknown, as a bar and a click-to-filter list) — so a whole-tenant export opens straight onto "19 assigned, 9 unassigned" with the 9 cleanup candidates one click away.
- **🔎 Investigate** — the troubleshooting tab. Type the problem (*"usb blocked"*, *"copilot uninstalls itself"*) and/or pick a topic. Topics are grouped into five areas (*Devices & peripherals, Apps & browser, Network & files, Sign-in & privacy, Security & updates*) with an icon and a consistent name each; a topic expands your words into the synonyms Intune actually uses (USB → *removable storage, WPD, device installation, device control, RDVDeny…*; app removal → *uninstall intent, Remove-Appx, excluded Microsoft 365 apps, AppLocker…*) and auto-engages from your text — a leading glyph shows each chip's state (**↻** auto-detected, **✓** engaged, **✕** dismissed). Generic polarity words on their own (*blocked*, *disabled*, *off*) are treated as too vague to rank on — so *"usb blocked"* ranks the device-control policies, not every profile that happens to contain a *Block…* setting; pair a vague word with a topic or a specific term (an app name, *USB*, *BitLocker*) for a precise result. Output, ranked:
  - **Suspect cards** — each policy that delivers matching settings, with status badge, assignment path (*via group X*), and a ⚑ count of settings whose value *looks restrictive* for its name (heuristic — verify). The top card is called out as the **Most likely cause** when it carries restrictive values; the rest fall under *Other suspects*, and each card's left edge encodes confidence (red = restrictive, amber = applicability unknown, neutral = applies cleanly). Click a card to focus its settings; link out to the Settings tab.
  - **Matching settings table** — culprits first, highlighted, with a *Matched on* column showing which synonyms hit each row, incl. script bodies and app assignment intents.
  - **Targeted but NOT applying** — excluded/filtered near-misses, explicitly ruled out as the cause on *this* device but explaining "works on that other machine".
  - **Topic hints** — a collapsible *Why these suspects?* note (auto-opened when nothing applies) on where else to look: MDE portal Device Control, third-party DLP, hybrid GPO, Cloud Policy….
- **One filter bar for the whole report** — the search box (`/` focuses it; `a|b` = either, `"quoted phrase"` = exact, space = AND, matches highlighted) and the policy-type / category / policy / **status** dropdowns scope **Settings, Policies, Conflicts and Investigate alike**; tab badges show *filtered/total* and a note under the bar spells out the active scope. The **status** dropdown (offered only for the statuses that occur, with counts) isolates *applies / assigned*, *excluded / filtered out*, *not assigned* or *unknown / reported-only* — the fast path to "which policies aren't assigned to anything?". Tab-specific controls stay explicit: *hide duplicates* only affects Settings rows, *conflicts only* affects Settings + Policies, and Investigate keeps its own problem-description search (it hunts **within** the global scope). On long tables the column headers stay pinned below the filter bar as you scroll.
- **Detail inspector** — click any policy row (Policies tab, conflict source, Investigate suspect) or setting row (Settings / Investigate tables) for a side pane: status, why it applies (the full evaluation reasons), the **include/exclude assignment breakdown with filter names and modes**, template/baseline, assignment intent for apps, device-reported state, conflict cross-links, and a one-click "show only this policy's settings". A selected setting also gets a **Microsoft Learn** section — Microsoft's own concise description of the setting (baked in from the Settings Catalog / Endpoint Security definition) plus a **View on Microsoft Learn ↗** link (its documentation deep-link when the definition supplies one, otherwise a Learn search on the setting name / OMA-URI path).
- **Settings** — every setting with **Category** (the same grouping the portal uses, e.g. *Defender*, *BitLocker*), sortable columns, long/JSON values collapse with click-to-expand; click a row for its policy & assignment context.
- **Policies** — status badges, template/baseline version, assignment intent chip for apps, last-modified date, device-reported state, assignment reason; click a row for the full assignment picture.
- **Conflicts** — one card per conflicting setting with each policy's value; the cards honour the global filters and click through to the policy inspector.
- **Device matrix** (multi-device queries) — policies × devices grid: ✓ applies, ✕ excluded, ? unknown, R reported-only.
- **⬇ CSV (filtered)** exports exactly what you've filtered on screen. Light/dark theme with a manual toggle.

## CSV columns

`DeviceName, SerialNumber, PolicyType, AssignmentIntent, PolicyName, Category, Setting, Value, Conflict, AppliesVia, PolicyReported, PolicyId, SettingKey` — pivot-ready in Excel. App rows carry `PolicyType = Apps` with the intent (`Required install`, `Uninstall`, …) in `AssignmentIntent`; in scoped `-All` exports `AppliesVia` starts with the scope reason.

## What it pulls (and caches for `-CacheMinutes`, default 60)

| Source | Endpoint (beta) |
|---|---|
| Settings Catalog / modern ES / Baselines | `configurationPolicies` + per-policy `settings?$expand=settingDefinitions` |
| Setting category names | `configurationCategories` |
| Classic templates | `deviceConfigurations` |
| ADMX | `groupPolicyConfigurations` + `definitionValues` (with category paths) |
| Legacy ES / baselines | `intents` + `templates/{id}/categories?$expand=settingDefinitions` for real setting names |
| Compliance | `deviceCompliancePolicies` (`-SkipCompliance` to omit) |
| Windows Update | `windowsFeatureUpdateProfiles`, `windowsQualityUpdateProfiles`, `windowsDriverUpdateProfiles` (`-SkipUpdates`) |
| Platform scripts (incl. decoded bodies) | `deviceManagementScripts` + per-item GET for base64 content (`-SkipScripts`) |
| Apps, one entry per assignment intent | `deviceAppManagement/mobileApps?$filter=isAssigned eq true&$expand=assignments` (`-SkipApps`) |
| Filters | `assignmentFilters`, `evaluateAssignmentFilter` |
| Devices / directory | `managedDevices`, `devices/groups/users getMemberGroups`, `directoryObjects/getByIds`, `groups/{id}/transitiveMemberOf` (scoped `-All` only) |
| Device truth | `reports/getConfigurationPoliciesReportForDevice` |

Cache file: `~/.intune-rsop-cache-<tenantId>.json` (schema-versioned; `-Refresh` or menu `[R]` re-pulls).

## Reading the statuses

| Status | Meaning |
|---|---|
| `Applies` / `Assigned` | Include assignment matched and survived its filter (scoped `-All`: an include path reaches the scope) |
| `Excluded` | Device or primary user is in an excluded group (scoped `-All`: the policy only *excludes* the scope) |
| `FilteredOut` | Group matched but the assignment filter removed the device |
| `Unknown` | Filter could not be evaluated locally **or** server-side — see Run diagnostics |
| `ReportedOnly` | Device reported it at check-in but prediction didn't find it — check indirect targeting |
| `NotAssigned` | (`-All` mode) policy exists but has no assignments — cleanup candidate |

## Known limitations

- Conflict matching is per setting key: Catalog/modern-ES/Baseline overlaps are caught; the same CSP via ADMX or a classic template can't be auto-correlated with a Catalog key.
- User-targeted policies are evaluated via the *primary* user; shared/kiosk devices may differ per signed-in user.
- Group mode enumerates *device* members (transitive); user members aren't expanded to their devices.
- The local filter evaluator covers the documented `device.*` properties and operators; exotic rules fall back to `Unknown` rather than guessing.
- **Encrypted custom OMA-URI values are decrypted** into the report via `getOmaSettingPlainTextValue` (needs the `DeviceManagementConfiguration.Read.All` scope you already grant; falls back to `(encrypted value - could not decrypt; view in portal)` if the call is refused). This means **the exported HTML/CSV can contain plaintext secrets** (VPN/Wi-Fi keys, certificates) — treat the export as sensitive. Settings Catalog secret values remain masked as `(secret)`; Graph does not return those in clear text.
- Apps: each assignment intent is evaluated independently. If *Required* and *Uninstall* both reach a device, both show `Applies` and the shared **Assignment intent** setting is flagged as a CONFLICT — Intune's own precedence (Required wins over Uninstall) is not modeled. Win32 supersedence and dependency chains aren't expanded.
- The ⚑ *restrictive value* marker in Investigate is a text heuristic over setting name + value polarity; treat it as a sorting aid, not a verdict.
- Script bodies are truncated at 6,000 chars in the report; settings of excluded/filtered policies are capped at 4,000 rows per device.
- Enrollment-time configuration (ESP/Autopilot profiles) is out of scope.
