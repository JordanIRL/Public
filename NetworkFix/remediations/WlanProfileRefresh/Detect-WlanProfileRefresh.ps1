<#
.SYNOPSIS
    Detects stale or duplicate WLAN profiles.
.DESCRIPTION
    Reports the profile count, whether the active SSID's profile is set to automatic
    connection, and how many non-active profiles exist.

    SAFETY: this pair NEVER touches the profile that is currently carrying the
    connection - see the remediation script's header for why.
.NOTES
    Context: SYSTEM. 64-bit host. Exit 1 = refreshable condition found.
#>
$ErrorActionPreference = 'SilentlyContinue'

$profiles = @((netsh wlan show profiles) |
    Select-String 'All User Profile\s*:\s*(.+)$' |
    ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() })

$active = ([regex]::Match(((netsh wlan show interfaces) -join "`n"),
           '^\s*SSID\s*:\s*(.+)$', 'IgnoreCase,Multiline')).Groups[1].Value.Trim()

$issues = @()
if (-not $active) { $issues += 'active=none' }

if ($active) {
    $det = (netsh wlan show profile name="$active") -join "`n"
    if ($det -match 'Connection mode\s*:\s*Connect manually') { $issues += 'mode=manual' }
}

$stale = @($profiles | Where-Object { $_ -ne $active })
if ($stale.Count -gt 10) { $issues += "stale=$($stale.Count)" }

Write-Output ("WLAN_PROF|count=$($profiles.Count)|active=$(if($active){'yes'}else{'no'})|" +
              $(if ($issues) { ($issues -join '|') } else { 'ok' }))
if ($issues.Count -gt 0) { exit 1 }
exit 0
