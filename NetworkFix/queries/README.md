# Device Query snippets

Real-time KQL, run from **Devices > Windows > _device_ > Monitor > Device query**.
Requires the Intune Suite / Advanced Analytics add-on and the `Managed Devices/Query` permission.

## What Device Query can and cannot do here

**It cannot diagnose the network fault directly.** The Intune data platform has no entity
exposing Wi-Fi link state, RX/TX rate, adapter counters, or TCP settings. `NetworkAdapter`
exists but is inventory / multi-device only, and on Windows it carries just `Identifier`,
`Manufacturer` and `Type` - no link rate and no throughput.

That is precisely why the fingerprint is a remediation script rather than a query. Device
Query is still the fastest way to answer the narrow questions below, in seconds, with no
script run - so use it to triage before committing to a script.

## Constraints that bite

- Single quotes only on `contains` / `startswith` / `endswith`. The editor suggests double
  quotes; they do not work.
- `!like` is not supported.
- Query input caps at 2048 characters; 15 queries per minute.
- `WindowsRegistry` cannot return 64-bit shared registry keys - so it is NOT a reliable way
  to read the Uninstall hive. Use `Detect-BandwidthManagers.ps1` for that.
- `WindowsDriver` shows in-use drivers only, not installed-but-unused ones.
