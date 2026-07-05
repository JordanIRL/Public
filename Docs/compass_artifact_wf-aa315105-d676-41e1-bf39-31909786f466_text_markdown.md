# Microsoft Purview Endpoint DLP: Stopping the Persistent "Uploading This File Isn't Recommended" Warn-and-Allow Prompts

## TL;DR
- The prompts persist because Purview Endpoint DLP has **multiple, independent allow/block mechanisms**, and your `onedrive.exe` and `powerapps.com` entries are almost certainly on the *wrong* one for the activity that is actually firing — the **"Sensitive service domains" list only governs browser uploads (Edge, or Chrome/Firefox with the Purview extension)**, while the **OneDrive sync client is treated as an application** governed by the separate **Restricted apps / Restricted app groups** list.
- Your first job is **diagnosis, not configuration**: open **Activity Explorer** in the Purview portal, read the **Activity type** ("File copied to cloud" = browser/cloud egress vs. "File accessed by unallowed app" = sync client), the **Policy name**, **Rule name**, **Application/executable**, and **Target domain**. That single row tells you which mechanism to fix.
- "Warn and Allow" = the rule action is **Block with override** (Warn). The override is **not remembered** for cloud-upload/app-access activities — Microsoft states that for these "users will need to repeat the process after clicking 'Allow' to bypass the policy" — so the real fix is to put the file/destination on the correct allow list (or change the action), not to train users to keep clicking Allow.

## Key Findings

**1. There are four different "lists," and they do not interchange.** New Purview admins almost always conflate these. They live in different places and apply to different activities:

| Mechanism | Where it lives | What it governs | Applies to your scenario? |
|---|---|---|---|
| **Sensitive service domains / Service domains** (allow or block list) + **Sensitive service domain groups** | Endpoint DLP settings → *Browser and domain restrictions to sensitive data* | **Browser** uploads/print/copy/save-as to websites. **Only works in Microsoft Edge, or Chrome/Firefox with the Microsoft Purview extension.** | Only if the trigger is a *browser* upload to powerapps.com |
| **Restricted apps** + **Restricted app groups** (formerly "Unallowed apps") | Endpoint DLP settings → *Restricted apps and app groups* | Whether a **desktop application** (e.g., `onedrive.exe`) may **access** a DLP-protected file. Condition = "Access by restricted apps." | Yes — this is what governs the **OneDrive sync client** |
| **Unallowed browsers** | Endpoint DLP settings → *Browser and domain restrictions to sensitive data* | Blocks non-Edge browsers from opening protected files and redirects to Edge | Only if an unsupported browser was used |
| **File path exclusions / Network share coverage and exclusions** | Endpoint DLP settings | Turns monitoring off for specific local paths or network share UNC paths | Useful as a targeted exclusion, not a per-domain allow |

**2. The crucial browser-vs-sync distinction.** Microsoft Learn ("Configure endpoint data loss prevention settings") states verbatim: **"The Service domains setting only applies to files uploaded by using Microsoft Edge, or by using instances of Google Chrome or Mozilla Firefox that have the Microsoft Purview Chrome Extension installed."** So if your powerapps.com entry is in the **Sensitive service domains** allow list, it does **nothing at all** for a file moved by the OneDrive sync client from File Explorer. The sync client is an *application*: the same Microsoft Learn page says verbatim, **"To prevent sensitive items from syncing to the cloud by cloud sync apps such as onedrive.exe, add the cloud sync app to the Restricted apps list with Auto-quarantine."** That means your `onedrive.exe` entry, if it is on a Restricted apps list/group with an action of **Block with override (Warn)**, is the most likely source of the recurring prompt — and adding powerapps.com to service domains will never silence it.

**3. How the OneDrive/File-Explorer path gets classified.** When the sync client touches a sensitive file, Endpoint DLP records it as **"File accessed by unallowed app"** (the *Access by restricted apps* condition) — an *application* event — not as a website "upload." A genuine browser HTTP POST upload, by contrast, is recorded as the **"File copied to cloud"** cloud-egress event, which carries a **Target domain** (and, since the early-2025 rollout, a **Full URL**) field. The two are evaluated by completely different policy conditions. This is why your intuition ("I allow-listed the domain and the app") fails: the domain allow list and the app restriction are orthogonal mechanisms.

