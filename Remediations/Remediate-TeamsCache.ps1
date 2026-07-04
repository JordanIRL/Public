# Runs in logged-on user context. Stops Teams and clears cache for New Teams and Classic Teams.
# Preserves credentials and settings; only transient cache folders are removed.
$ErrorActionPreference = 'Stop'

try {
    # 1) Stop Teams processes (both variants + helpers)
    $procs = 'ms-teams','msteams','Teams','Update','Squirrel','CefSharp.BrowserSubprocess'
    foreach ($p in $procs) {
        Get-Process -Name $p -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2

    $cleared = @()

    # 2) New Teams (MSIX) — wipe LocalCache; package rebuilds it on next launch
    $newTeamsCache = "$env:LOCALAPPDATA\Packages\MSTeams_8wekyb3d8bbwe\LocalCache"
    if (Test-Path $newTeamsCache) {
        Get-ChildItem -Path $newTeamsCache -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        $cleared += 'New Teams LocalCache'
    }

    # 3) Classic Teams — only cache-ish subfolders, never the root (would nuke desktop-config.json)
    $classicRoot = "$env:APPDATA\Microsoft\Teams"
    if (Test-Path $classicRoot) {
        $subs = 'Cache','Code Cache','GPUCache','blob_storage','databases',
                'IndexedDB','Local Storage','tmp','Service Worker\CacheStorage',
                'Service Worker\ScriptCache'
        foreach ($s in $subs) {
            $full = Join-Path $classicRoot $s
            if (Test-Path $full) {
                Remove-Item -Path (Join-Path $full '*') -Recurse -Force -ErrorAction SilentlyContinue
                $cleared += "Classic Teams\$s"
            }
        }
    }

    if (-not $cleared) {
        Write-Output "No Teams cache directories found."
        exit 0
    }

    Write-Output ("Cleared: " + ($cleared -join ', '))
    exit 0
}
catch {
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
