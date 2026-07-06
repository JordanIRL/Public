# Runbook: Deploy Microsoft Cloud PKI, Issue Wi-Fi/VPN Client-Auth Certificates, and Decommission NDES

**Environment:** Windows (Entra-joined, cloud-only) · iOS/iPadOS (Supervised/ADE) · Android (COPE + Fully Managed) · Intune-managed relying parties for 802.1X Wi-Fi and certificate-based VPN.

**Outcome:** A cloud-hosted two-tier PKI issues client-authentication (leaf) certificates to managed devices over SCEP. Wi-Fi (EAP-TLS) and VPN authenticate with those certificates. The on-premises CA + NDES + Intune Certificate Connector + SCEP reverse proxy are retired.

---

## 1. What replaces what

| Legacy component | Replacement |
|---|---|
| On-prem issuing CA (for device auth certs) | Cloud PKI issuing CA (or BYOCA anchored to an existing private root) |
| NDES server + IIS | Cloud PKI SCEP registration authority (hosted) |
| Intune Certificate Connector | Not required |
| SCEP reverse proxy / App Proxy publishing of the NDES URL | Not required — SCEP URI resolves inside the `*.manage.microsoft.com` namespace |
| On-prem CRL/AIA endpoints | Intune-hosted CRL distribution point and AIA endpoint per CA |

The registration authority requests certificates from the issuing CA on behalf of enrolled devices using a SCEP certificate profile. Root and issuing CA keys are provisioned in Azure Managed HSM (no Azure subscription required for the HSM).

---

## 2. Prerequisites

**Licensing.** Cloud PKI requires a subscription in addition to Intune Plan 1 or Plan 2 — either the Intune Suite or the standalone Cloud PKI add-on. Confirm entitlement under **Tenant administration > Intune add-ons** before starting.

**Roles.** The signing-in account needs permission to create a CA. The Intune Administrator (Intune service administrator) role has this built in. For least privilege, assign the granular Cloud PKI permissions to a custom Intune role instead:
- **Read CAs** — read CA properties.
- **Create certificate authorities (CAs)** — create root/issuing CAs.
- **Revoke issued leaf certificates** — manually revoke a leaf certificate (also requires Read CAs).

Scope tags may be applied to root and issuing CAs to control visibility.

**Platform support.** Android, iOS/iPadOS, macOS, and Windows are all supported, provided the device is enrolled and the platform supports the Intune device-configuration SCEP certificate profile.

**Pre-work inventory (do before touching production):**
- Enumerate every existing NDES/SCEP certificate profile and its assignments, and the certificate templates each maps to.
- Record what each certificate is used for (Wi-Fi EAP-TLS, VPN, 802.1X wired, other) and which subject name / SAN format and EKUs it carries.
- Identify every relying party that validates these certificates: RADIUS/NPS servers, wireless LAN controllers/APs, VPN gateways.
- Note the existing root/issuing CA chain currently trusted by those relying parties.

**Capacity limit.** A tenant can hold a maximum of **three** CAs. Root CA, Cloud PKI issuing CA, and BYOCA issuing CA all count toward that cap. Plan the hierarchy accordingly (e.g., one root + up to two issuing CAs).

---

## 3. Phase A — Build the Cloud PKI hierarchy

Decide the deployment model first:
- **Cloud PKI root CA** — create both the root and issuing CA in the cloud. Two-tier, private to the tenant. Default choice for a cloud-only estate with no requirement to preserve an existing root.
- **BYOCA** — create only a cloud issuing CA and anchor it to an existing private root (e.g., ADCS) by signing a CSR. Choose this only if relying parties must keep trusting the existing root chain. The steps below assume the Cloud PKI root CA model; BYOCA differs only in that the issuing CA is created from a downloaded CSR signed by the private CA.

### A1. Create the root CA

