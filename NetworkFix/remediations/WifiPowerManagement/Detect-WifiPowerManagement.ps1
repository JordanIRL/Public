<#
.SYNOPSIS
    Detects Wi-Fi radio power-saving settings that degrade the receive path.
.DESCRIPTION
    Aggressive 802.11 power save lets the radio doze between beacons. Buffered
    downstream frames get dropped, which shows up as inbound packet loss and
    collapses download throughput while upload stays healthy.

    Checks three independent places this is configured:
      1. The adapter's "allow the computer to turn off this device" flag
      2. The active power plan's Wireless Adapter power-saving mode (AC and DC)
      3. The driver's own advanced properties (selective suspend, power save profile)
.NOTES
    Context: SYSTEM. 64-bit host. Exit 1 = issue found.
#>
$ErrorActionPreference = 'SilentlyContinue'

$adapter = Get-NetAdapter -Physical |
    Where-Object { $_.Status -eq 'Up' -and ($_.PhysicalMediaType -match '802.11' -or $_.MediaType -eq 'Native 802.11') } |
    Select-Object -First 1

if (-not $adapter) { Write-Output 'WIFI_PWR|noadapter'; exit 0 }

$issues = @()

$pm = Get-NetAdapterPowerManagement -Name $adapter.Name
if ($pm -and $pm.AllowComputerToTurnOffDevice -eq 'Enabled') { $issues += 'sleepok=enabled' }

# SUB_WIRELESSADAPTER / Power Saving Mode. 0 = Maximum Performance.
$sub = '19cbb8fa-5279-450e-9fac-8a3d5fedd0c1'
$set = '12bbebe6-58d6-4636-95bb-3217ef867c1a'
$q   = (powercfg /q SCHEME_CURRENT $sub $set) -join "`n"
$ac  = ([regex]::Match($q, 'Current AC Power Setting Index:\s*0x([0-9a-f]+)', 'IgnoreCase')).Groups[1].Value
$dc  = ([regex]::Match($q, 'Current DC Power Setting Index:\s*0x([0-9a-f]+)', 'IgnoreCase')).Groups[1].Value
if ($ac -and [Convert]::ToInt32($ac, 16) -ne 0) { $issues += "plan_ac=$([Convert]::ToInt32($ac,16))" }
if ($dc -and [Convert]::ToInt32($dc, 16) -ne 0) { $issues += "plan_dc=$([Convert]::ToInt32($dc,16))" }

$ss = Get-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword '*SelectiveSuspend'
if ($ss -and $ss.RegistryValue[0] -ne '0') { $issues += 'selsuspend=on' }

if ($issues.Count -gt 0) { Write-Output ('WIFI_PWR|' + ($issues -join '|')); exit 1 }
Write-Output 'WIFI_PWR|ok'
exit 0
