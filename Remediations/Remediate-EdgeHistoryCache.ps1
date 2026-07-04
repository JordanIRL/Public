# Runs in logged-on user context. Clears Edge cache + browsing history per profile.
# Preserves: cookies, saved passwords (Login Data), autofill (Web Data), bookmarks,
# preferences, extensions + their state, open tabs/sessions, IndexedDB, Local Storage,
# and Service Worker registrations. Only transient cache + history artifacts are removed.
$ErrorActionPreference = 'Stop'

try {
    # 1) Stop Edge + helpers (files are locked while running)
    $procs = 'msedge','msedgewebview2','MicrosoftEdgeUpdate','identity_helper'
    foreach ($p in $procs) {
        Get-Process -Name $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2

    $userData = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
    if (-not (Test-Path $userData)) {
        Write-Output "Edge not installed for this user."
        exit 0
    }

    $profiles = Get-ChildItem -Path $userData -Directory -ErrorAction SilentlyContinue |
                Where-Object { Test-Path (Join-Path $_.FullName 'Preferences') }

    # Folders: removed wholesale (contents only — keep the folder itself)
    $cacheFolders = 'Cache','Code Cache','GPUCache','DawnCache','DawnGraphiteCache',
                    'DawnWebGPUCache','Service Worker\CacheStorage','Service Worker\ScriptCache'

    # Files: browsing history + omnibox-derived state. Edge recreates these on next launch.
    $historyFiles = 'History','History-journal','History Provider Cache',
                    'Top Sites','Top Sites-journal',
                    'Visited Links',
                    'Media History','Media History-journal',
                    'Shortcuts','Shortcuts-journal'

    $cleared = [System.Collections.Generic.List[string]]::new()

    foreach ($profile in $profiles) {
        foreach ($f in $cacheFolders) {
            $full = Join-Path $profile.FullName $f
            if (Test-Path $full) {
                Remove-Item -Path (Join-Path $full '*') -Recurse -Force -ErrorAction SilentlyContinue
                $cleared.Add("$($profile.Name)\$f")
            }
        }
        foreach ($f in $historyFiles) {
            $full = Join-Path $profile.FullName $f
            if (Test-Path $full) {
                Remove-Item -Path $full -Force -ErrorAction SilentlyContinue
                $cleared.Add("$($profile.Name)\$f")
            }
        }
    }

    if ($cleared.Count -eq 0) {
        Write-Output "No Edge cache or history artifacts found."
        exit 0
    }

    Write-Output ("Cleared $($cleared.Count) item(s) across $($profiles.Count) profile(s).")
    exit 0
}
catch {
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