**4. Why the prompt repeats every time.** With the **Block with override** action (shown in the diagnostic logs as `EnforcementMode = 2`, "Warn"), Microsoft Learn ("Data Loss Prevention policy reference") documents that the override is only auto-resumed for a fixed set of activities: **"Once allowed, Endpoint DLP will automatically resume for actions including 'Copy to a network share', 'Copy to a removable USB device', and 'Print'. For other actions, users will need to repeat the process after clicking 'Allow' to bypass the policy."** For those three resumable activities, the same reference notes the user has a short window — **"Within 30 seconds of the popup notification showing, the activity is allowed to continue. If the user doesn't select the Allow option within 30 seconds, the activity is blocked"** — and a separate statement notes that once overridden, "the action is permitted for a period of 1 minute" to retry. Critically, **there is no per-file "remember my choice"** for cloud-upload or access-by-restricted-app. So a sync client that retries continuously produces an endless loop of toasts. Microsoft's documented remedy for the sync loop specifically is **Auto-quarantine**: *"DLP might generate repeated notifications. You can avoid these repeated notifications by enabling Auto-quarantine. You can also use autoquarantine to prevent an endless chain of DLP notifications for the user and admins."*

**5. The actual policy match is driven by content, not the app or domain.** The warning only fires because the file matches a **sensitivity label or a sensitive information type (SIT)** named in some DLP rule's conditions. The app/domain only decides *which egress action* is restricted. If powerapps.com/OneDrive traffic is legitimate, you can stop the noise by (a) allow-listing the correct egress channel, (b) excluding the path, or (c) tightening the *content* condition so business files stop matching.

## Details

### Diagnostic workflow (do this first — ~15 minutes)

**Step A — Read the user's toast.** The Windows toast is generated by the Endpoint DLP client and shows the **policy name** and the **action verb**. Microsoft renders the action from a token (`%%AppliedActions%%`); a cloud upload renders as **"uploading to this site,"** access by an app renders as **"opening with this app."** That verb alone hints at browser-upload vs. app-access. Note: Microsoft does **not** publish the exact default sentence verbatim, and it is admin-customizable in the rule's **User notifications** section (Title up to 120 chars, Content up to 250), so wording in your tenant may have been changed — don't rely on it; rely on Activity Explorer.

**Step B — Activity Explorer (the authoritative source).**
1. Go to **purview.microsoft.com** → **Data Loss Prevention** → **Activity explorer** (also reachable under **Information Protection → Explorers → Activity explorer**).
2. Set the **Location** filter to **Devices** and narrow the **Date range** and **User**.
3. Add/enable these columns (column chooser): **Activity type**, **Policy**, **Rule**, **Application** (executable), **Target domain** (and **Full URL** if available), **Sensitivity label**, **Sensitive info type**, **Enforcement mode**, **Device name**.
4. Find the offending event and read it:
   - **Activity type = "File copied to cloud"** with a **Target domain** of powerapps.com → this is a **browser/cloud-egress** upload → fix via **Sensitive service domains** (below).
   - **Activity type = "File accessed by unallowed app"** with **Application = onedrive.exe** → this is the **sync client / Restricted apps** path → fix via **Restricted apps / Restricted app groups**.
   - Note the **Enforcement mode** (Warn = Block with override), **Policy** and **Rule** names, and the **Sensitivity label/SIT** that caused the match.
   
   Caveat from Microsoft: for endpoint events Activity Explorer shows **only the most restrictive rule**, there is roughly a **5-minute delay** before events appear, and retention is **30 days**.

**Step C — Confirm which list your entries are on.** Go to **purview.microsoft.com → Data Loss Prevention → Settings (gear) → Data loss prevention → Endpoint settings** (equivalently: *Data loss prevention → Overview → Data loss prevention settings → Endpoint settings*). Then:
   - Expand **Browser and domain restrictions to sensitive data** → check **Service domains** (is it in Allow or Block mode? is powerapps.com listed?) and **Sensitive service domain groups**. Also check **Unallowed browsers**.
   - Expand **Restricted apps and app groups** → check whether `onedrive.exe` is in **Restricted apps** and/or in any **Restricted app group**, and what action is set.
   - This is how you answer "which allow list are my entries actually on?"

