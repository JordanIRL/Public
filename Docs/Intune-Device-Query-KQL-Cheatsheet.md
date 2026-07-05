# Intune Device Query (multiple devices) — KQL Cheatsheet

A practical reference for **Devices → Device query** in the Intune admin center, focused on getting a
broad view of your fleet fast: querying by **model, OS, and manufacturer**, plus combined/aggregate queries.

> Scope: this is the **"Device query for multiple devices"** feature (KQL across collected inventory).
> It uses only a *subset* of Kusto Query Language. Every operator, table, column, and limit below is
> verified against Microsoft Learn (links in §10). Where the docs disagree with themselves, it's flagged.

---

## 0. Fast fleet health check (paste these in, top to bottom)

Run this set whenever you want a 60-second read on the estate. Highlight one statement and click **Run**
to execute just that one.

```kusto
// 1) Headcount + ownership split in a single row
Device
| summarize Total = count(),
            Corporate = countif(Ownership == "Corporate"),
            Personal  = countif(Ownership == "Personal")
```
```kusto
// 2) Devices per platform
OsVersion
| summarize DeviceCount = count() by OsName
| order by DeviceCount desc
```
```kusto
// 3) Top 25 models in use
Device
| summarize DeviceCount = count() by Manufacturer, Model
| order by DeviceCount desc
| take 25
```
```kusto
// 4) OS version spread per platform (spot stragglers on old builds)
OsVersion
| summarize DeviceCount = count() by OsName, OsVersion
| order by OsName asc, DeviceCount desc
```
```kusto
// 5) Stale devices — not checked in for 30+ days
Device
| where LastSeenDateTime < ago(30d)
| project DeviceName, Manufacturer, Model, OSVersion, LastSeenDateTime
| order by LastSeenDateTime asc
```

---

## 1. The mental model (read this first)

1. **You query a *table* (Microsoft calls them "entities").** A query always *starts* with a table name,
   then pipes (`|`) the data through operators that filter / shape / aggregate it.

   ```kusto
   TableName
   | where SomeColumn == "value"
   | project ColumnA, ColumnB
   | order by ColumnA asc
   ```

2. **`Device` is the table you'll use most.** It has one row per managed device and carries the core
   identity fields: `DeviceName`, `Manufacturer`, `Model`, `OSVersion`, `Ownership`, etc. For "all devices
   by model/OS/manufacturer", start here.

3. **Every other table is auto-linked to `Device`.** When you query a hardware table (e.g. `Cpu`,
   `Battery`, `EncryptableVolume`), each row already knows its device — reference it as `Device.Model`,
   `Device.SerialNumber`, etc. **You rarely need a `join`** just to get the model/OS — it's already there.
   Use `join` only to combine *two different* inventory tables on the same device.

   > ⚠️ **Bare `Device` means `Device.DeviceId`, not the name.** `where Device == "PC-01"` matches on the
   > *ID* and usually returns nothing; `order by Device` sorts by ID. Always filter/sort on an explicit
   > property — `Device.DeviceName`, `Device.Model`, etc. (The default results *column* shows the friendly
   > name, but in query logic `Device` resolves to the ID.)

4. **`Device` has no platform/OS-name field.** To split the fleet by *platform* (iOS vs iPadOS vs Windows
   vs Android vs macOS), use the **`OsVersion`** table's `OsName` column instead.

5. **The left pane is the source of truth for names.** In the query UI, expand the left pane to browse
   every table and property; clicking one inserts the **exact** name. KQL is **case-sensitive on table and
   column names**, so when in doubt, click rather than type.

6. **This is inventory data, not live — and it can be days old.** Multi-device query reads the collected
   inventory snapshot, not the device right now. The **initial** collection after enrollment/policy can
   take **up to 24 hours**, and hardware/software inventory refreshes roughly **every ~7 days** from
   enrollment (devices also do maintenance check-ins ~every 8 hours). So treat values as potentially
   several days stale. `LastSeenDateTime` reflects the last check-in; the hardware/OS fields reflect the
   last *inventory* sync, which can be older. For a live read of a single Windows device, use
   *single-device* query (§9).

