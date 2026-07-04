$issues = @()

try {
    $svc = Get-Service -Name "W32Time" -ErrorAction Stop

    if ($svc.Status -ne "Running") {
        $issues += "W32Time service is not running"
    }

    if ($svc.StartType -ne "Automatic") {
        $issues += "W32Time startup type is '$($svc.StartType)' instead of 'Automatic'"
    }
}
catch {
    $issues += "W32Time service not found"
}

if ($issues.Count -gt 0) {
    $issues | ForEach-Object { Write-Output $_ }
    exit 1
}

Write-Output "Windows Time service is healthy"
exit 0