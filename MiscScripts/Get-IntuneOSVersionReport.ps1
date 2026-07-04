<#
.TITLE
    Get Intune OS Version Report

.SYNOPSIS
    Device counts per operating system and OS version across Intune.

.DESCRIPTION
    Groups all managed devices by operating system and version and exports the
    counts, largest first per platform — a quick patch-currency view for spotting
    Windows builds and mobile OS versions that have fallen behind.

.TAGS
    Intune, Devices, Audit, OSVersion, Patching, MicrosoftGraph, ReadOnly

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
    .\Get-IntuneOSVersionReport.ps1

.NOTES
    Read-only report. Connect to Microsoft Graph with the listed scope before
    running.
#>
param(
    [string]$OutputPath = (Join-Path (Join-Path $PSScriptRoot 'Exports') "$([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)).csv")
)

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory) {
    New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
}

Get-MgDeviceManagementManagedDevice -All -Property OperatingSystem,OsVersion |
    Group-Object OperatingSystem,OsVersion |
    ForEach-Object {
        [pscustomobject]@{
            OperatingSystem = $_.Group[0].OperatingSystem
            OsVersion       = $_.Group[0].OsVersion
            DeviceCount     = $_.Count
        }
    } |
    Sort-Object OperatingSystem, @{Expression = 'DeviceCount'; Descending = $true} |
    Export-Csv -Path $OutputPath -NoTypeInformation
