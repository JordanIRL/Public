<#
.SYNOPSIS
    Sets the Wi-Fi radio to maximum performance and disables device power-down.
.DESCRIPTION
    Idempotent. Only writes settings that are actually wrong.

    USER-PERCEPTIBLE: changing an adapter advanced property restarts the adapter,
    which drops the Wi-Fi connection for a few seconds. Everything else here applies
    live. The adapter-property write is therefore last, and is skipped entirely when
    that property is already correct.
.NOTES
    Context: SYSTEM. 64-bit host. Contains no reboot command.
#>
$ErrorActionPreference = 'SilentlyContinue'

$adapter = Get-NetAdapter -Physical |
    Where-Object { $_.Status -eq 'Up' -and ($_.PhysicalMediaType -match '802.11' -or $_.MediaType -eq 'Native 802.11') } |
    Select-Object -First 1

if (-not $adapter) { Write-Output 'WIFI_PWR|noadapter'; exit 0 }

$changed = @()

# 1. Non-disruptive: adapter power-down flag.
$pm = Get-NetAdapterPowerManagement -Name $adapter.Name
if ($pm -and $pm.AllowComputerToTurnOffDevice -eq 'Enabled') {
    $pm.AllowComputerToTurnOffDevice = 'Disabled'
    $pm | Set-NetAdapterPowerManagement
    $changed += 'sleepok:disabled'
}

# 2. Non-disruptive: power plan, both AC and DC. 0 = Maximum Performance.
$sub = '19cbb8fa-5279-450e-9fac-8a3d5fedd0c1'
$set = '12bbebe6-58d6-4636-95bb-3217ef867c1a'
$q   = (powercfg /q SCHEME_CURRENT $sub $set) -join "`n"
$ac  = ([regex]::Match($q, 'Current AC Power Setting Index:\s*0x([0-9a-f]+)', 'IgnoreCase')).Groups[1].Value
$dc  = ([regex]::Match($q, 'Current DC Power Setting Index:\s*0x([0-9a-f]+)', 'IgnoreCase')).Groups[1].Value
if ($ac -and [Convert]::ToInt32($ac, 16) -ne 0) {
    $null = powercfg /setacvalueindex SCHEME_CURRENT $sub $set 0
    $changed += 'plan_ac:maxperf'
}
if ($dc -and [Convert]::ToInt32($dc, 16) -ne 0) {
    $null = powercfg /setdcvalueindex SCHEME_CURRENT $sub $set 0
    $changed += 'plan_dc:maxperf'
}
if ($changed -match 'plan_') { $null = powercfg /setactive SCHEME_CURRENT }

# 3. DISRUPTIVE (brief disconnect): only touched if genuinely wrong.
$ss = Get-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword '*SelectiveSuspend'
if ($ss -and $ss.RegistryValue[0] -ne '0') {
    Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword '*SelectiveSuspend' `
        -RegistryValue 0 -NoRestart:$false
    $changed += 'selsuspend:off(adapter bounced)'
}

if ($changed.Count -eq 0) { Write-Output 'WIFI_PWR|nochange'; exit 0 }
Write-Output ('WIFI_PWR|fixed|' + ($changed -join '|'))
exit 0
