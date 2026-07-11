# Intune implementation plan: fully managed iOS/iPadOS

## Scope and target state

This plan delivers corporate-owned, supervised iPhone and iPad devices through Apple Business Manager (ABM) and Microsoft Intune. The supplier adds devices to ABM, the ABM/Intune Automated Device Enrolment (ADE) connection is already active, and Apps and Books (VPP) and APNs are connected.

The intended end state is:

| Area | Target configuration |
|---|---|
| Enrolment | One new iOS/iPadOS ADE enrolment policy, set as the default policy for the ABM token |
| Ownership | Corporate-owned, supervised, and locked enrolment |
| User association | Enrol with User Affinity |
| Authentication | Setup Assistant with modern authentication |
| Registration and SSO | Just-in-time (JIT) registration through the Microsoft Entra SSO extension |
| Company Portal | Required, device-licensed VPP app; available as the self-service app catalogue |
| Core apps | Required VPP apps, targeted during enrolment |
| Optional apps | Available for enrolled devices in Company Portal, targeted to user groups |
| Security | Compliance policy, configuration baseline, app protection, and Conditional Access |
| Provisioning speed | Enrolment-time grouping for core device policies and required apps |
| Updates | Declarative Device Management (DDM) software update policies, piloted before broad enforcement |

## Intended end-user experience

1. The supplier assigns the device to the organisation’s Intune MDM server in ABM. Intune synchronises the serial number and applies the default ADE policy before the device is turned on.
2. The user turns on a new or wiped device, sees the organisation’s remote-management screen, and signs in with their work account during Apple Setup Assistant.
3. The user completes an approved MFA challenge and the device enrols in Intune with user affinity.
4. Intune holds the user briefly at the end of Setup Assistant while critical device configuration policies install. It then releases the device to the Home Screen.
5. Company Portal, Microsoft Authenticator, Teams, and the required business apps start installing without an Apple Account or App Store sign-in.
6. After Teams appears, the user opens it as their first work app. JIT registration completes Microsoft Entra registration and the compliance check, then provides SSO across Microsoft apps and configured third-party apps.
7. Company Portal remains on the device for optional apps, compliance status, sync, diagnostics, and support.

JIT registration is the preferred experience because standard modern-authentication ADE requires the user to sign in to Company Portal and select **Begin** after reaching the Home Screen before Entra registration, compliance evaluation, and Conditional Access access are complete. JIT still requires a second sign-in, but places it in the first work app rather than Company Portal.

## Implementation sequence

### 1. Confirm service decisions, ownership, and success measures

- Confirm the supported iOS/iPadOS version standard and procurement rule. Setup Assistant with modern authentication requires iOS/iPadOS 13 or later; current devices should meet the organisation’s current-supported-version standard.
- Decide whether personal Apple Accounts, iCloud services, App Store access, AirDrop, screenshots, backups, and device-to-device migration are allowed on corporate devices. The implementation does not require a personal Apple Account.
- Agree the initial required-app set and the optional app catalogue. Keep the required first-day app set small and essential.
- Confirm the app that users will open first after landing on the Home Screen. Use Teams where available; Microsoft recommends it for JIT registration.
- Define the enrolment MFA journey. Setup Assistant does not support phishing-resistant MFA, so every user needs an approved alternative method that can be completed during initial setup. Test password-change, expired-password, and MFA recovery journeys before production.
- Name accountable owners for Intune, Microsoft Entra/Conditional Access, ABM, Apps and Books/VPP purchasing, service desk, asset management, and security approval.
- Define rollout measures: successful enrolment rate, time to first productive use, compliance rate, required-app success rate, and support contacts per wave.

**Completion condition:** approved service design, named owners, a documented support route, and a pilot acceptance checklist.

### 2. Prepare licence capacity, supplier flow, targeting, and enrolment controls

