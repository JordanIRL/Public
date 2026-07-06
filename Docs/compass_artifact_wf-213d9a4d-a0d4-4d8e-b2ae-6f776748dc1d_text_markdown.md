# Enterprise Microsoft Intune Takeover & Remediation Plan (2025/2026)

**Scope:** Intune + associated third-party tooling only. Windows = Entra-joined (cloud-only), iOS/iPadOS = Supervised/ADE, Android = COPE + Fully Managed. Conditional Access is covered only as it enforces device compliance.

## TL;DR
- **Do NOT big-bang rebuild.** Run a disciplined Phase 0 assessment first: export the entire tenant to a private Git repo with IntuneCD and IntuneManagement, flip the tenant-wide "Mark devices with no compliance policy assigned as" to **Not compliant** (after verifying coverage), and stabilise critical conflicts (LAPS, ASR, driver policies where one-policy-per-device rules apply) before touching architecture.
- **Rebuild on modern primitives:** Settings Catalog over legacy templates; assignment filters for platform/ownership refinement over proliferating dynamic groups; ring-based staged rollout; a rigid naming convention; and DDM-based Apple software updates (legacy MDM update commands are being removed in the OS 26 wave — this is a hard deadline, not a project).
- **Operationalise as code:** IntuneCD in an Azure DevOps or GitHub Actions pipeline for backup/documentation/DEV→PROD promotion; Graph PowerShell SDK for hygiene/reporting; Log Analytics diagnostic settings for monitoring/alerting; and Intune RBAC custom roles + scope tags for least-privilege delegation.

## Key Findings

1. **The single highest-value quick win is a tenant setting, not a policy.** Audits repeatedly find the tenant-wide "Mark devices with no compliance policy assigned as" left at the permissive default of *Compliant*. With Conditional Access requiring compliant devices, this is a silent bypass. Change it to *Not compliant* — but only after confirming every enrolled device has a platform compliance policy, or you cause mass lockout.

2. **Assignment filters, not dynamic groups, are the modern targeting primitive.** Filters evaluate device properties at check-in with no group-membership processing delay, and Microsoft explicitly recommends them for ownership/platform/model/OS targeting while reserving dynamic groups for cross-workload scenarios (CA, licensing, Autopilot).

3. **Apple's Declarative Device Management (DDM) migration is time-critical.** Per Apple Support ("What's new for enterprise in iOS 26," support.apple.com/en-us/125073): *"Software update management using mobile device management commands, restrictions, the com.apple.SoftwareUpdate payload, and queries is deprecated and will be removed next year. Going forward, software updates can be managed and enforced using only declarative software update management."* (Microsoft references this as MC1113111 / Apple WWDC 2025 Session 258.) DDM update policies must be in place before the OS 26 wave or you lose managed update enforcement.

4. **Windows Autopilot device preparation ("v2") is now Microsoft's recommended path for greenfield Entra-join** — but with real constraints. It removes hardware-hash pre-registration but supports Entra join only, user-driven/automatic modes only, and a limited set of tracked apps/scripts during OOBE. Classic Autopilot remains necessary for pre-provisioning, self-deploying, and hybrid.

5. **Microsoft Cloud PKI eliminates NDES.** For a cloud-only Entra-joined estate, Cloud PKI replaces on-prem CA + NDES + certificate connector with a cloud two-tier PKI and SCEP registration authority — the correct modern choice for Wi-Fi/VPN certificate profiles.

## Details

### 1. Takeover / Assessment Phase (Phase 0)

**Objective:** achieve full, documented current-state visibility and a restorable baseline before changing anything.

**Inventory everything via export, not clicking through blades.** Two complementary community tools should be run day one (both third-party/community, both free):
- **IntuneManagement (Micke-K)** — WPF/PowerShell tool using MSAL + Graph. Exports/imports/copies/compares/documents virtually every object type (configuration & compliance policies, Settings Catalog, endpoint security, enrollment configs, app protection, policy sets, ADMX ingestion, scope tags, assignments with a migration table). Its **Compare** extension diffs live Intune objects against exported JSON and highlights changed values using the same language strings as the portal — ideal for detecting drift and documenting "as-is."
- **IntuneCD (almenscorner / Tobias Almén)** — Python tool purpose-built for backup + continuous delivery. Backs up configuration to Git as JSON/YAML, auto-generates markdown as-built documentation, and detects/propagates changes DEV→PROD. Stand this up immediately pointed at a **private** repo (the backup exposes your entire security posture even without secrets).

**What to inventory and assess:**
- All configuration profiles (template vs Settings Catalog vs ADMX/custom OMA-URI), compliance policies, endpoint security policies, enrollment configurations (Autopilot profiles, ESP, enrollment restrictions, ADE profiles, Android enrollment profiles/tokens), app deployments and app protection/config policies, filters, scope tags, RBAC roles/assignments, and every assignment (include/exclude, filter, user vs device targeting).
- **Conflicts and drift:** Use the built-in **Devices > Monitor > Profile configuration status / Policies with noncompliant and error devices** reports to surface `conflict` and `error` states. For Autopatch-managed estates, the **Policy health** workflow surfaces conflicting policies, affected devices, and open alerts. For deeper analysis, community tooling such as Jannik Reinhard's **Intune-PolicyManagement** (open-source, Graph-based) fetches all policy types and performs cross-policy conflict/overlap analysis and description generation.
- **Known trap — policy tattooing:** Deleted/unassigned settings may not be removed from devices. Patch My PC documented a case where a single **orphaned/invalid assignment filter** referenced by an old policy assignment froze the entire delete pipeline for ALL policies in a tenant. During assessment, hunt for orphaned assignments and broken filter references explicitly.
- **Orphaned/stale objects:** enumerate empty groups, unused filters, unassigned policies, and devices past inactivity thresholds.

