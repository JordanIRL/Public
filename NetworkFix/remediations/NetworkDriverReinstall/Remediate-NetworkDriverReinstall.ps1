<#
.SYNOPSIS
    Removes and re-detects the Wi-Fi adapter, reinstalling its driver from the local
    driver store. Highest-risk pair in the kit.
.DESCRIPTION
    SAFETY DESIGN - read all of this before changing anything below.

    The naive implementation is two lines: remove the device, rescan. On a remote laptop
    those two lines have three separate ways to end in a site visit, and each one is
    handled explicitly here.

    1. The driver package is gone from the store.
       Removal is one-way if there is nothing local to rebind against, and a device with
       no driver has no network to fetch one over. The INF is verified present BEFORE the
       removal, and the check is repeated here rather than trusted from the detection run
       - the two run as separate processes, minutes apart.

    2. The script dies between remove and rescan.
       A one-shot scheduled task is registered FIRST, before anything is removed, and it
       runs 'pnputil /scan-devices' at startup then deletes itself. If this process is
       killed mid-flight the device is one reboot from healthy instead of one visit. It
       is unregistered on success, and deliberately LEFT REGISTERED on failure.

    3. The adapter comes back with a new interface GUID.
       WLAN profiles are stored per interface. A new GUID orphans them: adapter alive,
       driver fine, no profile, no Wi-Fi, no Intune sync, unrecoverable remotely. The
       active profile is exported to disk before removal and re-added afterwards. If the
       export fails and there is no wired fallback, the script ABORTS without touching
       the device - the same reasoning as WLAN Profile Refresh, which never deletes the
       profile carrying the connection.

    NO REBOOT COMMAND. Microsoft forbids reboot commands in remediation scripts. Where
    pnputil reports 3010 the script records REBOOT_REQUIRED and writes the PendingReboot
    marker under HKLM:\SOFTWARE\NetworkFix; issue the reboot with the Intune Restart
    action as with Stack Reset.

    Expect the Intune result upload for this run to be late. The adapter is down for part
    of it, so the device cannot report until its next sync. The script itself keeps
    running locally throughout - a missing result means the sync has not happened yet, it
    does not mean the script stopped.

    Recovery ladder if the adapter does not return: rescan, retry, then an explicit
    'pnputil /add-driver /install' of the stored INF, then the boot watchdog.
.NOTES
    Context: SYSTEM. 64-bit host. Contains no reboot command.
    Runs well inside the Intune 60-minute script timeout - worst case is about 4 minutes.
#>
$ErrorActionPreference = 'SilentlyContinue'

$key = 'HKLM:\SOFTWARE\NetworkFix'
if (-not (Test-Path $key)) { $null = New-Item -Path $key -Force }

$task = 'NetworkFix-DriverRescan'
$work = Join-Path $env:ProgramData 'NetworkFix\wlan'
$null = New-Item -ItemType Directory -Path $work -Force

function Get-WifiAdapter {
    Get-NetAdapter -Physical |
        Where-Object { $_.PhysicalMediaType -match '802.11' -or $_.MediaType -eq 'Native 802.11' } |
        Select-Object -First 1
}

$adapter = Get-WifiAdapter
if (-not $adapter) { Write-Output 'DRV_REINST|abort|adapter=none'; exit 0 }

$drv = Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='NET'" |
    Where-Object { $_.DeviceID -eq $adapter.PnPDeviceID } | Select-Object -First 1
$inf     = $drv.InfName
$infPath = "$env:windir\INF\$inf"
$before  = $drv.DriverVersion
$id      = $adapter.PnPDeviceID

# GATE 1 - never remove a device we cannot rebind locally.
if (-not $inf -or -not (Test-Path $infPath)) {
    Write-Output "DRV_REINST|abort|store=missing|inf=$inf"
    exit 0
}

$wired = @(Get-NetAdapter -Physical | Where-Object {
    $_.Status -eq 'Up' -and $_.PhysicalMediaType -match '802.3' }).Count -gt 0

# GATE 2 - export the active WLAN profile, or abort unless wired covers the risk.
$active = ([regex]::Match(((netsh wlan show interfaces) -join "`n"),
           '^\s*SSID\s*:\s*(.+)$', 'IgnoreCase,Multiline')).Groups[1].Value.Trim()
