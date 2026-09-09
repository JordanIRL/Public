Samsung KME Migration Safety for Existing Intune COPE Devices

Executive conclusion

Assuming these are Android Enterprise Corporate-owned devices with a work profile (COPE):

Assigning a standard Samsung Knox Mobile Enrollment profile to an already-running Intune-enrolled device is safe and should not disrupt it.

KME profile assignment is essentially a server-side instruction telling Samsung:

The next time this device goes through out-of-box setup, enroll it using this EMM configuration.

It does not replace the current Intune enrollment, reinstall the work profile, factory-reset the phone, or push a new MDM configuration onto the currently running device.

Samsung explicitly describes profile assignment as enabling OOBE enrollment, and states that a newly assigned or changed KME enrollment profile requires a factory reset before the changes take effect on the device. (Samsung Knox)

So this state is perfectly valid:

Today

Samsung phone
→ Intune COPE enrollment created using your Intune QR
→ Currently managed normally
→ KME profile assigned in Knox Admin Portal
→ Nothing changes on the phone

Later, after a factory reset

Samsung OOBE
→ Device identifies itself to Samsung
→ Samsung sees assigned KME profile
→ Intune enrollment information is automatically supplied
→ No Intune QR needs to be scanned
→ User completes the normal Intune authentication/enrollment process.

That is exactly the migration model I would use.

⸻

What I would do with your 400 phones

If the 400 existing devices already appear in Knox Admin Portal/KME, I would eventually assign the KME profile to all 400.

I would not factory-reset them merely to convert them to KME.

They can continue operating exactly as they are. The KME assignment simply makes them KME-ready for their next reset.

This gives you a particularly nice migration:

Device	Current operation	Next factory reset
Existing 400	Existing Intune enrollment continues	KME → Intune automatically
New Samsung devices	N/A	KME → Intune automatically
Replacement/reused device	Existing enrollment until wiped	KME → Intune automatically

There is therefore no need for a “big bang” migration of your deployed fleet.

⸻

Use a standard KME profile, not an Advanced profile

This is the biggest precaution I would take.

Create a standard KME enrollment profile whose purpose is simply:

Samsung KME → Microsoft Intune

Do not enable KME Advanced settings during this migration.

Advanced KME profiles provide functionality such as:

* locking a device if enrollment isn’t completed within a specified period;
* immediately locking certain compromised devices;
* preventing users from bypassing KME enrollment;
* remotely locking/unlocking devices;
* remotely factory-resetting locked devices;
* pre-installing applications.

Samsung documents these separately and requires Knox Suite Enterprise licensing for the advanced functionality. (Samsung Knox)

These features may be useful later, but they add absolutely nothing necessary to your current objective.

For your first deployment I would have:

EMM: Microsoft Intune
Enrollment: KME OOBE
Advanced profile: Off
Knox Guard integration: None unless already deliberately used
Additional Knox services: None unless already deliberately used

Once the basic KME → Intune path has been proven, you can investigate Advanced KME separately.

⸻

I would initially reuse your existing Intune enrollment profile

Your current Intune QR code ultimately represents an Intune Android Enterprise enrollment profile and enrollment token.

KME can use that same Intune enrollment token.

Microsoft specifically supports exporting the enrollment information from:

Intune → Devices → Enrollment → Android → Corporate-owned devices with work profile → your profile → Token

and using it with KME. (Microsoft Learn)

Microsoft’s required KME DPC data is essentially:

{"com.google.android.apps.work.clouddpc.EXTRA_ENROLLMENT_TOKEN":"YOUR_INTUNE_TOKEN"}

Microsoft explicitly states that this JSON is required for successful Intune enrollment through KME. (Microsoft Learn)

Why I favour reusing the existing Intune profile initially

Suppose your current profile is:

Corporate Android - COPE

and your applications/policies use a dynamic group such as:

device.enrollmentProfileName = "Corporate Android - COPE"

If you create a completely new Intune enrollment profile called:

Corporate Android - KME

your KME-enrolled devices may no longer enter the same dynamic groups.

