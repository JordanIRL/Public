# Intune Device Query — Useful KQL Commands

A practical, copy‑paste library of Kusto Query Language (KQL) queries for **Intune Device Query** (the **Advanced Analytics** capability in the Intune Suite / Intune Suite add‑on).

Every entity and property name below is taken from Microsoft's **Intune data platform schema** (links at the bottom). Where Microsoft's own docs disagree, it's called out inline. The in‑product **property picker** (left pane) is always the final word for your tenant.

---

## 1. Two flavors of Device Query — know which one you're in

| | **Single‑device query** (real‑time) | **Device query for multiple devices** (fleet) |
|---|---|---|
| Where | **Devices > Windows > [pick a device] > Monitor > Device query** | **Devices > Device query** |
| Platforms | **Windows only** | Windows, Android (corp AE: COSU/COBO/COPE), iOS/iPadOS, macOS |
| Data source | Live device, on demand (over **WNS** push) | Collected **inventory** (Properties Catalog) |
| Best for | Deep, live troubleshooting of one device | Fleet reporting, trends, building dynamic groups |
| Prereq | Entra joined / hybrid joined, corp‑owned | Corp‑owned; **Windows needs a Properties Catalog inventory policy**. Apple/Android collect automatically |

**Real‑time‑only entities (single‑device):** `Process`, `WindowsService`, `WindowsRegistry`, `WindowsEvent`, `WindowsAppCrashEvent`, `WindowsDriver`, `Certificate`, `FileInfo`, `LocalUserAccount`, `LocalGroup`.

**Shared (both modes):** `Cpu`, `MemoryInfo`, `OsVersion`, `BiosInfo`, `DiskDrive`, `LogicalDrive`, `EncryptableVolume`, `Tpm`, `SystemInfo`, `SystemEnclosure`, `WindowsQfe`.

**Fleet‑only (inventory):** `Battery`, `NetworkAdapter`, `VideoController`, `DeviceStorage`, `Time`, `Bluetooth`, `Cellular`, `SimInfo`, `SharediPad`, `AppleAutoSetupAdminAccounts`, `AppleDeviceStates`, `AppleUpdateSettings`.

> **No "installed apps" entity exists** in device query. For one device, read the app's uninstall registry key (see §4). For fleet app inventory, use **Apps > Discovered apps** instead.

> **Tip:** Use **Copilot in Intune** to turn plain English ("Show me TPM 2.0 devices") into KQL — it only emits supported columns.

---

## 2. Supported operators & functions (the important subset)

Device query supports **only a subset** of KQL — stay inside this list or queries fail.

- **Table operators:** `count`, `distinct`, `join`, `order by`, `project`, `take`, `top`, `where`, `summarize`
  - ⚠️ **No `extend`, `let`, `parse`, `mv-expand`, `render`.** Add computed columns with **`project`**, not `extend`.
- **String/scalar operators:** `== != < > <= >=`, `+ - * / %`, `and` `or`, `contains`/`!contains`, `startswith`/`!startswith`, `endswith`/`!endswith`, `like` (⚠️ `!like` is **not** supported).
- **Aggregations (`summarize`):** `count`, `countif`, `dcount`, `avg`, `min`/`minif`, `max`/`maxif`, `sum`/`sumif`, `percentile`.
- **Scalar functions:** `ago`, `now` (no offset), `datetime_add` (⚠️ no negative amounts), `datetime_diff`, `bin`, `case`, `iif`, `indexof`, `substring`, `strcat`, `strlen`, `tostring`, `isnull`, `isnotnull`.

> **Single‑device quoting quirk:** for `contains`/`startswith`/`endswith`, use **single quotes** (the editor may wrongly suggest double quotes). `==` is fine with double quotes. Fleet sample queries use double quotes throughout.

---

## 3. The `Device` entity (fleet queries)

In **multiple‑device** queries every entity auto‑joins to a `Device` entity, so you get device context free.

- Bare `Device` resolves to **`Device.DeviceId`** (the grid shows the friendly name, but filter/sort uses the ID).
- Filter/sort by name with `Device.DeviceName`.
- `Device` is an entity type — don't put bare `Device` in `summarize`/`distinct`/`order by`; use a scalar property.
- **Joins:** join `on Device` (`on Device.DeviceId` is no longer supported). Max **3 joins**/query.

```kusto
Cpu
| where Device.DeviceName == "FINANCE-LT-014"
```