**Baseline & document:** Commit the first IntuneCD backup as the immutable "inherited-state" tag. Generate the as-built markdown. Record the tenant-wide compliance default, enrollment restrictions, MDM authority, connector states (ABM/VPP tokens, managed Google Play, Defender connector, certificate connectors), and licensing (Intune Plan 1/2, Intune Suite add-ons, E3/E5).

### 2. Policy Architecture & Hygiene

**Naming convention (adopt and enforce):** A self-documenting, sortable, script-friendly scheme. Community consensus (Cloud Engineer Lab, Mobile Mentor, ctrlaltnod) converges on a prefixed, ordered pattern such as `CFG-WIN-PRD-BitLocker-Encryption` / `CMP-iOS-PRD-Baseline`, and groups like `GRP-MDM-WIN-PilotRing`. Principles: most-significant identifier first (type → platform → ring/state → purpose); one abbreviation per concept (WIN not Windows/Win); **never put dates or version numbers in the display name** (put them in the description) — deployment ring (PIL/PRD) yes, versions no; always distinguish pilot from production in the name to prevent accidental broad deployment.

**Assignment strategy:**
- Prefer **user groups** for most policies (staged deployment mindset) and **device groups** where user context doesn't apply (kiosk, shared, LAPS — see below). Do not mix user and device groups within one ring model.
- Use **assignment filters** (include/exclude) for ownership, platform, OS, model, VM-vs-physical refinement rather than creating a new group per attribute. Per Microsoft Learn ("Create assignment filters in Microsoft Intune"): *"You can have up to 200 assignment filters for each tenant. Each assignment filter is limited to 3,072 characters."* Filters apply to configuration/compliance/app deployment but for MAM only to app protection/app config policies.
- Keep group design minimal — community targeting guidance: 5–8 core groups should handle ~80% of assignments; no policy should have more than two exclusion groups or one exclusion filter; every exclusion group needs a documented justification and review date.

**Ring-based deployment:** Establish standard rings (e.g., Ring 0/IT, Ring 1/pilot early-adopters, Ring 2/broad, Ring 3/all) via manually-managed static groups for the pilot rings and dynamic/all-device for broad. A common cadence is Ring 1 immediate → +7 days → +14 days → all. Rings apply to everything: update rings, feature/driver updates, configuration profiles, apps, scripts.

**Settings Catalog vs templates vs ADMX:** Standardise net-new work on **Settings Catalog** (unified CSP-backed surface, per-setting granularity, best IntuneCD/documentation fidelity). Retain templates only where a capability isn't in the catalog (note: the ASR **Application control** profile is still template-format). Use **ADMX ingestion** only for third-party/LOB admin templates not otherwise covered.

**Change management:** All policy changes flow through the Git/IntuneCD DEV→PROD pipeline (below) with peer review, plus consider **Multi-Admin Approval (MAA)** for high-blast-radius object types (scripts, apps, some device actions).

### 3. Windows Management (Entra-joined)

**Provisioning — choose the model deliberately:**
- **Windows Autopilot device preparation ("device prep"/"v2")** is Microsoft's recommended path for new cloud-native Entra-join deployments. Its core mechanism is **Enrollment Time Grouping**: the policy is assigned to a **user group**; when the user signs in during OOBE the device is auto-added to a pre-defined **device security group** (which must have "Intune Provisioning Client" as its owner), and apps/scripts assigned to that device group provision. Critically it needs **no hardware-hash pre-registration** — the profile is fetched *after* Entra authentication, not before. Constraints (per the Microsoft Learn Compare doc, ms.date 2025-04-02): **Entra join only** (no hybrid), **user-driven and automatic modes only**, **Windows 11 24H2+ or 23H2/22H2 with KB5035942** (no Windows 10), and it supports LOB+Win32 in the same deployment (classic does not). **App limit:** Microsoft's "What's new in Windows Autopilot device preparation" states the maximum was increased to **25 apps as of the January 30, 2026 update** (*"The maximum number of apps… has been increased to 25… applies to both user-driven and automatic modes"*); the **10 PowerShell script** limit is unchanged. The stale 10-app figure still appears in the live Autopilot device preparation FAQ (*"almost 90% of all Windows Autopilot deployments are deployed with 10 or fewer apps"*) — verify against the live doc for your date. No pre-provisioning, self-deploying, existing-device, Autopilot Reset, DFCI, or Autopilot-into-co-management support.
- **Classic Autopilot (user-driven, pre-provisioning/white glove)** remains required for technician pre-provisioning, self-deploying/shared, DFCI, device rename before enrollment, and any hybrid. Both models can coexist; a device registered in classic Autopilot always uses classic (Autopilot profiles take precedence).
- Given a cloud-only Entra-joined estate, standardise new provisioning on device preparation, keep classic where pre-provisioning is genuinely required, and pilot v2 side-by-side.

**Enrollment Status Page:** Do not rely on the default ESP (which hides app/profile progress). Create a custom ESP that shows progress and blocks device use until required apps/policies install — Microsoft explicitly recommends overriding the default. Understand the Device ESP → User ESP phases; ESP tracks SCEP device certs, Wi-Fi/VPN profiles, and tracked apps.

**Security baselines:** Deploy the **Windows security baseline (MDM)**, **Microsoft Defender for Endpoint baseline**, and **Microsoft Edge baseline**. Baselines are templates of multiple config profiles. Watch for **cross-baseline default conflicts** (the same setting can have different defaults in the Windows vs Defender baseline) — review and customise, don't accept defaults blindly. Only the newest version of a baseline can be used to create new instances; migrate old instances forward. The **STIG audit baseline** is audit-only (reports, doesn't enforce).

