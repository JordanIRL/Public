<#
.SYNOPSIS
    Detects a restricted TCP receive-window auto-tuning level.
.DESCRIPTION
    When auto-tuning is disabled or restricted, Windows pins a small fixed receive
    window and inbound throughput collapses to roughly RWIN/RTT. Outbound is
    unaffected - which is exactly the "slow download, fast upload" signature.

    Also checks Window Scaling Heuristics, which can silently clamp auto-tuning
    back to restricted even when the level itself reads as normal.
.NOTES
    Context: SYSTEM. 64-bit host. Exit 1 = issue found.
#>
$ErrorActionPreference = 'SilentlyContinue'

$issues = @()

$global = (netsh int tcp show global) -join "`n"
$level  = ([regex]::Match($global, 'Receive Window Auto-Tuning Level\s*:\s*(\w+)', 'IgnoreCase')).Groups[1].Value
if ($level -and $level -notmatch '^normal$') { $issues += "autotune=$level" }

$heur = (netsh int tcp show heuristics) -join "`n"
$wsh  = ([regex]::Match($heur, 'Window Scaling heuristics\s*:\s*(\w+)', 'IgnoreCase')).Groups[1].Value
if ($wsh -match '^enabled$') { $issues += 'heuristics=enabled' }

$supp = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' -Name 'Tcp1323Opts'
if ($null -ne $supp -and $supp.Tcp1323Opts -eq 0) { $issues += 'tcp1323=0' }

if ($issues.Count -gt 0) {
    Write-Output ("TCP_WINDOW|" + ($issues -join '|'))
    exit 1
}
Write-Output "TCP_WINDOW|ok|level=$level"
exit 0