- Confirm each intended user has the required Intune licence and the Conditional Access entitlement is available where Conditional Access will be used.
- Confirm the supplier’s ABM workflow assigns every new serial number to the organisation’s Intune MDM server, not merely to ABM.
- Verify that the active ADE token synchronises new devices into Intune and assign the new ADE policy before a device is activated. An ADE device without an assigned policy cannot enrol successfully.
- Obtain Apps and Books licences for Company Portal and every required or optional app, including free apps. Keep a capacity buffer and enable automatic VPP app updates.
- Create the following Microsoft Entra groups:

  | Group | Type | Purpose |
  |---|---|---|
  | **GRP-INTUNE-IOS-ADE-FOUNDATION** | Static assigned device security group | Enrolment-time grouping; targets core device configuration policies and required apps |
  | **GRP-INTUNE-IOS-PILOT-USERS** | Assigned user security group | Pilot users, user-targeted app protection, optional apps, and pilot Conditional Access |
  | **GRP-INTUNE-IOS-PRODUCTION-USERS** | Assigned user security group | Production users, user-targeted app protection, and optional apps |
  | **GRP-CA-EMERGENCY-EXCLUSIONS** | Assigned user security group | Emergency access accounts excluded from Conditional Access |

- Configure enrolment-time grouping by adding **Intune Provisioning Client** as an owner of **GRP-INTUNE-IOS-ADE-FOUNDATION**, then select that static group in the ADE policy’s **Device group** page. This speeds delivery of device-targeted policies and apps during enrolment.
- Configure an iOS/iPadOS enrolment restriction that blocks **personally owned** devices for the target users while allowing corporate devices. Do not block the iOS/iPadOS platform itself; that prevents ADE devices from enrolling.
- Put users into their pilot or production user group before they activate devices. Do not rely on dynamic-group membership for first-day app delivery.

**Completion condition:** a new device serial is visible in Intune, policy assignment is ready before activation, licence capacity is sufficient, and the target groups are populated.

### 3. Build the app catalogue

- Add Company Portal from Apps and Books as a **Required** iOS/iPadOS VPP app with **device licensing**. Deploy it through Intune, not the public App Store.
- Enable automatic updates for the VPP token that provides Company Portal.
- Add Microsoft Authenticator and Teams as required apps. They are part of the JIT registration journey.
- Add the organisation’s core productivity, security, connectivity, and line-of-business apps as required VPP apps with device licensing. Assign them to **GRP-INTUNE-IOS-ADE-FOUNDATION**.
- Add role-based supplementary apps as **Available for enrolled devices** in Company Portal. Assign available apps to pilot and production **user** groups; available VPP assignments do not support device groups.
- Configure app categories, descriptions, help contacts, privacy information, and branding so Company Portal functions as a clear self-service catalogue.
- Create managed app-configuration and app-protection policies for Microsoft 365 and other supported business apps. Apply data-transfer, account, save, copy/paste, and web-link controls appropriate to the organisation’s data classification.
- Do not manually deploy the Company Portal ADE app-configuration payload to new modern-authentication ADE devices. Intune automatically sends the required configuration when Company Portal installation is enabled in the enrolment policy, and a duplicate deployment causes a conflict.

**Completion condition:** every first-day app is device-licensed and required; optional apps are visible to the correct users in Company Portal; Company Portal automatic updates are enabled.

### 4. Build the device configuration, compliance, and update baseline

Create separate, purpose-specific policies to avoid setting conflicts:

- **JIT registration / SSO:** Create an iOS/iPadOS **Single sign-on app extension** policy with extension type **Microsoft Entra ID**. Add the following additional configuration:

  | Key | Type | Value |
  |---|---|---|
  | **device_registration** | String | **{{DEVICEREGISTRATION}}** |
  | **browser_sso_interaction_enabled** | Integer | **1** |

  Add bundle IDs only for supported non-Microsoft SSO apps. Do not add Microsoft app bundle IDs or Microsoft Authenticator; the extension applies to Microsoft apps automatically. Assign the policy to the pilot and production user groups.

- **Core security and restrictions:** Set the organisation’s supervised-device baseline for passcode, inactivity lock, jailbreak detection, unmanaged data destinations, iCloud/backup behaviour, AirDrop, certificates, lock-screen exposure, browser controls, and other approved restrictions. Configure passcode rules in policy rather than in Setup Assistant.
- **Network and access:** Deploy Wi-Fi, certificate, VPN, DNS, proxy, and per-app VPN profiles before business apps depend on them. Test home, office, guest, cellular, captive-portal, and remote-network paths.
- **Compliance:** Create an iOS/iPadOS compliance policy that blocks jailbroken devices, requires the approved passcode, and enforces minimum OS and build versions. Add a mobile-threat-defence or Defender risk requirement only when that service is deployed and validated. Assign the policy to enable JIT compliance remediation.
- **App protection:** Apply app protection policies to the user groups for supported corporate apps, even on fully managed devices, to protect work data inside the app layer.
- **Software updates:** Use Apple DDM update policies for supported supervised iOS/iPadOS devices. Create a test ring, then a production policy with planned notification and enforcement deadlines. Use compliance minimum OS/build requirements to control access after the approved grace period.