---

## 2. Quick syntax reference

### Pipe flow
`Table | where … | summarize … | project … | order by … | take …`  — data flows left→right, top→bottom.

### Table operators (the "verbs")
| Operator | What it does |
| --- | --- |
| `where` | Keep only rows matching a condition (filter) |
| `project` | Choose / rename / compute columns to keep |
| `summarize` | Aggregate — counts, sums, group-by |
| `distinct` | Unique combinations of the listed columns |
| `count` | Single number: how many rows (`Device \| count`) |
| `order by` | Sort rows (`asc` / `desc`) — only `order by` is documented here |
| `top N by Col` | First N rows by a column |
| `take N` | Up to N rows (no specific order — for sampling) |
| `join` | Combine two tables on the same device (`… \| join (Other) on Device`) |

### Comparison / string operators
| Operator | Meaning | Example |
| --- | --- | --- |
| `==`  `!=` | Equal / not equal | `Manufacturer == "Apple"` |
| `<` `>` `<=` `>=` | Compare numbers / dates / strings | `MajorVersion >= 14` |
| `contains` / `!contains` | Substring match / no match (case-insensitive) | `Model contains "iPhone"` |
| `startswith` / `endswith` | Prefix / suffix match | `OSVersion startswith "10.0"` |
| `like` | Wildcard match with `%` | `Model like "%Pro%"` |
| `and` `or` | Combine conditions | `… and Ownership == "Corporate"` |

> **String comparisons are case-insensitive** here (per Microsoft's operator examples — `'aBc' == 'AbC'`
> is listed as equal, and `contains` ignores case). So `Manufacturer == "apple"` matches `"Apple"`.
> If you're ever unsure, `contains` is reliably case-insensitive.
> **Table/column *names* are still case-sensitive** — note `Device.OSVersion` (caps "OS") vs the
> `OsVersion` table's `OsVersion` column ("Os").

### Aggregation functions (used inside `summarize`)
`count()` · `countif(predicate)` · `dcount(col)` (distinct count) · `sum()` · `avg()` ·
`min()` / `max()` · `minif()` / `maxif()` · `sumif()` · `percentile(col, n)`

> **Always name your aggregate**: `summarize DeviceCount = count()`. An un-named aggregate (e.g.
> `summarize dcount(DeviceId)`) can break a later `order by` — this is a documented gotcha.

### Scalar functions (handy ones)
`ago(30d)` · `now()` · `bin(value, size)` · `iif(cond, a, b)` · `case(...)` ·
`datetime_diff('day', a, b)` · `datetime_add()` *(no negative amounts)* · `strcat(a, b)` ·
`tostring(x)` · `isnull()` / `isnotnull()` · `substring()` · `strlen()` · `indexof()`

> **Integer math truncates.** `Bytes/(1000*1000*1000)` gives whole GB. For percentages, multiply first:
> `(Free * 100) / Total`.

---

## 3. The `Device` table — your main columns

| Column | Type | Notes |
| --- | --- | --- |
| `DeviceName` | string | Device name |
| `Manufacturer` | string | e.g. `Apple`, `Microsoft Corporation`, `Dell Inc.`, `LENOVO`, `Google` |
| `Model` | string | e.g. `iPhone15,3` or `iPhone 14 Pro`, `Surface Pro 9`, `Latitude 7440` |
| `OSVersion` | string | OS version string (note: **OS** in caps on the Device table) |
| `OSDescription` | string | Full OS edition description |
| `Ownership` | string | e.g. `Corporate` / `Personal` |
| `SerialNumber` | string | Hardware serial |
| `LastSeenDateTime` | date | Last check-in with Intune |
| `EnrolledDateTime` | datetime | When enrolled |
| `EnrollmentProfileName` | string | Assigned enrollment profile |
| `CertExpirationDateTime` | datetime | Mgmt cert expiry |
| `DeviceId` / `EntraDeviceId` | string | Intune ID / Entra ID |
| `ManagementName` | string | Admin-center-only friendly name |
| `PrimaryUserId` / `LastLoggedOnUserId` / `EnrolledByUserId` | string | User GUIDs |
| `DeviceCategoryId` | string | Device category |
| `InCompliancePeriodUntilDateTime` | datetime | Compliance grace period end |

