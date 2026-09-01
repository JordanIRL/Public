# Network Triage Kit

Remote, unattended network diagnosis for Entra-joined / Intune-managed Windows laptops.

Built to replace speculative trial-and-error with a measurement. Everything runs as SYSTEM
in the background; nothing asks the user to do anything.

**Start with [RUNBOOK.md](RUNBOOK.md).** This file covers setup and design; the runbook
covers what to actually do when a ticket lands.

---

## The problem it solves

A laptop reports ~3 Mbps download against 40-130 Mbps upload, on Wi-Fi, everywhere, while
peers on the same APs are fine.

That asymmetry is far more diagnostic than it looks. A download-only cap on Windows has a
closed list of causes, because Windows QoS throttle rates and "limit reservable bandwidth"
are **outbound-only** and so are excluded by definition. What remains:

1. **Receive-path packet loss.** Mathis: `BW ~= MSS / (RTT * sqrt(p))`. At MSS 1460 B,
   RTT 30 ms, 1% loss that is **~3.9 Mbps** - which lands on the reported figure, explains
   why upload is untouched (laptop->AP transmit is healthy, AP->laptop receive is dropping),
   and explains why AP-side link speed looks fine: PHY rate stays high while retries climb.
2. **TCP receive window pinned.** Auto-tuning disabled or restricted collapses inbound
   throughput to roughly `RWIN/RTT`. Outbound unaffected.
3. **A hard rate cap in software.** OEM bandwidth managers, AV/EDR inbound inspection, or a
   leftover NDIS/LSP filter driver.
4. **Radio configuration.** Aggressive power save, stuck on 2.4 GHz / 20 MHz.

**The discriminator is single-stream vs parallel-stream download**, and it runs unattended:

- parallel >> single -> loss- or window-limited (causes 1, 2)
- parallel ~= single -> a hard aggregate cap (cause 3)
- both low *and* PHY rate low -> cause 4

One test, no guessing, half the problem space gone.

---

## Layout

```
src/                  Detect-NetworkFingerprint.ps1        triage collector + verdict engine
                      Detect-NetworkFingerprint.User.ps1   user-context companion probe
remediations/         seven narrow, idempotent Detect/Remediate pairs
deploy/               packages.json, Invoke-Deploy.ps1, Get-RemediationResults.ps1
queries/              Device Query KQL snippets
tests/                Test-Fingerprint.ps1  (runs anywhere pwsh runs)
```

Every `.ps1` is self-contained and pasteable straight into the portal. That means a little
duplicated helper code - a deliberate trade for no build step and no ambiguity about which
version is deployed.

---

## Setup

### 1. Settings that must be right

| Setting | Value | Why it matters |
|---|---|---|
| **Run script in 64-bit PowerShell** | **Yes** | **The portal default is No.** A 32-bit host on 64-bit Windows hits WOW64 registry redirection, so the native Uninstall hive and several net cmdlets return wrong or empty data. The fingerprint still renders - it is just quietly incorrect. This is the single easiest way to get a plausible, wrong answer. |
| Run using logged-on credentials | **No** (Yes only for the USER probe) | SYSTEM context, no user involvement. |
| Enforce script signature check | No | Otherwise scripts must be signed and in Trusted Publishers. |
| Encoding | UTF-8 **without** BOM | A BOM breaks the signature-check path. `Invoke-Deploy.ps1` handles this. |

### 2. Deploy

Portal: **Devices > Scripts and remediations > Create**, paste the detection and
remediation scripts, and apply the settings above.

Or version-controlled, via Graph:

```bash
pwsh -File deploy/Invoke-Deploy.ps1 -WhatIf
```

```bash
pwsh -File deploy/Invoke-Deploy.ps1
```

Needs `Microsoft.Graph.Authentication` and `DeviceManagementConfiguration.ReadWrite.All`.
It uses `Invoke-MgGraphRequest` against `/beta`, so the huge `Microsoft.Graph.Beta` module
is not required.