**Completion condition:** policy status is conflict-free on pilot devices, the device becomes compliant after the required remediation steps, and the required network and app paths work.

### 5. Create the single new ADE enrolment policy

Create the policy at **Devices > Device onboarding > Enrollment > Apple mobile > Enrollment program tokens > [token] > Enrollment policies > Create policy > iOS/iPadOS**. Use **Enrollment policies**, not the legacy **Profiles** experience.

Configure the policy as follows:

| Setting | Value |
|---|---|
| Device group | **GRP-INTUNE-IOS-ADE-FOUNDATION** |
| User affinity | Enrol with User Affinity |
| Authentication method | Setup Assistant with modern authentication |
| Install Company Portal | Yes, using the Apps and Books/VPP token with device licensing |
| Supervised | Yes |
| Locked enrolment | Yes |
| Company Portal Single App Mode | No |
| Await final configuration | Yes |
| Device name template | **{{DEVICETYPE}}-{{SERIAL}}** or the approved asset-naming standard |
| Department and telephone | Service desk name and support telephone number |

Recommended Setup Assistant treatment:

- Hide restore, device-to-device migration, Android migration, Apple Account, Apple Pay, App Store, Apple Watch migration, and other panes that are not part of the corporate setup journey.
- Hide **Passcode** and **Touch ID/Face ID** panes on iOS/iPadOS 14.5 and later. Enforce the passcode through device configuration or compliance, then let users configure biometrics in Settings afterwards.
- Show only the screens needed for accessibility, legal acceptance, cellular setup, or organisational policy.
- Do not use Company Portal Single App Mode when users need same-device MFA; the device cannot switch apps to complete the second factor.
- Keep the number of critical configuration policies deliberately small. **Await final configuration** holds users only until device configuration policies apply; it does not wait for applications.

Set the policy as the **default policy** for the ABM token and assign it to already synchronised devices where necessary. Treat policy edits as high-impact changes: almost all changes require a factory reset and reactivation before they take effect.

**Completion condition:** a new or wiped pilot iPhone and iPad receive the correct policy, are supervised, have locked enrolment, and show the approved device name.

### 6. Configure Conditional Access safely

- Create the iOS/iPadOS compliance policy before Conditional Access enforcement.
- Create a Conditional Access policy that requires a compliant device for the intended corporate resources.
- Exclude emergency access accounts and any approved non-interactive service accounts.
- Start in **Report-only** mode, review sign-in impact and policy simulation results, and verify that a test device completes JIT registration and becomes compliant.
- Move the pilot group to enforcement only after successful testing. Expand to production users in rollout waves.
- Ensure the end-user guide tells users to open Teams first after Home Screen arrival. Without JIT, the guide must instead instruct users to open Company Portal, sign in, and select **Begin**.

**Completion condition:** pilot users can enrol, become Entra-registered and compliant, and access corporate resources without bypassing Conditional Access.

### 7. Execute the pilot

Start with IT and service-desk users, then expand to a representative cross-section of departments, locations, networks, iPhone and iPad models, and user MFA methods. Do not begin with VIP users.

Test each scenario on a new or fully wiped device:

- Direct shipment and setup without IT touching the device.
- ABM synchronisation and default-policy assignment.
- Work account sign-in, MFA, password change, expired password, and recovery.
- JIT registration: Home Screen arrival, first Teams sign-in, Entra registration, compliance, and SSO.
- Required-app installation, optional Company Portal app installation, update behaviour, and licence consumption.
- Wi-Fi, certificates, VPN, Microsoft 365, line-of-business apps, and Conditional Access.
- Passcode and restriction enforcement, compliance remediation, and OS update policy.
- Factory reset, wipe/re-enrolment, Lost Mode, Activation Lock recovery, and device replacement.

Capture timing, errors, support calls, failed app assignments, compliance failures, and user feedback. Fix repeatable issues before releasing the next pilot cohort.

