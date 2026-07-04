try {
    Set-Service -Name "W32Time" -StartupType Automatic
    Start-Service -Name "W32Time" -ErrorAction SilentlyContinue

    w32tm /config /update | Out-Null
    w32tm /resync /force | Out-Null

    Write-Output "Time sync triggered successfully"
    exit 0
}
catch {
    Write-Output "Failed to trigger time sync: $($_.Exception.Message)"
    exit 1
}