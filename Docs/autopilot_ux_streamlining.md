# Streamlining the Post-Autopilot User Experience
### Cloud-native, Entra-joined Windows 11, Microsoft 365 E5, Intune-managed

Autopilot delivers a clean *enrolment*. It does not, by itself, deliver a clean *desktop*. The in-box consumer apps, Copilot+ AI surfaces, Spotlight/“finish setting up” upsell, and per-application sign-in prompts are a separate configuration layer applied through Intune Settings Catalog policy and the Enrollment Status Page. This guide defines that layer.

All policies here are **device-targeted** and assigned to the same Autopilot device group(s) used for the deployment profile, so they install during the **Device setup** phase of the ESP and take effect before the user reaches the desktop. Where a setting is user-scoped, it is noted explicitly.

---

## Layer 1 — Remove in-box and consumer apps

Two distinct mechanisms are required, because they act on two different categories of app.

### 1a. Native removal of provisioned in-box apps (preferred)

| Item | Detail |
|---|---|
| Policy | **Remove default Microsoft Store packages from the system** (`RemoveDefaultMicrosoftStorePackages`) |
| Location | Settings Catalog → *Application Management* (also surfaced under *Administrative Templates → Windows Components → App Package Deployment*) |
| Scope | **Device** |
| Edition / version | **Windows 11 Enterprise / Education, 25H2 or later only.** Pro/Business return *Not applicable*. |
| CSP | `./Device/Vendor/MSFT/Policy/Config/ApplicationManagement/RemoveDefaultMicrosoftStorePackages` |

Enable the master toggle, then set each app to **True** to remove it. Targets a curated list of in-box packages (Xbox, Solitaire Collection, Clipchamp, Feedback Hub, Bing Weather, etc.).

Operational notes:
- Removal also **blocks reinstallation** from Store/Winget (error `0x80073D3F`). Do not remove anything you later intend to deploy from the Store.
- Do **not** flag **Teams** or **Outlook (new)** for removal if you deploy the enterprise builds — the policy blocks the subsequent enterprise install.
- Enforcement runs during OOBE, on sign-in after an OS upgrade, and on sign-in after the policy changes. With the policy in the device group and ESP blocking on, removal completes in the device phase.
- Residual Start menu shortcuts may briefly persist after deprovisioning; they resolve on first sign-in. Verify via `HKLM\SOFTWARE\Policies\Microsoft\Windows\Appx\RemoveDefaultMicrosoftStorePackages` and Event ID 762.
- Not supported on multi-session / pooled AVD.

### 1b. Fallback for 24H2 and older, or apps the native policy doesn’t cover

Deploy `Remove-AppxProvisionedPackage` (device image) and `Remove-AppxPackage` (current user) as a **Win32 app** (detection rule + retry logic) rather than a one-shot Platform Script, so it survives reattempts and reports status. Identify exact `PackageFamilyName` values on a reference device with `Get-AppxPackage -AllUsers | Select Name, PackageFamilyName`.

### 1c. Stop the post-OOBE promoted consumer apps

| Item | Detail |
|---|---|
| Policy | **Allow Windows Consumer Features** → **Block** |
| Location | Settings Catalog → *Experience* |
| Scope | Device |
| Edition | Enterprise / Education |
| CSP | `./Device/Vendor/MSFT/Policy/Config/Experience/AllowWindowsConsumerFeatures` (value `0`) |

This suppresses silently auto-installed third-party promoted apps (Candy Crush–class), Start suggestions, membership notifications, and post-OOBE redirect tiles. It is **complementary** to 1a, not a substitute — 1a removes apps already in the image; 1c prevents new ones being pushed.

---

## Layer 2 — Disable Copilot+ AI surfaces (Recall, Click to Do, Copilot)

On Entra-joined, Intune-managed devices Recall is **off by default** and cannot be user-enabled without policy. Click to Do is built on the same Recall component. Treat these as “keep disabled and make auditable,” and apply an **applicability rule** so the profile is excluded from anything below Windows 11 24H2.

| Setting | Value | Location | Scope |
|---|---|---|---|
| Allow Recall Enablement | Disabled | Settings Catalog → *Windows AI* | Device |
| Disable Click To Do | Enabled / Disable | Settings Catalog → *Windows AI* | Device |
| Turn off Windows Copilot | Enabled | Settings Catalog → *Windows AI* / *Windows Components* | User |
| Disable AI Data Analysis (Recall) | Enabled | Settings Catalog → *Windows AI* | Device |

Recall and Click to Do are Copilot+ hardware features (NPU-class devices); on non-Copilot+ hardware they are absent regardless. The applicability rule keeps the profile status clean (*Not applicable* rather than *Error*) across mixed hardware.

---

## Layer 3 — Suppress Spotlight, tips, welcome and “finish setting up”

These remove the promotional and onboarding surfaces that make a managed device feel like a consumer device. All under Settings Catalog → *Experience* unless noted.

| Setting | Value | Scope |
|---|---|---|
| Configure Windows spotlight on lock screen | Disabled | Device |
| Allow Windows Spotlight | Block | User |
| Allow Third Party Suggestions in Windows Spotlight | Block | User |
| Allow Windows Spotlight on Settings | Block | User |
| Allow Spotlight Collection on Desktop | Block | User |
| Allow Windows Tips | Block | Device |
| Allow Windows Spotlight Windows Welcome Experience | Block | User |
| Do Not Show Feedback Notifications | Enabled | Device |

