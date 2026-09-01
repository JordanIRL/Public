<#
.SYNOPSIS
    Refreshes the active WLAN profile in place and prunes stale non-active profiles.
.DESCRIPTION
    SAFETY DESIGN - read before changing this script.

    The obvious implementation (delete the profile, let Intune re-push it) can strand a
    remote laptop: between the delete and the next successful Intune sync there is no
    profile, and with no profile there is no Wi-Fi, and with no Wi-Fi there is no sync.
    On a device with no hands available and no wired fallback, that is unrecoverable
    without a site visit.

    So instead:
      - The ACTIVE profile is exported and re-added with 'netsh wlan add profile', which
        overwrites in place. There is never a window with no profile present.
      - Only NON-ACTIVE profiles are deleted, and only beyond a keep threshold.

    This is less thorough than a true delete-and-recreate. That is the correct trade
    when the device cannot be physically reached.
.NOTES
    Context: SYSTEM. 64-bit host. Contains no reboot command.
#>
$ErrorActionPreference = 'SilentlyContinue'

$work = Join-Path $env:ProgramData 'NetworkFix\wlan'
$null = New-Item -ItemType Directory -Path $work -Force

$active = ([regex]::Match(((netsh wlan show interfaces) -join "`n"),
           '^\s*SSID\s*:\s*(.+)$', 'IgnoreCase,Multiline')).Groups[1].Value.Trim()

$done = @()

# 1. Refresh the active profile IN PLACE. Export first; abort if the export fails.
if ($active) {
    $null = netsh wlan export profile name="$active" folder="$work" key=clear
    $xml  = Get-ChildItem -Path $work -Filter '*.xml' |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($xml) {
        $r = (netsh wlan add profile filename="$($xml.FullName)" user=all) -join ' '
        $done += "refresh=$(if($r -match 'added|is added'){'ok'}else{'failed'})"
        Remove-Item $xml.FullName -Force   # contains the key in clear text
    } else {
        # No export means no safe refresh. Do nothing rather than risk the profile.
        $done += 'refresh=skipped(noexport)'
    }
}

# 2. Prune stale NON-ACTIVE profiles only, keeping the most recent 10.
$profiles = @((netsh wlan show profiles) |
    Select-String 'All User Profile\s*:\s*(.+)$' |
    ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() } |
    Where-Object { $_ -ne $active })

$removed = 0
if ($profiles.Count -gt 10) {
    foreach ($p in ($profiles | Select-Object -Skip 10)) {
        $null = netsh wlan delete profile name="$p"
        $removed++
    }
}
$done += "pruned=$removed"

Write-Output ('WLAN_PROF|' + ($done -join '|'))
exit 0
