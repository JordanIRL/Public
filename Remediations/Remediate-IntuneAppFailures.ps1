try {
    $remediated = @()
    $root = 'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps'

    $scopes = Get-ChildItem -Path $root -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^S-\d-\d+' -or $_.PSChildName -eq 'Reporting' -eq $false }

    foreach ($scope in $scopes) {
        Get-ChildItem -Path $scope.PSPath -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -ne 'GRS' -and $_.PSChildName -ne 'OperationalState' } |
            ForEach-Object {
                $appId = $_.PSChildName
                $prop  = Get-ItemProperty -Path $_.PSPath -Name 'EnforcementStateMessage' -ErrorAction SilentlyContinue
                if ($prop.EnforcementStateMessage) {
                    try {
                        $msg = $prop.EnforcementStateMessage | ConvertFrom-Json
                        if ($msg.EnforcementState -ge 3000 -or $msg.ErrorCode -ne 0) {
                            # Clear Global Retry Schedule so IME retries immediately
                            $grs = Join-Path $scope.PSPath "GRS\$appId"
                            if (Test-Path $grs) { Remove-Item -Path $grs -Recurse -Force -ErrorAction SilentlyContinue }

                            # Drop cached enforcement state to force re-evaluation
                            Remove-ItemProperty -Path $_.PSPath -Name 'EnforcementStateMessage' -Force -ErrorAction SilentlyContinue
                            $remediated += $appId
                        }
                    } catch { }
                }
            }
    }

    # Clear Win32 app cache so IME re-downloads failed content
    $cache = "$env:ProgramData\Microsoft\IntuneManagementExtension\Content\Incoming"
    if (Test-Path $cache) { Get-ChildItem $cache -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }

    # Kick IME to re-evaluate assignments
    Restart-Service -Name 'IntuneManagementExtension' -Force -ErrorAction Stop

    # Trigger an MDM sync
    Get-ScheduledTask -TaskPath '\Microsoft\Windows\EnterpriseMgmt\*' -TaskName 'PushLaunch' -ErrorAction SilentlyContinue |
        Start-ScheduledTask -ErrorAction SilentlyContinue

    if ($remediated.Count -gt 0) {
        Write-Output "Reset $($remediated.Count) failed app(s): $($remediated -join ', ')"
    } else {
        Write-Output "No failed apps found; IME restarted and sync triggered."
    }
    exit 0
}
catch {
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
