<#
.SYNOPSIS
    Detects an available Dell network driver update via Dell Command | Update CLI.
.DESCRIPTION
    Dell's OEM Wi-Fi driver releases routinely lag Intel's generic ones by months, and
    specific AX201/AX211 driver builds produce exactly this fault: healthy PHY rate and
    transmit, collapsed receive throughput.

    Scans the NETWORK device category ONLY. A blanket driver update on a user's laptop
    is a far bigger change than this ticket justifies.

    dcu-cli scan exit codes:
      0   updates are available
      500 no updates found
      1   reboot required to complete a previous action
      2   fatal error
      501 scan could not be performed
.NOTES
    Context: SYSTEM. 64-bit host. Exit 1 = a network driver update is available.
#>
$ErrorActionPreference = 'SilentlyContinue'

$paths = @(
    "$env:ProgramFiles\Dell\CommandUpdate\dcu-cli.exe"
    "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe"
    "$env:ProgramFiles\Dell\CommandUpdate\CLI\dcu-cli.exe"
)
$dcu = $paths | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $dcu) { Write-Output 'DRV_UPD|dcu=missing'; exit 0 }

$log = Join-Path $env:ProgramData 'NetworkFix\dcu-scan.log'
$null = New-Item -ItemType Directory -Path (Split-Path $log) -Force

$p = Start-Process -FilePath $dcu -Wait -PassThru -WindowStyle Hidden -ArgumentList @(
    '/scan', '-updateType=driver', '-updateDeviceCategory=network', "-outputLog=$log"
)

$ver = (Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='NET'" |
        Where-Object { $_.DeviceName -match 'Wi-?Fi|Wireless|802\.11' } |
        Select-Object -First 1).DriverVersion

switch ($p.ExitCode) {
    0   { Write-Output "DRV_UPD|available|cur=$ver"; exit 1 }
    500 { Write-Output "DRV_UPD|current|cur=$ver";   exit 0 }
    1   { Write-Output "DRV_UPD|rebootpending";      exit 0 }
    default { Write-Output "DRV_UPD|scanfail=$($p.ExitCode)"; exit 0 }
}
