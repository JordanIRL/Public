<#
.TITLE
    Get Intune Unencrypted Devices

.SYNOPSIS
    Intune-managed devices not reporting disk encryption.

.DESCRIPTION
    Exports managed devices where isEncrypted is false or not reported — BitLocker
    on Windows, FileVault on macOS, device encryption on mobile — with compliance
    state and last sync so dead records are easy to spot.

.TAGS
    Intune, Devices, Audit, Encryption, BitLocker, FileVault, MicrosoftGraph, ReadOnly

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
    .\Get-IntuneUnencryptedDevices.ps1

.NOTES
    Read-only report. Connect to Microsoft Graph with the listed scope before
    running. Devices that have never reported hardware inventory show as
    unencrypted until their first full sync.
#>
param(
    [string]$OutputPath = (Join-Path (Join-Path $PSScriptRoot 'Exports') "$([IO.Path]::GetFileNameWithoutExtension($PSCommandPath)).csv")
)

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory) {
    New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
}

Get-MgDeviceManagementManagedDevice -All `
    -Property DeviceName,UserPrincipalName,OperatingSystem,OsVersion,Model,IsEncrypted,ComplianceState,LastSyncDateTime |
    Where-Object { -not $_.IsEncrypted } |
    Select-Object DeviceName,UserPrincipalName,OperatingSystem,OsVersion,Model,ComplianceState,LastSyncDateTime |
    Export-Csv -Path $OutputPath -NoTypeInformation