1. **Tenant administration > Cloud PKI > Create**.
2. **Basics** — Name (e.g., `C-PKI Root CA G1`) and optional Description.
3. **Configuration settings:**
   - **CA type:** Root CA.
   - **Validity period:** 5/10/15/20/25 years (custom values via Graph). A long-lived root (e.g., 15–25 years) is normal.
   - **Extended Key Usages:** define the superset of EKUs the hierarchy will ever need. Issuing-CA EKUs can only be a subset of the root's, so include **Client Authentication** here (add Server Authentication or custom OIDs only if genuinely required). **Do not select Any Purpose (2.5.29.37.0)** — it is overly permissive and unsupported for issuance.
   - **Subject attributes:** Common Name (required); optionally O, OU, C (two-character limit), ST, L.
   - **Encryption (key size and algorithm):** RSA-2048/SHA-256, RSA-3072/SHA-384, or RSA-4096/SHA-512. This sets the upper bound for key size/hash selectable in downstream SCEP profiles. 1024-bit and SHA-1 are not supported.
4. **Scope tags** (optional) → **Review + create** → **Create**.
5. Properties are immutable after creation — to change EKUs later you must create a new CA. **Refresh** the list to confirm.

### A2. Create the issuing CA

1. **Cloud PKI > Create**, Name (e.g., `C-PKI Issuing CA G1`) and Description.
2. **Configuration settings:**
   - **CA type:** Issuing CA.
   - **Root CA source:** Intune.
   - **Root CA:** select the root created in A1.
   - **Validity period:** 2/4/6/8/10 years — must not exceed the root's remaining validity (custom via Graph).
   - **Extended Key Usages:** select from the root's EKUs — include **Client Authentication**. (If it isn't offered here, it wasn't defined on the root.)
   - **Subject attributes:** Common Name (required); optional O, OU, C, ST, L.
3. **Scope tags** (optional) → **Review + create** → **Create** → **Refresh**.

### A3. Record the CA endpoints

Open each CA's **Properties** and record:
- **CRL distribution point (CDP) URI** — root and issuing.
- **AIA URI** — issuing CA.
- **SCEP URI** — issuing CA only (needed when building SCEP profiles).

The CRL is valid 7 days, republished every 3.5 days, and refreshed immediately on any revocation. Relying parties must be able to reach the CDP and AIA endpoints for revocation checking and chain building.

---

## 4. Phase B — Create certificate profiles

Three profile types are required, each created **per target platform** (Windows, iOS/iPadOS, Android — and macOS if in scope): a trusted profile for the root, a trusted profile for the issuing CA, and a SCEP profile for the leaf certificate.

### B1. Download the CA public keys

For each CA: **Cloud PKI >** select the CA **> Properties > Download**. This yields the `.cer` public key used in the trusted certificate profiles and required on relying parties. (Microsoft Edge may warn on `.cer` downloads — choose **Keep**.)

### B2. Create trusted certificate profiles (root and issuing, per platform)

For each platform, create two trusted certificate profiles — one carrying the **root** public key, one carrying the **issuing** public key.

1. **Devices > Manage devices > Configuration > Create > New policy**.
2. Platform = the target OS; Profile type = **Trusted certificate**.
3. Name (e.g., `CERT-Trusted-Root-WIN-CloudPKI`, `CERT-Trusted-Issuing-WIN-CloudPKI`).
4. Browse to the corresponding `.cer`.
5. For Windows, confirm the destination store is **Computer certificate store - Root** for the root CA profile.
6. Assign to the pilot group (see B4).

Deploying the issuing CA as a trusted profile is optional (devices can retrieve it via AIA) but **recommended** to avoid chain-building delays — and it is effectively mandatory for Android, which does not follow AIA paths and requires the full chain present.

### B3. Create SCEP client-authentication certificate profiles (per platform)

This profile requests the leaf client-auth certificate used by Wi-Fi and VPN.

