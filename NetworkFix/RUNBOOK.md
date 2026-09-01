# Network Triage Runbook

**Time-box: 25 minutes of automated collection. No manual trial-and-error at any step.**

The point of this runbook is to reach one of three outcomes fast: a named cause you can
fix, a measured confirmation the fix worked, or a defensible "this is hardware, stop
touching software." Anything else means the fingerprint is incomplete, not that you should
start guessing.

---

## Step 0 - Fire the free stuff first (T+0, ~30 seconds of your time)

Do these together before anything else. Both are silent and neither needs the user.

1. **Collect diagnostics** on the affected device (Devices > _device_ > Collect diagnostics).
   You get, with no scripting at all:
   - `wlan-report-latest.html` - three days of Wi-Fi sessions, disconnects, signal history
   - `pnputil /enum-drivers` - exact Wi-Fi driver version
   - both Uninstall registry hives - reveals SmartByte / Killer / Dell Optimizer / VPN / AV
   - `ipconfig /all`, `netsh winhttp show proxy`, `dsregcmd /status`

2. **Run remediation on-demand**: `Network Triage - Fingerprint (SYSTEM)`.

3. **Capture a baseline** from a known-good laptop of the same model. Do not skip this.

> **The baseline is the whole method.** A fingerprint on its own needs interpretation.
> A fingerprint *diffed against a healthy machine of the same model* usually just shows
> you the answer. Keep baselines per model; they are reusable forever.

---

## Step 1 - Read the verdict (T+10)

The detection output ends with `VERDICT|<NAME>|conf=<level>`.

| Verdict | What the evidence showed | Do this |
|---|---|---|
| `TCP_WINDOW` | Auto-tuning not normal; parallel streams recovered throughput | Run **TCP Autotuning**. No reboot, no disconnect. |
| `HARD_CAP` | Parallel streams changed nothing; loss low; PHY healthy | Run **Bandwidth Managers** (detection first - it is the dry run), then **Filter Driver Audit**. |
| `RX_LOSS_RADIO` | Retransmits/discards high, PHY rate healthy, parallel recovered | Run **Wi-Fi Driver Update**. Then go to the Stopping Rule. |
| `RADIO_LINK` | PHY rate low and signal weak | Run **Wi-Fi Power Management**, then **WLAN Profile Refresh**. |
| `HEALTHY` | Probe measured normal throughput | Not reproducing right now. Deploy the **USER** probe and schedule the SYSTEM one daily. |
| `NO_PROBE` | Probe was skipped - read the `skip=` reason | metered / battery / cooldown / no endpoint. Re-run once the reason clears. |
| `INCONCLUSIVE` | Thresholds not met cleanly | Diff against the baseline manually. Do not start guessing. |

### Reading the fingerprint yourself

The `THRU` line carries the discriminator:

```
THRU|s1=3.1|s8=22.4|ratio=7.2|ep=speed.cloudflare.com
      |      |       |
      |      |       +-- ratio >> 1 : per-connection limit (loss or receive window)
      |      |           ratio ~= 1 : aggregate cap (software, policy, or driver)
      |      +---------- 8 parallel streams
      +----------------- single stream, what the user actually experiences
```

`ratio` is the single most informative number in the whole output. A `NO_PROBE` verdict
means you do not have it, and without it you are guessing again - clear the skip reason
before going further.

---

## Step 2 - Apply exactly one fix (T+15)

One pair, then re-measure. Never stack two fixes before measuring; that is how you end up
not knowing which one worked, and it is the habit this kit exists to break.

**User impact of each pair** - only two can be felt at all, and both only briefly:

| Pair | Impact |
|---|---|
| TCP Autotuning | None. Applies live. |
| Bandwidth Managers | None, unless the product needs a reboot to release its filter driver. |
| Filter Driver Audit | None. Report-only. |
| Wi-Fi Driver Update | Usually none; brief link drop during driver swap. |
| **Wi-Fi Power Management** | **Few seconds offline** *only if* selective suspend was wrong. |
| **WLAN Profile Refresh** | **Few seconds offline** during the in-place profile refresh. |
| Stack Reset | None immediately, but **requires a reboot** to fully apply. |

---

## Step 3 - Prove it (T+25)

Re-run `Network Triage - Fingerprint (SYSTEM)` on-demand and compare `THRU`.

> **A remediation that reports success without moving `THRU` has not fixed anything.**
> Record the before/after numbers on the ticket. That is the difference between "I did
> some things and the user stopped complaining" and knowing what happened.

If `THRU` moved and the user agrees, close it. If not, go to the Stopping Rule.

---

## The Stopping Rule

**Stop doing software fixes when all of these hold:**

- Verdict is `RX_LOSS_RADIO`
- The Wi-Fi driver update did not move `THRU`
- `SW` shows no bandwidth managers and `FILT` shows no unexpected bindings
- The pattern reproduces across several different `bssid` values (multiple APs/locations)
- `PHY` shows healthy `rxrate` alongside elevated `rxdisc` / `retx`, with normal transmit

That combination - the radio negotiating a fast rate, transmitting fine, and dropping
inbound frames, everywhere, with a clean software profile - is the remote signature of a
degraded receive chain. Antenna lead or radio silicon.

**Open a Dell warranty case and attach the fingerprint.** The fingerprint is what makes
that a substantiated hardware claim rather than "we tried some things and gave up."

### What you genuinely cannot rule out remotely

Antenna seating and radio silicon. No amount of further scripting changes this, and
neither reset option helps:

| Action | Keeps Wi-Fi profiles | Keeps driver store | Removes OEM apps | Effect on this fault |
|---|---|---|---|---|
| **Autopilot Reset** | Yes | Yes | No | **Will not help.** Preserves Wi-Fi details and SCEP certs; Intune re-pushes identical policy. |
| **Fresh Start** (retain user data) | No | Partial | **Yes** | The only reset that clears OEM bandwidth managers. Stays Entra-joined, auto re-enrolls. |
| **Wipe** | No | No | Yes | Full OOBE. Longest path, last resort. |

If the fingerprint says `HARD_CAP` and the targeted uninstall failed, **Fresh Start** is the
justified escalation. For every other verdict, resetting is motion without progress.

---

## When the SYSTEM probe says HEALTHY but the user insists

Deploy `Network Triage - Fingerprint (USER)`. SYSTEM has no per-user WinINET/PAC proxy
config, so a user-context-only fault is invisible to the SYSTEM probe *by construction* -
a HEALTHY verdict does not contradict the user, it narrows where to look.

Compare `THRU|s1` between the two runs:

- **user << system** - the network stack is fine. Look at the user-scoped proxy
  (`PROXY` / `EFFPROXY` lines), a per-user security product, or browser policy.
- **user ~= system** - machine-wide. Trust the SYSTEM fingerprint, and schedule the probe
  daily to catch it when it next reproduces.
