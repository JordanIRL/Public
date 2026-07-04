# Runs as SYSTEM. Non-compliant when any install matching $AppNamePattern is found.
# Edit the pattern to target a specific app. Wildcards supported.

$AppNamePattern = '*ExampleApp*'
$IncludeAppx    = $true

try {
    $found = @()

    $uninstallPaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $found += Get-ItemProperty -Path $uninstallPaths -ErrorAction SilentlyContinue |
              Where-Object { $_.DisplayName -like $AppNamePattern } |
              Select-Object -ExpandProperty DisplayName

    if ($IncludeAppx) {
        $found += Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -like $AppNamePattern -or $_.PackageFullName -like $AppNamePattern } |
                  Select-Object -ExpandProperty Name
        $found += Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                  Where-Object { $_.DisplayName -like $AppNamePattern } |
                  Select-Object -ExpandProperty DisplayName
    }

    $found = $found | Select-Object -Unique
    if ($found.Count -gt 0) {
        Write-Output "Matched '$AppNamePattern': $($found -join ', ')"
        exit 1
    }

    Write-Output "No installs match '$AppNamePattern'."
    exit 0
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}
