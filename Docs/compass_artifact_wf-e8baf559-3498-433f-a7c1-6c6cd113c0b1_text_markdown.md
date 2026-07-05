# Runbook: Allow PDF Gear in Microsoft Purview Endpoint DLP

This runbook stops Microsoft Purview DLP warning popups when end users open files in **PDF Gear** (`PDFGear.exe`, pdfgear.com) on company-managed Windows endpoints, while leaving every other DLP rule untouched. The popup almost certainly originates from **Microsoft Purview Endpoint DLP** — a Windows toast notification raised by the Defender for Endpoint sensor on a monitored file activity (open, copy, print, USB, network share, cloud upload). Office policy tips render inside Word/Excel/Outlook ribbons; browser DLP popups render inside Edge/Chrome/Firefox. If your popup names PDF Gear and a file path with an **Allow** button, you are in the Endpoint DLP surface and this runbook applies end-to-end.

The cleanest fix is **not** to disable user notifications (that suppresses the toast but the block still fires silently); it is to ensure `PDFGear.exe` is not enforced against by any Endpoint DLP rule. In practice that means removing it from the **Restricted apps** list and any **Restricted app group**, and — if your tenant uses an explicit allow-list pattern — adding it to a trusted-apps group with action **Allow** or **Don't restrict file activity**. Plan for **~1 hour** for changes to propagate from the Purview service to onboarded devices, with **MDE Policy sync** as the fast-path lever (~10 minutes).

---

## 1. Identify which DLP surface is firing

Before changing anything, confirm Endpoint DLP is the source. The popup wording and process context are the fastest tells.

| Surface | Where the popup renders | Process / context | Audit workload |
|---|---|---|---|
| **Office DLP policy tips** | Word/Excel/PowerPoint Message Bar or Outlook compose banner | `WINWORD.EXE`, `OUTLOOK.EXE`, etc. | Exchange / SharePoint / OneDrive |
| **Endpoint DLP** | Native Windows toast, names policy + file + app, optional **Allow** button | `PDFGear.exe` (any third-party process) | **Endpoint DLP** / `DLPEndpoint` |
| **Browser / Edge DLP** | In-browser dialog (Edge for Business) or extension toast (Chrome/Firefox + Purview extension) | `msedge.exe`, `chrome.exe`, `firefox.exe` | Endpoint DLP, browser plane |

Because PDF Gear is a Win32 desktop app and not a browser, **a popup naming `PDFGear.exe` is Endpoint DLP by definition**. The other two surfaces cannot host this process.

### Confirm in Activity explorer

1. Open `https://purview.microsoft.com` → **Solutions** → **Data Loss Prevention** → **Activity explorer**. (Legacy path: `compliance.microsoft.com` → **Data classification** → **Activity explorer**, but the compliance portal is being retired — use the Purview portal.)
2. Apply filters in this order: **Activity = DLP rule matched** → **Location = Endpoint** → **User = `<affected user>`** → **Device = `<hostname>`** → **Application = `PDFGear.exe`**.
3. Endpoint DLP writes **paired events**: a `DLPRuleMatched` event next to an egress event such as `FileAccessedByUnallowedApp`, `FileCopiedToClipboard`, `FileCopiedToRemovableMedia`, `FileCopiedToNetworkShare`, `FilePrinted`, or `CloudEgress`. The paired record exposes the **Policy name**, **Rule name**, **Action** (`Audit`, `Warn`/`BlockWithOverride`, `Block`), and the matched **Sensitive Info Type**. Record these — you will need the policy and rule names later.
4. Activity explorer retains **30 days** of data. Endpoint events typically appear with **up to a few hours latency** (Microsoft documents 60–90 minutes for core services and longer for "other services," which includes Endpoint DLP).

### Cross-check the DLP alerts dashboard

