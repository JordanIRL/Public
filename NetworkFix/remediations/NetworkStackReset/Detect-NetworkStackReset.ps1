<#
.SYNOPSIS
    Gate for the network stack reset. NEVER ASSIGN THIS PACKAGE ON A SCHEDULE.
.DESCRIPTION
    This is the heavy hammer - run it on-demand against one device, after the
    fingerprint has failed to name a cause. It is the last software step before the
    Stopping Rule in RUNBOOK.md.

    A 7-day cooldown marker is the safety net. If this package is ever assigned to a
    group by mistake, the cooldown stops it becoming a fleet-wide reset loop; each
    device resets at most once a week rather than every check-in.
.NOTES
    Context: SYSTEM. 64-bit host.
    Exit 1 = outside cooldown, remediation is allowed to run.
#>
$ErrorActionPreference = 'SilentlyContinue'

$key  = 'HKLM:\SOFTWARE\NetworkFix'
$last = (Get-ItemProperty -Path $key -Name 'LastStackResetUtc').LastStackResetUtc

if ($last) {
    $age = ((Get-Date).ToUniversalTime() - [datetime]$last).TotalDays
    if ($age -lt 7) {
        Write-Output ("STACK_RESET|cooldown|days={0:N1}" -f $age)
        exit 0
    }
}

$pending = Test-Path 'HKLM:\SOFTWARE\NetworkFix\PendingReboot'
Write-Output "STACK_RESET|armed|pendingreboot=$pending"
exit 1