`Device` properties: `DeviceName`, `SerialNumber`, `Manufacturer`, `Model`, `OSDescription`, `OSVersion`, `Ownership`, `EnrolledDateTime`, `CertExpirationDateTime`, `LastSeenDateTime`, `PrimaryUserId`, `LastLoggedOnUserId`, `EnrollmentProfileName`, `DeviceCategoryId`, `EntraDeviceId`, `DeviceId`, `ManagementName`, `InCompliancePeriodUntilDateTime`, `EnrolledByUserId`.

---

## 4. Single‑device queries (real‑time, Windows)

You're already targeting one device — no device filter needed.

> **Three entities are parameterized** — you must pass an argument: `WindowsRegistry('<key>')`, `FileInfo('<path>')`, `WindowsEvent(<LogName>, <lookback>)`.

### Snapshot
```kusto
SystemInfo
| project ComputerName, FqdnHostname, HardwareManufacturer, HardwareModel, PhysicalProcessorCount, ProcessorArchitecture
```
```kusto
OsVersion
| project OsName, OsVersion, MajorVersion, MinorVersion, BuildVersion, Architecture, InstallDateTime
```

### Processes
```kusto
// Top 10 processes by memory (private working set)
Process
| project ProcessName, ProcessId, WorkingSetSizeBytes, Path
| top 10 by WorkingSetSizeBytes desc
```
```kusto
// Top 10 by CPU time
Process
| project ProcessName, ProcessId, ProcessorTimePercent, Path
| top 10 by ProcessorTimePercent desc
```
```kusto
// Is a process running? (single quotes for contains on single-device)
Process
| where ProcessName contains 'Teams'
| project ProcessName, ProcessId, Path, CommandLine, WindowsUserAccount
```

### Windows services
```kusto
// All services and state
WindowsService
| project ServiceName, DisplayName, State, StartMode, Path
| order by ServiceName asc
```
```kusto
// Auto-start services that are NOT running (note UPPERCASE values)
WindowsService
| where StartMode == "AUTO_START" and State != "RUNNING"
| project ServiceName, DisplayName, State, StartMode, Path
```
```kusto
// Is Microsoft Defender Antivirus running?
WindowsService
| where ServiceName == "WinDefend"
| project ServiceName, DisplayName, State, StartMode
```
```kusto
// Intune Management Extension health
WindowsService
| where ServiceName == "IntuneManagementExtension"
| project ServiceName, DisplayName, State, StartMode
```

### Patches / hotfixes (QFE)
```kusto
// Installed updates, newest first
WindowsQfe
| project HotFixId, Caption, QfeDescription, InstalledDate
| order by InstalledDate desc
```
```kusto
// Is a specific KB installed?
WindowsQfe
| where HotFixId == "KB5034123"
```

### Drivers
```kusto
// Drivers grouped by provider
WindowsDriver
| summarize Count = count() by ProviderName
| order by Count desc
```
```kusto
// Display adapters and driver versions
WindowsDriver
| where Class == "Display"
| project FriendlyName, ProviderName, DriverVersion, BuildDate, Signed
```

### Certificates
```kusto
// Certs expiring in the next 30 days
Certificate
| where ValidToDateTime < datetime_add('day', 30, now())
| project SubjectName, Issuer, ValidToDateTime, StoreName, SerialNumber
| order by ValidToDateTime asc
```

### App crashes & event log
```kusto
// Recent application crashes
WindowsAppCrashEvent
| project LoggedDateTime, AppName, AppVersion, AppPath, WindowsUserAccount
| order by LoggedDateTime desc
| take 10
```
```kusto
// System log errors in the last day  (param: log name, lookback)
WindowsEvent(System, 1d)
| where Level == "ERROR"
| project LoggedDateTime, ProviderName, EventId, Message
| order by LoggedDateTime desc
```

### Files
```kusto
// Check a file's version  (param: file path)
FileInfo('C:\\Program Files\\Contoso\\app.exe')
| project FileName, FileVersion, ProductVersion, ProductName, LastModifiedDateTime
```
```kusto
// 20 most-recently-created files in a folder  (param: directory = recurses)
FileInfo('C:\\Windows\\Temp')
| project FileName, Path, SizeBytes, CreatedDateTime
| top 20 by CreatedDateTime desc
```

### Local accounts & groups (privilege audit)
```kusto
LocalUserAccount
| project Username, UserDescription, HomeDirectory, WindowsSid
```
```kusto
LocalGroup
| project GroupName, GroupId, WindowsSid
```

