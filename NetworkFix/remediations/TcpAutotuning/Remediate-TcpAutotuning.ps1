<#
.SYNOPSIS
    Restores normal TCP receive-window auto-tuning.
.DESCRIPTION
    Idempotent. Takes effect on new TCP connections immediately - no reboot and no
    adapter bounce, so this is the least disruptive fix in the kit.

    Deliberately does NOT touch congestion provider or RSS/RSC. Those are separate
    variables; changing several at once is the speculative approach this kit replaces.
.NOTES
    Context: SYSTEM. 64-bit host. Contains no reboot command.
#>
$ErrorActionPreference = 'SilentlyContinue'

$changed = @()

$level = ([regex]::Match(((netsh int tcp show global) -join "`n"),
          'Receive Window Auto-Tuning Level\s*:\s*(\w+)', 'IgnoreCase')).Groups[1].Value
if ($level -notmatch '^normal$') {
    $null = netsh int tcp set global autotuninglevel=normal
    $changed += "autotune:$level->normal"
}

# Window Scaling Heuristics can re-clamp auto-tuning behind your back.
$wsh = ([regex]::Match(((netsh int tcp show heuristics) -join "`n"),
        'Window Scaling heuristics\s*:\s*(\w+)', 'IgnoreCase')).Groups[1].Value
if ($wsh -match '^enabled$') {
    $null = netsh int tcp set heuristics wsh=disabled
    $changed += 'heuristics:disabled'
}

# Tcp1323Opts=0 disables window scaling outright, capping the window at 64 KB.
$p = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
$opts = (Get-ItemProperty $p -Name 'Tcp1323Opts').Tcp1323Opts
if ($null -ne $opts -and $opts -eq 0) {
    Set-ItemProperty -Path $p -Name 'Tcp1323Opts' -Value 3 -Type DWord -Force
    $changed += 'tcp1323:0->3(reboot to apply)'
}

if ($changed.Count -eq 0) { Write-Output 'TCP_WINDOW|nochange'; exit 0 }
Write-Output ('TCP_WINDOW|fixed|' + ($changed -join '|'))
exit 0
