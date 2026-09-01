<#
.SYNOPSIS
    Applies Dell network driver updates only, with reboot suppressed.
.DESCRIPTION
    Scoped to -updateDeviceCategory=network so nothing else on the machine moves.
    Records the before/after driver version so the effect is measurable rather than
    assumed - re-run the triage probe afterwards and compare THRU.

    -reboot=disable is mandatory here: Microsoft forbids reboots from remediation
    scripts, and an unannounced reboot is exactly the user disruption this kit avoids.
    A driver swap usually applies live; where a reboot is genuinely required the
    detection script reports 'rebootpending' on its next run.
.NOTES
    Context: SYSTEM. 64-bit host. Contains no reboot command.
#>
$ErrorActionPreference = 'SilentlyContinue'

$paths = @(
    "$env:ProgramFiles\Dell\CommandUpdate\dcu-cli.exe"
    "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe"
    "$env:ProgramFiles\Dell\CommandUpdate\CLI\dcu-cli.exe"
)
$dcu = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $dcu) { Write-Output 'DRV_UPD|dcu=missing'; exit 0 }

function Get-WifiDriverVersion {
    (Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='NET'" |
        Where-Object { $_.DeviceName -match 'Wi-?Fi|Wireless|802\.11' } |
        Select-Object -First 1).DriverVersion
}

$before = Get-WifiDriverVersion
$log    = Join-Path $env:ProgramData 'NetworkFix\dcu-apply.log'
$null   = New-Item -ItemType Directory -Path (Split-Path $log) -Force

$p = Start-Process -FilePath $dcu -Wait -PassThru -WindowStyle Hidden -ArgumentList @(
    '/applyUpdates', '-updateType=driver', '-updateDeviceCategory=network',
    '-reboot=disable', '-silent', "-outputLog=$log"
)

Start-Sleep -Seconds 5
$after = Get-WifiDriverVersion

Write-Output "DRV_UPD|applied|rc=$($p.ExitCode)|before=$before|after=$after"
exit 0
