<#
.SYNOPSIS
    Runs a health check over a user's OneDrive for Business and flags issues.

.DESCRIPTION
    Checks storage quota state, then scans items (bounded) for common problems: files above the upload
    limit, over-long paths, sync-blocking names/characters, .pst files, large space consumers, recycle-bin
    footprint and sharing exposure. Optionally pulls the OneDrive usage report for last-activity/allocation.

    Graph scopes (delegated): Files.Read.All + Sites.Read.All + User.Read.All
        (add Reports.Read.All for -IncludeUsageReport).

.PARAMETER UserEmail          UPN/SMTP of the user.
.PARAMETER MaxItems           Safety cap on items scanned (default 5000). If hit, results are partial.
.PARAMETER LargeFileThresholdGB  Flag files at/above this size (default 10 GB).
.PARAMETER IncludeUsageReport Pull getOneDriveUsageAccountDetail (needs Reports.Read.All + Microsoft.Graph.Reports).

.EXAMPLE
    ./Test-OneDriveHealth.ps1 -UserEmail jane@contoso.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$UserEmail,
    [int]$MaxItems = 5000,
    [double]$LargeFileThresholdGB = 10,
    [switch]$IncludeUsageReport
)

. "$PSScriptRoot/../Common/GraphCommon.ps1"
$scopes = @('Files.Read.All', 'Sites.Read.All', 'User.Read.All')
if ($IncludeUsageReport) { $scopes += 'Reports.Read.All' }
Connect-GraphSession -Scopes $scopes

# OneDrive sync-blocking constraints (approximate current limits).
$UploadLimitBytes = 250GB
$PathLimit = 400
$InvalidChars = '"', '*', ':', '<', '>', '?', '/', '\', '|'
$BlockedNames = 'CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
                'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9', 'desktop.ini', '.lock'

$user = Resolve-GraphUserId -User $UserEmail
Write-Section "OneDrive health check - $($user.UserPrincipalName)"

# ---- Drive + quota -----------------------------------------------------------
try {
    $drive = Invoke-MgGraphRequest -Method GET `
        -Uri "/v1.0/users/$($user.Id)/drive?`$select=id,driveType,webUrl,quota,owner" -OutputType PSObject
} catch {
    Write-Host "FAIL  OneDrive is not provisioned / not accessible for this user." -ForegroundColor Red
    throw "No drive found for $($user.UserPrincipalName). The user may be unlicensed or OneDrive not provisioned. $_"
}

$q = $drive.quota
$pctUsed = if ($q.total) { [math]::Round(($q.used / $q.total) * 100, 1) } else { $null }
$quotaFlag = switch ($q.state) { 'normal' { 'OK' } 'nearing' { 'WARN' } 'critical' { 'FAIL' } 'exceeded' { 'FAIL' } default { 'INFO' } }

Write-Host ("Drive type      : {0}" -f $drive.driveType)
Write-Host ("Quota state     : {0}   ({1})" -f $q.state, $quotaFlag) -ForegroundColor (@{OK='Green';WARN='Yellow';FAIL='Red';INFO='Gray'}[$quotaFlag])
Write-Host ("Used / Total    : {0} / {1}  ({2}% used)" -f (Format-Bytes $q.used), (Format-Bytes $q.total), $pctUsed)
Write-Host ("Remaining       : {0}" -f (Format-Bytes $q.remaining))
Write-Host ("Recycle bin     : {0}" -f (Format-Bytes $q.deleted))

# ---- Scan items --------------------------------------------------------------
Write-Host "`nScanning items (cap $MaxItems)..." -ForegroundColor DarkGray
$issues = @{
    OversizeFiles   = [System.Collections.Generic.List[object]]::new()
    LongPaths       = [System.Collections.Generic.List[object]]::new()
    BadNames        = [System.Collections.Generic.List[object]]::new()
    PstFiles        = [System.Collections.Generic.List[object]]::new()
    LargeFiles      = [System.Collections.Generic.List[object]]::new()
    SharedItems     = [System.Collections.Generic.List[object]]::new()
}
$fileCount = 0; $folderCount = 0; $scanned = 0; $truncated = $false
$largeThresholdBytes = $LargeFileThresholdGB * 1GB