---

## 4. Table (entity) catalog — multi-device

Use these as the **starting table**. Click them in the left pane to get exact names/casing.

### Cross-platform / Apple / Android (inventory auto-collected — no policy needed)
| Table | Key columns | Platforms |
| --- | --- | --- |
| `Device` | DeviceName, Manufacturer, Model, OSVersion, OSDescription, Ownership, SerialNumber, LastSeenDateTime, EnrolledDateTime | All |
| `OsVersion` | **OsName**, **OsVersion**, MajorVersion, MinorVersion, PatchVersion, BuildVersion, Architecture (Win), AndroidSecurityPatchLevel, AppleSupplemental* | All (best for OS breakdowns) |
| `DeviceStorage` | DeviceCapacityBytes, Encrypted (Android) | Android, iOS, iPadOS, macOS |
| `Battery` | Health, CycleCount, InstanceName, Manufacturer, Model, DesignCapacity, FullChargedCapacity, SerialNumber | Android, iOS, iPadOS, macOS, Windows* |
| `NetworkAdapter` | Identifier, MacAddress, Type, Manufacturer (Win), IpAddressV4 (Android) | Android, iOS, iPadOS, macOS, Windows |
| `SimInfo` | Imei, Iccid, Meid, Eid, PhoneNumber, SubscriberCarrierNetwork, CurrentCarrierNetwork, IsRoaming | Android, iOS, iPadOS, (Windows eSIM) |
| `Cellular` | CellularTechnology, DataRoamingEnabled, HotspotEnabled, ModemFirmwareVersion | Android, iOS, iPadOS |
| `Bluetooth` | MacAddress | iOS, iPadOS, macOS |
| `AppleDeviceStates` | Supervised, ActivationLockSupported, MdmLostModeEnabled, SystemIntegrityProtectionEnabled (macOS SIP) | iOS, iPadOS, macOS |
| `AppleUpdateSettings` | AutomaticOSInstallationEnabled, AutomaticSecurityUpdatesEnabled, PreviousScanDateTime | macOS |
| `AppleAutoSetupAdminAccounts` | AccountGUID, AccountShortName | macOS |
| `SharediPad` | IsMultiUser, ResidentUsersCount, EstimatedResidentUsersCount, QuotaSizeBytes | iPadOS |
| `LocalAiAgent` | Discovers local AI-agent software on Windows devices (Copilot/NL2KQL help not available for this entity) | Windows |

\* **Battery caveat:** most capacity columns are Windows-only; on **Android** the rich fields
(`CycleCount`, `Health`, `InstanceName`, `SerialNumber`) report **only on Zebra devices**. `Health` and
`InstanceName` are the most broadly available across platforms.

### Windows-only (require a *Properties Catalog* device-config policy to collect)
| Table | Key columns |
| --- | --- |
| `Cpu` | Architecture, CoreCount, LogicalProcessorCount, Model, Manufacturer, MaxClockSpeed, ProcessorId |
| `MemoryInfo` | PhysicalMemoryTotalBytes, VirtualMemoryTotalBytes |
| `DiskDrive` | Model, Manufacturer, SizeBytes, InterfaceType, SerialNumber, PartitionCount |
| `LogicalDrive` | DriveIdentifier, DriveType, FileSystem, FreeSpaceBytes, DiskSizeBytes |
| `EncryptableVolume` | ProtectionStatus, EncryptionMethod, EncryptionPercentage, WindowsDriveLetter, Locked |
| `Tpm` | Enabled, Activated, Owned, Manufacturer, SpecVersion, ManufacturerVersion |
| `BiosInfo` | Manufacturer, SmBiosVersion, ReleaseDateTime, SerialNumber, BiosName |
| `SystemEnclosure` | SerialNumber, Manufacturer, Model, Sku, SmBiosAssetTag, SecurityBreach *(ChassisTypes NOT supported in multi-device)* |
| `VideoController` | GraphicsModel, AdapterRam, VideoModeDescription, AdapterDacType |
| `WindowsQfe` | HotFixId, InstalledDate, QfeDescription, Caption (security patches/hotfixes) |
| `Time` | TimeZone |

