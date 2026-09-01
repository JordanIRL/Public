<#
.SYNOPSIS
    Silently uninstalls allowlisted OEM bandwidth-management software.
.DESCRIPTION
    Allowlist match is EXACT on DisplayName - no wildcards, no "-like *Killer*".
    A wildcard here would eventually uninstall something it should not.

    Uninstalls only when a silent method genuinely exists (QuietUninstallString or an
    MSI product code). Anything else is reported as MANUAL rather than being fed
    guessed silent switches, which is how unattended uninstalls hang a machine.

    Does not touch the REPORT tier (Dell Optimizer etc.) under any circumstances.
.NOTES
    Context: SYSTEM. 64-bit host. Contains no reboot command.
    Some products only fully release their filter driver after a reboot - the
    detection script will keep reporting until then. Reboot via the Intune
    Restart device action, not from here.
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

$hives = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$results = @()
foreach ($app in (Get-ItemProperty $hives | Where-Object { $_.DisplayName })) {
    $name = $app.DisplayName.Trim()
    if ($RemoveTier -notcontains $name) { continue }

    $code = $null
    if ($app.QuietUninstallString) {
        # Match once. Never name this $args - that is an automatic variable, and
        # assigning to it then passing it to Start-Process misbehaves.
        $cmd = $app.QuietUninstallString
        if ($cmd -match '^"([^"]+)"\s*(.*)$') {
            $exe = $Matches[1]; $argList = $Matches[2]
        } else {
            $exe = ($cmd -split ' ')[0]; $argList = ($cmd -split ' ', 2)[1]
        }
        # Start-Process throws on a null/empty -ArgumentList, so omit it entirely.
        $p = if ([string]::IsNullOrWhiteSpace($argList)) {
                 Start-Process -FilePath $exe -Wait -PassThru -WindowStyle Hidden
             } else {
                 Start-Process -FilePath $exe -ArgumentList $argList -Wait -PassThru -WindowStyle Hidden
             }
        $code = $p.ExitCode
    }
    elseif ($app.UninstallString -match '(\{[0-9A-Fa-f\-]{36}\})') {
        $p    = Start-Process msiexec.exe -ArgumentList "/x $($Matches[1]) /qn /norestart" -Wait -PassThru
        $code = $p.ExitCode
    }
    else {
        $results += "$name=MANUAL"
        continue
    }
    $results += "$name=$code"
}

if ($results.Count -eq 0) { Write-Output 'BW_MGR|nochange'; exit 0 }
Write-Output ('BW_MGR|removed|' + ($results -join ';'))
exit 0
