<#
.SYNOPSIS
    Resets the Windows network stack. Requires a reboot to fully apply.
.DESCRIPTION
    Runs the classic sequence: Winsock catalog reset, IP stack reset, DNS cache flush,
    DHCP re-acquire.

    NO REBOOT COMMAND. Microsoft explicitly forbids reboot commands in detection and
    remediation scripts, and a surprise reboot is precisely the user disruption this
    kit is built to avoid. Instead this writes a PendingReboot marker under
    HKLM:\SOFTWARE\NetworkFix. Issue the reboot with the Intune Restart device action,
    or let it land on the next natural reboot.

    Until that reboot happens the reset is only partially in effect - do not judge
    whether it worked until the device has restarted. Re-run the triage probe after.
.NOTES
    Context: SYSTEM. 64-bit host.
#>
$ErrorActionPreference = 'SilentlyContinue'

$key = 'HKLM:\SOFTWARE\NetworkFix'
if (-not (Test-Path $key)) { $null = New-Item -Path $key -Force }

$steps = @()

$null = netsh winsock reset
$steps += "winsock=$(if ($LASTEXITCODE -eq 0) { 'ok' } else { "rc$LASTEXITCODE" })"

$null = netsh int ip reset
$steps += "ipreset=$(if ($LASTEXITCODE -eq 0) { 'ok' } else { "rc$LASTEXITCODE" })"

$null = ipconfig /flushdns
$steps += 'dns=flushed'

$null = ipconfig /release
$null = ipconfig /renew
$steps += 'dhcp=renewed'

Set-ItemProperty -Path $key -Name 'LastStackResetUtc' `
    -Value ((Get-Date).ToUniversalTime().ToString('o')) -Force
$null = New-Item -Path "$key\PendingReboot" -Force

Write-Output ('STACK_RESET|done|' + ($steps -join '|') + '|REBOOT_REQUIRED')
exit 0