**Windows Update / Autopatch:** Move the Windows Update workload to **Windows Autopatch** (embedded in Intune, entitlement in E3/E5/Business Premium). Autopatch auto-creates its own Entra groups, update rings, and configuration profiles — **do not modify Autopatch-created groups/policies**; the service raises Policy health alerts and can restore them if they drift. Target 95% by compliance date; enable **hotpatching** on Windows 11 24H2 to apply security updates without reboot. Don't assign custom update rings to Autopatch-managed devices.

**Driver & firmware updates:** Use Intune **Driver update policies** (Devices > Manage updates > Windows updates > Driver updates). OEMs (Dell/HP/Lenovo) publish firmware to Windows Update as driver updates — manage them centrally with Automatic (with a 0–30 day deferral) or Manual approval per ring, giving a single pane across vendors. **Prerequisite:** the update ring / Settings Catalog "Windows driver" setting must be Allow (older tenants sometimes set Block). Recommend **one driver policy per device** (multiple policies risk approve/decline conflicts); driver policies do not support assignment filters; switching a ring between Automatic/Manual regenerates policies and loses prior approvals.

**BitLocker/disk encryption:** Endpoint security > Disk encryption; silent enablement requires Entra join + TPM + proper mode. Ensure recovery keys escrow to Entra ID (they live on the device object — back them up before any device deletion).

**Windows LAPS with Entra ID:** First enable LAPS at the tenant level (Entra > Devices > Device settings > Enable LAPS). Deploy via Endpoint security > Account protection > Local admin password solution. Best practices: **backup to Entra ID only** (cloud-only estate); **assign to device groups, not user groups** (user-group assignment cycles LAPS config per signed-in user and causes conflicts); **one LAPS policy / one managed account per device** (conflicts otherwise block backup); on Windows 11 24H2 use **Automatic Account Management** (no script/CSP needed to create the account). Community-recommended settings (ourcloudnetwork/Daniel Bradley): password length ≥ 15, complexity "large+small+numbers+special (improved readability)", and a shorter PasswordAgeDays (e.g., 7) to mitigate copy/paste-less self-service. Protect password retrieval with RBAC.

**Compliance policies (Windows):** minimum OS (target Windows 11 24H2/23H2 — Windows 10 reached end of support 14 Oct 2025), BitLocker required, Secure Boot, Defender AV active, firewall, and **Defender for Endpoint machine risk score** ≤ Medium. Pair with grace periods (see §6).

**Defender for Endpoint integration:** Establish the service-to-service connector in the Defender portal AND enable the Intune connection; deploy the **EDR onboarding** policy (Intune auto-provisions the onboarding package for Windows). Without the connector the machine-risk compliance check does nothing.

**Endpoint Privilege Management (EPM):** Intune Suite add-on. Per the Microsoft Intune Blog ("Advanced Microsoft Intune capabilities now available in Microsoft 365 E3 and E5"): *"The packaging changes announced in December 2025 are now in effect. As of July 1, advanced Intune Suite capabilities are included in Microsoft 365 E5, with select capabilities available in Microsoft 365 E3."* **EPM (with Enterprise App Management and Cloud PKI) is E5-only** — E3 receives Remote Help, Advanced Analytics, and Intune Plan 2, not EPM. Remove standing local admin; two policy types — **Elevation settings** (provisions the agent, sets default response; recommend Deny elevation for unsigned files, require business justification) and **Elevation rules** (per-file: Automatic / User confirmed / Support approved / Elevate as current user [Oct 2025]). **Audit-first**: deploy settings policy in report-only to a pilot, mine the Elevation report + Overview dashboard for the top elevation candidates, build rules (prefer publisher certificate + path over file hash — hashes change every update), then remove local admin. Requires 64-bit, supported builds, and clear line-of-sight without SSL inspection.

**Proactive remediations (Remediations):** Detection + remediation script pairs for drift correction and device hygiene (E3+MDE/E5). Use community repos (MSEndpointMgr, Intune Remediation Repo) as a starting library.

**Windows Hello for Business:** Configure cloud Kerberos trust for Entra-join; EPM can require the WHfB PIN to authorise elevation.

**App deployment:** See §7.

### 4. iOS/iPadOS Management (Supervised/ADE)

**ADE enrollment profile design:** Enrol all corporate devices via **Apple Business Manager + ADE** for supervision (tamper-resistant, locked MDM profile, prevents user removal, enables the broadest management surface). Customise Setup Assistant panes; use `{{SERIAL}}`-based naming templates. **Exclude the Microsoft Intune cloud app** from any "require compliant device"/Block CA policy affecting the enrollment flow (the Apple setup uses a Chrome/Safari auth tab).

**Supervised configuration & security controls:** Device restriction profiles expose supervised-only controls (block App Store / in-app purchases, restrict Siri content, force-delay software update visibility, single/autonomous app mode/kiosk). Align to the CIS/Microsoft security levels.

**Declarative Device Management (DDM) — the priority item:** Apple deprecated legacy MDM `ScheduleOSUpdate`/`OSUpdateStatus` commands at WWDC 2025; they are **removed in iOS/iPadOS/macOS 26** (Apple: *"…deprecated and will be removed next year. Going forward, software updates can be managed and enforced using only declarative software update management."*). Intune's legacy Apple update policies are already marked deprecated. Configure DDM update policies via **Settings Catalog** (iOS/iPadOS > Configuration > Settings Catalog > Software Update): either **Enforce latest** with a deferral (e.g., 3 days) or **Targeted version**. Known issue: **"Enforce latest" is unreliable on iPads** (shows the "install by January 1, Year 1" bug) — use Targeted Version policy for iPads. Migrate to DDM **before** the OS 26 wave; if no DDM policy exists when OS 26 ships you lose managed update control. Per Microsoft's Intune Customer Success blog ("Support tip: Move to declarative device management for Apple software updates"), Intune's **August 2025** release added real-time DDM-based software update reporting, with product-team guidance to *"migrate now, not later."*

