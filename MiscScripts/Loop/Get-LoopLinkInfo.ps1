<#
.SYNOPSIS
    Resolves a Microsoft Loop (or any OneDrive/SharePoint) sharing link and returns metadata about
    the item it points to, including who has access.

.DESCRIPTION
    Encodes the link into a sharing token and calls the Graph /shares endpoint. Loop pages/components
    are stored as driveItems (.loop packages), so the same call works for them. Sharing/permission
    detail is expanded so you can see how the link is shared.

    Graph scopes (delegated): Files.Read.All + Sites.Read.All   (Files.ReadWrite.All also works).

    Peek only - this does NOT redeem the link, so it won't grant the caller durable access.

.PARAMETER LoopLink   The sharing URL.

.EXAMPLE
    ./Get-LoopLinkInfo.ps1 -LoopLink 'https://contoso.sharepoint.com/:fl:/g/contentstorage/...'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$LoopLink
)

. "$PSScriptRoot/../Common/GraphCommon.ps1"
Connect-GraphSession -Scopes @('Files.Read.All', 'Sites.Read.All')

$token = ConvertTo-GraphShareToken -Url $LoopLink.Trim()
Write-Section "Loop / share link lookup"

try {
    $item = Invoke-MgGraphRequest -Method GET `
        -Uri "/v1.0/shares/$token/driveItem?`$expand=permissions" -OutputType PSObject
} catch {
    throw "Could not resolve the link. Ensure it is a valid, current sharing URL and the identity can read it. $_"
}

$kind = if ($item.package) { "package/$($item.package.type)" }
        elseif ($item.folder) { 'folder' }
        elseif ($item.file) { $item.file.mimeType }
        else { 'item' }

$detail = [pscustomobject]@{
    Name           = $item.name
    Kind           = $kind
    Size           = Format-Bytes $item.size
    CreatedBy      = $item.createdBy.user.displayName
    CreatedByEmail = $item.createdBy.user.email
    Created        = $item.createdDateTime
    ModifiedBy     = $item.lastModifiedBy.user.displayName
    LastModified   = $item.lastModifiedDateTime
    DriveType      = $item.parentReference.driveType
    ParentPath     = $item.parentReference.path
    DriveId        = $item.parentReference.driveId
    ItemId         = $item.id
    WebUrl         = $item.webUrl
}
$detail | Format-List

$perms = @($item.permissions)
Write-Section "Access / sharing ($($perms.Count) permission entr$(if($perms.Count -eq 1){'y'}else{'ies'}))"
if ($perms) {
    $perms | ForEach-Object {
        $grantee = if ($_.grantedToV2.user.displayName) { $_.grantedToV2.user.displayName }
                   elseif ($_.grantedToV2.siteUser.displayName) { $_.grantedToV2.siteUser.displayName }
                   elseif ($_.link) { "link:$($_.link.scope)/$($_.link.type)" }
                   else { '(unknown)' }
        [pscustomobject]@{
            Roles     = ($_.roles -join ',')
            GrantedTo = $grantee
            LinkScope = $_.link.scope
            LinkType  = $_.link.type
            LinkUrl   = $_.link.webUrl
        }
    } | Format-Table -AutoSize
} else {
    Write-Host "No expanded permission entries returned (you may lack rights to read them)." -ForegroundColor Yellow
}

[pscustomobject]@{ Item = $detail; Permissions = $perms }
