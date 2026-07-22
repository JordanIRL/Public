<#
.SYNOPSIS
    Inventories Microsoft Loop content related to a user: Loop workspaces (SharePoint Embedded
    containers), deleted/recycled workspaces, and the user's Loop files in OneDrive.

.DESCRIPTION
    Microsoft Loop workspaces are stored as SharePoint Embedded (SPE) containers owned by the Loop
    applications. There is NO Graph/PowerShell filter that returns "containers for user X", so this
    script:
      1. Lists ALL Loop containers (active) via Get-SPOContainer for both Loop app ids.
      2. Best-effort matches the user by inspecting each container's detail (Get-SPOContainer -Identity)
         for the user's address. This is heuristic - authoritative membership lives in the SharePoint
         admin center container details or the Loop app (Owner/Editor roles only).
      3. Lists deleted Loop containers (Get-SPODeletedContainer, 93-day retention).
      4. Uses Graph to list the user's Loop files (.loop / .fluid) in their OneDrive - these are the
         Loop components/pages created in chats, Outlook and the Loop app "My workspace".

    Requirements:
      * SharePoint Embedded Administrator + SharePoint Online Management Shell (Microsoft.Online.SharePoint.PowerShell)
        for sections 1-3. Provide -SPOAdminUrl (https://<tenant>-admin.sharepoint.com). If omitted,
        those sections are skipped.
      * Microsoft Graph, delegated Files.Read.All + Sites.Read.All + User.Read.All for section 4.

    Recycle bin note: file-level OneDrive recycle bin is not exposed by Graph. Deleted *workspaces* are
    covered by section 3; for deleted *files*, use the OneDrive web recycle bin or PnP.PowerShell
    (Get-PnPRecycleBinItem) against the user's -my site.

.PARAMETER UserEmail   UPN/SMTP of the user.
.PARAMETER SPOAdminUrl SharePoint admin URL, e.g. https://contoso-admin.sharepoint.com
.PARAMETER SkipUserMatch  List the full Loop container inventory without the per-user heuristic match.
.PARAMETER MaxContainers  Cap on containers inspected for the per-user match (default 2000).

.EXAMPLE
    ./Get-UserLoopWorkspaces.ps1 -UserEmail jane@contoso.com -SPOAdminUrl https://contoso-admin.sharepoint.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$UserEmail,
    [string]$SPOAdminUrl,
    [switch]$SkipUserMatch,
    [int]$MaxContainers = 2000
)

. "$PSScriptRoot/../Common/GraphCommon.ps1"

$LoopAppIds = @{
    'Loop Web'    = 'a187e399-0c36-4b98-8f04-1edc167a0996'
    'Loop Mobile' = '0922ef46-e1b9-4f7e-9134-9ad00547eb41'
}

function Get-Prop {
    param($Object, [string[]]$Names)
    foreach ($n in $Names) {
        $p = $Object.PSObject.Properties[$n]
        if ($p -and $null -ne $p.Value) { return $p.Value }
    }
    return $null
}
function Test-Match { param($Object, [string]$Needle) (($Object | Out-String) -match [regex]::Escape($Needle)) }

