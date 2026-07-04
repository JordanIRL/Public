<#
.TITLE
    Get Inactive Licensed Users

.SYNOPSIS
    Licensed users with no sign-in for N days — licence reclaim candidates.

.DESCRIPTION
    Fetches only licensed users (server-side assignedLicenses/$count filter), takes
    the most recent of the interactive and non-interactive sign-in from
    signInActivity, and exports users whose last sign-in is older than the cutoff
    (or who have never signed in) together with their assigned licence SKUs.

.TAGS
    Microsoft365, Licensing, Audit, InactiveUsers, MicrosoftGraph, ReadOnly

.PLATFORM
    PowerShell 7; Microsoft Graph PowerShell SDK

.PERMISSIONS
    User.Read.All, AuditLog.Read.All, Organization.Read.All

.AUTHOR
    Jordan

.VERSION
    1.0.0

.CHANGELOG
    1.0.0 - Initial release.

.LASTUPDATE
    2026-06-10

.EXAMPLE
    .\Get-InactiveLicensedUsers.ps1 -DaysInactive 90

.NOTES
    Read-only report. Connect to Microsoft Graph with the listed scopes before
    running. signInActivity requires Microsoft Entra ID P1. Users with no recorded
    sign-in at all are included as inactive.
#>
param(
    [int]$DaysInactive = 90,
    [string]$OutputPath = (Join-Path (Join-Path $PSScriptRoot 'Exports') "$([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)).csv")
)

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory) {
    New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
}

$cutoff = (Get-Date).AddDays(-$DaysInactive)

$skuMap = @{}
Get-MgSubscribedSku | ForEach-Object { $skuMap[$_.SkuId] = $_.SkuPartNumber }

$users = Get-MgUser -All `
    -Filter 'assignedLicenses/$count ne 0' -ConsistencyLevel eventual -CountVariable licensedCount `
    -Property DisplayName,UserPrincipalName,AccountEnabled,AssignedLicenses,SignInActivity

$report = foreach ($u in $users) {
    $lastSignIn = $u.SignInActivity.LastSignInDateTime
    if ($u.SignInActivity.LastNonInteractiveSignInDateTime -gt $lastSignIn) {
        $lastSignIn = $u.SignInActivity.LastNonInteractiveSignInDateTime
    }
    if ($lastSignIn -ge $cutoff) { continue }

    [pscustomobject]@{
        DisplayName       = $u.DisplayName
        UserPrincipalName = $u.UserPrincipalName
        AccountEnabled    = $u.AccountEnabled
        LastSignIn        = $lastSignIn
        Licenses          = (($u.AssignedLicenses | ForEach-Object { $skuMap[$_.SkuId] }) -join ', ')
    }
}

$report | Sort-Object LastSignIn | Export-Csv -Path $OutputPath -NoTypeInformation
