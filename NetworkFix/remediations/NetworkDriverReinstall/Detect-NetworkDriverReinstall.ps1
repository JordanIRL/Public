<#
.SYNOPSIS
    Preflight gate for the Wi-Fi driver reinstall. NEVER ASSIGN THIS PACKAGE ON A SCHEDULE.
.DESCRIPTION
    This is the highest-risk action in the kit - higher than Stack Reset, which needs a
    reboot but cannot strand a device. Removing a Wi-Fi adapter from a laptop that has no
    hands on it and no wired fallback is the one operation here that can end in a site
    visit. So unlike the other detection scripts, this one is a hard preflight: it exits 1
    ONLY when every safety precondition for a survivable reinstall is satisfied.

    Distinct from Wi-Fi Driver Update, which is forward-only. Update fixes "the driver is
    too old". This fixes "the driver is the right version but its installed state is
    wrong" - a corrupt binding, a half-applied update, mangled per-adapter registry
    config - and it is the only path back when the device is already on the newest Dell
    build and that build is the bad one. The README notes specific AX201/AX211 releases
    produce this exact fault; dcu-cli cannot walk backwards off one.

    PRECONDITIONS CHECKED (all must pass):
      os        Build 19041+. 'pnputil /remove-device' does not exist before that.
      adapter   A Wi-Fi adapter is present and Up.
      store     The backing INF is still in the local driver store. This is the critical
                one. Re-detection rebinds from the store with no network involved; if the
                INF is gone, removal is one-way and the adapter does not come back.
      profile   A WLAN profile exists for the active SSID and can be re-added afterwards.
                Removing the device can change the interface GUID, which orphans the
                profiles stored against the old one - adapter alive, no Wi-Fi, stranded.
      reboot    No reboot already pending. Reinstalling on top of a half-applied change
                makes the result unreadable.

    Also reports 'wired=' and 'rollback=' because both change the operator's risk
    calculus: a wired fallback makes this nearly free, and a second driver package in the
    store means a rollback target exists if the reinstall alone does not move THRU.

    A 14-day cooldown - twice Stack Reset's - limits the blast radius if this package is
    ever assigned to a group by mistake.
.NOTES
    Context: SYSTEM. 64-bit host.
    Exit 1 = every precondition passed, remediation is allowed to run.
#>
$ErrorActionPreference = 'SilentlyContinue'

$key  = 'HKLM:\SOFTWARE\NetworkFix'
$last = (Get-ItemProperty -Path $key -Name 'LastDriverReinstallUtc').LastDriverReinstallUtc
if ($last) {
    $age = ((Get-Date).ToUniversalTime() - [datetime]$last).TotalDays
    if ($age -lt 14) {
        Write-Output ("DRV_REINST|cooldown|days={0:N1}" -f $age)
        exit 0
    }
}

$blockers = @()

if ([Environment]::OSVersion.Version.Build -lt 19041) { $blockers += 'os=unsupported' }

$adapter = Get-NetAdapter -Physical |
    Where-Object { $_.Status -eq 'Up' -and ($_.PhysicalMediaType -match '802.11' -or $_.MediaType -eq 'Native 802.11') } |
    Select-Object -First 1

if (-not $adapter) { Write-Output 'DRV_REINST|blocked|adapter=none'; exit 0 }

# Driver package backing THIS device, matched on the exact PnP ID rather than on a name.
$drv = Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='NET'" |
    Where-Object { $_.DeviceID -eq $adapter.PnPDeviceID } | Select-Object -First 1
if (-not $drv) {
    $drv = Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='NET'" |
        Where-Object { $_.DeviceName -match 'Wi-?Fi|Wireless|802\.11' } | Select-Object -First 1
}

# Locale-independent on purpose: this tests the INF is on disk, it does not parse
# pnputil's localised labels. Inbox drivers report a bare name and live in the same folder.
$inf = $drv.InfName
if (-not $inf)                                { $blockers += 'store=noinf' }
elseif (-not (Test-Path "$env:windir\INF\$inf")) { $blockers += 'store=missing' }

$active = ([regex]::Match(((netsh wlan show interfaces) -join "`n"),
           '^\s*SSID\s*:\s*(.+)$', 'IgnoreCase,Multiline')).Groups[1].Value.Trim()
$profiles = @((netsh wlan show profiles) |
    Select-String 'All User Profile\s*:\s*(.+)$' |
    ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() })

$wired = @(Get-NetAdapter -Physical | Where-Object {
    $_.Status -eq 'Up' -and $_.PhysicalMediaType -match '802.3' }).Count -gt 0

# A wired fallback makes an orphaned profile recoverable, so it is only a blocker without one.
if (-not $active)                     { $blockers += 'profile=nossid' }
elseif ($profiles -notcontains $active) { if (-not $wired) { $blockers += 'profile=missing' } }

if (Test-Path "$key\PendingReboot") { $blockers += 'reboot=pending' }

# Rollback target = another Net-class package from the SAME provider, at a different
# version, still staged in the driver store. Counted via Get-WindowsDriver rather than by
# parsing 'pnputil /enum-drivers': pnputil lists every OEM package on the box - printers,
# chipset, dock - so a raw oem*.inf count reports 'available' on essentially any device,
# which is worse than not reporting it at all. ClassName is a fixed string, so this stays
# locale-independent. Reports 'unknown' rather than guessing if the cmdlet is unavailable.
$rollback = 'unknown'
$store = Get-WindowsDriver -Online -All | Where-Object {
    $_.ClassName -eq 'Net' -and $_.ProviderName -eq $drv.DriverProviderName }
if ($null -ne $store) {
    $others = @($store | Where-Object { $_.Version -ne $drv.DriverVersion })
    $rollback = if ($others.Count -gt 0) { "avail($($others.Count))" } else { 'none' }
}

$state = "cur=$($drv.DriverVersion)|inf=$inf|wired=$(if ($wired) { 'yes' } else { 'no' })|rollback=$rollback"

if ($blockers.Count -gt 0) {
    Write-Output ("DRV_REINST|blocked|" + ($blockers -join '|') + "|$state")
    exit 0
}

Write-Output "DRV_REINST|armed|$state"
exit 1