Navigate to **Data Loss Prevention** → **Alerts**. Find the alert created by the same user/device/time, click **View details** → **Events** tab → **Details** → **Other matched conditions** to capture the SIT, severity, and rule. Confirm the alert workload is `Endpoint DLP`. The Defender XDR portal at `security.microsoft.com` (**Incidents & alerts → Incidents**) also correlates DLP alerts and is the recommended pane of glass with E5/Compliance licensing.

### Endpoint DLP prerequisites checklist

Validate these before troubleshooting further — most "DLP isn't working" tickets resolve at this layer:

- Device is **onboarded to Microsoft Purview** (shared onboarding with Microsoft Defender for Endpoint). Verify at **Purview portal → Settings → Device onboarding → Devices**. Onboarding via MDE auto-onboards the device for DLP. Onboarding propagation takes ~60 seconds, up to 30 minutes.
- **Defender AV real-time protection and behavior monitoring** are enabled. The `MpDlpService.exe` process must be allowed by any third-party AV, firewall, or WDAC/AppLocker.
- **Advanced classification scanning and protection** is on, with Windows KB5016688 (Win10) or KB5016691 (Win11) installed. Required for EDM SITs, trainable classifiers, and contextual text in Activity explorer.
- **Unified Audit Log** is enabled tenant-wide. Verify in Exchange Online PowerShell — the property reports incorrectly from the Security & Compliance session:
  ```powershell
  Connect-ExchangeOnline
  Get-AdminAuditLogConfig | Format-List UnifiedAuditLogIngestionEnabled  # Must be True
  ```
- Licensing: Microsoft 365 **E5 / E5 Compliance / E5 Information Protection & Governance / Microsoft Purview Suite**. Endpoint DLP is not available on E3 alone.

---

## 2. Required roles to make the changes below

Use Microsoft Purview RBAC rather than tenant-wide Entra roles where possible. The least-privilege role that can both view diagnostics and edit Endpoint DLP settings is **Information Protection Admin**.

| Task | Minimum role group |
|---|---|
| View Activity explorer and DLP alerts | **Information Protection Analyst** |
| View Activity explorer + matched sensitive content preview | **Information Protection Investigator** (adds Content Explorer Content Viewer) |
| Edit DLP policies, rules, and Endpoint DLP settings (the work in §3) | **Information Protection Admin**, **Compliance Administrator**, or **Compliance Data Administrator** |
| Run Security & Compliance PowerShell (`Connect-IPPSSession`) for any of the above | Same role groups as the matching task |

There is **no dedicated "DLP Administrator" Entra directory role**. The closest equivalent is the *DLP Compliance Management* role inside Purview RBAC, granted via the role groups above.

---

## 3. The fix — allow PDF Gear cleanly