# ------------------------------------------------------------------ SPE containers (Loop workspaces)
if ($SPOAdminUrl) {
    Import-Module Microsoft.Online.SharePoint.PowerShell -DisableNameChecking -ErrorAction Stop
    Connect-SPOService -Url $SPOAdminUrl -ErrorAction Stop

    Write-Section "Loop workspaces (active SharePoint Embedded containers)"
    # Get-SPOContainer pages at 200; iterate -Paged/-PagingToken until the end marker so ALL containers
    # are seen (the trailing string entry per page is the paging token, or "End of containers view.").
    $allContainers = foreach ($kv in $LoopAppIds.GetEnumerator()) {
        $token = $null
        do {
            try {
                $page = if ($token) {
                    Get-SPOContainer -OwningApplicationId $kv.Value -Paged -PagingToken $token -ErrorAction Stop
                } else {
                    Get-SPOContainer -OwningApplicationId $kv.Value -Paged -ErrorAction Stop
                }
            } catch {
                Write-Warning "Could not list containers for $($kv.Key): $($_.Exception.Message)"
                break
            }
            $token = $null
            foreach ($entry in $page) {
                if ($entry -is [string]) {
                    if ($entry -notmatch 'End of containers view') { $token = $entry }
                } else {
                    $entry | Add-Member -NotePropertyName _LoopApp -NotePropertyValue $kv.Key -Force -PassThru
                }
            }
        } while ($token)
    }

    $inventory = foreach ($c in $allContainers) {
        [pscustomobject]@{
            LoopApp        = $c._LoopApp
            Name           = Get-Prop $c @('ContainerName', 'DisplayName', 'Name')
            OwnershipType  = Get-Prop $c @('OwnershipType')
            OwnersCount    = Get-Prop $c @('OwnersCount')
            StorageUsed    = Format-Bytes (Get-Prop $c @('StorageUsedInBytes', 'StorageUsed'))
            Created        = Get-Prop $c @('CreatedOn', 'ContainerCreatedTime', 'CreatedDateTime')
            Status         = Get-Prop $c @('Status', 'ContainerStatus')
            ContainerId    = Get-Prop $c @('ContainerId', 'Id')
            _raw           = $c
        }
    }
    Write-Host ("Total Loop containers in tenant: {0}" -f @($inventory).Count) -ForegroundColor Cyan

    if ($SkipUserMatch) {
        $inventory | Select-Object LoopApp, Name, OwnershipType, OwnersCount, StorageUsed, Created, Status |
            Format-Table -AutoSize
    } else {
        Write-Host "Inspecting container detail to match '$UserEmail' (heuristic; may be slow on large tenants)..." -ForegroundColor DarkGray
        $matched = [System.Collections.Generic.List[object]]::new()
        $checked = 0
        foreach ($item in $inventory) {
            if ($checked -ge $MaxContainers) { Write-Warning "Reached -MaxContainers ($MaxContainers); stopping match scan."; break }
            $checked++
            try {
                $detail = Get-SPOContainer -Identity $item.ContainerId -ErrorAction Stop
                if (Test-Match $detail $UserEmail) {
                    $item | Add-Member -NotePropertyName MatchedOn -NotePropertyValue 'container detail' -Force
                    $matched.Add($item)
                }
            } catch { }
        }
        Write-Section "Loop workspaces matched to $UserEmail"
        if ($matched.Count) {
            $matched | Select-Object LoopApp, Name, OwnershipType, StorageUsed, Created, ContainerId | Format-Table -AutoSize
        } else {
            Write-Host "No workspace membership for this user was found via the container detail heuristic." -ForegroundColor Yellow
            Write-Host "Confirm in SharePoint admin center > Containers, or in the Loop app. Full inventory returned below." -ForegroundColor Yellow
        }
        $matched
    }

    # -------------------------------------------------------------- Deleted (recycled) Loop workspaces
    Write-Section "Deleted Loop workspaces (recycle bin, 93-day retention)"
    try {
        $deleted = Get-SPODeletedContainer -ErrorAction Stop
        $deletedLoop = $deleted | Where-Object {
            $app = Get-Prop $_ @('OwningApplicationId')
            (-not $app) -or ($LoopAppIds.Values -contains ([string]$app))
        }
        if ($deletedLoop) {
            $deletedLoop |
                Select-Object @{n = 'Name'; e = { Get-Prop $_ @('ContainerName', 'DisplayName', 'Name') } },
                              @{n = 'ContainerId'; e = { Get-Prop $_ @('ContainerId', 'Id') } },
                              @{n = 'DeletedOn'; e = { Get-Prop $_ @('DeletedTime', 'DeletedOn') } },
                              @{n = 'MatchesUser'; e = { Test-Match $_ $UserEmail } } |
                Format-Table -AutoSize
        } else { Write-Host "No deleted Loop containers." -ForegroundColor Gray }
    } catch {
        Write-Warning "Get-SPODeletedContainer failed: $($_.Exception.Message)"
    }
} else {
    Write-Warning "No -SPOAdminUrl supplied: skipping Loop workspace (SPE container) sections. Only the OneDrive Loop-file inventory will run."
}

# ------------------------------------------------------------------ OneDrive Loop files (Graph)
Connect-GraphSession -Scopes @('Files.Read.All', 'Sites.Read.All', 'User.Read.All')

$user = Resolve-GraphUserId -User $UserEmail
Write-Section "Loop files in $($user.UserPrincipalName)'s OneDrive (.loop / .fluid)"

$drive = Invoke-MgGraphRequest -Method GET -Uri "/v1.0/users/$($user.Id)/drive?`$select=id,webUrl" -OutputType PSObject
$loopFiles = [System.Collections.Generic.List[object]]::new()
$seen = @{}
foreach ($ext in @('.loop', '.fluid')) {
    $hits = Invoke-GraphPaged -Uri "/v1.0/drives/$($drive.id)/root/search(q='$ext')"
    foreach ($it in $hits) {
        if (-not $it.file) { continue }                       # folders/other
        if ($it.name -notlike "*$ext") { continue }           # search is fuzzy - keep true extension hits
        if ($seen.ContainsKey($it.id)) { continue }
        $seen[$it.id] = $true
        $loopFiles.Add([pscustomobject]@{
            Name         = $it.name
            Size         = Format-Bytes $it.size
            LastModified = $it.lastModifiedDateTime
            ModifiedBy   = $it.lastModifiedBy.user.displayName
            Shared       = [bool]$it.shared
            Path         = $it.parentReference.path
            WebUrl       = $it.webUrl
            ItemId       = $it.id
        })
    }
}

if ($loopFiles.Count) {
    $loopFiles | Select-Object Name, Size, LastModified, Shared, Path | Format-Table -AutoSize
    Write-Host ("Loop files: {0}  (shared: {1})" -f $loopFiles.Count, (@($loopFiles | Where-Object Shared).Count)) -ForegroundColor Green
} else {
    Write-Host "No .loop/.fluid files found in this user's OneDrive." -ForegroundColor Gray
}
$loopFiles
