<#
.SYNOPSIS
    Detects OEM bandwidth-management software that can cap download throughput.
.DESCRIPTION
    Dell SmartByte (Rivet Networks) and the Killer suite deprioritise "non-priority"
    traffic and have a long, well-documented history of pinning downloads to single-digit
    Mbps while leaving upload untouched. That is precisely the fault signature this kit
    exists to resolve.

    TWO TIERS, deliberately:
      REMOVE  - pure bandwidth managers with no other function. Safe to uninstall.
      REPORT  - suites that also own thermal/battery/audio (Dell Optimizer, SupportAssist).
                Flagged, NEVER auto-removed. Yanking a fleet-managed suite to chase a
                network fault is exactly the kind of collateral damage to avoid.

    This detection script doubles as the dry run: it prints precisely what the
    remediation would uninstall, without changing anything.
.NOTES
    Context: SYSTEM. 64-bit host (a 32-bit host misses the native Uninstall hive).
    Exit 1 = a REMOVE-tier product is present.
#>
$ErrorActionPreference = 'SilentlyContinue'

$RemoveTier = @(
    'SmartByte Drivers and Services'
    'SmartByte'
    'Killer Control Center'
    'Killer Performance Suite'
    'Intel Killer Performance Suite'
    'Killer Network Manager'
    'Rivet Networks Killer'
)
$ReportTier = @('Dell Optimizer', 'Dell SupportAssist', 'Dell Power Manager')

$hives = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$installed = Get-ItemProperty $hives | Where-Object { $_.DisplayName }

$toRemove = @(); $toReport = @()
foreach ($app in $installed) {
    $name = $app.DisplayName.Trim()
    if ($RemoveTier -contains $name) {
        $quiet = if ($app.QuietUninstallString) { 'quiet' }
                 elseif ($app.UninstallString -match '\{[0-9A-Fa-f\-]{36}\}') { 'msi' }
                 else { 'MANUAL' }
        $toRemove += "$name($quiet)"
    }
    elseif ($ReportTier | Where-Object { $name -like "$_*" }) { $toReport += $name }
}

$out = @()
if ($toRemove) { $out += 'remove=' + ($toRemove -join ';') }
if ($toReport) { $out += 'report=' + ($toReport -join ';') }
if (-not $out)  { $out += 'none' }

Write-Output ('BW_MGR|' + ($out -join '|'))
if ($toRemove.Count -gt 0) { exit 1 }
exit 0
