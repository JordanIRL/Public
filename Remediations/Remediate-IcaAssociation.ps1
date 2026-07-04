try {
    $icaExe = @(
        "${env:ProgramFiles(x86)}\Citrix\ICA Client\wfica32.exe",
        "$env:ProgramFiles\Citrix\ICA Client\wfica32.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $icaExe) { throw "Citrix wfica32.exe not found." }

    $progId  = 'Citrix.ICAClient'
    $classes = 'HKLM:\Software\Classes'

    New-Item -Path "$classes\$progId\shell\open\command" -Force | Out-Null
    Set-Item -Path "$classes\$progId"                    -Value 'Citrix ICA Client'
    Set-Item -Path "$classes\$progId\shell\open\command" -Value "`"$icaExe`" `"%1`""

    New-Item -Path "$classes\.ica" -Force | Out-Null
    Set-Item         -Path "$classes\.ica" -Value $progId
    Set-ItemProperty -Path "$classes\.ica" -Name 'Content Type' -Value 'application/x-ica'

    if (-not (Get-PSDrive -Name HKU -ErrorAction SilentlyContinue)) {
        New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS | Out-Null
    }

    $userHives = Get-ChildItem -Path 'HKU:\' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^S-1-5-21-' -and $_.PSChildName -notmatch '_Classes$' }

    $cleaned = 0
    foreach ($hive in $userHives) {
        $sid = $hive.PSChildName
        Remove-Item -Path "HKU:\$sid\Software\Classes\.ica"                                                       -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "HKU:\$sid\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.ica\UserChoice" -Recurse -Force -ErrorAction SilentlyContinue
        $cleaned++
    }

    $sig = '[DllImport("shell32.dll")] public static extern void SHChangeNotify(int e, int f, IntPtr i, IntPtr j);'
    Add-Type -MemberDefinition $sig -Namespace Win32 -Name Shell -ErrorAction SilentlyContinue
    [Win32.Shell]::SHChangeNotify(0x08000000, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero)

    Write-Output "ICA handler set to $icaExe; cleaned $cleaned user hive(s)."
    exit 0
}
catch {
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}