---

## 5. Useful queries

### 5a. Start here — discover the actual values in *your* tenant
Filters must match real strings; vendor spellings vary. Run these first.

```kusto
// What manufacturers do I have, and how many of each?
Device
| summarize DeviceCount = count() by Manufacturer
| order by DeviceCount desc
```
```kusto
// Exact model strings (so your `where` filters match)
Device
| distinct Manufacturer, Model
| order by Manufacturer asc, Model asc
```
```kusto
// What platforms (OS names) exist in this tenant?
OsVersion
| distinct OsName
```

### 5b. Fleet overview

```kusto
// One row per device with the essentials
Device
| project DeviceName, Manufacturer, Model, OSVersion, Ownership, LastSeenDateTime
| order by Manufacturer asc, Model asc
```
```kusto
// Total managed devices
Device | count
```
```kusto
// How many distinct models / manufacturers are in play?
Device
| summarize Models = dcount(Model), Manufacturers = dcount(Manufacturer)
```
```kusto
// Enrollments per day over the last 30 days (trend)
Device
| where EnrolledDateTime > ago(30d)
| summarize Enrolled = count() by bin(EnrolledDateTime, 1d)
| order by EnrolledDateTime asc
```

### 5c. By manufacturer

```kusto
// All devices from one manufacturer
Device
| where Manufacturer == "Apple"
| project DeviceName, Model, OSVersion, SerialNumber, LastSeenDateTime
| order by Model asc
```
```kusto
// Models within a manufacturer, counted
Device
| where Manufacturer contains "Microsoft"
| summarize DeviceCount = count() by Model
| order by DeviceCount desc
```

### 5d. By model

```kusto
// Every device of a given model family
Device
| where Model contains "Surface"
| project DeviceName, Model, OSVersion, SerialNumber, Ownership
| order by Model asc
```
```kusto
// Most common models across the whole fleet
Device
| summarize DeviceCount = count() by Manufacturer, Model
| order by DeviceCount desc
| take 25
```

### 5e. By OS / OS version

```kusto
// OS version spread for the whole fleet
OsVersion
| summarize DeviceCount = count() by OsName, OsVersion
| order by OsName asc, DeviceCount desc
```
```kusto
// Windows versions only
OsVersion
| where OsName == "Windows"
| summarize DeviceCount = count() by OsVersion
| order by OsVersion desc
```
```kusto
// Devices on a specific OS version (iOS 17.x example)
Device
| where OSVersion startswith "17."
| project DeviceName, Manufacturer, Model, OSVersion
```

> **Windows 10 vs 11:** both report `OsName == "Windows"` with versions like `10.0.xxxxx`. Windows 11
> is build **22000+**. Use `MajorVersion`/`MinorVersion` from the `OsVersion` table, or filter the build
> segment of the version string, to separate them.
>
> **macOS note:** `OsName`/`OsVersion` populate for Android, iOS, iPadOS, and Windows; **macOS may not
> populate `OsName`**. Identify Macs via `Device.Model` / `Manufacturer == "Apple"` instead, and run a
> `distinct OsName` first to see what your tenant returns.

### 5f. ⭐ Combined queries (your iPhone example + variants)

**The headline: all iPhone OS versions, with model and a device count.**

```kusto
// iPhone OS versions + model + count (simplest — uses the Device table)
Device
| where Model contains "iPhone"
| summarize DeviceCount = count() by Model, OSVersion
| order by Model asc, DeviceCount desc
```

**Same idea, driven off the OS platform name** (catches all iOS cleanly; pulls model from linked `Device`):

```kusto
OsVersion
| where OsName == "iOS"
| summarize DeviceCount = count() by OsVersion, Device.Model
| order by OsVersion desc
```