**It creates packages but never assigns them.** Creating a package is inert; assigning one
is what makes it run on real hardware. Assignment is left to the portal deliberately, so a
scripting mistake here can never fire `Stack Reset` at the fleet.

### 3. Baseline before you touch the broken device

Assign the fingerprint package to a pilot group containing **one known-good laptop of the
same model** and capture its output. Diffing against that baseline is the method - see
RUNBOOK.md.

### 4. Pull results back

```bash
pwsh -File deploy/Get-RemediationResults.ps1 -PackageName 'Network Triage - Fingerprint (SYSTEM)' -OutFile triage.csv
```

Read-only, needs `DeviceManagementConfiguration.Read.All`. Parses the fingerprint into
columns so you can sort a whole fleet by `THRU_s1`.

---

## Design notes

**Output budget.** Intune truncates detection output at 2048 characters and the `VERDICT`
line is emitted last, so an overlong fingerprint loses exactly the field that matters.
`tests/Test-Fingerprint.ps1` asserts a deliberately worst-case device stays under the cap.
Rows that did truncate are flagged in the CSV rather than silently misparsed.

**Bandwidth.** The probe is both time-boxed (8 s) and byte-capped (25 MB) per test, so a
fast link stops on bytes and a slow link stops on time - bounded in both directions. It
skips entirely on metered connections and on low battery, and a 4-hour cooldown marker
stops a recurring schedule re-probing endlessly. A skipped probe reports `NO_PROBE` with the
reason; it is never reported as healthy.

**No reboots.** Microsoft forbids reboot commands in detection and remediation scripts, and
a surprise reboot is exactly the disruption this kit avoids. `Stack Reset` writes a
`PendingReboot` marker under `HKLM:\SOFTWARE\NetworkFix`; issue the reboot with the Intune
Restart action or let it land naturally.

**Two things are deliberately not automated:**
- **Filter Driver Audit has no remediation.** Auto-unbinding a filter driver can sever
  connectivity on a remote device, and the right fix depends on which product it is.
- **WLAN Profile Refresh never deletes the active profile.** The obvious implementation
  (delete, let Intune re-push) can strand a remote laptop: between the delete and the next
  sync there is no profile, no Wi-Fi, and therefore no sync. It refreshes in place instead.
  Less thorough, and correct when nobody can touch the device.

**Bandwidth Managers uses an exact-match allowlist, in two tiers.** SmartByte and the Killer
suite are removed. Dell Optimizer and SupportAssist are *reported only* - they also own
thermal, battery and audio, and yanking a fleet-managed suite to chase a network fault is
collateral damage. Detection doubles as the dry run.

**Device Query cannot diagnose this fault.** The Intune data platform has no entity exposing
Wi-Fi link state, RX/TX rate, adapter counters, or TCP settings. `NetworkAdapter` is
inventory / multi-device only and on Windows carries just `Identifier`, `Manufacturer` and
`Type`. That is why the fingerprint is a script. The queries in `queries/` cover the narrow
questions Device Query *can* answer in seconds - driver version, running bandwidth managers,
inline inspection services, WLAN event errors.

---

## Known limitations

- **Locale.** `netsh wlan` and `netsh int tcp` output is localised; the parsers match
  English labels. On a non-English OS the affected fields emit `?` rather than a wrong
  value - visibly missing, not silently incorrect.
- **Probe endpoint reachability.** If every endpoint is blocked by proxy or firewall the
  run reports `ep=none` and `skip=noendpoint`. Edit `$ProbeEndpoint` in the detection script
  to something inside your allowlist.
- **`Get-NetAdapterStatistics` counters are cumulative since boot**, so `rxdisc` on a
  long-uptime device looks alarming without being so. Compare against the baseline, and
  prefer the `retx` ratio, which is normalised.
- **Wi-Fi Driver Update needs Dell Command | Update** installed; it reports `dcu=missing`
  otherwise.
- Requires Windows Enterprise E3/E5 (or equivalent) for Remediations; Device Query
  additionally requires the Intune Suite add-on.

## Tests

```bash
pwsh -NoProfile -File tests/Test-Fingerprint.ps1
```