Microsoft Purview Endpoint DLP **matches restricted apps by executable filename only on Windows** — not by full path, not by digital signature, not by file hash. Per the Microsoft Learn reference for `dlp-configure-endpoint-settings`: *"Don't include the path to the executable for Windows devices. Include only the executable name, such as `browser.exe`."* That means **one entry — `PDFGear.exe` — covers every install location** (per-machine `C:\Program Files\PDFGear\`, per-user `%LocalAppData%\Programs\PDFGear\`, 32-bit, 64-bit, ARM64) regardless of publisher or version.

There is **no global allow list tab** in Endpoint DLP. The model is permissive by default: an app only triggers app-based DLP actions if it is explicitly placed on the **Restricted apps** list or in a **Restricted app group**. Some activities (clipboard, USB, print, network share, cloud upload) are monitored for **all apps** unless scoped otherwise by a rule.

### Step 1 — Open the Endpoint DLP settings

Microsoft Purview portal (`https://purview.microsoft.com`) → **Data Loss Prevention** → **Overview** → **Data loss prevention settings** → **Endpoint settings**. The left-rail sub-sections you will use are **Restricted apps**, **Restricted app groups**, and (optionally) **File path exclusions**.

### Step 2 — Remove PDFGear.exe from any restricted lists

This is the simplest and most common fix.

1. Open **Endpoint settings → Restricted apps**. If `PDFGear.exe` appears, select it → **Delete** → **Save**.
2. Open **Endpoint settings → Restricted app groups**. Expand each group; if `PDFGear.exe` is a member, remove it from the group and save.
3. Open **Data Loss Prevention → Policies**. For each policy with Devices in scope (especially the one identified in §1), edit each rule → **Audit or restrict activities on devices** → review **Restricted app activities** and **File activities for apps in restricted app groups**. Ensure no group still containing PDF Gear is selected.

If PDF Gear was on no restricted list to begin with, jump to Step 3 — the popup is coming from a globally monitored activity (clipboard, print, USB, etc.) and needs scoping rather than removal.

### Step 3 — Allow-list PDF Gear with a Restricted app group (recommended for control)

This is the supported, documented pattern for telling Endpoint DLP "this app is trusted; do not enforce against it." It scales as you onboard more trusted PDF tools and keeps an auditable inventory.

1. **Endpoint settings → Restricted app groups → + Create app group**. Name it `Trusted PDF tools` (or similar).
2. Click **Add app**. Set **Name** to `PDF Gear`, **Executable name** to `PDFGear.exe`. Save. Add other trusted PDF apps to the same group (Adobe Acrobat `Acrobat.exe`, Reader `AcroRd32.exe`, etc.) up to **50 apps per group**. Tenant limits: **10 groups, 500 apps total**.
3. Go to **Data Loss Prevention → Policies → [policy from §1] → Edit policy**.
4. In the rule editor, expand **Audit or restrict activities on devices** → **File activities for apps in restricted app groups → Add** → select `Trusted PDF tools`.
5. Choose **Don't restrict file activity**. This is the documented allow semantics: *"Tells DLP to allow users to access DLP-protected items using apps in the app group without taking any action when the user attempts to Copy to clipboard, Copy to a USB removable drive, Copy to a network drive, or Print from the app."*
6. Save the rule and republish the policy. Repeat for any other Devices-scoped policy that matched in §1.

**Precedence rule that makes this work:** A Restricted app group setting **overrides** both the tenant Restricted apps list and the rule's "File activities for all apps" section *for apps in that group, within that rule*. So `Trusted PDF tools` with **Don't restrict file activity** wins over anything else evaluating `PDFGear.exe`.

### Step 4 — Optional: explicit allow-list pattern (block-all-except-allowed)

If your security baseline mandates blocking all apps from accessing protected files except a whitelist, use the documented pattern:

1. Add `PDFGear.exe` (and every other approved app) to a Restricted app group.
2. In the policy rule, set that group's activity to **Allow**.
3. Set **Access by apps that aren't on the 'unallowed apps' list** to **Block**.

Common background processes (`svchost.exe`, `teamsupdate.exe`, etc.) are pre-bypassed by Microsoft. **Note the rename-bypass risk**: because matching is filename-only, a user (or attacker) renaming the binary defeats the list. The block-all-except-allowed pattern mitigates this since unlisted filenames are blocked by default.

### Step 5 — Do not "fix" this by disabling user notifications

The rule's **User notifications** toggle suppresses the popup but **does not disable enforcement**. If the rule action is Block, the file activity will still fail silently — the user sees no toast and no override option. User overrides themselves require notifications to be on. Use notification suppression only when you intend to keep enforcement and stop user prompting — for instance, during pilot tuning. For "PDF Gear is approved, leave it alone," always use Steps 2–4.

---

## 4. PowerShell management

Microsoft Purview DLP is managed through **Security & Compliance PowerShell**. As of May 2026, Microsoft Graph beta exposes `informationProtection/dataLossPreventionPolicies` with an `evaluate` action only — there is **no Graph parity for Endpoint DLP CRUD**. PowerShell remains the supported automation surface.

### Connect

```powershell
Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser
Import-Module ExchangeOnlineManagement
Connect-IPPSSession -UserPrincipalName admin@contoso.com
```

### Enumerate Endpoint-DLP policies and rules

```powershell
# All Endpoint-scoped policies
Get-DlpCompliancePolicy |
    Where-Object { $_.EndpointDlpLocation.Status -eq 'Enabled' } |
    Select-Object Name, Mode, Enabled, Priority, WhenChanged

# Rules in a specific policy
Get-DlpComplianceRule -Policy "Endpoint - Restrict Unallowed Apps" |
    Select-Object Name, Disabled, BlockAccess, NotifyUser, NotifyAllowOverride,
                  EndpointDlpRestrictions, ContentContainsSensitiveInformation
```

The `EndpointDlpRestrictions` property is per-activity JSON (Print, CopyToClipboard, CloudEgress, RestrictedApp, etc.) and references restricted-app groups by ID.

### Inspect tenant-wide Endpoint DLP settings and app groups

```powershell
$cfg = Get-PolicyConfig
$cfg.DlpAppGroups | ConvertTo-Json -Depth 10      # Restricted app groups (incl. trusted/allow groups)
$cfg.EndpointDlpGlobalSettings | ConvertTo-Json -Depth 10
```

The hashtable schemas for `Set-PolicyConfig -DlpAppGroups` are not formally documented. Use PowerShell here primarily for **inspection, audit, and configuration backup**; perform edits in the portal.

### Check policy distribution status

```powershell
$dlp = Get-DlpCompliancePolicy
ForEach ($d in $dlp) {
    Get-DlpCompliancePolicy -DistributionDetail $d.Name |
        Format-List Name, DistributionStatus, Mode
}
```

### Audit log query for PDF Gear activity after the change

```powershell
Search-UnifiedAuditLog -StartDate (Get-Date).AddHours(-6) -EndDate (Get-Date) `
    -RecordType DLPEndpoint -ResultSize 200 |
    Where-Object { $_.AuditData -match 'PDFGear.exe' } |
    Select-Object CreationDate, UserIds, Operations, AuditData
```

---

## 5. Force sync and verify on a test endpoint

Endpoint DLP rules are pulled from the Purview service by the **MDE sensor**; they are not delivered by Intune/GPO and there is no Group Policy or `gpupdate` lever. Microsoft's documented sync timings:

- **~1 hour** for a policy change in Purview to synchronize across the service.
- **Up to 2 hours** for a device's "Configuration status" to show **Updated** in the Purview Devices list.
- **~10 minutes** if you trigger **MDE Policy sync** manually (fast path).
- **24 hours** for edits to Authorized Groups (sender/sensitivity group membership inside a rule).

### Force the sync

1. Microsoft Defender portal (`https://security.microsoft.com`) → **Assets → Devices** → select the test device → action menu → **Policy sync**. Wait 10–15 minutes.
2. Ensure the device is online, Azure AD–joined or registered, and Defender AV is healthy:
   ```powershell
   Get-MpComputerStatus | Select RealTimeProtectionEnabled, BehaviorMonitorEnabled, AMServiceEnabled
   ```
3. There is **no documented `gpupdate`-equivalent** for Endpoint DLP rules. `Update-MpSignature`, `Get-MpPreference`, Intune MDM sync, and `dsregcmd /refreshprerequisites` do not refresh the DLP policy cache.

### Verify the rule no longer fires

1. On the test endpoint, open a known-sensitive document (one that previously triggered the popup) inside `PDFGear.exe`. Perform the same action that triggered before — copy/print/save to USB.
2. **No toast** should appear.
3. In Activity explorer, filter on **User**, **Device**, **Application = `PDFGear.exe`**. Confirm either no `DLPRuleMatched` event for the new activity, or — if the rule was previously matched and policy re-evaluated — a `DLPRuleUndo` event for the historical match. The egress event (e.g., `FileCopiedToClipboard`) may still appear when "Always audit file activity for devices" is enabled; that is auditing, not enforcement.
4. Allow up to a few hours latency before concluding events are missing.

### Deep client-side verification with MDE Client Analyzer

For tickets where the popup persists past the sync window, the **MDE Client Analyzer (MDECA)** with the `-t` switch is Microsoft's supported endpoint diagnostic for DLP:

```cmd
:: From an elevated cmd in the extracted MDEClientAnalyzer folder
MDEClientAnalyzer.cmd -t
```

Reproduce the activity, press **q** to stop the trace. Open `MDEClientAnalyzerResult_<ID>.zip` and inspect:

- `DLP\FileEAs.txt` — per-file classification. The `Enforce PolicyRuleIds` and `Actions` sections show which rule will fire and the EnforcementMode: `0=Off`, `1=Audit`, `2=Warn (Block with override)`, `3=Block`, `4=Allow (JIT only)`. If your rule still shows under `Enforce PolicyRuleIds` for `PDFGear.exe`, the policy hasn't synced yet.
- `DLP\dlpPolicy.json` — the cached policy definitions on the device.
- `DLP\dlpActionsOverridePolicy.json` — printer / network share / removable media groups.

The runtime location of these files in `ProgramData` is not formally documented; MDECA is the supported access path.

---

## 6. Gotchas and known issues

Even after a clean fix, the popup can persist for reasons outside the restricted-apps configuration. Walk this list before escalating:

1. **Multiple policies enforce the most restrictive aggregate.** If a second Endpoint DLP policy also lists PDF Gear or hits the same activity, removing it from one policy doesn't help. Audit **every** active Endpoint DLP policy with `Get-DlpCompliancePolicy | Where-Object { $_.EndpointDlpLocation.Status -eq 'Enabled' }`.
2. **Filename-only matching → rename bypass risk.** `PDFGear.exe` renamed to `PDFGear_v2.exe` would bypass the list. Use the block-all-except-allowed pattern (§3 Step 4) if this matters for your threat model.
3. **Just-In-Time (JIT) protection** can block activity *before* classification completes. Files blocked by JIT generate no `DLPRuleMatch` event and no alert — only a JIT event. Allow-listing the app does not bypass JIT. If JIT is enabled and PDF Gear is being blocked at file open, review JIT settings.
4. **Monitored file extension scope.** Endpoint DLP only audits a specific extension list (`.pdf`, `.docx`, `.xlsx`, `.pptx`, `.csv`, `.tsv`, archive formats, etc.). If popups are on a non-monitored extension, the source is not Endpoint DLP file-activity monitoring.
5. **Always audit file activity for devices.** When enabled in Endpoint DLP settings, Office/PDF/CSV file activity is audited regardless of policy scope. PDF Gear activity will continue to appear in Activity explorer after your fix — this is auditing, not enforcement, and not a user-visible popup.
6. **Simulation mode masks results.** A policy in "Run in simulation mode" with policy tips on shows `Block` as `Block with override` to the user; with tips off, `Block-with-override` reduces to `Audit`. Simulation insights take up to **24 hours** to stop appearing after disable. Confirm policy state is `Turn it on right away` for a true enforcement test.
7. **Devices list "Not updated" status lag.** Allow up to 2 hours after a change before concluding policy didn't sync.
8. **`MpDlpService.exe` blocked.** Third-party AV, host firewall, WDAC, or AppLocker can silently block the DLP service component. Symptom: device shows as onboarded but no DLP events ever appear.
9. **Server SKUs require explicit enablement.** Windows Server 2019/2022 are not Endpoint-DLP-enabled by default after onboarding — flip **"Enable Endpoint DLP for Windows Servers"** in Endpoint DLP settings.
10. **Legacy compliance portal is retired.** `compliance.microsoft.com` redirects to `purview.microsoft.com`. UI labels match between the portals; if a screenshot in older documentation diverges, trust the Purview portal.
11. **Disabling Notify users doesn't disable enforcement.** Re-stating because this is the most common self-inflicted incident: turning off the policy tip suppresses the toast but blocks still fire silently and user overrides become impossible. Always fix the rule scope, not the notification.

---

## 7. Conclusion and operational takeaways

**Endpoint DLP's matching model is intentionally simple — exact, case-insensitive filename match on the Windows binary.** That property makes whitelisting PDF Gear a single configuration entry (`PDFGear.exe`) that covers every install variant, but it also means filename-renaming defeats the list. Choose between *implicit allow* (remove from all restricted lists and groups — sufficient if your policies use a deny-list model) and *explicit allow* (a `Trusted PDF tools` group with **Don't restrict file activity**, which scales as more PDF tools are approved and preserves a clear audit trail).