**Just the iPhone OS-version distribution (no model split):**

```kusto
Device
| where Model contains "iPhone"
| summarize DeviceCount = count() by OSVersion
| order by OSVersion desc
```

**All Apple mobile devices grouped by model and OS (iPhone + iPad):**

```kusto
Device
| where Model contains "iPhone" or Model contains "iPad"
| summarize DeviceCount = count() by Model, OSVersion
| order by Model asc, OSVersion desc
```

### 5g. Lifecycle / hygiene

```kusto
// Stale devices — not seen in 30+ days
Device
| where LastSeenDateTime < ago(30d)
| project DeviceName, Manufacturer, Model, OSVersion, Ownership, LastSeenDateTime
| order by LastSeenDateTime asc
```
> If a `LastSeenDateTime` date comparison errors in your tenant (it can surface as a string), drop the
> `where` and just `order by LastSeenDateTime asc`, or use `EnrolledDateTime` (a true datetime) for math.

```kusto
// Recently enrolled (last 14 days)
Device
| where EnrolledDateTime > ago(14d)
| project DeviceName, Manufacturer, Model, OSVersion, EnrolledDateTime
| order by EnrolledDateTime desc
```
```kusto
// Management certs expiring in the next 30 days
Device
| where CertExpirationDateTime < now() + 30d
| project DeviceName, Model, CertExpirationDateTime
| order by CertExpirationDateTime asc
```

### 5h. Security / compliance posture

```kusto
// (Windows) Unencrypted volumes — BitLocker not protecting
EncryptableVolume
| where ProtectionStatus != "PROTECTED"
| project Device, WindowsDriveLetter, ProtectionStatus, EncryptionMethod, EncryptionPercentage
```
```kusto
// (Windows) TPM not enabled
Tpm
| where Enabled != true
| project Device, Manufacturer, SpecVersion, Enabled, Activated
```
```kusto
// (Apple) Supervision + activation lock status
AppleDeviceStates
| project Device, Supervised, ActivationLockSupported, MdmLostModeEnabled
```
```kusto
// (macOS) Devices with System Integrity Protection OFF
AppleDeviceStates
| where SystemIntegrityProtectionEnabled == false
| project Device, SystemIntegrityProtectionEnabled
```
```kusto
// (Windows) Recently installed security patches (hotfixes)
WindowsQfe
| project Device, HotFixId, QfeDescription, InstalledDate
| order by InstalledDate desc
```
```kusto
// (Windows) How many devices have each hotfix installed
WindowsQfe
| summarize DeviceCount = dcount(Device.DeviceId) by HotFixId
| order by DeviceCount desc
```

### 5i. Hardware / capacity

```kusto
// (Windows) CPU architecture spread (e.g. find ARM64 devices)
Cpu
| summarize DeviceCount = count() by Architecture
```
```kusto
// (Windows) Low physical memory, in GB
MemoryInfo
| project Device, PhysicalMemoryGB = PhysicalMemoryTotalBytes/(1000*1000*1000)
| where PhysicalMemoryGB < 8
| order by PhysicalMemoryGB asc
```
```kusto
// (Windows) Volumes low on free space (< 10% free)
LogicalDrive
| where DiskSizeBytes > 0
| project Device, DriveIdentifier, FileSystem,
          FreeGB = FreeSpaceBytes/(1000*1000*1000),
          SizeGB = DiskSizeBytes/(1000*1000*1000),
          PercentFree = (FreeSpaceBytes * 100) / DiskSizeBytes
| where PercentFree < 10
| order by PercentFree asc
```
```kusto
// (Apple/Android) Storage capacity, in GB
DeviceStorage
| project Device, StorageGB = DeviceCapacityBytes/(1000*1000*1000)
| order by StorageGB asc
```
```kusto
// Battery health — simplest, broadly available
Battery
| project Device, Manufacturer, Model, Health, CycleCount
| order by CycleCount desc
```
```kusto
// (Windows) Battery capacity health %, worst first
// NOTE: schema lists the design column as `DesignCapacity`; the in-product sample query labels it
// `DesignedCapacity`. If one errors, try the other — confirm the exact name in the left pane.
Battery
| project Device, Model, CycleCount, DesignCapacity, FullChargedCapacity,
          HealthPercent = (FullChargedCapacity * 100) / DesignCapacity
| order by HealthPercent asc
| take 20
```