$queue = [System.Collections.Generic.Queue[string]]::new()
$queue.Enqueue("/v1.0/drives/$($drive.id)/root/children")
while ($queue.Count -gt 0) {
    if ($scanned -ge $MaxItems) { $truncated = $true; break }
    $uri = "$($queue.Dequeue())?`$top=200&`$select=id,name,size,file,folder,webUrl,shared,parentReference,lastModifiedDateTime"
    $children = Invoke-GraphPaged -Uri $uri
    foreach ($it in $children) {
        $scanned++
        if ($scanned -ge $MaxItems) { $truncated = $true; break }

        $relPath = ($it.parentReference.path -replace '^/drives/[^/]+/root:', '') + '/' + $it.name
        $isFolder = $null -ne $it.folder

        if ($isFolder) {
            $folderCount++
            $queue.Enqueue("/v1.0/drives/$($drive.id)/items/$($it.id)/children")
        } else {
            $fileCount++
            if ($it.size -ge $UploadLimitBytes) { $issues.OversizeFiles.Add([pscustomobject]@{ Name = $it.name; Size = Format-Bytes $it.size; Path = $relPath }) }
            elseif ($it.size -ge $largeThresholdBytes) { $issues.LargeFiles.Add([pscustomobject]@{ Name = $it.name; Size = Format-Bytes $it.size; Path = $relPath }) }
            if ($it.name -like '*.pst') { $issues.PstFiles.Add([pscustomobject]@{ Name = $it.name; Size = Format-Bytes $it.size; Path = $relPath }) }
        }

        if ($relPath.Length -gt $PathLimit) { $issues.LongPaths.Add([pscustomobject]@{ Name = $it.name; Length = $relPath.Length; Path = $relPath }) }

        $nameNoExt = [IO.Path]::GetFileNameWithoutExtension($it.name)
        $badChar = ($InvalidChars | Where-Object { $it.name.Contains($_) }) -join ' '
        $leadTrail = ($it.name -ne $it.name.Trim()) -or $it.name.EndsWith('.')
        if ($badChar -or $leadTrail -or ($BlockedNames -contains $nameNoExt) -or ($BlockedNames -contains $it.name) -or $it.name.StartsWith('~$')) {
            $reason = @()
            if ($badChar) { $reason += "chars:$badChar" }
            if ($leadTrail) { $reason += 'leading/trailing space or dot' }
            if (($BlockedNames -contains $nameNoExt) -or ($BlockedNames -contains $it.name)) { $reason += 'reserved name' }
            if ($it.name.StartsWith('~$')) { $reason += 'temp (~$) file' }
            $issues.BadNames.Add([pscustomobject]@{ Name = $it.name; Reason = ($reason -join '; '); Path = $relPath })
        }

        if ($it.shared) { $issues.SharedItems.Add([pscustomobject]@{ Name = $it.name; Path = $relPath }) }
    }
}

# ---- Report ------------------------------------------------------------------
Write-Section "Findings"
function Show-Finding {
    param([string]$Label, $Items, [string]$OkText = 'none', [ValidateSet('warn','fail')][string]$Level = 'warn')
    $n = @($Items).Count
    if ($n -eq 0) { Write-Host ("OK    {0}: {1}" -f $Label, $OkText) -ForegroundColor Green }
    else {
        $c = if ($Level -eq 'fail') { 'Red' } else { 'Yellow' }
        Write-Host ("{0}  {1}: {2}" -f ($Level.ToUpper().PadRight(4)), $Label, $n) -ForegroundColor $c
        @($Items) | Select-Object -First 10 | Format-Table -AutoSize | Out-String | Write-Host
        if ($n -gt 10) { Write-Host "      ...and $($n-10) more" -ForegroundColor DarkGray }
    }
}

Write-Host ("Scanned {0} items ({1} files, {2} folders){3}" -f $scanned, $fileCount, $folderCount, $(if ($truncated) { " - TRUNCATED at cap $MaxItems" } else { '' })) -ForegroundColor Cyan
Show-Finding 'Quota'                        $(if ($quotaFlag -in 'FAIL','WARN') { @([pscustomobject]@{ State = $q.state; PctUsed = $pctUsed }) } else { @() }) -Level $(if ($quotaFlag -eq 'FAIL') { 'fail' } else { 'warn' })
Show-Finding 'Files over 250GB upload limit' $issues.OversizeFiles -Level 'fail'
Show-Finding 'Over-long paths (>400 chars)'  $issues.LongPaths -Level 'fail'
Show-Finding 'Sync-blocking names/characters' $issues.BadNames -Level 'warn'
Show-Finding '.pst files (not recommended)'   $issues.PstFiles -Level 'warn'
Show-Finding "Large files (>= $LargeFileThresholdGB GB)" $issues.LargeFiles -Level 'warn'
Show-Finding 'Shared items (sharing exposure)' $issues.SharedItems -Level 'warn'

# ---- Optional usage report ---------------------------------------------------
$usage = $null
if ($IncludeUsageReport) {
    Write-Section "OneDrive usage report (D7)"
    try {
        Import-Module Microsoft.Graph.Reports -ErrorAction Stop
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("od-usage-{0}.csv" -f ([guid]::NewGuid()))
        Get-MgReportOneDriveUsageAccountDetail -Period 'D7' -OutFile $tmp -ErrorAction Stop
        $row = Import-Csv $tmp | Where-Object { $_.'Owner Principal Name' -eq $user.UserPrincipalName }
        Remove-Item $tmp -ErrorAction SilentlyContinue
        if ($row) {
            $usage = $row | Select-Object 'Last Activity Date', 'File Count', 'Active File Count',
                'Storage Used (Byte)', 'Storage Allocated (Byte)', 'Is Deleted'
            $usage | Format-List
        } else {
            Write-Host "No usage row (names may be de-identified by the M365 admin-center privacy setting)." -ForegroundColor Yellow
        }
    } catch {
        Write-Warning "Usage report unavailable: $($_.Exception.Message)"
    }
}

[pscustomobject]@{
    User      = $user.UserPrincipalName
    DriveType = $drive.driveType
    Quota     = $q
    QuotaFlag = $quotaFlag
    Counts    = [pscustomobject]@{ Scanned = $scanned; Files = $fileCount; Folders = $folderCount; Truncated = $truncated }
    Issues    = $issues
    Usage     = $usage
    WebUrl    = $drive.webUrl
}