**The change is service-pulled to MDE-onboarded devices in roughly an hour**, faster with manual Policy sync from the Defender portal. Verification belongs in Activity explorer (look for absence of `DLPRuleMatched` or presence of `DLPRuleUndo`) and, when that's insufficient, in the MDE Client Analyzer's `FileEAs.txt`. Resist the temptation to silence the popup by turning off user notifications — that path keeps blocks enforced silently and removes the override safety valve.

For ongoing operations, treat tenant-wide Endpoint DLP settings (Restricted apps, Restricted app groups, File path exclusions) as a controlled inventory: review quarterly, version it via `Get-PolicyConfig | Export-Clixml`, and pair every new approved app onboarding with a matching `Trusted apps` group entry rather than per-policy ad-hoc edits.

---

## References

- Microsoft Learn — *Learn about Endpoint DLP*: https://learn.microsoft.com/purview/endpoint-dlp-learn-about
- Microsoft Learn — *Configure Endpoint DLP settings*: https://learn.microsoft.com/purview/dlp-configure-endpoint-settings
- Microsoft Learn — *Get started with Endpoint DLP*: https://learn.microsoft.com/purview/endpoint-dlp-getting-started
- Microsoft Learn — *DLP policy reference*: https://learn.microsoft.com/purview/dlp-policy-reference
- Microsoft Learn — *Use DLP notifications and policy tips*: https://learn.microsoft.com/purview/dlp-use-notifications-and-policy-tips
- Microsoft Learn — *Activity explorer*: https://learn.microsoft.com/purview/data-classification-activity-explorer
- Microsoft Learn — *Available activities in Activity explorer*: https://learn.microsoft.com/purview/data-classification-activity-explorer-available-events
- Microsoft Learn — *DLP alerts dashboard*: https://learn.microsoft.com/purview/dlp-alerts-dashboard-get-started
- Microsoft Learn — *Device onboarding overview*: https://learn.microsoft.com/purview/device-onboarding-overview
- Microsoft Learn — *Troubleshoot Endpoint DLP device/policy sync*: https://learn.microsoft.com/purview/dlp-edlp-tshoot-sync
- Microsoft Learn — *Collect Endpoint DLP diagnostic logs (MDECA)*: https://learn.microsoft.com/troubleshoot/microsoft-365/purview/data-loss-prevention/collect-endpoint-dlp-diagnostic-logs
- Microsoft Learn — *Analyze Endpoint DLP diagnostic logs*: https://learn.microsoft.com/troubleshoot/microsoft-365/purview/data-loss-prevention/analyze-endpoint-dlp-diagnostic-logs
- Microsoft Learn — *Manage MDE security policies (Policy sync action)*: https://learn.microsoft.com/defender-endpoint/manage-security-policies
- Microsoft Learn — *Microsoft Purview permissions*: https://learn.microsoft.com/purview/purview-permissions
- Microsoft Learn — *Security & Compliance PowerShell*: https://learn.microsoft.com/powershell/exchange/scc-powershell
- Microsoft Learn — `Get-DlpCompliancePolicy`: https://learn.microsoft.com/powershell/module/exchangepowershell/get-dlpcompliancepolicy
- Microsoft Learn — `Get-DlpComplianceRule`: https://learn.microsoft.com/powershell/module/exchangepowershell/get-dlpcompliancerule
- Microsoft Learn — `Set-PolicyConfig`: https://learn.microsoft.com/powershell/module/exchangepowershell/set-policyconfig
- Microsoft Learn — *Audit search & retention*: https://learn.microsoft.com/purview/audit-search