### 5j. Mobile / cellular inventory

```kusto
// IMEI, phone number, carrier for mobile devices
SimInfo
| project Device, Imei, PhoneNumber, SubscriberCarrierNetwork, IsRoaming
```
```kusto
// (Windows) Asset tags + chassis details
SystemEnclosure
| project Device, SmBiosAssetTag, Manufacturer, Model, Sku, SerialNumber
```
```kusto
// MAC addresses across platforms
NetworkAdapter
| project Device, Identifier, MacAddress, Type, Manufacturer
```

### 5k. `join` — combining two inventory tables on the same device
You only need this to merge *two* inventory tables; model/OS already come free via `Device.`.

```kusto
// Pair BitLocker status with TPM state per Windows device
EncryptableVolume
| project Device, ProtectionStatus
| join (Tpm | project Device, TpmEnabled = Enabled) on Device
| project Device.DeviceName, ProtectionStatus, TpmEnabled
```
> Join rules here: `on Device` is **optional** when joining on the device entity (you can omit it). Do
> *not* use `on Device.DeviceId` — it's deprecated. Max **3 joins** per query. The editor may
> red-underline `$left`/`$right` joins, but they still run.

---

## 5l. Scenario pack — Quick fleet dashboard

Run top-to-bottom for a fast, broad read of the estate. Tuned for **Windows + iOS/iPadOS + Android**, with
**encryption** and **TPM** security tiles (Windows Properties Catalog is collecting). Thresholds (e.g. 30
days) are yours to change.

```kusto
// TILE 1 — Headcount + ownership split (one row)
Device
| summarize Total = count(),
            Corporate = countif(Ownership == "Corporate"),
            Personal  = countif(Ownership == "Personal")
```
```kusto
// TILE 2 — Devices per platform
OsVersion
| summarize Devices = count() by OsName
| order by Devices desc
```
```kusto
// TILE 3 — Top 20 models
Device
| summarize Devices = count() by Manufacturer, Model
| order by Devices desc
| take 20
```
```kusto
// TILE 4 — OS version spread per platform (spot stragglers)
OsVersion
| summarize Devices = count() by OsName, OsVersion
| order by OsName asc, Devices desc
```
```kusto
// TILE 5 — Activity: how many seen recently vs gone quiet
Device
| summarize Total   = count(),
            Last7d  = countif(LastSeenDateTime > ago(7d)),
            Last30d = countif(LastSeenDateTime > ago(30d)),
            Over30d = countif(LastSeenDateTime < ago(30d))
```
> If `LastSeenDateTime` comparisons error (it can surface as a string), use the §5g stale query sorted by
> date instead. Remember inventory itself is ~7-day refresh (§1.6), so "quiet" ≠ offline.

```kusto
// TILE 6 — Encryption posture (Windows / BitLocker): volumes by protection status
EncryptableVolume
| summarize Volumes = count() by ProtectionStatus
```
```kusto
// TILE 6b — ACTIONABLE: unencrypted Windows volumes (→ "Add all items to a group")
EncryptableVolume
| where ProtectionStatus != "PROTECTED"
| project Device, WindowsDriveLetter, ProtectionStatus, EncryptionMethod, EncryptionPercentage
```
```kusto
// TILE 7 — TPM posture (Windows): enabled vs not
Tpm
| summarize Devices = count() by Enabled
```
```kusto
// TILE 7b — TPM spec version spread (2.0 readiness)
Tpm
| summarize Devices = count() by SpecVersion
| order by Devices desc
```
```kusto
// TILE 7c — ACTIONABLE: Windows devices with TPM not enabled (→ group)
Tpm
| where Enabled != true
| project Device, Manufacturer, SpecVersion, Enabled, Activated
```
```kusto
// TILE 8 — Android security patch level spread (security hygiene)
OsVersion
| where OsName == "Android"
| summarize Devices = count() by AndroidSecurityPatchLevel
| order by AndroidSecurityPatchLevel desc
```

