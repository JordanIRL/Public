# Intune iOS/iPadOS Automated Device Enrolment Implementation Plan

**Fact-checked:** 11 July 2026  
**Scope:** Corporate-owned, supervised iPhone and iPad devices supplied through Apple Business Manager and assigned to one user  
**Target platform:** Microsoft Intune, Microsoft Entra ID, Apple Business Manager and Microsoft Defender for Endpoint

## 1. Target design

The recommended production design is:

- Apple Automated Device Enrolment (ADE) with supervision and locked enrolment.
- One default ADE enrolment policy for standard, single-user devices.
- User affinity and **Setup Assistant with modern authentication**.
- Just-in-time (JIT) Microsoft Entra registration through the Microsoft Enterprise SSO extension.
- Microsoft Authenticator as the iOS broker and SSO extension provider.
- Company Portal installed as a required, device-licensed Apps and Books application, but not used as the mandatory post-enrolment registration step.
- Device-licensed Apps and Books deployment so that a personal Apple Account is not required.
- Settings Catalog configuration profiles, with Apple Declarative Device Management (DDM) used for software-update enforcement.
- Intune compliance feeding Microsoft Entra Conditional Access.
- Intune app protection policies for supported Microsoft 365 applications.
- Microsoft Defender for Endpoint deployed in a later enforcement phase, after zero-touch onboarding has been proven in the pilot.

This plan assumes the devices are individually assigned. Shared iPad, kiosk, frontline shared-device mode and userless devices require separate enrolment policies and are outside this design.

## 2. Fact-check corrections

The following corrections supersede earlier recommendations.

| Status | Earlier position | Corrected position | Operational effect |
|---|---|---|---|
| **Correction** | “Microsoft E5” was treated as sufficient confirmation of the required licences. | Confirm the exact SKU. Microsoft 365 E5 includes Intune Plan 1, Microsoft Entra ID Plan 2 and Defender for Endpoint Plan 2. Office 365 E5 does not include Intune. In the EEA, Microsoft 365 E5 may also be sold without Teams, requiring a separate Teams entitlement. | Verify the service plans assigned to every user before piloting. If Teams is not licensed, use Outlook, OneDrive, Edge or another supported Microsoft work app as the first JIT app. |
| **Correction** | DDM passcode was described as the definitive ADE passcode configuration. | Microsoft recommends `Declarative Device Management > Passcode`, and Apple supports declarative passcode configuration with ADE. However, Microsoft's Settings Catalog documentation also states that non-User-Enrolment iOS devices continue to use the standard MDM protocol for general settings. For this ADE build, use the documented `Security > Passcode` Settings Catalog payload unless the DDM passcode category is validated on the tenant's ADE pilot devices. | DDM remains the definitive choice for managed software updates. Passcode enforcement must be tested separately and must not be assumed to use DDM on ADE merely because the category is visible. |
| **Correction** | Compliance included a separate “Require encryption” setting. | The iOS/iPadOS compliance settings do not expose a separate encryption requirement. Apple data protection is enabled when a device passcode is set. | Enforce the passcode through configuration and compliance; do not search for or document a non-existent iOS encryption compliance switch. |
| **Correction** | Conditional Access MFA was framed primarily around the `Register or join devices` user action. | For Intune enrolment, create a Conditional Access policy targeting the **Microsoft Intune Enrollment** cloud application. Keep the older tenant-wide “Require multifactor authentication to register or join devices” switch off when Conditional Access provides the control. Use the `Register or join devices` user action only if there is a deliberate tenant-wide device-registration requirement beyond Intune enrolment. | Avoid duplicate or poorly scoped MFA controls and test Setup Assistant authentication with the exact policy set. |
| **Correction** | The Conditional Access design did not explicitly address the approved-client-app retirement. | Do not create new policies that depend on **Require approved client app**. Microsoft stopped enforcing that grant control after 30 June 2026. Use **Require app protection policy** for supported mobile applications. | Review and replace any inherited approved-client-app policies before production. |
| **Correction** | App protection and compliant-device grants were presented as one broad policy. | Use separate Conditional Access policies: one requiring a compliant iOS/iPadOS device for Microsoft 365, and another requiring app protection for mobile apps and desktop clients. Browser behaviour must be tested separately because Safari does not carry an Intune app protection policy. | Prevent unsupported apps or browsers from being blocked accidentally by an app-protection grant they cannot satisfy. |
| **Correction** | Defender risk was suitable for immediate compliance enforcement. | Defender zero-touch onboarding should be deployed and monitored before its risk signal is made mandatory. Microsoft's Defender deployment article still lists Company Portal installation, sign-in and completed enrolment as prerequisites, while the newer ADE JIT flow removes Company Portal as the registration requirement. | Validate Defender onboarding on JIT-only devices. Do not make Defender risk a production compliance dependency until reporting is consistent. |
| **Correction** | Defender privacy wording implied that malicious-domain information is always collected. | Microsoft states that malicious domain and IP information is collected only when the Defender privacy setting is disabled. Required device, tenant, account and service telemetry is still collected. | Set and document the privacy configuration deliberately and include it in the employee privacy notice. |
| **Correction** | “Microsoft 365” was used as the current mobile application name. | The current application name is **Microsoft 365 Copilot**. | Use the current application name in Apps and Books, Intune assignments and user instructions. |
| **Correction** | Creating a static enrolment-time group was sufficient. | The static group must also have the **Intune Provisioning Client** service principal as an owner, and the administrator must be able to see the group through the appropriate Intune scope groups. | Complete these ownership and RBAC requirements before attaching the group to the ADE enrolment policy. |

