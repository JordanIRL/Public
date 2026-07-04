<#
.TITLE
    Get Duplicate Licence Assignments

.SYNOPSIS
    Users holding the same licence SKU both directly and via group-based licensing.

.DESCRIPTION
    Reads licenseAssignmentStates for every licensed user and flags SKUs assigned
    more than once — directly and inherited from one or more groups. The direct
    assignment is usually safe to remove once the group assignment is active,
    freeing nothing but tidying the tenant and preventing future double-billing
    confusion.

.TAGS
    Microsoft365, Licensing, Audit, GroupBasedLicensing, MicrosoftGraph, ReadOnly

.PLATFORM
    PowerShell 7; Microsoft Graph PowerShell SDK

.PERMISSIONS
    User.Read.All, Group.Read.All, Organization.Read.All

.AUTHOR
    Jordan

.VERSION
    1.0.0

.CHANGELOG
    1.0.0 - Initial release.

.LASTUPDATE
    2026-06-10

.EXAMPLE
    .\Get-DuplicateLicenseAssignments.ps1

.NOTES
    Read-only report. Connect to Microsoft Graph with the listed scopes before
    running. One row per duplicated SKU per user.
#>
param(
    [string]$OutputPath = (Join-Path (Join-Path $PSScriptRoot 'Exports') "$([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)).csv")
)

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory) {
    New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
}

$skuMap = @{}
Get-MgSubscribedSku | ForEach-Object { $skuMap[$_.SkuId] = $_.SkuPartNumber }

$groupNames = @{}

$users = Get-MgUser -All `
    -Filter 'assignedLicenses/$count ne 0' -ConsistencyLevel eventual -CountVariable licensedCount `
    -Property DisplayName,UserPrincipalName,LicenseAssignmentStates

$report = foreach ($u in $users) {
    foreach ($sku in ($u.LicenseAssignmentStates | Group-Object SkuId)) {
        $direct = @($sku.Group | Where-Object { -not $_.AssignedByGroup })
        $fromGroups = @($sku.Group | Where-Object { $_.AssignedByGroup })
        if ($direct.Count -eq 0) { continue }
        if ($fromGroups.Count -eq 0) { continue }

        $names = foreach ($state in $fromGroups) {
            if (-not $groupNames.ContainsKey($state.AssignedByGroup)) {
                $groupNames[$state.AssignedByGroup] = (Get-MgGroup -GroupId $state.AssignedByGroup -Property DisplayName).DisplayName
            }
            $groupNames[$state.AssignedByGroup]
        }

        $license = $skuMap[$sku.Name]
        if (-not $license) { $license = $sku.Name }

        [pscustomobject]@{
            DisplayName       = $u.DisplayName
            UserPrincipalName = $u.UserPrincipalName
            License           = $license
            AssignedByGroups  = ($names -join ', ')
        }
    }
}

$report | Sort-Object UserPrincipalName, License | Export-Csv -Path $OutputPath -NoTypeInformation