1. Copy the issuing CA **SCEP URI** to the clipboard (**Cloud PKI >** issuing CA **> Properties > Copy to clipboard**).
2. **Devices > Manage devices > Configuration > Create > New policy**, Platform = target OS, Profile type = **SCEP certificate**.
3. Configure:
   - **Certificate type:** Device or User.
     - *Wi-Fi/802.1X on Entra-joined Windows and on user-less devices:* Device.
     - *Per-user certificates:* User.
   - **Subject name format:** build from attributes present on the Entra object (e.g., `CN={{DeviceName}}` for device certs, `CN={{UserPrincipalName}}` for user certs). If a referenced attribute is empty on the target object, issuance fails and the profile report shows an error.
   - **Subject alternative name:** for any certificate used with EAP-TLS Wi-Fi, add **SAN → UPN = `{{UserPrincipalName}}`**. If the UPN is absent from the SAN, Wi-Fi profile deployment fails on the affected platforms. (For device certs where no user context exists, align the RADIUS policy to the SAN/subject you can populate, e.g., DNS name or device attributes.)
   - **Certificate validity period:** per policy (commonly 1 year for leaf certs).
   - **Key storage provider (Windows):** TPM if available, else software.
   - **Key usage:** Digital signature + Key encipherment.
   - **Extended key usage:** **Client Authentication (1.3.6.1.5.5.7.3.2)**. The EKU selected must exist on the issuing CA. **Any Purpose is not supported.**
   - **Renewal threshold (%):** e.g., 20 (renew when 80% through lifetime). *iOS/iPadOS and macOS caveat:* renewal only occurs during the threshold window while the device is unlocked and syncing; a certificate that expires without renewing is not auto-redeployed — the device must be temporarily removed from the SCEP profile scope to clear and reissue.
   - **Root Certificate:** link the **trusted root** certificate profile created in B2 (must be the root the issuing CA is anchored to).
   - **SCEP Server URLs:** paste the SCEP URI. **Leave `{{CloudPKIFQDN}}` in the string exactly as-is** — Intune substitutes the correct FQDN (within `*.manage.microsoft.com`) at delivery. **Do not add any NDES SCEP URL to a Cloud PKI SCEP profile, and do not add the Cloud PKI URL to an NDES profile** — the two must never be combined in one profile.
4. Assign to the pilot group.

**Platform constraint — Android:** Fully Managed, Dedicated, and Corporate-Owned Work Profile (COPE) devices support **SCEP only** (not PKCS) for client-auth certificates. Cloud PKI's SCEP model fits these directly.

### B4. Assignment strategy

Assign all Cloud PKI profiles (trusted root, trusted issuing, SCEP) to a **pilot ring group** first. Certificate delivery order matters: the trusted profiles and SCEP profile must all land before the consuming Wi-Fi/VPN profile authenticates. Keep the consuming network profiles scoped to the same ring so issuance precedes consumption.

---

## 5. Phase C — Prepare the relying parties

Every relying party that validates device certificates must trust the Cloud PKI chain **before** any device is cut over. Install the Cloud PKI **root** (and recommended **issuing**) CA `.cer` into the trust store of:
- RADIUS / NPS servers used for 802.1X Wi-Fi (and wired, if applicable).
- Wireless LAN controllers / access points that terminate authentication.
- VPN gateways using certificate-based authentication.

Deployment method:
- **AD domain-joined relying parties:** Group Policy certificate distribution.
- **Non-domain relying parties:** install manually into the appropriate platform/application trust store.

During a Cloud PKI root CA deployment, relying parties can auto-retrieve a missing issuing CA via the AIA URL in the leaf certificate (certificate chaining engine). Regardless, ensure the **root** is present. For Android clients specifically, the server side must return the **entire** chain — Android does not perform AIA discovery — so deploy the full chain to Android devices and ensure relying parties present it.

On the RADIUS/NPS side, update the network policy so the certificate identity you issue (subject/SAN — typically UPN for user certs, or the device attribute you populated) maps to the intended authorization. Add the Cloud PKI issuer to any "trusted CA" allow-list the RADIUS policy enforces.

---

## 6. Phase D — Wi-Fi profiles (EAP-TLS client authentication)

Create one Wi-Fi profile per platform per SSID. Only one Wi-Fi profile with a given SSID can apply to a device; duplicates with the same SSID silently fail to deploy.

