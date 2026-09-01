<#
.SYNOPSIS
    Resets the Wi-Fi adapter's advanced properties to their driver defaults.
.DESCRIPTION
    Idempotent. Only resets properties that actually differ from the default the INF
    declares, so a clean adapter is a no-op and the adapter is never bounced for nothing.

    USER-PERCEPTIBLE: resetting an advanced property restarts the adapter, dropping the
    Wi-Fi connection for a few seconds. Every drifted property is therefore reset in a
    SINGLE call, which produces exactly one bounce rather than one per property.

    ORDERING DEPENDENCY - this matters, read it before scheduling anything.
    Driver defaults include power saving. Resetting to defaults therefore UNDOES the
    Wi-Fi Power Management pair, which deliberately turns power saving off. Run this
    first and Power Management second, never the other way round. The output ends with
    RERUN=WifiPowerManagement as a reminder, and the 24-hour cooldown in the detection
    script stops a mis-assignment from fighting Power Management on every check-in.

    It will also undo advanced-property overrides an admin set on purpose (a pinned
    preferred band, for instance). Every value changed is printed as keyword=old/new so
    the ticket records exactly what moved.

    DELIBERATELY NOT TOUCHED:
      - Windows Firewall. 'netsh advfirewall reset' would discard Intune-pushed firewall
        policy fleet-wide. It cannot cause a download-only cap. It is not worth it.
      - Static IP / static DNS / WinHTTP proxy / persistent routes. Reported by the
        detection script, never changed here - see that script's header for why.
      - The IP stack and Winsock catalog. That is Stack Reset, and it needs a reboot.
.NOTES
    Context: SYSTEM. 64-bit host. Contains no reboot command.
#>
$ErrorActionPreference = 'SilentlyContinue'

$key = 'HKLM:\SOFTWARE\NetworkFix'
if (-not (Test-Path $key)) { $null = New-Item -Path $key -Force }

$adapter = Get-NetAdapter -Physical |
    Where-Object { $_.Status -eq 'Up' -and ($_.PhysicalMediaType -match '802.11' -or $_.MediaType -eq 'Native 802.11') } |
    Select-Object -First 1

if (-not $adapter) { Write-Output 'NET_RESET|noadapter'; exit 0 }

# Re-derive drift here rather than trusting the detection run - the two scripts execute
# as separate processes and something may have changed in between.
$keywords = @()
$changed  = @()
foreach ($p in (Get-NetAdapterAdvancedProperty -Name $adapter.Name)) {
    $def = $p.DefaultRegistryValue
    if ($null -eq $def -or $def -eq '') { continue }
    $cur = if ($p.RegistryValue) { $p.RegistryValue[0] } else { '' }
    if ($cur -ne $def) {
        $keywords += $p.RegistryKeyword
        $changed  += "$($p.RegistryKeyword)=$cur/$def"
    }
}

if ($keywords.Count -eq 0) { Write-Output 'NET_RESET|nochange'; exit 0 }

# One call, one adapter bounce. -NoRestart:$false is explicit: the restart is what makes
# the reset take effect, and suppressing it would report success while changing nothing.
Reset-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword $keywords -NoRestart:$false

# Confirm the adapter came back before reporting success. The reset restarts the miniport,
# it does not remove the device, so this should be immediate - but assert it rather than
# assume it, because everything after this point is a remote device with no hands on it.
$back = $false
foreach ($i in 1..15) {
    Start-Sleep -Seconds 2
    $a = Get-NetAdapter -Name $adapter.Name
    if ($a -and $a.Status -eq 'Up') { $back = $true; break }
}

Set-ItemProperty -Path $key -Name 'LastSettingsResetUtc' `
    -Value ((Get-Date).ToUniversalTime().ToString('o')) -Force

$shown = if ($changed.Count -gt 8) { ($changed[0..7] -join '|') + "|+$($changed.Count - 8)more" }
         else                      { $changed -join '|' }

Write-Output ("NET_RESET|reset=$($keywords.Count)|link=$(if ($back) { 'up' } else { 'DOWN' })|" +
              "$shown|RERUN=WifiPowerManagement")
exit 0