### Registry (config & app‑version checks)
```kusto
// Read values under a key  (param: full key path; use double backslashes)
WindowsRegistry('HKEY_LOCAL_MACHINE\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate')
| project RegistryKey, ValueName, ValueType, ValueData
```
```kusto
// App name + version from an uninstall key (stands in for "installed apps")
WindowsRegistry('HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall')
| where ValueName == "DisplayName" or ValueName == "DisplayVersion"
| project RegistryKey, ValueName, ValueData
```

### Disk, encryption, TPM, BIOS
```kusto
// Free space per logical drive (GB)
LogicalDrive
| project DriveIdentifier, FileSystem,
          FreeGB = FreeSpaceBytes/(1024*1024*1024),
          SizeGB = DiskSizeBytes/(1024*1024*1024)
| order by FreeGB asc
```
```kusto
// BitLocker / encryption status per volume
EncryptableVolume
| project WindowsDriveLetter, ProtectionStatus, EncryptionMethod, EncryptionPercentage, Locked
```
```kusto
// TPM present & enabled?
Tpm
| project Enabled, Activated, Owned, SpecVersion, Manufacturer
```
```kusto
// BIOS / firmware
BiosInfo
| project Manufacturer, SmBiosVersion, ReleaseDateTime, SerialNumber
```

---

## 5. Fleet queries (device query for multiple devices)

### OS, hardware & inventory
```kusto
// Device count by OS version
OsVersion
| summarize DevicesCount = count() by OsVersion
```
```kusto
// Windows 11 devices — adjust the filter to the OsName/OsVersion your tenant reports
OsVersion
| where OsName contains "Windows" and OsVersion contains "11"
| project Device, OsName, OsVersion, Architecture
```
```kusto
// Device count by CPU architecture   (ARM64 / x64 …)
Cpu
| summarize DeviceCount = count() by Architecture
```
```kusto
// ARM64 devices
Cpu
| where Architecture == "ARM64"
```
```kusto
// Top 5 CPUs by core count  (Microsoft shipped sample)
Cpu
| project Device, ProcessorId, Model, Architecture, CpuStatus, ProcessorType,
          CoreCount, LogicalProcessorCount, Manufacturer, AddressWidth
| order by CoreCount asc
| take 5
```
```kusto
// Physical RAM per device (GB), lowest first
MemoryInfo
| project Device, PhysicalMemoryGB = PhysicalMemoryTotalBytes/(1000*1000*1000)
| order by PhysicalMemoryGB asc
```
```kusto
// Devices with less than 16 GB RAM
MemoryInfo
| where PhysicalMemoryTotalBytes < 16000000000
| project Device, PhysicalMemoryGB = PhysicalMemoryTotalBytes/(1000*1000*1000)
| order by PhysicalMemoryGB asc
```
```kusto
// BIOS by manufacturer  (Microsoft shipped sample)
BiosInfo
| where Manufacturer contains "Microsoft"
```
```kusto
// Fleet by model — refresh planning
Cpu
| summarize DeviceCount = count() by Device.Model
| order by DeviceCount desc
```

### Disk space across the fleet
```kusto
// Drives under 10 GB free
LogicalDrive
| where FreeSpaceBytes < 10737418240
| project Device, DriveIdentifier,
          FreeGB = FreeSpaceBytes/(1024*1024*1024),
          SizeGB = DiskSizeBytes/(1024*1024*1024)
| order by FreeGB asc
```

### Security & compliance posture
```kusto
// Unencrypted volumes across the fleet  (Microsoft shipped sample)
EncryptableVolume
| where ProtectionStatus != "PROTECTED"
| join LogicalDrive on Device
```
```kusto
// TPM disabled devices  (Microsoft shipped sample)
Tpm
| where Enabled != true
```
```kusto
// TPM 2.0 devices
Tpm
| where SpecVersion startswith "2.0"
| project Device, SpecVersion, Enabled, Activated
```

### Patch compliance (QFE)
```kusto
// Which devices have a specific KB?
WindowsQfe
| where HotFixId == "KB5034123"
| project Device, HotFixId, InstalledDate
```
```kusto
// Most recent patch per device, oldest first (find lagging devices)
WindowsQfe
| summarize LastPatch = max(InstalledDate) by Device.DeviceName
| order by LastPatch asc
```