**Windows** (**Devices > Configuration > Create**, Platform = Windows 10 and later, Profile = Templates > **Wi-Fi**):
- Wi-Fi type: **Enterprise**; enter SSID and connection name.
- **EAP type: EAP-TLS.**
- **Root certificates for server validation:** select the trusted **root** profile (and issuing, if deployed) so the client validates the RADIUS server certificate.
- **Certificate server names:** add the RADIUS server certificate common name(s) to suppress the dynamic-trust prompt.
- **Authentication method: SCEP certificate** → select the Cloud PKI SCEP profile.

**iOS/iPadOS** (Platform = iOS/iPadOS, Profile = **Wi-Fi**):
- Wi-Fi type: **Enterprise**; SSID; Security type WPA2/WPA3-Enterprise.
- **EAP type: EAP-TLS.**
- **Root certificate for server validation:** trusted root profile.
- **Certificate server names:** RADIUS server CN (wildcard suffix allowed, e.g., `*.contoso.com`).
- **Authentication method → Certificates:** select the Cloud PKI SCEP profile.

**Android (COPE / Fully Managed)** (Platform = Android Enterprise, correct ownership profile, Profile = **Wi-Fi**):
- Wi-Fi type: **Enterprise**; SSID.
- **EAP type: EAP-TLS.**
- **Root certificate for server validation:** trusted root profile (Android 11+ requires a trusted root).
- **Client certificate (identity certificate):** the Cloud PKI SCEP profile.
- **SAN must contain the UPN** or the profile deployment fails.

---

## 7. Phase E — VPN profiles (certificate authentication)

**iOS/iPadOS (per-app or device-wide VPN):**
1. Export the VPN gateway's **root** certificate (`.cer`) from the gateway and import it as an iOS trusted certificate profile so the device trusts the gateway automatically. (This is in addition to the Cloud PKI trusted profiles, which cover the client-cert chain.)
2. Ensure the Cloud PKI **SCEP** profile (EKU = Client Authentication) is assigned — this is the credential the client presents for silent authentication.
3. Create the **VPN** profile (Templates > VPN), select the connection type/vendor, set authentication to **Certificates**, and select the SCEP profile. For per-app VPN, associate the profile with the target app and enable per-app scoping.
4. Assign the trusted, SCEP, and VPN profiles to the same group.

**Android (COPE / Fully Managed) — per-app VPN via app configuration policy:**
1. Confirm the VPN client supports Intune app configuration (e.g., Cisco AnyConnect, Citrix SSO, F5 Access, Palo Alto GlobalProtect, Pulse Secure, SonicWall Mobile Connect).
2. Deploy certificate profiles first (trusted chain + Cloud PKI **SCEP** — SCEP only on these ownership types) and confirm successful issuance; this creates a certificate token referenced by the VPN policy.
3. Add the VPN client app from managed Google Play and capture each target app's package ID (e.g., `com.microsoft.emmx`).
4. Create the VPN **app configuration policy** (configuration designer or JSON), referencing the certificate token and the per-app package IDs. Deploy and validate. Note Android does not auto-launch VPN on app open unless always-on VPN is configured.

**Windows VPN:** create a Templates > VPN profile, choose the connection type, set authentication to use a client certificate, and select the Cloud PKI SCEP profile; provide the trusted root for gateway validation as required by the gateway.

---

## 8. Phase F — Pilot validation and ring-based cutover

**Validate issuance (pilot ring):**
- **Devices > Monitor > Certificates** to confirm leaf certificates are being issued by the Cloud PKI issuing CA. (The per-CA **View all certificates** list caps at 1,000; use Monitor > Certificates for the full view.)
- On a Windows pilot device, confirm the leaf in the machine store with the correct issuer, subject/SAN, and **Client Authentication** EKU, and confirm the full chain resolves.
- Check the SCEP profile device status report for errors (empty SAN/subject attributes are the common failure).

**Validate consumption:**
- Confirm Wi-Fi (EAP-TLS) associates and authenticates against RADIUS using the Cloud PKI certificate.
- Confirm VPN establishes and, for per-app VPN, that only the scoped app's traffic tunnels.

