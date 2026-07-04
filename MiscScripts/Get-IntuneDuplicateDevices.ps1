<#
.TITLE
    Get Intune Duplicate Devices

.SYNOPSIS
    Intune device records sharing a serial number — stale re-enrolment leftovers.

.DESCRIPTION
    Groups managed devices by serial number (skipping blank and known-bogus OEM
    serials) and exports every record where the same serial appears more than once.
    The most recently synced record per serial is marked IsNewest so the older
    duplicates are easy to pick out for cleanup.

.TAGS
    Intune, Devices, Audit, Duplicates, MicrosoftGraph, ReadOnly

.PLATFORM
    PowerShell 7; Microsoft Graph PowerShell SDK

.PERMISSIONS
    DeviceManagementManagedDevices.Read.All

.AUTHOR
    Jordan

.VERSION
    1.0.0

.CHANGELOG
    1.0.0 - Initial release.

.LASTUPDATE
    2026-06-10

.EXAMPLE
    .\Get-IntuneDuplicateDevices.ps1

.NOTES
    Read-only report. Connect to Microsoft Graph with the listed scope before
    running. Review the IsNewest=False rows before deleting anything — virtual
    machines can legitimately share factory-default serials.
#>
param(
    [string]$OutputPath = (Join-Path (Join-Path $PSScriptRoot 'Exports') "$([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)).csv")
)

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory) {
    New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
}

$bogusSerials = @('Defaultstring', 'SystemSerialNumber', 'To Be Filled By O.E.M.', '0')

$devices = Get-MgDeviceManagementManagedDevice -All `
    -Property Id,DeviceName,SerialNumber,UserPrincipalName,OperatingSystem,Model,EnrolledDateTime,LastSyncDateTime

$report = $devices |
    Where-Object { $_.SerialNumber } |
    Where-Object { $bogusSerials -notcontains $_.SerialNumber } |
    Group-Object SerialNumber |
    Where-Object { $_.Count -gt 1 } |
    ForEach-Object {
        $ordered = $_.Group | Sort-Object LastSyncDateTime -Descending
        $newestId = $ordered[0].Id

        foreach ($device in $ordered) {
            [pscustomobject]@{
                SerialNumber      = $device.SerialNumber
                DeviceName        = $device.DeviceName
                UserPrincipalName = $device.UserPrincipalName
                OperatingSystem   = $device.OperatingSystem
                Model             = $device.Model
                EnrolledDateTime  = $device.EnrolledDateTime
                LastSyncDateTime  = $device.LastSyncDateTime
                IsNewest          = ($device.Id -eq $newestId)
            }
        }
    }

$report | Export-Csv -Path $OutputPath -NoTypeInformation
