# Runs as SYSTEM. Kicks the Entra/Intune identity plumbing without tearing down the join:
# bounces dependencies, triggers Automatic-Device-Join, forces MDM sync, then reports the
# post-state so you can see whether the fix took in Intune's remediation output.
$ErrorActionPreference = 'Stop'
$actions = [System.Collections.Generic.List[string]]::new()

try {
    # 1) Restart dependencies that commonly wedge
    foreach ($svc in 'cryptsvc','dmwappushservice','W32Time') {
        try {
            Restart-Service -Name $svc -Force -ErrorAction Stop
            $actions.Add("restarted $svc")
        } catch {
            $actions.Add("$svc restart failed: $($_.Exception.Message)")
        }
    }

    # 2) Automatic device join task — covers both AAD-join and hybrid scenarios
    try {
        Start-ScheduledTask -TaskPath '\Microsoft\Windows\Workplace Join\' -TaskName 'Automatic-Device-Join' -ErrorAction Stop
        $actions.Add("triggered Automatic-Device-Join")
    } catch {
        $actions.Add("Automatic-Device-Join failed: $($_.Exception.Message)")
    }

    # 3) Force MDM push sync across every enrollment GUID
    $pushTasks = Get-ScheduledTask -TaskPath '\Microsoft\Windows\EnterpriseMgmt\*' -TaskName 'PushLaunch' -ErrorAction SilentlyContinue
    $triggered = 0
    foreach ($t in $pushTasks) {
        try { Start-ScheduledTask -InputObject $t -ErrorAction Stop; $triggered++ } catch { }
    }
    $actions.Add("triggered $triggered PushLaunch task(s)")

    # 4) Post-check so the remediation output shows what state we landed in
    Start-Sleep -Seconds 5
    $post  = & dsregcmd /status 2>&1
    $state = @{}
    foreach ($line in $post) {
        if ($line -match '^\s+([A-Za-z]+)\s+:\s+(.+)$') { $state[$Matches[1]] = $Matches[2].Trim() }
    }
    $actions.Add("post: AzureAdJoined=$($state.AzureAdJoined) DeviceAuth=$($state.DeviceAuthStatus) KeySign=$($state.KeySignTest)")

    Write-Output ($actions -join ' | ')

    # Fail remediation if the core signals are still broken — surfaces in Intune's output
    if ($state.AzureAdJoined -ne 'YES' -or $state.DeviceAuthStatus -ne 'SUCCESS') { exit 1 }
    exit 0
}
catch {
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