Microsoft specifically supports dynamic device group membership based on enrollmentProfileName. (Microsoft Learn)

Reusing the existing Intune enrollment profile means:

Old process

Intune enrollment profile
→ QR code
→ Phone

becomes:

New process

Intune enrollment profile
→ KME
→ Phone

The Intune configuration is unchanged. You are only changing the mechanism used to bootstrap it.

That is the lowest-risk migration.

You can create a separate Intune profile later if you deliberately want different grouping, naming or staging behaviour.

⸻

Intune enrollment tokens are important operationally

For normal COPE enrollment profiles, Microsoft states that the enrollment token does not automatically expire. (Microsoft Learn)

That is useful for KME because you don’t need to periodically update KME just because the token reached an arbitrary expiry date.

However:

Do not revoke that Intune enrollment token without also planning for KME.

Revoking the token doesn’t affect phones already enrolled in Intune, but it prevents the token from being used for subsequent enrollments. Microsoft explicitly states that revocation has no effect on already-enrolled devices. (Microsoft Learn)

In practice I would document:

Intune COPE profile: Corporate Android - COPE
Used by: Samsung KME production profile
Do not revoke without updating KME

That prevents somebody cleaning up Intune enrollment profiles a year from now and accidentally breaking your zero-touch enrollment.

⸻

KME does not mean completely userless enrollment

This distinction is worth making.

KME removes this:

Tap setup screen → invoke QR enrollment → scan Intune QR

It does not necessarily remove:

User signs in with Microsoft 365/Entra credentials

For user-affiliated COPE devices, Samsung describes the OOBE process as:

1. Turn on device.
2. Connect to network.
3. KME retrieves the enrollment configuration.
4. Follow enrollment screens.
5. Enter EMM credentials.
6. Complete enrollment. (Samsung Knox)

So the experience becomes substantially cleaner:

Power on → connect Wi-Fi → Samsung automatically finds Intune → user signs in

rather than:

Power on → special enrollment gesture → scan QR → connect Wi-Fi → Intune → user signs in

KME is effectively your zero-touch bootstrap mechanism.

Intune remains the actual device-management platform.

⸻

What happens to your existing devices when you assign the profile

For one of your currently deployed phones, expect KME to show something such as:

Profile assigned

rather than:

Provisioned

That does not mean the existing Intune enrollment is broken.

Samsung defines Profile assigned as a device which has an enrollment profile assigned but has not completed enrollment through KME.

A device moves to Provisioned after it actually performs KME enrollment. (Samsung Knox)

So for your migrated fleet you could quite reasonably have hundreds of devices showing:

KME: Profile assigned

while simultaneously being:

Intune: Enrolled / Compliant / Healthy

Eventually, as devices are replaced or reset, they will go through KME and become Provisioned.

⸻

Factory reset behaviour is the main thing you need to operationalise

Once KME is assigned, a factory reset changes your recovery workflow.

Instead of your technician needing the Intune QR:

Factory reset

→ Samsung OOBE
→ Internet connection
→ Samsung recognises IMEI/serial
→ KME retrieves assigned profile
→ Android Enterprise provisioning starts
→ Intune enrollment token is supplied automatically
→ Microsoft Intune app/required components install
→ user signs in
→ Intune policies/apps/compliance apply.

Samsung explicitly defines KME OOBE as applying after either unboxing or factory resetting a device. (Samsung Knox)

That is one of KME’s biggest advantages for an enterprise fleet.

⸻

Prefer an Intune Wipe for planned reprovisioning

There is an important Android 15+ consideration: Factory Reset Protection.

For COPE devices, Microsoft documents different FRP behaviour depending on how the reset occurs.

In particular, Microsoft shows that an Intune Wipe does not invoke FRP for COPE devices, while a reset performed through Settings or recovery can invoke FRP. Microsoft also warns that on Android 15 devices, a reset through Settings can require the Google account associated with the configuration afterward. (Microsoft Learn)

Samsung separately states that KME cannot bypass FRP on Android 15 or later. (Samsung Knox)

Therefore I would make your normal corporate reprovisioning procedure:

Preferred

