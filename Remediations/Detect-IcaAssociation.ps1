try {
    $icaExe = @(
        "${env:ProgramFiles(x86)}\Citrix\ICA Client\wfica32.exe",
        "$env:ProgramFiles\Citrix\ICA Client\wfica32.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $icaExe) {
        Write-Output "Citrix Workspace not installed; nothing to associate."
        exit 0
    }

    $extKey = Get-Item -Path 'Registry::HKEY_LOCAL_MACHINE\Software\Classes\.ica' -ErrorAction SilentlyContinue
    $cmdKey = Get-Item -Path 'Registry::HKEY_LOCAL_MACHINE\Software\Classes\Citrix.ICAClient\shell\open\command' -ErrorAction SilentlyContinue
    $ext = if ($extKey) { $extKey.GetValue('') } else { $null }
    $cmd = if ($cmdKey) { $cmdKey.GetValue('') } else { $null }

    if ($ext -ne 'Citrix.ICAClient' -or $cmd -notlike '*wfica32.exe*') {
        Write-Output "HKLM association missing or wrong. ext=$ext cmd=$cmd"
        exit 1
    }

    if (-not (Get-PSDrive -Name HKU -ErrorAction SilentlyContinue)) {
        New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS | Out-Null
    }

    $userHives = Get-ChildItem -Path 'HKU:\' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^S-1-5-21-' -and $_.PSChildName -notmatch '_Classes$' }

    foreach ($hive in $userHives) {
        $sid = $hive.PSChildName

        if (Test-Path "HKU:\$sid\Software\Classes\.ica") {
            Write-Output "$sid has HKCU\Software\Classes\.ica override."
            exit 1
        }

        $uc = (Get-ItemProperty -Path "HKU:\$sid\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.ica\UserChoice" -ErrorAction SilentlyContinue).ProgId
        if ($uc -and $uc -notmatch 'Citrix|ica') {
            Write-Output "$sid UserChoice=$uc (not Citrix)."
            exit 1
        }
    }

    Write-Output "ICA association OK (cmd=$cmd)."
    exit 0
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}