$xml = $null
if ($active) {
    $null = netsh wlan export profile name="$active" folder="$work" key=clear
    $xml  = Get-ChildItem -Path $work -Filter '*.xml' |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
if (-not $xml -and -not $wired) {
    Write-Output "DRV_REINST|abort|profile=noexport|ssid=$active|wired=no"
    exit 0
}

# GATE 3 - boot watchdog, registered BEFORE the removal so a mid-flight death is survivable.
$cmd = "pnputil /scan-devices; Unregister-ScheduledTask -TaskName '$task' -Confirm:`$false"
$act = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"$cmd`""
$null = Register-ScheduledTask -TaskName $task -Action $act `
        -Trigger (New-ScheduledTaskTrigger -AtStartup) `
        -Principal (New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest) -Force
$watchdog = [bool](Get-ScheduledTask -TaskName $task)

$steps = @("export=$(if ($xml) { 'ok' } else { 'none' })", "watchdog=$(if ($watchdog) { 'armed' } else { 'FAILED' })")

# --- past this point the adapter may be down. Everything below is recovery. ---

$null = pnputil.exe /remove-device "$id"
$rc = $LASTEXITCODE
$steps += "remove=$(if ($rc -in 0, 3010) { 'ok' } else { "rc$rc" })"
$rebootNeeded = ($rc -eq 3010)

$null = pnputil.exe /scan-devices
$steps += 'rescan=1'

function Wait-ForAdapter {
    param([int] $Seconds = 60)
    foreach ($i in 1..([math]::Ceiling($Seconds / 3))) {
        Start-Sleep -Seconds 3
        $a = Get-WifiAdapter
        if ($a) { return $a }
    }
    $null
}

$adapter = Wait-ForAdapter -Seconds 60

# Recovery 1 - a second rescan. PnP occasionally needs the nudge twice.
if (-not $adapter) {
    $null = pnputil.exe /scan-devices
    $steps += 'rescan=2'
    $adapter = Wait-ForAdapter -Seconds 60
}

# Recovery 2 - force the stored package back in explicitly.
if (-not $adapter) {
    $null = pnputil.exe /add-driver "$infPath" /install
    $steps += "adddriver=rc$LASTEXITCODE"
    $null = pnputil.exe /scan-devices
    $adapter = Wait-ForAdapter -Seconds 60
}

if (-not $adapter) {
    # Watchdog stays registered on purpose - a reboot is now the recovery path.
    Set-ItemProperty -Path $key -Name 'LastDriverReinstallUtc' `
        -Value ((Get-Date).ToUniversalTime().ToString('o')) -Force
    $null = New-Item -Path "$key\PendingReboot" -Force
    Write-Output ('DRV_REINST|FAILED|adapter=absent|' + ($steps -join '|') +
                  '|watchdog=left-armed|REBOOT_REQUIRED')
    exit 0
}

# Adapter is back. Restore the WLAN profile - the export may now belong to a new GUID.
if ($xml) {
    $r = (netsh wlan add profile filename="$($xml.FullName)" user=all) -join ' '
    $steps += "profile=$(if ($r -match 'added|is added') { 'restored' } else { 'FAILED' })"
    Remove-Item $xml.FullName -Force   # contains the key in clear text
}

# Give the supplicant a chance to associate before reporting link state.
$up = $false
foreach ($i in 1..20) {
    Start-Sleep -Seconds 3
    $a = Get-WifiAdapter
    if ($a -and $a.Status -eq 'Up') { $up = $true; break }
}

if ($up) {
    Unregister-ScheduledTask -TaskName $task -Confirm:$false
    $steps += 'watchdog=cleared'
} else {
    $steps += 'watchdog=left-armed'
}

$after = (Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='NET'" |
    Where-Object { $_.DeviceID -eq (Get-WifiAdapter).PnPDeviceID } | Select-Object -First 1).DriverVersion

Set-ItemProperty -Path $key -Name 'LastDriverReinstallUtc' `
    -Value ((Get-Date).ToUniversalTime().ToString('o')) -Force
if ($rebootNeeded) { $null = New-Item -Path "$key\PendingReboot" -Force }

Write-Output ("DRV_REINST|done|link=$(if ($up) { 'up' } else { 'DOWN' })|" +
              "before=$before|after=$after|" + ($steps -join '|') +
              $(if ($rebootNeeded) { '|REBOOT_REQUIRED' } else { '' }))
exit 0