**Step D — Device-side diagnostics (if Activity Explorer is ambiguous).** On the affected Windows device, collect Endpoint DLP diagnostics with the **MDE Client Analyzer** tool (`MDEClientAnalyzer.cmd`; admin rights not required for log retrieval). Then open **`MDEClientAnalyzerResult_<ID>\DLP\FileEAs.txt`** and read:
   - The **Enforce PolicyRuleIds / Test PolicyRuleIds** sections — each lists **PolicyName**, **RuleName**, and a JSON **Actions** block.
   - In **Actions**, the **EnforcementMode** integers: `0`=Off, `1`=Audit, `2`=Warn (block-with-override — *this is your "warn and allow"*), `3`=Block, `4`=Allow (JIT only).
   - The **InfoTypes** / **Labels** values show exactly which SIT or label matched (and `RMS = 0x1` means the file is encrypted/password-protected and can't be evaluated).
   - `dlpWebSitesPolicy.json` (service-domain groups), `dlpActionsOverridePolicy.json` (printer/network-share/USB groups), and `dlpPolicy.json` (other groups) resolve any GroupId you see.
   - In `MDEClientAnalyzer.htm`, verify the device is **Entra-joined or Workplace-joined** and has a non-blank **Device ID** (otherwise MDE/DLP isn't healthy).
   - In 2025 Microsoft added **Always-on diagnostics** (preview) under **Settings → Data Loss Prevention → Always-on diagnostics**, which keeps ~90 days of traces you can request from a device, alert event, or Activity Explorer row.
   - The `MpCmdRun.exe -GetFiles` command (in `C:\Program Files\Windows Defender\`) collects the broader Defender support cab (`MpSupportFiles.cab`) if Microsoft Support asks.

### Decision tree — once you know the activity type

**If the event is "File copied to cloud" / target domain = powerapps.com (a true browser upload):**
1. Endpoint settings → **Browser and domain restrictions to sensitive data → Service domains**.
2. If the list is in **Block** mode: simply *do not* list powerapps.com (in Block mode, only listed domains are restricted; everything else is allowed). If powerapps.com is currently listed there, remove it (or move it to a group set to Allow).
3. If the list is in **Allow** mode (only listed domains are allowed; *all others are restricted*): **add powerapps.com to the allow list.** In Allow mode you must have at least one domain configured for enforcement to behave. To allow subdomains use `*.powerapps.com`; use a trailing `/` to scope to a single site. Edge should be reasonably current (120+) and Chrome/Firefox must have the **Microsoft Purview extension**, or the upload won't be evaluated correctly.
4. Confirm the browser in use is **supported**. If the user uploaded via an *unsupported* browser, the platform blocks it and redirects to Edge regardless of the domain list — check the **Unallowed browsers** list.

**If the event is "File accessed by unallowed app" / Application = onedrive.exe (the sync-client / File-Explorer path you described):**
1. Adding powerapps.com to service domains will **not** help — stop doing that.
2. Go to Endpoint settings → **Restricted apps and app groups** and decide the intent:
   - **If OneDrive sync of these files is legitimate** (most likely): **remove `onedrive.exe` from the Restricted apps list / Restricted app group**, or set its action to **Allow / Audit only** instead of Block with override. Check **both** the list and any group, because Microsoft Learn states *"Settings in a restricted app group override any restrictions set in the restricted apps list when they are in the same rule. So, if an app is on the restricted apps list and is also a member of a restricted apps group, the settings of the restricted apps group is applied."* You can also exclude the local OneDrive sync folder via **File path exclusions for Windows** to turn monitoring off for that path entirely.
   - **If you intend to block OneDrive sync of these sensitive files**: keep it restricted but switch from "Warn" to **Auto-quarantine** (Endpoint settings → Restricted apps → Auto-quarantine settings). The file is moved to a quarantine folder and replaced with a `.txt` placeholder, so the sync client stops retrying and the notification loop ends.
3. Note the powerapps.com angle: Power Apps frequently uses the **OneDrive / OneDrive for Business connector**, so an action that *looks* like "OneDrive → powerapps.com" can surface in telemetry with powerapps.com as the destination even though the local actor was the sync client. Trust the **Application** column: if it says `onedrive.exe`, treat it as an app / Restricted-apps problem. (Separately, **Power Platform has its own, unrelated DLP** in the Power Platform admin center governing *connectors* — if a user ever sees "Your flow violates your org's data loss prevention policy (DLP)… connector," that is a different product entirely, fixed by reclassifying the connector, not in Purview Endpoint DLP.)

### Reducing prompt frequency in general
- Switch the matching rule's action from **Block with override (Warn)** to **Audit only** (silent logging) or **Allow** while you tune — Allow still audits but never alerts or prompts.
- For sync apps specifically, use **Auto-quarantine** (above) — Microsoft's documented anti-loop control.
- Tighten the **content condition** (label/SIT and instance-count threshold) so routine business files stop matching.
- Run new/edited policies in **simulation mode** first.

## Recommendations

**Stage 1 — Diagnose (today).** Open Activity Explorer (Location = Devices), reproduce or locate the event, and record: Activity type, Application, Target domain, Policy, Rule, Sensitivity label/SIT, Enforcement mode. This single row decides everything. *Benchmark that changes the plan:* if Activity type = "File accessed by unallowed app" + Application = onedrive.exe, you are in the **Restricted apps** branch; if it's "File copied to cloud" + a target domain, you are in the **Service domains** branch.

**Stage 2 — Fix the correct list (same day).**
- *Restricted-apps branch* (your described File-Explorer/sync case): set `onedrive.exe` to **Allow/Audit** or remove it (legitimate sync) **or** enable **Auto-quarantine** (intended block). Verify both the Restricted apps *list* and any Restricted app *group* (the group wins).
- *Service-domains branch*: in **Allow** mode add `*.powerapps.com`; in **Block** mode ensure powerapps.com is *not* listed. Confirm a supported browser + Purview extension.

**Stage 3 — Verify (allow up to ~1 hour; longer on offline/slow devices).** Microsoft states policy/setting updates "generally take about an hour" to sync; real-world endpoint propagation can be longer if the device is offline. Confirm the device shows **Policy sync status = Updated** under **Settings → Device onboarding → Devices**, then re-test the exact user action and confirm the toast is gone and Activity Explorer shows Allow/Audit.

**Stage 4 — Harden.** Keep the policy in **Audit/simulation** for ~2 weeks after any change to catch false positives; set **policy priority** deliberately (lower number = higher priority; Endpoint DLP applies the **aggregate of the most restrictive actions** across matching rules, and the highest-priority policy wins ties); and document which list each approved destination/app lives on so this confusion doesn't recur.

## Caveats
- **The default toast wording is not published verbatim by Microsoft and is admin-customizable**, so the phrase your users see may be either the client-generated default or text a prior admin entered. Don't rely on wording — rely on Activity Explorer's Activity type.
- **"Most restrictive wins."** If multiple rules/policies match the same file, a stricter rule elsewhere can keep prompting even after you relax one list. Check for *all* matching policies, not just the obvious one.
- **Override timing is short and not persistent.** The bypass window is ~30 seconds to click Allow (and ~1 minute to retry) and applies cleanly only to Print/USB/network-share; cloud-upload and access-by-restricted-app must be repeated each time.
- **Content-not-scanned cases behave inconsistently:** password-protected/encrypted files, files still in OneDrive "cloud-only" (Files On-Demand) state, ZIP-archived content, and unsupported file types. A file that is "cloud only" may not have endpoint policy applied until it's downloaded locally.
- **Advanced classification** must be enabled for EDM, trainable classifiers, credential classifiers, and named-entity SITs to be detected on the endpoint; otherwise your assumption about *why* the rule fired may be wrong.
- **Power Platform DLP ≠ Purview Endpoint DLP.** If a message references a *connector* being blocked, that's the Power Platform admin center — a separate system.
- Activity Explorer endpoint data has a **~5-minute ingestion delay, shows only the most restrictive rule, and retains 30 days** — use the device-side `FileEAs.txt` for ground truth when the portal is ambiguous.