Sources: [Microsoft enterprise plan comparison](https://www.microsoft.com/content/dam/microsoft/final/en-us/microsoft-product-and-services/microsoft-365/Modern-Work-Plan-Comparison-Enterprise.pdf), [Intune licensing](https://learn.microsoft.com/en-us/intune/fundamentals/licensing), [Settings Catalog](https://learn.microsoft.com/en-us/intune/device-configuration/settings-catalog/), [Apple declarative passcode configuration](https://support.apple.com/en-ie/guide/deployment/depf72b010a8/web), [iOS compliance settings](https://learn.microsoft.com/en-us/intune/device-security/compliance/ref-ios-ipados-settings), [approved-client-app retirement](https://learn.microsoft.com/en-us/entra/identity/conditional-access/migrate-approved-client-app), [Defender for iOS deployment](https://learn.microsoft.com/en-us/defender-endpoint/ios-install), [Defender iOS privacy](https://learn.microsoft.com/en-us/defender-endpoint/ios-privacy), [enrolment-time grouping](https://learn.microsoft.com/en-us/intune/device-enrollment/setup-time-grouping), [Microsoft 365 Copilot application rename](https://support.microsoft.com/en-us/microsoft-365-copilot/the-microsoft-365-app-transition-to-the-microsoft-365-copilot-app).

## 3. Decisions required before configuration

### 3.1 Confirm the licence bundle

Confirm that each user is assigned Microsoft 365 E5 with these service plans enabled:

- Microsoft Intune Plan 1.
- Microsoft Entra ID Plan 2.
- Microsoft Defender for Endpoint Plan 2, if Defender is included in the rollout.
- Exchange Online and the required Microsoft 365 applications.
- Microsoft Teams or Teams Enterprise, if Teams is to be used.

Do not rely on the display name “E5”. Verify the underlying service plans in the Microsoft 365 admin centre or through licence reporting.

### 3.2 Choose the Apple Account posture

The recommended corporate-only posture is:

- Do not require a personal Apple Account.
- Hide Apple Account, restore and device-to-device migration in Setup Assistant.
- Use device-licensed Apps and Books applications.
- Block account modification after enrolment.
- Keep supervised Activation Lock disabled unless there is a documented theft-deterrence requirement.
- Store business files in Microsoft 365 rather than relying on local or personal iCloud backup.

If personal use is permitted, document the following before changing the baseline:

- Whether users can add personal Apple Accounts and install personal applications.
- Whether iCloud Backup, iCloud Drive, iMessage and FaceTime are permitted.
- What happens to personal data when the organisation wipes or recovers the device.
- How Activation Lock is controlled and how its bypass code is recovered before a wipe.

### 3.3 Define supported hardware and operating-system policy

Intune's July 2026 documentation supports iOS/iPadOS 17 and later and requires iOS/iPadOS 17 or later for current app protection and app configuration. This is a service floor, not a recommended production target.

The production standard should be:

- Hardware capable of running a currently supported Apple production release.
- Current major iOS/iPadOS or the immediately previous major release.
- Current security update within the organisation's update deadline.
- No maximum OS version in compliance unless an emergency compatibility block is required.

Do not depend on Intune platform enrolment restrictions to enforce a minimum OS for ADE. Microsoft documents that the minimum/maximum version range in platform restrictions is not applicable to Apple ADE in the normal way and can affect Entra registration rather than providing a clean pre-enrolment block. Use DDM updates and compliance instead.

Sources: [Intune supported operating systems](https://learn.microsoft.com/en-us/intune/fundamentals/ref-supported-platforms), [Apple update management](https://support.apple.com/guide/deployment/install-and-enforce-software-updates-depd30715cbb/web), [Intune platform restrictions](https://learn.microsoft.com/en-us/intune/device-enrollment/create-platform-restrictions).

## 4. Tenant and administrative foundation

### 4.1 Intune and Entra administration

1. Confirm that the MDM authority is Microsoft Intune.
2. Enable unlicensed administrator access if appropriate for the tenant and permitted by policy; this does not replace user or feature licensing.
3. Use Microsoft Entra Privileged Identity Management for Intune Administrator, Conditional Access Administrator and related roles.
4. Maintain two cloud-only emergency access accounts excluded from normal Conditional Access policies and monitored for any use.
5. Use built-in Intune roles or custom least-privilege roles for daily work:
   - Policy and Profile Manager.
   - Application Manager.
   - Endpoint Security Manager.
   - Help Desk Operator.
6. Use scope tags only where administrative separation is genuinely required. Avoid unnecessary complexity in a new tenant.
7. Enable Intune audit-log monitoring and retain configuration exports or change records.

### 4.2 Apple connector ownership

Maintain a connector register containing:

| Dependency | Renewal | Critical requirement |
|---|---:|---|
| Apple MDM Push certificate | Every 365 days | Renew the existing certificate with the same Apple account. Do not replace it. |
| ADE server token | Annually | Download and upload the renewed token as one controlled change. Downloading a new server token invalidates the token currently in use until renewal is completed. |
| Apps and Books location token | Every 365 days | Renew the token for the same Apple Business Manager location and monitor licence availability. |
| Apple Business Manager terms | When Apple changes them | Unaccepted terms can suspend synchronisation. Review ABM operationally, not only at annual renewal. |

Use organisation-controlled accounts with at least two authorised administrators. Do not use a departing employee's personal Apple account as the only renewal identity.

Create renewal alerts at 60, 30, 14 and 7 days. Test the documented renewal process before the first production expiry window.

Sources: [Apple MDM Push certificate](https://learn.microsoft.com/en-us/intune/device-enrollment/apple/create-mdm-push-certificate), [ADE token setup and renewal](https://learn.microsoft.com/en-us/intune/device-enrollment/apple/setup-automated-ios), [Apps and Books token management](https://learn.microsoft.com/en-us/intune/app-management/deployment/manage-vpp-apple).

### 4.3 Network readiness

Provide one of the following during Setup Assistant:

- Cellular connectivity; or
- A restricted enrolment Wi-Fi network that does not require a device certificate; or
- A simple pre-shared-key network intended only for provisioning.

The enrolment network must permit Apple activation, APNs, Apple content delivery, Intune, Microsoft Entra authentication and the required Microsoft 365 endpoints. Do not expect an EAP-TLS corporate Wi-Fi profile to exist before MDM enrolment has started.

Deploy the production network in this order:

1. Trusted root certificate.
2. SCEP or PKCS certificate profile.
3. EAP-TLS Wi-Fi profile.
4. VPN or per-app VPN, if required.

### 4.4 Enrolment restrictions

If this tenant is intended to manage only corporate iOS/iPadOS devices:

- Edit the default iOS/iPadOS platform restriction to allow the platform but block personally owned enrolment.
- Do not create Apple User Enrolment, web-based device enrolment or Company Portal device-enrolment profiles for the production user population.
- Set a practical user device limit, normally two or three rather than one, so that a replacement device can be enrolled before the old record is removed.
- Maintain a separate, higher-priority exception only if a later BYOD requirement is formally approved.
- Use app protection without enrolment for any approved personal-device access instead of allowing personal devices into the corporate ADE management design.

Enrollment restrictions are a best-effort barrier and are not a security boundary. Microsoft also documents that iOS minimum and maximum version ranges in platform restrictions do not operate as a normal ADE pre-enrolment gate. Enforce OS state after enrolment through configuration, compliance and DDM updates.

Sources: [enrolment restrictions overview](https://learn.microsoft.com/en-us/intune/device-enrollment/restrictions), [create platform restrictions](https://learn.microsoft.com/en-us/intune/device-enrollment/create-platform-restrictions), [device limit restrictions](https://learn.microsoft.com/en-us/intune/device-enrollment/create-device-limit-restrictions).

## 5. Groups, assignments and naming

Create the following groups:

| Group | Type | Purpose |
|---|---|---|
| `SG-Intune-iOS-ADE-1to1` | Static device security group | Enrolment-time grouping and core ADE device assignments. |
| `SG-Intune-iOS-Users-Pilot` | User security group | Pilot app protection, compliance and Conditional Access. |
| `SG-Intune-iOS-Users-Production` | User security group | Production user-scoped policies. |
| `SG-Intune-iOS-Update-Canary` | Static device group | First software-update ring. |
| `SG-Intune-iOS-Update-Pilot` | Static device group | Wider update validation. |
| `SG-Intune-iOS-Update-Production` | Static device group | Broad software-update deployment. |
| `SG-CA-Emergency-Exclusions` | User security group | Controlled Conditional Access exclusions. |

For `SG-Intune-iOS-ADE-1to1`:

1. Set membership type to **Assigned**.
2. Add the **Intune Provisioning Client** service principal as an owner. Its documented application ID is `f1346770-5b25-470b-88bd-d5744ab7952c`.
3. Ensure the group is visible to the administrator through the required scope group and scope tag design.
4. Attach this group to the ADE enrolment policy as the enrolment-time group.

Enrolment-time grouping applies only to new enrolments. It does not add already-enrolled devices retrospectively. Without enrolment-time grouping, Microsoft states that application and policy delivery based on post-enrolment inventory grouping can take up to eight hours.

Use a device name template such as:

```text
{{DEVICETYPE}}-{{SERIAL}}
```

Use assignment filters only as an additional safeguard. Do not use a dynamic device group as the dependency for critical enrolment-time configuration.

## 6. Apple ADE enrolment policy

Create the policy under:

```text
Devices > Device onboarding > Enrollment > Apple > Enrollment program tokens > [token] > Enrollment policies
```

Do not build new policies under the older **Profiles** experience; Microsoft states that the older experience will be retired and does not receive new features.

Configure one default 1:1 policy:

| Setting | Recommended value | Reason |
|---|---|---|
| User affinity | Enrol with user affinity | Each device belongs to one licensed user. |
| Authentication method | Setup Assistant with modern authentication | Microsoft's recommended ADE authentication method for user-affinity devices. |
| Supervised | Yes | Enables the required corporate management controls. |
| Locked enrolment | Yes | Prevents the user removing the MDM management profile. |
| Install Company Portal | Yes | Provides support, sync, compliance and application-catalogue functions. |
| Company Portal source | Apps and Books token | Avoids a personal Apple Account. |
| Company Portal licence type | Device | Supports silent installation without an Apple Account. |
| Run Company Portal in Single App Mode | No | JIT registration is completed in the first work app; forcing Company Portal defeats that flow. |
| Await final configuration | Yes | Holds the device until critical device configuration policies have begun installing. |
| Apply device name template | Yes | Produces predictable inventory names. |
| Set as default policy | Yes | Prevents newly synchronised devices activating without an assigned ADE policy. |

Important behaviour:

- `Await final configuration` installs device configuration policies, not applications.
- The wait has no Microsoft-enforced minimum or maximum duration.
- Microsoft reports that most validation devices were released within 15 minutes, but this is not a service-level guarantee.
- Keep policies assigned to the enrolment-time group small, conflict-free and essential.
- Except for the device-name template, changes to an ADE enrolment policy normally require factory reset and reactivation before they affect an already-enrolled device.
- ADE devices need sufficient Company Portal Apps and Books licences. An expired Apps and Books token or insufficient Company Portal licences can block enrolment.

Source: [Set up ADE for iOS/iPadOS](https://learn.microsoft.com/en-us/intune/device-enrollment/apple/setup-automated-ios).

### 6.1 Setup Assistant panes

For the corporate-only baseline:

| Pane | Action |
|---|---|
| Language, region and keyboard | Show as required by the deployment region. |
| Passcode | Show. Require the user to create the device passcode during setup. |
| Location Services | Show. Explain the business use and privacy position. |
| Apple Account | Hide. |
| Restore | Hide. |
| Device-to-device migration | Hide. |
| Move from Android | Hide. |
| Apple Pay | Hide. |
| Screen Time | Hide. |
| Siri | Hide unless there is a business requirement. |
| Analytics and diagnostics | Hide. |
| Other consumer onboarding panes | Hide unless required. |

Hiding a pane does not necessarily prevent the user configuring the feature later. Enforce the final corporate-only posture with a separate device-restrictions profile.

Add the support department and telephone number shown through **About Configuration** and **Need Help**.

## 7. JIT registration and Microsoft Enterprise SSO

Create an iOS/iPadOS **Device features > Single sign-on app extension** profile.

Configure:

| Setting | Value |
|---|---|
| SSO app extension type | Microsoft Entra ID |
| Key | `device_registration` |
| Type | String |
| Value | `{{DEVICEREGISTRATION}}` |
| Key | `browser_sso_interaction_enabled` |
| Type | Integer |
| Value | `1` |

Do not add Microsoft application bundle identifiers, including Microsoft Authenticator. Microsoft states that the extension applies automatically to Microsoft applications. Add only approved non-Microsoft applications that support the extension.

Deploy Microsoft Authenticator as a required, device-licensed application to the ADE enrolment-time group.

Source: [Set up JIT registration](https://learn.microsoft.com/en-us/intune/device-enrollment/apple/setup-just-in-time-registration).

### 7.1 User authentication sequence

The expected sequence is:

1. The user starts the device and connects it to the Internet.
2. Setup Assistant retrieves the Remote Management configuration.
3. The user signs in with the Microsoft Entra account.
4. The user completes MFA if required by Conditional Access.
5. Intune establishes user affinity and MDM enrolment.
6. The device waits for final configuration and reaches the Home Screen.
7. The user opens the designated first work app and signs in.
8. JIT completes Microsoft Entra registration and compliance evaluation.
9. The SSO extension provides sign-in reuse to the other supported Microsoft applications.

JIT relocates the second sign-in; it does not remove it.

Microsoft recommends Teams as the first application, but Teams is not mandatory. If Teams is not licensed, use Outlook, OneDrive, Edge signed into its work profile, or another supported Microsoft app. Microsoft Defender must not be the first app opened because Microsoft documents that Defender-first registration can interfere with JIT compliance remediation.

Setup Assistant does not support phishing-resistant MFA. Each user must have a tested alternative method available during enrolment. Do not rely solely on Microsoft Authenticator running on the new device. Temporary Access Pass can be considered for controlled onboarding, but it must be designed and tested with the organisation's authentication-strength policies before adoption.

Source: [ADE authentication methods](https://learn.microsoft.com/en-us/intune/device-enrollment/apple/ref-automated-authentication-methods).

## 8. Device configuration baseline

Create separate profiles by function. This isolates failures and makes policy conflicts easier to diagnose.

### 8.1 Passcode profile

For the initial ADE baseline, use:

```text
Settings Catalog > Security > Passcode
```

Recommended settings:

- Require a passcode.
- Minimum passcode length: 6.
- Block simple passcodes.
- Required type: Numeric. Apple also permits stronger alphabetic or alphanumeric values when Numeric is the minimum.
- Maximum inactivity until screen lock: 5 minutes.
- Maximum time after screen lock before passcode is required: Immediately.
- No routine passcode expiry.
- No passcode-history requirement unless regulation or policy requires it.
- Allow Face ID and Touch ID backed by the device passcode.

Do not block passcode modification. Apple and Microsoft document that blocking passcode modification can also prevent later passcode-policy changes from applying correctly.

The compliance policy should verify the passcode state, but the configuration profile should enforce it. When a passcode is set, iOS/iPadOS automatically enables data protection and the device remains encrypted while the passcode exists.

### 8.2 Corporate-only restrictions

Start with these controls and validate each one against business workflows:

- Block removal of the management profile through locked ADE enrolment.
- Block account modification if personal Apple Accounts are prohibited.
- Block iCloud Backup if all device backup to personal iCloud is prohibited.
- Block managed documents from opening in unmanaged destinations.
- Decide whether unmanaged documents may open in managed applications. Blocking both directions can prevent legitimate attachment and document workflows.
- Block unmanaged paste into managed destinations only if required by the data-handling policy.
- Configure managed pasteboard behaviour consistently with the app protection policy.
- Block iCloud Drive and personal cloud document synchronisation when required.
- Block AirDrop only if the organisation accepts the resulting productivity impact.
- Leave screenshots allowed unless the organisation has a specific high-security requirement. Screenshot blocking affects support and collaboration workflows.
- Block user erasure only if the support and recovery process requires IT-controlled wipes. This setting can increase helpdesk dependency.
- Do not enable Activation Lock while supervised unless the organisation has approved the lifecycle process and bypass-code handling.

Device restrictions and app protection overlap but are not interchangeable. Device restrictions control iOS data flows and device features; app protection controls corporate data inside SDK-enabled applications.

### 8.3 Certificates, Wi-Fi and VPN

Create separate profiles for:

- Trusted root certificates.
- SCEP or PKCS device certificate.
- SCEP or PKCS user certificate, if required.
- Production EAP-TLS Wi-Fi.
- Per-app VPN or full-device VPN.

Prefer per-app VPN when only defined corporate applications require the private network. Do not deploy Always-On VPN without testing it against Defender's supervised Control Filter, because Microsoft documents that the Defender Control Filter does not work with Always-On VPN.

### 8.4 Home Screen and support configuration

After the functional pilot:

- Apply a simple Home Screen layout only where consistency is required.
- Place the first JIT app, Company Portal and support application on the first page.
- Configure a lock-screen message or asset reference if appropriate.
- Configure Company Portal branding, privacy text and helpdesk contact details.

Avoid an over-controlled layout that prevents users organising permitted applications.

## 9. Application deployment

### 9.1 Apps and Books operation

Acquire applications through the correct Apple Business Manager location and synchronise the location token to Intune.

For free applications, still acquire enough Apps and Books licences for the expected estate plus a reasonable growth buffer. Enable automatic application updates at token level, then use per-application update prevention only for applications with a tested compatibility requirement.

### 9.2 Required applications

Deploy these as device-licensed required applications where supported:

- Microsoft Authenticator.
- Intune Company Portal.
- The designated first JIT application: Teams if licensed, otherwise Outlook, OneDrive or Edge.
- Microsoft Outlook.
- Microsoft Edge.
- Microsoft OneDrive.
- Microsoft 365 Copilot, if required.
- Microsoft Defender, initially to the Defender pilot.
- Approved VPN, support and line-of-business applications.

Make non-essential applications available through Company Portal rather than making every application required.

### 9.3 Company Portal rules

- Deploy Company Portal through Intune as an Apps and Books application.
- Use device licensing.
- Make it required.
- Enable automatic updates.
- Do not instruct users to install the public App Store version themselves.
- Do not create a separate managed-device application configuration containing the ADE Company Portal payload for devices enrolling with Setup Assistant modern authentication. Intune sends the required configuration during enrolment, and a duplicate configuration can cause an incorrect prompt to download another management profile.

Source: [Company Portal with ADE](https://learn.microsoft.com/en-us/intune/device-enrollment/apple/setup-automated-ios).

## 10. App protection policy

Create an iOS/iPadOS app protection policy targeted to the Microsoft **Core Microsoft Apps** group and the licensed iOS user group.

Recommended Level 2 starting position:

### Data protection

- Block backup of organisation data to iTunes and iCloud.
- Send organisation data only to policy-managed applications, subject to documented business exceptions.
- Receive data from all applications initially, or restrict it after testing inbound document workflows.
- Block saving copies of organisation data except to OneDrive for Business and SharePoint.
- Restrict cut, copy and paste to policy-managed applications, with a small character allowance only if required.
- Open web links from managed applications in Microsoft Edge.
- Require encryption of organisation data in supported applications.
- Disable printing unless required.

### Access requirements

- Require an app PIN.
- Allow Face ID or Touch ID instead of the app PIN after initial authentication.
- Configure a reasonable inactivity timeout.
- Require work-account credentials after the selected recheck interval.

### Conditional launch

- Block jailbroken devices.
- Block unsupported or obsolete OS versions.
- Block applications below the defined minimum application version where a critical defect exists.
- Add Defender threat-level enforcement only after Defender reporting is stable.
- Use selective wipe for long-offline or disabled accounts only after the support and leaver processes are defined.

Microsoft automatically sends the Intune MAM identity values to an expanding list of enrolled Microsoft applications, including Excel, Outlook, PowerPoint, Teams and Word. Third-party and line-of-business applications can still require explicit `IntuneMAMDeviceID` and related application configuration. Validate each non-Microsoft managed application independently.

Sources: [app protection framework](https://learn.microsoft.com/en-us/intune/app-management/protection/data-protection-framework), [create an app protection policy](https://learn.microsoft.com/en-us/intune/app-management/protection/create-policy), [iOS app protection settings](https://learn.microsoft.com/en-us/intune/app-management/protection/ref-settings-ios).

## 11. Compliance policy

Set the tenant-wide option **Mark devices with no compliance policy assigned as noncompliant** only after every Intune-managed platform in the tenant has an assigned compliance policy. The option is tenant-wide; enabling it for an iOS project can make unrelated managed platforms noncompliant if they have no policy.

Create two policies so that critical and remediable failures can use different timelines.

### 11.1 Critical compliance

Recommended settings:

- Jailbroken devices: Block.
- Defender machine risk: Not configured during the initial rollout.
- Restricted applications: configure only where there is a maintained prohibited-application list and an exception process.

Actions:

- Mark noncompliant immediately.
- Notify the user immediately.
- Escalate through the security process where appropriate.

After Defender has achieved the pilot exit criteria, add a maximum Defender machine risk of **Low** or the organisation's approved threshold. Do not choose **Clear** without understanding that any non-zero machine risk can block the device.

### 11.2 Standard compliance

Recommended settings:

- Require a password to unlock the device.
- Block simple passwords.
- Minimum password length: 6.
- Required password type: Numeric.
- Maximum inactivity until screen lock: 5 minutes.
- Maximum time after screen lock before the password is required: Immediately or the organisation's approved maximum.
- Minimum OS version: maintain a reviewed value aligned to the current Microsoft application support position.

Do not configure a maximum OS version as routine policy. Do not configure the managed-email-account compliance requirement when Outlook is used; that setting expects a managed native mail profile and can make otherwise healthy Outlook devices noncompliant.

Actions:

- Mark noncompliant after a short remediation interval, normally 24 hours.
- Notify the user immediately.
- Send a further reminder before the deadline.
- Add helpdesk or security escalation if the device remains noncompliant.

Source: [iOS/iPadOS compliance settings](https://learn.microsoft.com/en-us/intune/device-security/compliance/ref-ios-ipados-settings) and [Microsoft's iOS compliance examples](https://learn.microsoft.com/en-us/intune/device-security/security-configurations/ios-ipados-compliance).

## 12. Conditional Access

Create policies in report-only mode, review sign-in logs and use the Conditional Access What If tool before enabling them.

Exclude only:

- Emergency access accounts.
- Genuine non-interactive identities that cannot be replaced with workload identities or managed identities.
- Time-limited pilot exclusions with an owner and expiry date.

Do not exclude the entire mobility team or helpdesk permanently.

### 12.1 Enrolment MFA

Create `CA-Intune-Enrollment-Require-MFA`:

- Users: pilot, then all enrolment-eligible users.
- Target resource: **Microsoft Intune Enrollment**.
- Grant: Require multifactor authentication.
- State: Report-only, then On after pilot validation.

Leave the older Entra device-setting toggle for MFA registration set to **No** when Conditional Access supplies the enrolment control.

Because Setup Assistant does not support phishing-resistant MFA, test every permitted onboarding method. A policy requiring a phishing-resistant authentication strength at enrolment will block this ADE flow.

### 12.2 Require a compliant device

Create `CA-iOS-M365-Require-Compliant`:

- Users: pilot, then production iOS users.
- Target resource: Office 365 initially.
- Platform: iOS.
- Client apps: all supported client-app types.
- Grant: Require device to be marked as compliant.

Start with Office 365 rather than every resource. Expand only after the organisation has mapped SaaS dependencies and confirmed that the Intune registration and remediation paths are not caught in a circular dependency.

### 12.3 Require app protection

Create `CA-iOS-MobileApps-Require-APP`:

- Users: pilot, then production mobile users.
- Target resources: approved Microsoft 365 resources or all resources after application compatibility review.
- Platform: iOS.
- Client apps: Mobile apps and desktop clients.
- Grant: Require app protection policy.

Do not add **Require approved client app**. It ceased enforcement after 30 June 2026.

This policy intentionally blocks unsupported mobile applications that cannot receive an app protection policy. Maintain an exception list only where the application, data owner and compensating controls are documented.

### 12.4 Browser access

Safari cannot satisfy an Intune app protection policy. Browser access should therefore be controlled by the compliant-device policy, authentication controls and any application-enforced restrictions for Exchange, SharePoint and OneDrive.

If all managed web traffic must use Edge, configure managed links to open in Edge and test business URLs, universal links and third-party authentication redirects before blocking Safari.

Sources: [Conditional Access with Intune](https://learn.microsoft.com/en-us/intune/device-security/conditional-access-integration/overview), [require app protection](https://learn.microsoft.com/en-us/entra/identity/conditional-access/policy-all-users-approved-app-or-app-protection), [approved-client-app retirement](https://learn.microsoft.com/en-us/entra/identity/conditional-access/migrate-approved-client-app), [Conditional Access grant controls](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-conditional-access-grant).

## 13. Microsoft Defender for Endpoint

### 13.1 Deployment sequence

1. Connect Microsoft Defender for Endpoint and Intune.
2. Acquire and deploy Microsoft Defender to the Defender pilot group.
3. Create the managed-device Defender app configuration with:

   ```text
   issupervised = {{issupervised}}
   ```

4. Download the current Microsoft-provided **Zero-touch (Silent) Control Filter** profile.
5. Deploy that profile as a custom iOS/iPadOS configuration to supervised pilot devices.
6. Allow users to complete JIT in Teams, Outlook, OneDrive or Edge before opening Defender.
7. Confirm that devices appear in Microsoft Defender inventory and that web protection operates.
8. Monitor onboarding consistency before making Defender risk part of compliance.

The supervised Control Filter provides web protection without the visible local loopback VPN. It does not work with Always-On VPN because of Apple platform restrictions.

### 13.2 Defender caveats

- Microsoft Defender must not be the first work application opened for JIT.
- The Defender deployment documentation still lists Company Portal installation, sign-in and completed enrolment as prerequisites. Validate whether the current JIT flow in the tenant completes zero-touch onboarding without a Company Portal sign-in.
- Zero-touch configuration can still require user sign-in following password changes, MFA changes or similar security events.
- Newly onboarded devices can take several minutes to produce a usable compliance risk signal.
- Do not enable risk-based Conditional Access until these transitions have been tested.
- The Control Filter is delivered as a Microsoft-provided custom profile. Replace it only through a documented Microsoft update, not by manually editing the mobileconfig.

### 13.3 Privacy

Document that Defender collects required device, tenant, user and product-usage data. Microsoft states that domain and IP information for malicious detections is collected only when the Defender privacy setting is disabled. The employee notice must reflect the actual configured privacy value.

Sources: [deploy Defender on iOS](https://learn.microsoft.com/en-us/defender-endpoint/ios-install), [configure Defender iOS features](https://learn.microsoft.com/en-us/defender-endpoint/ios-configure-features), [Defender iOS privacy](https://learn.microsoft.com/en-us/defender-endpoint/ios-privacy).

## 14. Software-update strategy

Use Apple DDM update policies for iOS/iPadOS 17 and later. Microsoft describes the traditional MDM-based update policies as deprecated.

Create mutually exclusive device rings:

| Ring | Suggested population | Suggested latest-version enforcement delay | Purpose |
|---|---:|---:|---|
| Canary | Approximately 5%, including mobility IT | 1 day | Detect enrolment, identity, VPN and critical application failures. |
| Pilot | Approximately 15%, including business champions | 3 days | Validate representative workflows. |
| Production | Remaining devices | 7 days | Broad enforcement after validation. |

The percentages and delays are organisational recommendations, not Microsoft or Apple requirements. Change them to match the organisation's patching standard and risk tolerance.

Use a **latest-version** policy for routine patching:

- `Declarative Device Management > Software Update > Enforce Latest Delay in Days`.
- `Declarative Device Management > Software Update > Enforce Latest Install Time`.

Use a **targeted-version** policy only when:

- A major version needs a controlled rollout.
- A critical line-of-business application is incompatible with a newer release.
- A security incident requires enforcement of a defined build.

Important behaviour:

- A targeted policy can force installation and restart at the deadline.
- An update may install before the deadline when the device is idle.
- A configuration profile reporting success proves only that the policy reached the device; monitor the actual OS version separately.
- Remove an obsolete targeted-version policy after devices exceed the target, because devices can report an error when the declaration appears to request a downgrade.
- Maintain a support page URL in targeted update policies.

Source: [Configure Apple update policies](https://learn.microsoft.com/en-us/intune/device-updates/apple/) and [Apple update enforcement](https://support.apple.com/guide/deployment/install-and-enforce-software-updates-depd30715cbb/web).

## 15. Pilot plan

### Stage 1: Engineering validation

Use two to five IT-controlled devices representing supported iPhone and iPad models.

Test:

- Fresh supplier-assigned ABM device.
- Device already activated and then factory reset.
- Wi-Fi-only and cellular enrolment.
- All allowed MFA methods.
- A user whose password must be changed.
- JIT with the designated first application.
- Entra registration, Intune registration and compliance as three separate states.
- Required and available application delivery.
- Certificate-based Wi-Fi and VPN.
- App protection data-transfer paths.
- Conditional Access in native apps and browsers.
- Defender zero-touch onboarding.
- DDM software update enforcement.
- Lost Mode, remote lock, wipe and Activation Lock handling.
- Reassignment to a new user.

### Stage 2: Business pilot

Use ten to twenty users representing:

- Different offices and networks.
- Travelling and occasionally offline users.
- Executive or high-risk users.
- Users of every critical line-of-business application.
- Accessibility requirements.

### Stage 3: Controlled production

Deploy to approximately ten per cent of production users before broad rollout.

### Exit criteria

- All pilot devices complete ADE without manual MDM-profile installation.
- JIT creates the Microsoft Entra device record and compliance state reliably.
- No unresolved Conditional Access circular dependency.
- Required applications install without a personal Apple Account.
- Corporate Wi-Fi and VPN operate after enrolment.
- App protection permits documented workflows and blocks prohibited transfers.
- Defender devices consistently appear in Defender inventory before risk enforcement.
- Wipe and reassignment have been completed successfully on at least one device.
- Helpdesk staff can distinguish MDM enrolment, Entra registration, compliance and SSO state.

## 16. User experience

The user quick-start guide must state:

1. Connect the device to the Internet.
2. Continue until the **Remote Management** screen appears.
3. Sign in with the work account.
4. Complete the approved MFA method.
5. Create the device passcode.
6. Wait on **Awaiting final configuration**; do not restart the device unless support instructs it.
7. At the Home Screen, wait for the designated work application and Authenticator to install.
8. Open the designated work app and sign in again.
9. Wait while registration and compliance complete.
10. Open Company Portal for additional applications, device sync or support logs.

The guide must explicitly say that two work-account authentications are expected.

Users must also be told:

- The device is supervised and managed by the organisation.
- The organisation can factory-reset the device.
- What device and application information the organisation can see.
- Whether personal use and personal Apple Accounts are permitted.
- That local or personal data can be lost during a corporate wipe.

## 17. Operational lifecycle

### 17.1 New device

1. Supplier adds the serial number to Apple Business Manager.
2. ABM assigns the device to the Intune device-management service.
3. Intune synchronises the ADE device.
4. Operations confirms the default ADE policy is assigned.
5. The user receives the licence and production user-group membership before activation.
6. The device ships to the user.

Never allow a user to activate the device before it has an assigned enrolment policy. Microsoft documents that an ADE device without a policy can fail enrolment.

### 17.2 Lost or stolen device

1. Confirm the incident and device serial number.
2. Revoke the user's active sessions where appropriate.
3. Use supervised Lost Mode and locate if authorised by policy and law.
4. Disable the Entra device if access must stop immediately.
5. Wipe the device when recovery is no longer expected or the incident process requires it.
6. Retain the ABM record while the organisation owns the device.

### 17.3 Reassignment

1. Confirm whether supervised Activation Lock has been allowed.
2. If allowed, copy the Activation Lock bypass code or use the disable action before wiping. Microsoft warns that the code can be lost from Intune after reset.
3. Wipe the device.
4. Leave the device assigned to Intune in Apple Business Manager.
5. Confirm the default enrolment policy.
6. Re-enrol for the new user.

### 17.4 Retire, Delete and Wipe

- **Wipe** factory-resets a corporate iOS/iPadOS device and is the normal action for reassignment or disposal.
- **Retire** removes managed settings and corporate data but leaves personal data and is not a factory reset.
- **Delete** triggers Retire on iOS/iPadOS; it is not equivalent to Wipe.
- If a device is deleted from Intune but remains assigned to the ADE token in Apple Business Manager, it can reappear in Intune during a later full synchronisation.
- Removing the Intune record does not automatically remove the corresponding Microsoft Entra device record.

Sources: [Delete action](https://learn.microsoft.com/en-us/intune/device-management/actions/delete), [Retire action](https://learn.microsoft.com/en-us/intune/device-management/actions/retire), [manage ADE devices](https://learn.microsoft.com/en-us/intune/device-enrollment/apple/manage-devices-tokens-apple).

### 17.5 Disposal or sale

1. Recover or disable Activation Lock.
2. Wipe the device.
3. Remove obsolete Intune and Entra records.
4. Release the device from Apple Business Manager only when it is sold, permanently transferred, lost beyond recovery or otherwise no longer controlled by the organisation.

Do not release a device merely because it is being repaired or reassigned. Apple states that a released device can no longer be assigned normally to a device-management service and that Activation Lock can no longer be managed through ABM. Re-adding it requires Apple Configurator or action by the authorised reseller or carrier.

Source: [Release devices in Apple Business Manager](https://support.apple.com/guide/business/release-devices-axmec4d28461/web).

## 18. Monitoring and recurring operations

### Daily during rollout

- Failed and incomplete enrolments.
- Devices without a primary user.
- Devices that are MDM-enrolled but not Entra-registered.
- Noncompliant devices and remediation reasons.
- Required application installation failures.
- Defender onboarding status.
- Conditional Access failures for pilot users.

### Weekly

- Devices with stale check-in dates.
- OS version distribution by update ring.
- App protection status and selective-wipe events.
- Configuration-profile errors and conflicts.
- Devices in the wrong update ring or with overlapping update assignments.

### Monthly

- Connector and token expiry dates.
- Apps and Books licence capacity.
- Apple Business Manager synchronisation status and terms.
- Conditional Access exclusions.
- Intune administrator roles and PIM assignments.
- Unsupported OS and hardware population.
- Helpdesk trends and enrolment duration.

### Quarterly

- Complete a factory-reset and re-enrolment test.
- Complete a wipe and reassignment test.
- Review the Microsoft Intune What's New and Apple platform deployment changes.
- Review the iOS/iPadOS security configuration framework.
- Test the emergency access procedure.
- Review all permanent policy exceptions.

## 19. Troubleshooting states

Support must keep these states separate:

| State | Evidence | Meaning |
|---|---|---|
| ADE assignment | Device appears under the ADE token with the correct enrolment policy. | Apple can direct the device to Intune during activation. |
| MDM enrolled | Management profile is installed and the device checks in to Intune. | Intune can manage the device. |
| User affinity | Intune shows the expected primary user. | The device is associated with the licensed user. |
| Entra registered | Entra device record exists and Intune reports Entra registration. | Device identity can participate in device-based Conditional Access. |
| Compliant | Intune and Entra report the device compliant. | The device meets the assigned compliance policies. |
| SSO operating | Supported applications reuse the brokered account. | Authentication reuse works; this alone does not prove compliance. |

Known enrolment issues:

- If Setup Assistant reports `The SCEP server returned an invalid response`, Microsoft advises retrying management-profile download within 15 minutes; after that window, a factory reset can be required.
- Microsoft documents a possible one-time Entra registration failure for a new or existing tenant. A manual device sync can resolve the first failure and subsequent registrations. Test this in Stage 1 rather than discovering it in production.
- If the Home Screen is available but Conditional Access reports that the device is unmanaged, verify JIT completion, Entra registration and compliance before replacing the MDM profile.
- If Company Portal prompts the user to download a management profile that is already installed, check for a duplicate Company Portal ADE app-configuration policy.
- If required applications do not install, check Apps and Books token validity, licence capacity, device licensing, application assignment and Apple service availability.
- If Defender is installed but the device has no risk state, verify that JIT completed first, the supervised app configuration is applied and the Zero-touch Control Filter profile is installed.

## 20. Implementation order

1. Confirm Microsoft 365, Teams and Defender entitlements.
2. Approve the corporate-only or personal-use Apple Account posture.
3. Configure administrative roles, PIM and emergency accounts.
4. Document and alert on APNs, ADE and Apps and Books renewals.
5. Validate the enrolment network.
6. Block personally owned iOS/iPadOS enrolment and set the user device limit.
7. Create the static enrolment-time group and assign the Intune Provisioning Client owner.
8. Create pilot and update-ring groups.
9. Acquire Apps and Books applications and enable automatic updates.
10. Create the default ADE enrolment policy.
11. Create the SSO extension and JIT configuration.
12. Create the passcode and restrictions baseline.
13. Create certificates, Wi-Fi and VPN profiles.
14. Deploy Authenticator, Company Portal and the designated first JIT app.
15. Create app protection policies.
16. Create critical and standard compliance policies.
17. Create Conditional Access policies in report-only mode.
18. Complete the engineering pilot.
19. Deploy Defender zero-touch configuration to the Defender pilot.
20. Create DDM software-update rings.
21. Complete the business pilot and lifecycle tests.
22. Enable production Conditional Access in controlled stages.
23. Enable Defender risk compliance only after the Defender exit criteria are met.
24. Roll out to production waves.
25. Begin daily, weekly, monthly and quarterly operations.

## 21. Primary reference set

- [Set up automated device enrolment for iOS/iPadOS](https://learn.microsoft.com/en-us/intune/device-enrollment/apple/setup-automated-ios)
- [Authentication methods for Apple ADE](https://learn.microsoft.com/en-us/intune/device-enrollment/apple/ref-automated-authentication-methods)
- [Set up JIT registration](https://learn.microsoft.com/en-us/intune/device-enrollment/apple/setup-just-in-time-registration)
- [Enrolment-time grouping](https://learn.microsoft.com/en-us/intune/device-enrollment/setup-time-grouping)
- [Intune Settings Catalog](https://learn.microsoft.com/en-us/intune/device-configuration/settings-catalog/)
- [Apple device restrictions in Intune](https://learn.microsoft.com/en-us/intune/device-configuration/templates/ref-device-restrictions-apple)
- [iOS/iPadOS compliance settings](https://learn.microsoft.com/en-us/intune/device-security/compliance/ref-ios-ipados-settings)
- [iOS/iPadOS compliance security examples](https://learn.microsoft.com/en-us/intune/device-security/security-configurations/ios-ipados-compliance)
- [Intune app protection framework](https://learn.microsoft.com/en-us/intune/app-management/protection/data-protection-framework)
- [Conditional Access with Intune](https://learn.microsoft.com/en-us/intune/device-security/conditional-access-integration/overview)
- [Conditional Access app-protection control](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-conditional-access-grant)
- [Approved-client-app retirement](https://learn.microsoft.com/en-us/entra/identity/conditional-access/migrate-approved-client-app)
- [Apple DDM software updates in Intune](https://learn.microsoft.com/en-us/intune/device-updates/apple/)
- [Deploy Defender for Endpoint on iOS](https://learn.microsoft.com/en-us/defender-endpoint/ios-install)
- [Defender for Endpoint iOS privacy](https://learn.microsoft.com/en-us/defender-endpoint/ios-privacy)
- [Apple Platform Deployment: install and enforce updates](https://support.apple.com/guide/deployment/install-and-enforce-software-updates-depd30715cbb/web)
- [Apple Business Manager device release](https://support.apple.com/guide/business/release-devices-axmec4d28461/web)
- [Microsoft enterprise plan comparison](https://www.microsoft.com/content/dam/microsoft/final/en-us/microsoft-product-and-services/microsoft-365/Modern-Work-Plan-Comparison-Enterprise.pdf)