Intune → Wipe
→ Samsung OOBE
→ KME
→ Intune

rather than:

Avoid where practical

Device Settings → Factory data reset
→ possible FRP challenge
→ KME only after FRP has been satisfied.

This could save your service desk significant trouble.

⸻

Your biggest practical issue may actually be getting all 400 devices into KME

This depends on how you bought them.

For genuine KME zero-touch OOBE, Samsung’s current documentation expects the devices to exist in your Knox inventory, normally because a Samsung-approved reseller uploads the device identifiers to your Knox account.

Samsung recommends:

1. register your reseller;
2. give them your Knox Customer ID;
3. reseller uploads the devices;
4. approve the upload;
5. assign your KME profile.

You can also configure the reseller relationship so future uploads are:

automatically approved + automatically assigned your production enrollment profile. (Samsung Knox)

That is what I would configure for all future purchases.

For your existing 400

If they already appear in:

Knox Admin Portal → Devices

then this is easy.

Assign the standard KME profile.

If they do not appear in Knox Admin Portal, contact the reseller that supplied the devices and ask whether they can upload the historical devices to your Knox Customer ID.

There is an important documentation discrepancy here.

Microsoft’s April 2026 Intune documentation still references the Knox Deployment App as a method for uploading existing devices. (Microsoft Learn)

However, Samsung — which owns KME — announced that the Knox Deployment App was deprecated and specifically states:

you can no longer sign into or use it with KME for EMM enrollment.

Samsung now directs customers toward reseller upload or QR enrollment instead. (Samsung Knox)

I would therefore not design your migration around the Knox Deployment App, despite Microsoft’s page still mentioning it.

For a 400-device enterprise fleet, getting your reseller to populate the KME inventory is the correct route.

⸻

Future procurement should be automated

Once this is working, configure your Samsung reseller in Knox Admin Portal with:

Auto approve uploaded devices: Yes
Default KME profile: Your production Intune KME profile

Samsung supports both settings. (Samsung Knox)

Then your lifecycle becomes:

Purchase Samsung phone

→ reseller uploads IMEI to your Knox tenant
→ automatically approved
→ production KME profile automatically assigned
→ device shipped
→ user turns it on
→ Intune enrollment starts automatically.

At that point you should never need an Intune QR for normal corporate Samsung deployments again.

I would retain the QR only as an emergency/manual enrollment mechanism.

⸻

Conditional Access is worth testing

Microsoft has a specific warning about Android Enterprise enrollment.

If you have a Conditional Access policy that:

* requires the device to be compliant, or
* blocks access;
* applies to Android;
* applies to browser authentication;
* and applies broadly to cloud applications,

Microsoft recommends excluding the Microsoft Intune cloud app from the relevant enrollment-blocking CA policy.

This is because Android enrollment can use a Chrome authentication tab before the device has had a chance to become compliant. (Microsoft Learn)

Your current QR enrollments may already prove that your CA configuration works, but I would explicitly validate this as part of the KME pilot.

⸻

Don’t restart a phone halfway through enrollment

Microsoft also currently warns against rebooting fully managed/COPE devices during the Android Enterprise enrollment process.

A prematurely restarted device can appear to have enrolled while not actually being correctly registered/protected by Intune policies. (Microsoft Learn)

Your service desk instructions should therefore say:

Do not reboot the device until the Intune enrollment process has completed.

⸻

Recommended production profile

For your requirement, I would keep the KME configuration deliberately boring.

Intune

Enrollment type: Android Enterprise Corporate-owned devices with work profile

Enrollment profile: reuse your existing production COPE enrollment profile initially

Token: existing production token

Staging token: No, unless you deliberately want technician/vendor staging

Microsoft notes that enrollment-time grouping isn’t supported with the COPE staging token, which is another reason not to introduce staging unless you actually need it. (Microsoft Learn)

Knox Mobile Enrollment

Service: EMM

EMM: Microsoft Intune

DPC extras: existing Intune COPE enrollment token

QR enrollment: unnecessary for normal OOBE

Advanced settings: Off

Knox E-FOTA: Off unless you deliberately use it