### Lifecycle / hygiene
```kusto
// Devices not seen by Intune in 30+ days
// NOTE: Device.LastSeenDateTime is string-typed in the schema; if the comparison
// misbehaves, sort instead (| order by Device.LastSeenDateTime asc) and review.
Device
| where LastSeenDateTime < ago(30d)
| project Device.DeviceName, Device.SerialNumber, LastSeenDateTime, Device.PrimaryUserId
| order by LastSeenDateTime asc
```
```kusto
// Management certs expiring in the next 30 days
Device
| where CertExpirationDateTime < datetime_add('day', 30, now())
| project Device.DeviceName, CertExpirationDateTime
| order by CertExpirationDateTime asc
```
```kusto
// Recently enrolled (last 7 days)
Device
| where EnrolledDateTime > ago(7d)
| project Device.DeviceName, EnrolledDateTime, Device.EnrollmentProfileName
```
```kusto
// Battery health
Battery
| project Device, InstanceName, CycleCount, Health
| order by CycleCount desc
```
```kusto
// Battery charge capacity %  (Microsoft shipped sample — note: the sample uses
// DesignedCapacity, while the schema reference spells it DesignCapacity; if one
// errors, swap to the other)
Battery
| project Device, InstanceName, Manufacturer, Model, SerialNumber, CycleCount,
          DesignedCapacity, FullChargedCapacity,
          FullChargedCapacityPercent = (FullChargedCapacity * 100) / DesignedCapacity
| top 10 by FullChargedCapacityPercent asc
```

### Cross‑platform (Apple / mobile)
```kusto
// Local admin accounts on macOS
AppleAutoSetupAdminAccounts
| project Device, AccountShortName, AccountGUID
```
```kusto
// macOS: System Integrity Protection (SIP) disabled?
AppleDeviceStates
| where SystemIntegrityProtectionEnabled == false
| project Device, SystemIntegrityProtectionEnabled, Supervised
```
```kusto
// Discrete graphics inventory (Windows)
VideoController
| project Device, GraphicsModel, AdapterRam, VideoModeDescription
```

---

## 6. Reusable building blocks

```kusto
// Target by serial number (fleet)
DiskDrive | where Device.SerialNumber == "5CD1234ABC"
```
```kusto
// Count anything
WindowsQfe | where HotFixId == "KB5034123" | count
```
```kusto
// Distinct values (use a scalar property, not bare Device)
OsVersion | distinct OsVersion
```
```kusto
// Devices MISSING something (anti-join): no BitLocker-protected volume
Device
| join kind=leftanti (EncryptableVolume | where ProtectionStatus == "PROTECTED") on Device
| project Device.DeviceName, Device.SerialNumber, Device.PrimaryUserId
```

**From results you can:** export up to **50,000** rows to CSV, and **create an Entra security group** ("Add all items to a group") to target Conditional Access or Intune policy. In **single‑device** query you can also fire **remote actions** (restart, run remediation, etc.) from the results.

---

## 7. Limits & gotchas

**Single‑device query**
- Real‑time over **WNS** — fails if WNS is blocked or the device is offline. Up to **50 concurrent** queries.
- **15 queries/minute**; query text max **2048 chars**; result truncated past **128 KB**.
- `WindowsRegistry` can't return the root key, 64‑bit *shared* keys, or binary value data; `FileInfo` errors if the target file is in use.
- If the user is a local admin, client‑reported values (OS version, registry) can be tampered with.
- If TPM 2.0 is present, `Activated` and `Enabled` always return **TRUE**.

**Device query for multiple devices**
- ~**50,000** rows max; **10 queries/minute**; **1,000 queries/month**; **max 3 joins**/query.
- Name aggregated columns explicitly or sorting fails: `summarize X = dcount(DeviceId) | order by X` (not `order by dcount_DeviceId`).
- Bare `Device` in `summarize`/`order by` may show a red squiggle but usually still runs — prefer a scalar property.
- Windows fleet data needs a deployed **Properties Catalog** policy; Apple/Android auto‑collect. Properties vary by platform.

---

## 8. Licensing & roles

- Requires **Advanced Analytics** (Intune Suite, or the Advanced Analytics add‑on).
- Role: **Help Desk Operator**, or a custom role with **Managed devices/Query** plus read visibility (e.g. Organization/Read, Managed devices/Read).

---

## Sources (Microsoft Learn)

- Device query (single device): https://learn.microsoft.com/intune/advanced-analytics/device-query
- Device query for multiple devices: https://learn.microsoft.com/intune/advanced-analytics/device-query-multiple-devices
- Intune data platform schema (entity/property reference): https://learn.microsoft.com/intune/advanced-analytics/ref-data-platform-schema
- Collect device inventory (Properties Catalog): https://learn.microsoft.com/intune/device-configuration/collect-device-properties
- Copilot in Intune (generate KQL): https://learn.microsoft.com/intune/copilot/
- Advanced capabilities / licensing: https://learn.microsoft.com/intune/fundamentals/advanced-capabilities