**Cut over ring by ring:**
1. Add each production ring to the Cloud PKI SCEP profile (and the new Wi-Fi/VPN profiles).
2. Remove that same ring from the **legacy NDES SCEP profile** assignment. Because NDES and Cloud PKI SCEP URLs cannot coexist in one profile, cutover is a swap between two separate profiles, not an edit — devices unassigned from the NDES profile stop renewing the old certificate and obtain the Cloud PKI certificate instead.
3. Keep the legacy trusted-root profile and the legacy CA chain on relying parties until the corresponding ring's old certificates have fully aged out — clients and RADIUS need to trust both issuers during the transition.
4. Monitor issuance and Wi-Fi/VPN success per ring before advancing.

Advance through all rings until every device holds a Cloud PKI certificate and no production authentication depends on an NDES-issued certificate.

---

## 9. Phase G — Decommission NDES

Only begin once monitoring confirms zero production dependency on NDES-issued certificates.

1. **Retire legacy profiles in Intune:** unassign, then delete the NDES SCEP certificate profiles and the legacy trusted-root/issuing certificate profiles that are no longer referenced by any Wi-Fi/VPN profile.
2. **Remove the Certificate Connector:** uninstall the Certificate Connector for Microsoft Intune from the connector host and confirm it disappears from **Tenant administration > Connectors and tokens > Certificate connectors**.
3. **Remove NDES infrastructure:**
   - Uninstall the Network Device Enrollment Service role and remove the associated IIS site/application.
   - Remove the SCEP publishing path — the reverse proxy or Application Proxy configuration that exposed the NDES URL externally, plus its external DNS record and firewall/NAT rules.
   - Revoke the NDES registration-authority (Enrollment Agent / CEP Encryption) certificates on the on-premises CA.
4. **Retire the on-premises issuing CA (only if it existed solely for NDES/device certs):** revoke remaining leaf certificates if required, publish a final CRL, then decommission per standard CA retirement. If the CA still issues other certificate types, leave it in place and remove only the NDES-related templates/permissions.
5. **Clean up relying-party trust:** once no certificate in use chains to the old root, remove the legacy CA chain from RADIUS/NPS, WLC/AP, and VPN gateway trust stores (reverse the GPO or manual deployment). Leave the Cloud PKI chain in place.
6. **Update documentation** and the CMDB to reflect the removed servers, connectors, DNS entries, and firewall rules.

---

## 10. Ongoing operations

**CA renewal (staged model).** A CA becomes eligible for renewal at half its validity lifetime (or once expired). **Cloud PKI >** select CA **> Renew** creates a *staged* CA with a temporary SCEP URI, valid up to 90 days (deleted after a further 30-day grace period if not activated), allowing up to 50 test certificates. Validate issuance with a test SCEP profile against the staged URI, then **Activate** to promote the staged CA, retire the previous one, disable the staged URI, and restore the **original production SCEP URI** — so existing SCEP profiles need no change. For BYOCA, renewal generates a CSR to be re-signed by the private root before staging. Watch for the in-console renewal banners as CAs approach expiry.

**Revocation.** Revoke a leaf certificate from the issuing CA (requires the Revoke permission). The CRL updates immediately on revocation; relying parties must reach the Intune-hosted CDP for the revocation to take effect.

**Monitoring.**
- **Devices > Monitor > Certificates** — issued-certificate inventory (authoritative; not capped at 1,000).
- SCEP certificate profile **device status** reports — issuance failures (usually empty subject/SAN attributes or an EKU absent on the issuing CA).
- Wi-Fi and VPN profile status reports, plus RADIUS/NPS logs, for authentication health.
- Track CA validity/renewal-eligibility dates.

**Known limitations to design around.**
- Maximum three CAs per tenant (root, Cloud PKI issuing, and BYOCA issuing all count).
- The per-CA "View all certificates" list shows only the first 1,000 — use Monitor > Certificates.
- Data residency selection is not available for Cloud PKI.
- Any Purpose EKU is unsupported; issuing-CA EKUs are constrained to a subset of the root's, so an EKU not defined on the root cannot be added later without building a new CA.
- iOS/iPadOS and macOS do not auto-redeploy an expired leaf certificate; clear and reissue by temporarily excluding the device from the SCEP profile.