---

## 5m. Scenario pack — Apple OS-update compliance (iOS/iPadOS)

Find Apple mobile devices below a target OS. **Use the `OsVersion` table's numeric `MajorVersion`** for the
floor — comparing the version *string* is unreliable (`"9.0"` sorts after `"17.0"`). Set your floor in the
`MajorVersion <` lines (example uses **17**).

```kusto
// A — Adoption: how many iPhones on each major iOS version
OsVersion
| where OsName == "iOS"
| summarize Devices = count() by MajorVersion
| order by MajorVersion desc
```
```kusto
// B — Full iOS/iPadOS version distribution by model (extends your iPhone query)
OsVersion
| where OsName == "iOS" or OsName == "iPadOS"
| summarize Devices = count() by OsName, OsVersion, Device.Model
| order by OsName asc, OsVersion desc
```
```kusto
// C — Below-floor count, by model (who's behind, and on what hardware)
OsVersion
| where (OsName == "iOS" or OsName == "iPadOS") and MajorVersion < 17
| summarize Devices = count() by Device.Model, OsVersion
| order by Devices desc
```
```kusto
// D — ACTIONABLE: devices below the floor (→ "Add all items to a group" for an update policy)
OsVersion
| where (OsName == "iOS" or OsName == "iPadOS") and MajorVersion < 17
| project Device, OsName, OsVersion, MajorVersion
| order by MajorVersion asc
```
```kusto
// E — Rapid Security Response (RSR) state: who's on a supplemental build
OsVersion
| where OsName == "iOS" or OsName == "iPadOS"
| project Device, OsVersion, AppleSupplementalOSVersion
| order by OsVersion desc
```

> Notes: `MajorVersion`/`MinorVersion` are supported for iOS/iPadOS here, so prefer them for any
> version threshold logic. To target a *minor* floor too (e.g. below 17.5), add
> `or (MajorVersion == 17 and MinorVersion < 5)`. macOS is excluded (not in your fleet, and `OsName`
> may not populate for it).

---

## 6. Working with results (admin center)

- **Filter/group in the grid:** when a query returns **≤ 50 rows**, you can search and column-filter the
  results directly. For big result sets, narrow with `where`/`summarize` first.
- **Create a group:** **Add all items to a group** turns results into a Microsoft Entra security group —
  great for targeting a Conditional Access or Intune policy at exactly the devices a query found.
- **Export:** **Export** to CSV (all or selected columns), up to **50,000 rows**.
- **Run part of a query:** highlight one statement and click **Run** to execute just that one. There's no
  built-in saved-query store — keep a personal library of statements in the editor (or your own
  runbook/ITSM KB) and run them individually.
- **Copilot:** the **Copilot** box generates KQL from plain English (e.g. "show me Windows 11 devices",
  "which devices aren't encrypted") — handy for drafting, then refine the KQL by hand. (Copilot can't
  generate queries for the `Local AI Agent` entity.)

---

## 7. Limits & gotchas (multi-device)

- **Subset of KQL only** — the operators/functions in §2 are *all* you get. Common full-KQL features are
  **not** in the documented set: `extend`, `let`, `union`, `parse`, `mv-expand`, regex `matches`,
  `sort by` (use `order by`). Need a computed column? Create it inside `project` (e.g.
  `project GB = Bytes/(1000*1000*1000)`).
- **`Device` is an entity, not a scalar** — you can't `summarize`/`distinct`/`order by` on bare `Device`;
  use a specific property like `Device.Model` or `Device.OSVersion`. Using `Device` inside an aggregation
  red-underlines in the editor; reference a scalar property instead.
- **Name your aggregates** — `summarize DeviceCount = count()`; un-named outputs can break `order by`.
- **Volume caps:** max **~50,000 rows** per query · max **3 joins** · **10 queries/minute** ·
  **1,000 queries/month**.
