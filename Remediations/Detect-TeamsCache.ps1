# Runs in logged-on user context. Non-compliant when Teams cache exceeds threshold.
[int]$thresholdMB = 500

try {
    $paths = @(
        "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache",
        "$env:APPDATA\Microsoft\Teams"
    ) | Where-Object { Test-Path $_ }

    if (-not $paths) {
        Write-Output "No Teams cache present."
        exit 0
    }

    $bytes = (Get-ChildItem -Path $paths -Recurse -Force -ErrorAction SilentlyContinue |
              Measure-Object -Property Length -Sum).Sum
    $mb = [math]::Round(($bytes / 1MB), 1)

    if ($mb -gt $thresholdMB) {
        Write-Output "Teams cache ${mb}MB exceeds ${thresholdMB}MB threshold."
        exit 1
    }

    Write-Output "Teams cache ${mb}MB within threshold."
    exit 0
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}
