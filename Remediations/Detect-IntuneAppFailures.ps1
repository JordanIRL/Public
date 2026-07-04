try {
    $failed = @()
    $root = 'HKLM:\SOFTWARE\Microsoft\IntuneManagementExtension\Win32Apps'

    if (-not (Test-Path $root)) {
        Write-Output "Intune Win32Apps key not found."
        exit 0
    }

    $scopes = Get-ChildItem -Path $root -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^S-\d-\d+' -or $_.PSChildName -eq 'Reporting' -eq $false }

    foreach ($scope in $scopes) {
        Get-ChildItem -Path $scope.PSPath -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -ne 'GRS' -and $_.PSChildName -ne 'OperationalState' } |
            ForEach-Object {
                $prop = Get-ItemProperty -Path $_.PSPath -Name 'EnforcementStateMessage' -ErrorAction SilentlyContinue
                if ($prop.EnforcementStateMessage) {
                    try {
                        $msg = $prop.EnforcementStateMessage | ConvertFrom-Json
                        # 1000 = Success, 2000-2099 = In progress, 3000+ = failure/error states
                        if ($msg.EnforcementState -ge 3000 -or $msg.ErrorCode -ne 0) {
                            $failed += "$($_.PSChildName) (State=$($msg.EnforcementState), Err=$($msg.ErrorCode))"
                        }
                    } catch { }
                }
            }
    }

    # ESP / Autopilot tracked app failures (InstallationState 3 = Failed)
    $espRoot = 'HKLM:\SOFTWARE\Microsoft\Windows\Autopilot\EnrollmentStatusTracking\Device\Setup\Apps\Tracking'
    if (Test-Path $espRoot) {
        Get-ChildItem -Path $espRoot -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $state = (Get-ItemProperty -Path $_.PSPath -Name 'InstallationState' -ErrorAction SilentlyContinue).InstallationState
            if ($state -eq 3) { $failed += "ESP:$($_.PSChildName)" }
        }
    }

    if ($failed.Count -gt 0) {
        Write-Output "Failed Intune apps: $($failed -join '; ')"
        exit 1
    }
    Write-Output "All Intune/Autopilot required apps installed successfully."
    exit 0
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}
