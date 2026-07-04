# Runs as SYSTEM. Uninstalls every install matching $AppNamePattern.
# Edit the pattern — and optionally $IncludeAppx — before uploading to Intune.
# Handles MSI (ProductCode), classic EXE (QuietUninstallString preferred), and Appx/provisioned packages.

$AppNamePattern = '*ExampleApp*'
$IncludeAppx    = $true

$ErrorActionPreference = 'Stop'
$results = [System.Collections.Generic.List[string]]::new()

function Invoke-Uninstall {
    param([Parameter(Mandatory)] $App)

    $name  = $App.DisplayName
    $key   = $App.PSChildName
    $isMsi = $key -match '^\{[0-9A-Fa-f\-]+\}$'

    if ($isMsi) {
        $p = Start-Process -FilePath 'msiexec.exe' `
             -ArgumentList '/x', $key, '/qn', '/norestart' `
             -Wait -PassThru -NoNewWindow
        return "$name (MSI): exit $($p.ExitCode)"
    }

    $cmd = if ($App.QuietUninstallString) { $App.QuietUninstallString } else { $App.UninstallString }
    if (-not $cmd) { return "$name: no uninstall command in registry" }

    # Let cmd.exe handle quoting in the registry string
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $cmd -Wait -PassThru -NoNewWindow
    $tag = if ($App.QuietUninstallString) { 'EXE quiet' } else { 'EXE' }
    return "$name ($tag): exit $($p.ExitCode)"
}

try {
    # 1) Classic Win32 apps (HKLM native + WOW64)
    $uninstallPaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $apps = Get-ItemProperty -Path $uninstallPaths -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like $AppNamePattern }

    foreach ($app in $apps) {
        try   { $results.Add((Invoke-Uninstall -App $app)) }
        catch { $results.Add("$($app.DisplayName): $($_.Exception.Message)") }
    }

    # 2) Appx / MSIX packages
    if ($IncludeAppx) {
        $pkgs = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like $AppNamePattern -or $_.PackageFullName -like $AppNamePattern }
        foreach ($pkg in $pkgs) {
            try {
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                $results.Add("$($pkg.Name) (Appx): removed")
            } catch {
                $results.Add("$($pkg.Name) (Appx): $($_.Exception.Message)")
            }
        }

        # Stop the package from reinstalling for new user profiles
        $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like $AppNamePattern }
        foreach ($p in $prov) {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null
                $results.Add("$($p.DisplayName) (Provisioned): removed")
            } catch {
                $results.Add("$($p.DisplayName) (Provisioned): $($_.Exception.Message)")
            }
        }
    }

    if ($results.Count -eq 0) {
        Write-Output "No installs match '$AppNamePattern'."
        exit 0
    }

    $failed = $results | Where-Object { $_ -match 'exit (?!0\b)\d+' -or $_ -match ': (?!removed)[A-Z]' }
    Write-Output ($results -join ' | ')
    if ($failed) { exit 1 } else { exit 0 }
}
catch {
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