The post-update **“Let’s finish setting up your device” (SCOOBE)** page is driven primarily by the welcome-experience and consumer-features surfaces above; blocking the Windows Welcome Experience together with `AllowWindowsConsumerFeatures = Block` (Layer 1c) removes it for managed users. Pair with a Start/taskbar layout (Layer 5) to fully control first impressions.

---

## Layer 4 — Eliminate per-app sign-in prompts

### Foundation: the Primary Refresh Token

On an Entra-joined device the OS holds a **PRT** tied to the user who signed in. Apps using the **Web Account Manager (WAM)** broker — Microsoft 365 Apps, Teams, Edge — authenticate against it silently, so first sign-in to Windows is effectively the only credential prompt. Verify the PRT is present with `dsregcmd /status` → `AzureAdPrt : YES`. If the PRT is healthy, most “please sign in” prompts trace to per-app first-run experiences rather than missing auth.

### OneDrive (the usual offender)

| Setting | Value | Notes |
|---|---|---|
| Silently sign in users to the OneDrive sync app with their Windows credentials | Enabled | Consumes the PRT; sets `SilentAccountConfig=1`. Entra-joined supported. |
| Silently move Windows known folders to OneDrive | Enabled + **Tenant ID** | KFM with no wizard; redirects Desktop/Documents/Pictures. |
| Prevent users from syncing personal OneDrive accounts | Enabled | Blocks consumer OneDrive on corporate devices. |

Location: Settings Catalog → *OneDrive*. Silent account config relies on the PRT, so it works on a properly Entra-joined device where MFA was satisfied at Windows sign-in. If it stalls, check that a Conditional Access policy isn’t forcing additional interaction and that the sync client is current (18.151.x+, shipped with current Windows 11). Inform users before enabling silent KFM so the folder redirection isn’t a surprise.

### Microsoft Edge

| Setting | Value |
|---|---|
| Browser sign-in settings | Force users to sign in to use the browser |
| Hide the First-run experience and splash screen | Enabled |
| Configure the first-run experience / default profile | Enable automatic sign-in to the work profile (`NonRemovableProfileEnabled`) |

Location: Settings Catalog → *Microsoft Edge*. With the PRT present, Edge signs the work profile in automatically; these settings remove the first-run wizard and the personal/work profile choice.

### Microsoft 365 Apps (Office)

M365 Apps activate and sign in **silently** against the Windows primary account on an Entra-joined device — no product-key or sign-in step is required. Remove the remaining friction:
- Suppress the **first-run movie / “Your privacy matters” / Connected Experiences** first-run via the **Microsoft 365 Apps admin center → Cloud Policy** (or the Office Settings Catalog category).
- Confirm **“Automatically activate Office with the Windows primary account”** behaviour by deploying M365 Apps via Intune with shared-computer activation **off** for assigned (1:1) laptops.

### Teams

The new Teams client signs in automatically through WAM/PRT on Entra-joined devices — no policy required. If a prompt appears, it’s an auth/PRT health issue, not a Teams configuration gap.

---

## Layer 5 — Start menu and taskbar (optional polish)

After stripping apps, pin the intended app set so the Start menu reflects the corporate baseline rather than gaps where removed apps were.

| Setting | Location | Scope |
|---|---|---|
| Configure Start pins (Start layout JSON) | Settings Catalog → *Start* | User |
| Configure Taskbar (taskbar layout XML) | Settings Catalog → *Start* | User |
| Remove “Recommended” / tips & app promotions in Start | Settings Catalog → *Start* / *Experience* | User |

---

## Sequencing into Autopilot and the ESP

1. Place every **device-scoped** policy from Layers 1–5 in the Autopilot device group so it applies in the ESP **Device setup** phase, before desktop.
2. Set the app-removal and consumer-features policies as **blocking** in the ESP design where you need a guaranteed-clean first desktop; keep the blocking app list lean to avoid timeouts.
3. **User-scoped** Spotlight/Start/taskbar settings apply in the **Account setup** phase at first sign-in; expect a brief settle on the very first session.
4. Apply an **applicability rule** (OS edition + version) to the 25H2-only and 24H2-only profiles so mixed hardware reports *Not applicable* rather than *Error*, and so the right removal mechanism reaches the right device.
5. Validate on a pilot device end-to-end: confirm no consumer apps present, no Recall/Click to Do, no Spotlight/SCOOBE upsell, OneDrive signed in and syncing silently, Edge/Teams/Office authenticated without prompts, and the Start/taskbar layout applied.

## Edition / version gating summary

| Capability | Requirement |
|---|---|
| `RemoveDefaultMicrosoftStorePackages` (native in-box removal) | Windows 11 **Enterprise/Education 25H2+** |
| `AllowWindowsConsumerFeatures = Block` | Enterprise/Education |
| Recall / Click to Do controls | Windows 11 24H2+ (Copilot+ hardware) — gate with applicability rule |
| App removal on 24H2 / older | PowerShell Win32 fallback |
| PRT-based silent SSO (OneDrive/Edge/Teams/Office) | Any Entra-joined Windows 11; no edition gate |

A clean first desktop on 25H2 = native app-removal policy + consumer-features block + AI-surface disablement + Spotlight/welcome suppression + PRT-backed silent sign-in, all device-targeted and ESP-enforced. On 24H2, swap the native removal policy for the scripted fallback; everything else is identical.