Knox Asset Intelligence: Off unless deliberately used

Knox Service Plugin: only enable if you actually use KSP/OEMConfig policies in Intune

System applications: leave enabled as Microsoft recommends for the Intune KME configuration.

This gives you the smallest possible change from what is working today.

⸻

Migration sequence I recommend

Do not assign all 400 first simply because the documentation says it is safe.

Use one real production-like device to validate the whole lifecycle.

Phase 1 — Build

Create the KME profile.

Use the same Intune COPE enrollment token currently behind your working QR enrollment.

Disable Advanced KME settings.

Phase 2 — Live-device safety test

Take one currently enrolled Samsung device that is visible in KME.

Assign the KME profile.

Then do absolutely nothing to the phone.

Verify:

* Intune remains enrolled;
* work profile remains present;
* applications remain present;
* compliance remains unchanged;
* Conditional Access remains working;
* no KME prompt appears;
* user experiences no change.

This specifically proves your concern.

Phase 3 — Re-enrollment test

Use that same test device.

Perform an Intune Wipe.

Connect it to Wi-Fi during Samsung OOBE.

Expected result:

No QR requested

→ Knox/KME provisioning begins
→ Intune configuration downloaded
→ Microsoft authentication
→ COPE enrollment
→ work profile created
→ policies/apps/compliance return.

Phase 4 — Validate Intune

Check:

* ownership = Corporate;
* management = Android Enterprise;
* correct COPE enrollment type;
* correct enrollment profile;
* primary user;
* device naming;
* compliance;
* configuration profiles;
* Wi-Fi;
* VPN;
* certificates;
* required applications;
* Managed Google Play applications;
* Microsoft Authenticator;
* Conditional Access;
* any dynamic device groups using enrollmentProfileName.

I would not proceed until these are identical to a QR-enrolled phone.

Phase 5 — Small fleet

Assign KME to perhaps 10–20 currently deployed phones.

Do not reset them.

Leave them in production for several days.

There should be zero user-visible change.

Phase 6 — Existing fleet

Assign the KME profile to the remaining devices that are eligible and present in Knox.

Again:

no factory resets are required.

They simply become KME-ready.

Phase 7 — Future devices

Enable reseller:

Auto approve + Default KME profile

All new purchases then arrive KME-ready.

⸻

Overall risk assessment

Change	Risk	Assessment
Assign standard KME profile to currently enrolled phone	Very low	Safe; no factory reset means profile isn’t applied to running device
Reuse existing Intune enrollment token	Very low	Keeps Intune enrollment behaviour consistent
Assign profile to all 400 after pilot	Low	Appropriate migration
Factory reset after KME assignment	Expected	Triggers the new enrollment path
Intune Wipe → KME enrollment	Low	Preferred reprovisioning path
Local factory reset Android 15+	Medium	FRP can interfere
New Intune enrollment profile	Low–Medium	Check dynamic groups/policy targeting
Revoke Intune enrollment token	Medium	Breaks future KME enrollment using that token
Advanced KME profile	Medium–High	Unnecessary locking/enforcement capabilities during migration
Rely on Knox Deployment App	High operational risk	Samsung has deprecated the KME use case

⸻

Bottom line

I would proceed with KME.

There is no technical reason to wipe or manually re-enroll your existing 400 devices.

The clean architecture is:

Existing phones

Current Intune enrollment

* KME profile waiting in Samsung
    = no user disruption

After their next planned wipe

Samsung KME
→ automatically supplies Intune enrollment configuration
→ Intune COPE enrollment
→ no QR.

And for new devices:

Samsung reseller → Knox → KME → Intune

The three things I would be particularly strict about are:

1. Use a standard KME profile with Advanced features disabled.
2. Pilot using your existing Intune COPE enrollment token before changing the whole fleet.
3. Get your reseller/KME inventory process correct now, because reseller upload is the important component of true QR-less OOBE enrollment.

The actual act of assigning that standard KME profile to the currently deployed devices is not the dangerous part. The profile only becomes operational on those devices when they next enter OOBE after a factory reset.