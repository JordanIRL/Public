# Runs in logged-on user context. Non-compliant when Edge cache exceeds threshold.
[int]$thresholdMB = 1000

try {
    $userData = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    if (-not (Test-Path $userData)) {
        Write-Output "Edge not installed for this user."
        exit 0
    }

    # A profile directory has a Preferences file
    $profiles = Get-ChildItem -Path $userData -Directory -ErrorAction SilentlyContinue |
                Where-Object { Test-Path (Join-Path $_.FullName 'Preferences') }

    $cacheFolders = 'Cache','Code Cache','GPUCache','DawnCache','DawnGraphiteCache',
                    'DawnWebGPUCache','Service Worker\CacheStorage','Service Worker\ScriptCache'

    $targets = foreach ($p in $profiles) {
        foreach ($f in $cacheFolders) {
            $full = Join-Path $p.FullName $f
            if (Test-Path $full) { $full }
        }
    }

    if (-not $targets) {
        Write-Output "No Edge cache folders present."
        exit 0
    }

    $bytes = (Get-ChildItem -Path $targets -Recurse -Force -ErrorAction SilentlyContinue |
              Measure-Object -Property Length -Sum).Sum
    $mb = [math]::Round(($bytes / 1MB), 1)

    if ($mb -gt $thresholdMB) {
        Write-Output "Edge cache ${mb}MB exceeds ${thresholdMB}MB threshold."
        exit 1
    }

    Write-Output "Edge cache ${mb}MB within threshold."
    exit 0
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}