- **`datetime_add()`** doesn't accept negative amounts (use `ago()` / `-` for going back in time).
- **Coverage:** only **corporate-owned** devices managed by Intune. **Windows** needs a *Properties
  Catalog* policy deployed to collect the hardware tables (Cpu, Tpm, BitLocker, etc.); Apple/Android
  inventory is collected automatically.
- **Licensing:** this is an **Intune Suite / Advanced Analytics add-on** feature.
- **Not real-time:** reflects the last inventory snapshot, not the live device.

### What you *can't* query here (and where it lives)
Multi-device query is **hardware/OS inventory only**. These common asks aren't in the entity set — don't
hunt for them in KQL:

| You want… | Not here — use instead |
| --- | --- |
| Compliance state, grace period detail | **Devices → Monitor → Device compliance** reports (Device query only exposes `InCompliancePeriodUntilDateTime`) |
| Jailbreak / root status | Compliance policy + compliance reports |
| Installed applications | **Discovered apps**, or **device → All Apps → App Inventory** (Windows) |
| Entra group membership | Microsoft Entra / device group blades |
| Primary user name / UPN / email | Device query gives only GUIDs (`PrimaryUserId`, etc.) — resolve in Entra |
| Defender / threat / risk status | Microsoft Defender for Endpoint |
| Config-profile / app deployment status | Per-policy **Monitor** reports |

---

## 8. Common errors → fixes

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Empty results when filtering by model/manufacturer | String doesn't match exactly | Run a `distinct` first (§5a); switch `==` to `contains` |
| `where Device == "PC-01"` returns nothing | Bare `Device` = DeviceId, not name | Use `Device.DeviceName == "PC-01"` |
| Hardware/OS values look out of date | Inventory is ~7-day refresh, 24h initial | Expected — see §1.6; it's not live data |
| `order by` after `summarize` fails | Un-named aggregate | Name it: `DeviceCount = count()` |
| Red underline but query runs | `Device` in aggregation, or `$left`/`$right` join | Cosmetic — use a scalar property to silence it |
| "Too many joins" / query fails | More than 3 joins | Split into multiple queries |
| Windows hardware tables return nothing | No Properties Catalog policy deployed | Deploy the policy; Apple/Android need none |
| Date comparison errors on `LastSeenDateTime` | Surfaced as string | Sort instead, or use `EnrolledDateTime` for math |

---

## 9. Single-device query (real-time) — how it differs

Separate feature: **Devices → (a Windows device) → Monitor → Device Query**. Runs **in real time over
WNS** against **one Windows device** (Entra joined / hybrid joined, corporate-owned). Same KQL subset,
but it exposes **many more entities** that are **NOT available in multi-device**, including:

`Process` · `WindowsService` · `WindowsEvent(Log, lookback)` · `WindowsRegistry('key')` ·
`FileInfo('path')` · `Certificate` · `LocalUserAccount` · `LocalGroup` · `WindowsDriver` ·
`WindowsAppCrashEvent`

Different limits: result truncated at **128 KB**, **15 queries/min**, query input max **2,048 chars**,
`!like` not supported, and `contains`/`startswith`/`endswith` accept **single quotes** only. Use this for
deep, live troubleshooting of a single machine; use **multi-device** (everything above) for fleet trends.

---

## 10. Official references
- Device query for multiple devices: https://learn.microsoft.com/intune/advanced-analytics/device-query-multiple-devices
- Intune Data Platform schema (every table & property): https://learn.microsoft.com/intune/advanced-analytics/ref-data-platform-schema
- Single-device (real-time) query: https://learn.microsoft.com/intune/advanced-analytics/device-query
- Properties Catalog (Windows inventory collection): https://learn.microsoft.com/intune/device-configuration/collect-device-properties
- Query with Copilot in device query: https://learn.microsoft.com/intune/copilot/
- KQL language overview: https://learn.microsoft.com/azure/data-explorer/kusto/query/