**Pilot acceptance criteria:**

- Enrolment and user affinity complete without administrator intervention.
- Users can complete MFA and JIT registration without a support call.
- Required apps install successfully and optional apps can be installed from Company Portal.
- Devices become compliant and receive Conditional Access access within the agreed time.
- No critical configuration-policy conflict or unplanned security exception remains open.

### 8. Roll out in controlled production waves

- Publish a short setup guide before each wave: what the user needs, expected screens, MFA preparation, expected setup duration, first Teams sign-in, required apps, Company Portal catalogue, and the single support route.
- Ship only after the serial number is present in Intune, the default ADE policy is assigned, VPP licence capacity is confirmed, and the pilot acceptance criteria have passed.
- Roll out in measured waves. Monitor the first business day of each wave and pause the next wave if enrolment, app-install, compliance, or support thresholds are missed.
- Reconcile ABM, Intune, carrier, and asset-register serial numbers throughout deployment.

**Completion condition:** the production fleet is enrolled, compliant, correctly assigned, and its required applications are deployed.

### 9. Establish operations, support, and lifecycle management

Create a service-desk runbook that records the user principal name, serial number, Intune device ID, model, OS version, last check-in, enrolment-policy name, exact timestamp, screenshot/error text, app status, configuration status, compliance state, and Entra registration state.

Use the following lifecycle procedures:

| Scenario | Standard action |
|---|---|
| Lost or stolen | Record the incident; use Lost Mode and Locate where authorised; wipe if recovery is not viable |
| Replacement | Issue a new supplier-enrolled device through the normal ADE flow; retain the old record until the incident is resolved |
| Returned or reassigned | Confirm possession; capture the Activation Lock bypass code before wipe; wipe, retain ABM assignment, and allow the next user to enrol through ADE |
| Leaver | Remove access under the offboarding process and wipe the corporate device for redeployment |
| Disposal or sale | Wipe the device, complete disposal controls, remove the Entra/Intune record where appropriate, then release it from ABM only when it permanently leaves the organisation |

Do not use **Delete** as a replacement for a wipe. Retire preserves user data and requires a local reset before ADE re-enrolment. Company Portal self-service Remove Device and Factory Reset actions are unavailable for ADE devices, so the support process must include an IT-led wipe path.

Monitor:

- ADE enrolment and enrolment-time grouping failures.
- Device configuration assignment status and conflicts.
- Required and optional VPP app installation status.
- Compliance, noncompliance reasons, Entra registration, and Conditional Access sign-ins.
- APNs, ADE, and Apps and Books/VPP token expiry dates.
- VPP licence availability and automatic app-update status.
- Device inventory, last check-in, lost-device cases, and Activation Lock status.

Review material changes to authentication, Conditional Access, enrolment policies, high-impact restrictions, update policies, and core apps in a pilot ring before production deployment.

**Completion condition:** the service is owned, monitored, documented, renewable, and ready for routine joins, moves, leavers, replacements, and incidents.

## Reference material

- [Set up automated device enrolment for iOS/iPadOS](https://learn.microsoft.com/en-us/intune/device-enrollment/apple/setup-automated-ios)
- [Authentication methods for Apple automated device enrolment](https://learn.microsoft.com/en-us/intune/device-enrollment/apple/ref-automated-authentication-methods)
- [Set up just-in-time registration](https://learn.microsoft.com/en-us/intune/device-enrollment/apple/setup-just-in-time-registration)
- [Set up enrolment-time grouping](https://learn.microsoft.com/en-us/intune/device-enrollment/setup-time-grouping)
- [Manage Apple volume-purchased apps](https://learn.microsoft.com/en-us/intune/app-management/deployment/manage-vpp-apple)
- [iOS/iPadOS device compliance settings](https://learn.microsoft.com/en-us/intune/device-security/compliance/ref-ios-ipados-settings)
- [Require device compliance with Conditional Access](https://learn.microsoft.com/en-us/entra/identity/conditional-access/policy-all-users-device-compliance)
- [Configure update policies for Apple devices](https://learn.microsoft.com/en-us/intune/device-updates/apple/managed-software-updates-ios-macos)
- [Apple device restriction settings](https://learn.microsoft.com/en-us/intune/device-configuration/templates/ref-device-restrictions-apple)