**App Protection Policies vs device restrictions:** On supervised corporate devices, device restrictions + device compliance are the primary control; APP (MAM) is layered where you want data-containment inside apps. Note only **VPP-managed** app installs satisfy the CA "require app protection policy" control on iOS (standard App Store installs don't qualify).

**VPP / Apps & Books:** Use ABM **location tokens** (formerly VPP tokens; one per location, valid one year, multiple supported per tenant). Intune assigns licences; Apple performs installs. Device-licensing is preferred for supervised corporate devices (no Apple ID needed). Do not delete legacy tokens mid-migration or you must recreate all assignments; migrate one purchaser per location.

**Per-app VPN:** Deploy trusted root + SCEP/PKCS client cert (via Cloud PKI), then an iOS VPN profile flagged per-app, associated to the app + user group, so only corporate app traffic tunnels.

**Compliance (iOS):** min OS (target iOS 17+/latest), jailbreak detection, passcode, and MTD/Defender threat level. Enforce minimum OS in compliance alongside DDM update enforcement.

### 5. Android Management (COPE & Fully Managed)

**Foundations:** Set MDM authority to Intune and connect **managed Google Play**. Enrol via **corporate-owned work profile (COPE)** or **fully managed (COBO)** profiles/tokens; support bulk enrolment via QR, **Google Zero Touch**, or **Knox Mobile Enrollment**. The Microsoft Intune app (not Company Portal) is the required agent on these corporate profiles.

**COPE vs Fully Managed:**
- **COPE** = single user, work profile + personal space; admin controls a limited device-wide set (password, Bluetooth, roaming, factory-reset protection) plus full control of the work profile. Use for corporate devices that permit personal use. Note factory-reset-protection behaviour differs by enrollment type and Android 15 requires re-entering the associated Google account after a Settings-app reset — plan reprovisioning accordingly.
- **Fully Managed (COBO)** = whole device managed; use Microsoft/CIS **security configuration levels** (Level 1 minimum for corporate-owned) for both compliance and device-restriction policies.

**Configuration & security controls:** Use device restriction profiles for the built-in control surface; **app configuration policies** (managed configurations, configuration designer or JSON) for per-app settings and to restrict Microsoft apps to org accounts; **OEMConfig** for OEM-specific settings beyond the Android Management API (e.g., Samsung Knox Service Plugin, Zebra). OEMConfig caveats: max 500 KB profile, **assign only one OEMConfig profile per device**, Intune doesn't validate the OEM schema (contact OEM). Consider Managed Home Screen for kiosk/dedicated.

**Compliance & security signals:** Play Integrity verdicts (basic / basic+device / strong hardware-backed), Google Play Protect, rooted-device detection, min OS, and Defender/MTD machine-risk score. **Target dedicated/kiosk compliance policies at device groups**; COPE/Fully Managed can target user or device groups. For CA on dedicated devices use Entra shared device mode.

**App deployment & updates:** Deploy managed Google Play apps (required/available); use managed-Google-Play auto-update settings and priority. Device cleanup rules do **not** apply to Android Enterprise COBO/dedicated/COPE — handle stale records via Graph/manual.

### 6. Compliance & Conditional Access (device-compliance scope only)

**Design principles (fix the common anti-patterns):**
- Set the tenant-wide **"Mark devices with no compliance policy assigned as" = Not compliant** (audits show ~72% leave it at the permissive default) — after confirming coverage.
- **Platform-specific policies** (one per Windows/iOS/Android — a single global policy is invalid; ~38% of tenants do this wrong).
- **Assign compliance to user groups** for knowledge workers (device-group assignment causes per-sign-in gaps since CA evaluates user sign-ins) and refine with filters; device groups for user-less devices.
- **Grace periods / staged noncompliance actions:** by default the "mark noncompliant" action fires at 0 days (immediate CA block). Configure escalation: Day 0 user notification, a grace period sized to the risk (community norm ~3 days Windows/macOS, 1 day iOS/Android; another practical model is 24h existing / 72h new), then lock/retire for serious unresolved violations. ~53% of tenants have no grace period, causing helpdesk floods. But don't over-size grace periods — an over-long window is a silent security gap.

**Conditional Access integration (device-compliance enforcement only):**
- Grant control **Require device to be marked as compliant** (this estate is cloud-only, so use Compliant rather than hybrid-joined). For mixed patterns use **compliant OR Entra-joined** (OR, not AND).
- **Always deploy in report-only mode first** (only ~9% of tenants do) and pilot before enforcing.
- Understand the **propagation pipeline & latency**: Intune evaluates → writes `isCompliant` to the Entra device object on Intune's schedule → CA reads it on next token request. A remediated device can still be blocked briefly due to propagation lag — trigger a sync and wait; don't assume the CA policy is broken.
- Exclude break-glass/emergency-access accounts from CA. Use CA **device filters** to scope by device attributes where needed.
- Multi-policy behaviour: most-restrictive wins; any applicable Block takes precedence.

### 7. App Management

**Win32 packaging & deployment:**
- Package with **IntuneWinAppUtil** (Win32 Content Prep Tool); keep the source folder clean (the tool packages the *entire* folder). Prefer MSI over EXE where offered (auto-populates install/uninstall + product code). Apps must install **silently** — no interactive installers; ServiceUI-style forced interaction is unsupported.
- **Detection rules:** prefer **registry-based version detection** (Uninstall hive, "greater than or equal to" on version) over "file/folder exists" — more robust for updates and supersedence. MSI = product code; MSIX = package family name.
- **Supersedence:** create the new version as a Win32 app duplicating the original, with updated detection and a supersedence link to the old version (choose uninstall-previous only when the app won't upgrade in place or you're switching products). Get supersedence detection right from the start — **don't retroactively edit old package detection rules** (it forces Intune to re-evaluate compliance across all devices). Use the **Relationship viewer** to see dependency/supersedence chains.
- **Dependencies:** model app dependencies explicitly. During Autopilot, prefer the Win32 app type consistently — mixing Win32 and LOB apps during classic Autopilot enrollment can fail due to Trusted Installer contention (mixing IS supported under Autopilot device preparation).
- **PSADT (PowerShell App Deployment Toolkit)** — third-party, community standard for complex installs (user prompts to close apps, pre/post logic); widely documented silent-install recipes.

**MSIX / Store / LOB:** Use **Microsoft Store app (new)** for winget-backed apps (Intune keeps them updated where the publisher supports winget upgrade). Use the **Enterprise App Catalog** for pre-packaged Win32 apps. MSIX and MSI can also be LOB apps.

**App configuration policies (ACP):** deploy managed app configuration for iOS/Android (and the IntuneMAMUPN keys required for MAM on managed devices).

**App Protection Policies (MAM):** Use Microsoft's **data protection framework levels (1/2/3)** to prioritise. Layer with CA ("require app protection policy"). Note iOS requires VPP-managed apps to satisfy that CA control.

**Third-party app patching:** Intune-native supersedence requires manual repackaging per version. **Patch My PC** (third-party, commercial) automates detection, download, packaging as Win32, publishing to Intune, and supersedence for a large third-party catalogue — the standard enterprise answer to third-party patch fatigue. **WinTuner** / winget-based and **Scappman**-style solutions are lighter-weight alternatives. Vulnerability signals come from Defender for Endpoint.

### 8. Automation & Graph

**Graph PowerShell SDK** is the automation backbone: reporting, bulk policy operations, device hygiene, and remediation. Use app-registration (client secret/cert) for unattended runs with least-privilege Graph scopes (e.g., `DeviceManagementConfiguration.Read.All`, `DeviceManagementManagedDevices.ReadWrite.All`).

**Device hygiene / stale cleanup:**
- Intune native **Device cleanup rules** (Devices > Organize devices) soft-delete records inactive 30–270 days; platform-specific rules can be managed via Graph (`DeviceManagementManagedDevices.ReadWrite.All`). Caveats: only removes the **Intune** record (not Entra ID, not Autopilot registration); does not wipe; devices can auto-recover if they check in within ~180 days before cert expiry; **not available for Android Enterprise COBO/dedicated/COPE**.
- Entra ID has **no native stale-device rule** — script it with Graph (`Get-MgDevice` filtered on `ApproximateLastSignInDateTime`, disable-then-delete with a grace period) on a schedule (Azure Automation runbook with a managed identity, `Device.ReadWrite.All`). Community scripts: Mr T-Bone, Simon Skotheimsvik. **Back up BitLocker keys / LAPS before deleting Entra device objects** (they live on the object). Hybrid/Autopilot objects need special handling.

**Infrastructure-as-code & CI/CD:**
- **IntuneCD** in **Azure DevOps** (Azure AD-backed access; recommended for production) or **GitHub Actions**: scheduled `IntuneCD-startbackup` to a private repo, auto-generated as-built docs (publishable to a DevOps Code Wiki), commit messages linked to Intune audit-log events with the admin who made each change, and DEV→PROD promotion. Aaron Parker (stealthpuppy) publishes ready-to-fork templates; snodecoder maintains an Azure DevOps template with backup/restore pipelines. Microsoft's own Intune Customer Success blog documents a Config-as-Code pattern (app-registration + Graph app permissions, Key Vault for secrets).
- **IntuneManagement** supports silent/batch DevOps operation (app-auth) for cross-tenant DEV/TEST→PROD replace/update.
- Microsoft's supported DSC route is **Microsoft365DSC** for those wanting desired-state config/monitoring. (Terraform is explicitly out of scope for this plan.)

**Backup/restore & DR:** IntuneCD (Git) is the primary configuration DR mechanism; IntuneManagement export/import is the interactive equivalent. Keep repos private; treat backups as sensitive.

### 9. Monitoring, Reporting & Operations

**Native reporting:** Devices > Monitor and Reports — Profile configuration status (success/error/**conflict**/not applicable), Policy noncompliance / Noncompliant devices, Windows Update/Feature Update reports, app install status, and the DDM/EPM/Autopatch dashboards. Endpoint Analytics for user-experience/boot/reliability signals.

**Log Analytics / Azure Monitor (requires Azure subscription):** Reports > **Diagnostic settings** → send **Audit logs, Operational logs, Device Compliance Org logs, IntuneDevices** to a **Log Analytics workspace** (also/optionally Event Hubs for SIEM like Sentinel/Splunk/QRadar, or Storage for archive). Audit/Operational logs arrive near-immediately; Device Compliance Org and IntuneDevices data can take up to 48h. Build **Azure Monitor Workbooks** and KQL alerts for custom dashboards. Diagnostic settings are deployable via Bicep/REST for IaC.

**KPIs to track:** enrolment success rate, % devices compliant (by platform), non-compliance reasons breakdown, Autopatch update compliance vs target date (95%), configuration profile conflict/error counts, app install success rates, EPM managed-vs-unmanaged elevations, stale-device counts, and DDM/Apple update status.

**Operational runbooks:** documented procedures for enrolment troubleshooting, compliance remediation, app-deployment failures, driver approval cadence (align to Patch Tuesday), stale-device cleanup, token/connector renewal (ABM/VPP annually, certificate connectors), and baseline/version updates. Monitor **service health** and audit logs for unexpected policy/setting changes (compromised-admin indicator).

### 10. Security & Endpoint Protection

- **ASR rules:** deploy via Endpoint security > Attack surface reduction. **Requires Defender AV as primary AV in active mode** (third-party AV blocks enforcement). **Start every rule in Audit for ≥7–14 days**, review Event Viewer (1121 block/1122 audit/5007 change) and the Defender report, then move low-regret rules (LSASS credential theft, Office child-process/executable creation) to Block first. Configure each ASR rule in **only one policy per device** (or identical values everywhere) to avoid conflicts; maintain a documented exclusion register with owner + review date.
- **Defender for Endpoint:** connector + EDR onboarding (as §3); feeds compliance machine-risk score and vulnerability management.
- **Device control / removable storage:** via Defender integration and reusable device-control groups.
- **Endpoint DLP:** consider Purview endpoint DLP for data-movement control (adjacent to Intune; licensing-dependent).
- **Certificate management — Microsoft Cloud PKI:** For a cloud-only Entra-joined estate, **Cloud PKI** (Intune Suite; E5-only per the July 2026 packaging) is the modern replacement for on-prem CA + NDES + certificate connector. It provides a cloud two-tier hierarchy (root + issuing CA) or **BYOCA** anchoring to an existing private root, a SCEP registration authority, and Intune-hosted CRL/AIA endpoints. Create trusted-cert profiles per platform + SCEP profiles (leave `{{CloudPKIFQDN}}` intact; note EKU "Any Purpose" unsupported). Use for Wi-Fi/VPN/802.1x client-auth certs. **SCEP** issues unique per-request certs (incl. user-less devices); **PKCS** for per-user/device; **imported PKCS** for shared S/MIME. Legacy SCEP still needs NDES + certificate connector — Cloud PKI removes that dependency.
- **Security baseline management:** as §3 — version-managed, conflict-aware, monitored.

### 11. Third-Party / Community Tooling Ecosystem

All below are third-party/community (many free/open-source); note what each solves. Curated master lists: **awesomeintune.com** and the **awesome-intunetools** / Awesome Intune Tools GitHub repos.

- **IntuneManagement (Micke-K)** — export/import/copy/compare/**document** all policy types; cross-tenant migration; drift detection. *Solves:* assessment, documentation, DEV→PROD, backup.
- **IntuneCD (almenscorner)** — Git-based backup + CI/CD + as-built docs + DEV→PROD promotion. *Solves:* configuration-as-code, DR, change tracking.
- **Intune Debug Toolkit (MSEndpointMgr / Mattias Melkersen)** — on-device Windows troubleshooting toolbox (bundles IntuneDeviceDetails GUI [Petri Paavola, RSOP-style view], SyncMLViewer [Oliver Kieselbach], Win32 app rerun, CMTrace, corporate-identifier import). *Solves:* client-side diagnosis of policy/app delivery.
- **Microsoft Graph X-Ray** — captures the Graph calls the portal makes (browser extension), generating ready PowerShell. *Solves:* reverse-engineering Graph for automation.
- **IntuneDeviceDetails GUI (Petri Paavola)** — resultant-set-of-policy view per device. *Solves:* "what actually applied and why."
- **Intune-PolicyManagement (Jannik Reinhard)** — Graph-based, AI-assisted policy documentation + cross-policy conflict/overlap analysis. *Solves:* the assessment conflict-hunt.
- **Remediation script repos (MSEndpointMgr, Intune Remediation Repo)** — proactive remediation library. *Solves:* drift/hygiene automation.
- **Patch My PC** (commercial) — automated third-party app packaging/publishing/supersedence + updates. *Solves:* third-party patch management at scale.
- **WinTuner / WinTuner GUI** — winget → Intune Win32 packaging/publishing/update. *Solves:* fast packaging of common apps.
- **Scappman**-style / winget solutions — SaaS third-party patching alternatives.
- **PSADT (PowerShell App Deployment Toolkit)** — complex install orchestration + user interaction. *Solves:* hard-to-package apps.
- **OSDCloud (David Segura / OSD module)** — cloud-based bare-metal Windows imaging over the internet. *Solves:* re-imaging/repurposing hardware pre-Autopilot.
- **Master Packager** — repackaging/MSI authoring. *Solves:* installer inspection and repackaging.
- **DCToolbox (Daniel Chronlund)** — M365/CA automation PowerShell. *Solves:* CA/security scripting adjacent to Intune.
- **Intune Backup/Restore module (John Seerden)**, **Automatic M365 Documentation (Thomas Kurth)** — additional backup/doc options.

### 12. Governance & RBAC (Intune-scoped)

- **Least privilege:** don't use Intune Administrator (Entra) for daily work. Assign **built-in Intune RBAC roles** (Policy and Profile Manager, Application Manager, Help Desk Operator, etc.) to **groups**, not users; permissions are cumulative across assignments with no deny.
- **Custom roles:** create precise custom Intune roles where built-ins over/under-grant (e.g., a read-only Security operations role; a compliance-only author role). Note some actions need custom roles — e.g., enabling **Scoped permissions** requires a custom role with Organization/Update.
- **Scope tags:** roles define *what actions*; scope tags define *which objects are visible*. Use them for distributed IT (region/BU/team). Details: objects an admin creates inherit that admin's scope tags; VPP apps inherit the token's tags; a few object types don't support tags (corp device identifiers, Autopilot devices, compliance locations); an admin with no scope tag effectively sees all. **Scoped permissions is a one-time, irreversible tenant toggle** — run the Permissions Assessment Report first.
- **Separation of duties:** split policy authoring, app management, security/EPM approval, and help-desk operations across roles; require **Multi-Admin Approval** for high-risk object types.
- **Change management:** enforce the Git/IntuneCD pipeline + peer review; maintain the naming convention and as-built docs; review audit logs for unexpected changes.

### 13. Phased Implementation Roadmap

**Phase 0 — Assess / Baseline / Document (weeks 1–3).** Stand up IntuneCD (private repo) + IntuneManagement; full export + as-built. Inventory policies/apps/enrollment/RBAC/filters/connectors/licensing. Run conflict/overlap analysis (Profile config status, Policy health, Intune-PolicyManagement). Hunt orphaned assignments/broken filters (tattooing risk). Record the tenant compliance default. *Deliverable:* documented current state + immutable baseline tag. *Quick wins:* delete obviously orphaned/empty groups & unused filters; enable Log Analytics diagnostic settings.

**Phase 1 — Stabilise & critical fixes (weeks 2–5, overlaps).** Resolve one-policy-per-device conflicts (LAPS, ASR duplicates, driver policies). Fix broken filter references. Consolidate duplicate/contradictory compliance policies to platform-specific. Verify compliance coverage, then flip tenant default to **Not compliant**. Put all critical CA device-compliance policies into **report-only**. *Quick wins:* the tenant-default flip; LAPS to device-group/Entra-only; ASR audit-mode baseline.

**Phase 2 — Rebuild policy architecture (weeks 4–10).** Implement the naming convention (rename or rebuild). Establish ring groups + assignment filters. Migrate legacy templates → Settings Catalog. Rebuild configuration/compliance profiles on rings with filters. Stand up the IntuneCD DEV→PROD pipeline + peer review + MAA on high-risk objects. *Longer-term structural work.*

**Phase 3 — Security hardening & compliance/CA enforcement (weeks 8–16).** Deploy/customise security baselines (Windows/Defender/Edge). ASR audit→block progression. Onboard Defender for Endpoint (connector + EDR) and wire machine-risk into compliance. Deploy EPM audit-first then remove local admin. Roll out Cloud PKI + Wi-Fi/VPN cert profiles. **Migrate Apple updates to DDM (time-critical before OS 26).** Move Windows updates to Autopatch. Enforce CA "require compliant" ring-by-ring out of report-only. *Quick win within this phase:* DDM policy for iPhones (Targeted Version for iPads).

**Phase 4 — Automation, IaC & monitoring (weeks 12–20).** Mature CI/CD (gated PROD deploys, automated backup/doc). Graph runbooks for stale-device hygiene (Intune + Entra), reporting, remediation. Build Log Analytics workbooks + KQL alerts + KPI dashboards. Formalise operational runbooks. RBAC custom roles + scope tags + separation of duties.

**Phase 5 — Continuous improvement / operations (ongoing).** Quarterly policy/compliance review; drift detection via IntuneCD diffs; ring-based change management; baseline version upkeep; token/connector renewal calendar; audit-log review for unauthorised change; periodic RBAC recertification.

## Recommendations

1. **Week 1, non-negotiable:** private-repo IntuneCD + IntuneManagement export, immutable baseline tag, Log Analytics diagnostic settings on. Do not change any policy until the baseline exists.
2. **Fastest safe security win:** verify compliance coverage → flip tenant default to Not compliant → put "require compliant device" CA into report-only. *Threshold to enforce:* <5% non-compliance in a platform before switching that platform's CA from report-only to enforced.
3. **Fix conflicts before architecture.** Resolve LAPS/ASR/driver one-policy-per-device conflicts and broken filter references in Phase 1; a clean object graph makes the rebuild deterministic.
4. **Treat DDM as a deadline, not a project.** Deploy DDM Apple update policies now (Targeted Version for iPads to dodge the enforce-latest bug); you lose Apple update control when OS 26 ships without it.
5. **Standardise new Windows provisioning on Autopilot device preparation**, keeping classic only where pre-provisioning/self-deploying is genuinely required. *Threshold to reconsider:* if you need >25 tracked OOBE apps, hybrid join, or pre-provisioning, stay on classic.
6. **Go code-first for change management** (IntuneCD DEV→PROD + peer review + MAA) before widening the admin team; pair with RBAC custom roles + scope tags.
7. **Adopt Cloud PKI** to decommission NDES; **adopt Autopatch** to offload update orchestration; **adopt EPM audit-first** to remove standing local admin (confirm E5 entitlement first).
8. **Re-baseline quarterly.** Use IntuneCD Git diffs as the drift detector and the audit log as the tamper detector; recertify RBAC and exclusions on the same cadence.

## Caveats

- **Version-dependent facts move fast.** The Autopilot device preparation app limit is **25 apps + 10 scripts as of the January 30, 2026 update** ("What's new in Windows Autopilot device preparation"), but the still-live device-prep FAQ retains the older 10-app figure — verify against the live Compare/What's-new docs for your tenant's date. Some device-prep modes (pre-provisioning/self-deploying) are described as roadmap, not shipped.
- **DDM enforcement inconsistency is real:** the "Enforce latest" declaration is reported unreliable on iPads (the "install by January 1, Year 1" bug) even by admins in production; Targeted Version is the current workaround. This is community-reported behaviour, not a documented Microsoft position.
- **Licensing gates several recommendations and changed on a known schedule.** Per the Microsoft Intune Blog, the packaging changes announced **December 4, 2025** are now in effect: *"As of July 1, advanced Intune Suite capabilities are included in Microsoft 365 E5, with select capabilities available in Microsoft 365 E3."* **EPM, Enterprise App Management, and Cloud PKI are E5-only**; E3 gets Remote Help, Advanced Analytics, and Intune Plan 2. List-price changes effective July 1, 2026 raise M365 E3 from $36→$39 and E5 from $57→$60 per user/month; eligible EMS E3 and M365 E5 tenants are automatically provisioned the included Intune Suite capabilities. Validate entitlement in Tenant administration > Intune add-ons before designing around them. Defender machine-risk compliance needs Defender for Endpoint P1/P2.
- **Windows 10 reached end of support 14 Oct 2025.** It can still enrol but functionality "isn't guaranteed"; standardise on Windows 11 (24H2 for hotpatch/Automatic LAPS account management).
- **Cleanup asymmetry:** Intune cleanup rules don't touch Entra ID or Autopilot registrations and don't cover Android COBO/dedicated/COPE; back up BitLocker/LAPS before deleting Entra objects.
- **Third-party tools** listed are community/commercial and outside Microsoft support; validate against your change-control and security review before production use. Some cited best-practice thresholds (grace-period days, ring percentages, non-compliance %) are community conventions, not Microsoft-mandated values — tune to your risk appetite.
- Several statistics (e.g., % of tenants with misconfigured defaults) come from third-party consultancy audits, not Microsoft telemetry, and should be treated as directional.

## Priority To-Do Checklist

### Priority 1 — Baseline before changing anything
- [ ] Stand up IntuneCD against a **private** Git repo and run a full IntuneManagement export; commit the first backup as an immutable "inherited-state" tag
- [ ] Generate as-built markdown documentation from the export
- [ ] Enable Log Analytics diagnostic settings (Audit, Operational, Device Compliance Org, IntuneDevices) *(quick win)*
- [ ] Inventory all policies, apps, enrollment configs, filters, scope tags, RBAC assignments, and connector/token states (ABM/VPP, managed Google Play, Defender, cert connectors)
- [ ] Record the current tenant-wide "Mark devices with no compliance policy assigned as" setting
- [ ] Confirm licensing entitlements before designing around them (EPM, Cloud PKI, Enterprise App Management are E5-only; Defender machine-risk needs MDE P1/P2)

### Priority 2 — Critical stabilisation
- [ ] **Migrate Apple software updates to DDM before the OS 26 wave** — Settings Catalog update policies; Targeted Version for iPads, Enforce Latest + deferral for iPhones *(deadline-driven)*
- [ ] Run cross-policy conflict/overlap analysis (Profile configuration status, Policy health, Intune-PolicyManagement)
- [ ] Hunt and remove orphaned assignments and broken filter references (policy-delete/tattooing risk)
- [ ] Resolve one-policy-per-device conflicts for LAPS, ASR, and driver policies
- [ ] Fix LAPS: assign to **device groups**, back up to **Entra ID only**, one policy/one managed account per device
- [ ] Consolidate duplicate/contradictory compliance policies into one per platform (Windows/iOS/Android)
- [ ] Verify every enrolled device has a platform compliance policy, **then** flip the tenant default to **Not compliant**
- [ ] Put all "require compliant device" Conditional Access policies into **report-only**; exclude break-glass accounts
- [ ] Delete orphaned/empty groups and unused filters *(quick win)*

### Priority 3 — Rebuild policy architecture
- [ ] Define and enforce the naming convention (type → platform → ring → purpose; no dates/versions in display names)
- [ ] Build ring groups (IT / pilot / broad / all) and standard assignment filters for platform/ownership/model
- [ ] Migrate legacy template profiles to Settings Catalog
- [ ] Rebuild configuration and compliance profiles onto rings + filters
- [ ] Stand up the IntuneCD DEV→PROD pipeline (Azure DevOps or GitHub Actions) with peer review
- [ ] Enable Multi-Admin Approval on high-blast-radius object types (scripts, apps)

### Priority 4 — Security hardening & enforcement
- [ ] Deploy and customise the Windows, Defender for Endpoint, and Edge security baselines; resolve cross-baseline default conflicts
- [ ] Deploy ASR rules in **Audit** for 7–14 days, then move low-regret rules (LSASS, Office child-process) to Block
- [ ] Establish the Defender for Endpoint connector + EDR onboarding, and wire machine-risk score into compliance
- [ ] Deploy EPM in report-only, mine elevation candidates, build publisher/path rules, then remove standing local admin
- [ ] Deploy Microsoft Cloud PKI and issue Wi-Fi/VPN client-auth cert profiles (decommission NDES)
- [ ] Move the Windows Update workload to Windows Autopatch (target 95% by compliance date; enable hotpatching on 24H2)
- [ ] Configure compliance grace periods / staged noncompliance actions per platform
- [ ] Move CA "require compliant" out of report-only ring-by-ring once a platform is <5% non-compliant
- [ ] Configure Intune driver update policies (one policy per device, per-ring approval cadence)
- [ ] Standardise new Windows provisioning on Autopilot device preparation with a custom Enrollment Status Page

### Priority 5 — Automation, monitoring & governance
- [ ] Build Graph PowerShell runbooks for stale-device hygiene (Intune cleanup rules + Entra disable-then-delete, backing up BitLocker/LAPS first)
- [ ] Build Graph runbooks for scheduled reporting and remediation; seed a proactive remediation library
- [ ] Build Azure Monitor workbooks, KQL alerts, and a KPI dashboard (compliance %, Autopatch compliance, conflict counts, app success, EPM elevations)
- [ ] Design Intune RBAC custom roles + scope tags with separation of duties; run the Permissions Assessment Report before any Scoped Permissions toggle
- [ ] Formalise operational runbooks (enrollment, compliance remediation, app failures, driver approvals, token/connector renewal calendar)

### Priority 6 — Ongoing operations
- [ ] Quarterly policy, compliance, and exclusion-register review
- [ ] Drift detection via IntuneCD Git diffs; tamper detection via audit-log review
- [ ] Periodic RBAC recertification
- [ ] Baseline version upkeep and connector/token renewal tracking