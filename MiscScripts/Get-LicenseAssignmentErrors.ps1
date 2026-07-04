<#
.TITLE
    Get Licence Assignment Errors

.SYNOPSIS
    Users whose group-based licence assignment failed, with the failing SKU and error.

.DESCRIPTION
    Finds groups flagged with hasMembersWithLicenseErrors, lists each member with a
    licence error, and reports the failing SKU and error reason (CountViolation,
    MutuallyExclusiveViolation, ProhibitedInUsageLocationViolation, ...) from the
    user's licenseAssignmentStates.

.TAGS
    Microsoft365, Licensing, Audit, GroupBasedLicensing, LicenceErrors, MicrosoftGraph, ReadOnly

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
    .\Get-LicenseAssignmentErrors.ps1

.NOTES
    Read-only report. Connect to Microsoft Graph with the listed scopes before
    running. CountViolation means the SKU is out of seats; fix by buying seats or
    reclaiming licences, then the group assignment retries automatically.
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

$groups = Get-MgGroup -All -Filter 'hasMembersWithLicenseErrors eq true' -Property Id,DisplayName

$report = foreach ($group in $groups) {
    $members = Get-MgGroupMemberWithLicenseError -GroupId $group.Id -All

    foreach ($member in $members) {
        $u = Get-MgUser -UserId $member.Id -Property DisplayName,UserPrincipalName,LicenseAssignmentStates

        $errorStates = $u.LicenseAssignmentStates |
            Where-Object { $_.AssignedByGroup -eq $group.Id } |
            Where-Object { $_.Error } |
            Where-Object { $_.Error -ne 'None' }

        foreach ($state in $errorStates) {
            $license = $skuMap[$state.SkuId]
            if (-not $license) { $license = $state.SkuId }

            [pscustomobject]@{
                GroupName         = $group.DisplayName
                DisplayName       = $u.DisplayName
                UserPrincipalName = $u.UserPrincipalName
                License           = $license
                State             = $state.State
                Error             = $state.Error
            }
        }
    }
}

$report | Sort-Object GroupName, UserPrincipalName | Export-Csv -Path $OutputPath -NoTypeInformation
