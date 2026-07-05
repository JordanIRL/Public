#Requires -Version 5.1
<#
.SYNOPSIS
    Exports classic Intune device configuration profile settings to CSV.

.DESCRIPTION
    Connects to Microsoft Graph (beta) and exports every configured property of
    every classic device configuration profile (deviceManagement/deviceConfigurations),
    including template profiles, custom OMA-URI profiles and update rings.
    Output is a timestamped CSV in the Export folder next to this script.

    Settings Catalog policies are covered by Export.ps1 and compliance policies
    by Export-CompliancePolicies.ps1.

.PARAMETER PolicyName
    Only export profiles whose name contains this text.

.PARAMETER OutputPath
    Folder to write the CSV to. Defaults to 'Export' next to this script.

.EXAMPLE
    .\Export-DeviceConfigurations.ps1

.EXAMPLE
    .\Export-DeviceConfigurations.ps1 -PolicyName 'Kiosk'
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$PolicyName,

    [string]$OutputPath = (Join-Path $PSScriptRoot 'Export')
)

$GraphRoot = 'https://graph.microsoft.com/beta/deviceManagement'
$Scope = 'DeviceManagementConfiguration.Read.All'

# Profile metadata properties that are not settings.
$SkipProperties = @(
    'id', 'displayName', 'description', 'createdDateTime', 'lastModifiedDateTime', 'version',
    'roleScopeTagIds', 'supportsScopeTags', 'assignments',
    'deviceManagementApplicabilityRuleOsEdition', 'deviceManagementApplicabilityRuleOsVersion',
    'deviceManagementApplicabilityRuleDeviceMode'
)

function Get-Prop($Item, [string]$Name) {
    if ($null -eq $Item) { return $null }
    if ($Item -is [System.Collections.IDictionary]) {
        if ($Item.ContainsKey($Name)) { return $Item[$Name] }
        return $null
    }
    return $Item.$Name
}

function Invoke-GraphGet {
    param([Parameter(Mandatory)][string]$Uri)
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        try {
            $params = @{ Method = 'GET'; Uri = $Uri; OutputType = 'HashTable'; ErrorAction = 'Stop' }
            return Invoke-MgGraphRequest @params
        }
        catch {
            $retryable = $_.Exception.Message -match '429|TooManyRequests|throttl|timed?\s?out|temporarily|502|503|504|InternalServerError|ServiceUnavailable|BadGateway|GatewayTimeout'
            if (-not $retryable -or $attempt -eq 6) { throw }
            Start-Sleep -Seconds ([math]::Min(60, [math]::Pow(2, $attempt) * 2))
        }
    }
}

function Get-GraphCollection {
    param([Parameter(Mandatory)][string]$Uri)
    $items = New-Object System.Collections.Generic.List[object]
    while ($Uri) {
        $response = Invoke-GraphGet -Uri $Uri
        if ($response -is [System.Collections.IDictionary] -and $response.ContainsKey('value')) {
            foreach ($item in @($response['value'])) { $items.Add($item) }
            $Uri = Get-Prop $response '@odata.nextLink'
        }
        else {
            $items.Add($response)
            $Uri = $null
        }
    }
    return $items
}

function Get-PlatformFromType([string]$ODataType) {
    $typeName = $ODataType -replace '^#microsoft\.graph\.', ''
    if ($typeName -match '^(windows|sharedPC|editionUpgrade)') { return 'Windows' }
    if ($typeName -match '^(android|aosp)') { return 'Android' }
    if ($typeName -match '^ios') { return 'iOS/iPadOS' }
    if ($typeName -match '^macOS') { return 'macOS' }
    return ''
}

function Add-SettingRows {
    param($Value, [string]$Name, [System.Collections.Generic.List[object]]$Target)
    if ($null -eq $Value) { return }

    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in @($Value.Keys)) {
            if ($key -eq 'id' -or $key -like '*@odata*') { continue }
            Add-SettingRows -Value $Value[$key] -Name ('{0}.{1}' -f $Name, $key) -Target $Target
        }
        return
    }

    if ($Value -is [System.Collections.IList]) {
        $hasComplexItems = $false
        foreach ($item in $Value) {
            if ($item -is [System.Collections.IDictionary] -or $item -is [System.Collections.IList]) { $hasComplexItems = $true; break }
        }
        if (-not $hasComplexItems) {
            if ($Value.Count -gt 0) { $Target.Add(@{ Name = $Name; Value = (@($Value) -join '; ') }) }
        }
        else {
            for ($i = 0; $i -lt $Value.Count; $i++) {
                Add-SettingRows -Value $Value[$i] -Name ('{0}[{1}]' -f $Name, $i) -Target $Target
            }
        }
        return
    }

    $text = [string]$Value
    if ($text -eq '') { return }
    $Target.Add(@{ Name = $Name; Value = $text })
}

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    throw 'Microsoft.Graph.Authentication module not found. Install it with: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser'
}

Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

$acceptedScopes = @('DeviceManagementConfiguration.Read.All', 'DeviceManagementConfiguration.ReadWrite.All')
$context = Get-MgContext
$connected = $context -and $context.AuthType -eq 'Delegated' -and @($context.Scopes | Where-Object { $acceptedScopes -contains $_ }).Count -gt 0
if (-not $connected) {
    Connect-MgGraph -Scopes $Scope -NoWelcome -ErrorAction Stop | Out-Null
}

$null = New-Item -ItemType Directory -Path $OutputPath -Force
$rows = New-Object System.Collections.Generic.List[object]

Write-Host 'Loading device configuration profiles...'
$configProfiles = @(Get-GraphCollection "$GraphRoot/deviceConfigurations")
if ($PolicyName) {
    $configProfiles = @($configProfiles | Where-Object { ([string](Get-Prop $_ 'displayName')) -like "*$PolicyName*" })
}
if ($configProfiles.Count -eq 0) {
    if ($PolicyName) { Write-Warning "No profiles found matching '*$PolicyName*'." }
    else { Write-Warning 'No classic device configuration profiles found in this tenant.' }
}

$profileIndex = 0
foreach ($configProfile in $configProfiles) {
    $profileIndex++
    $profileName = [string](Get-Prop $configProfile 'displayName')
    if (-not $profileName) { $profileName = [string](Get-Prop $configProfile 'id') }
    $odataType = [string](Get-Prop $configProfile '@odata.type')
    $profileType = $odataType -replace '^#microsoft\.graph\.', ''
    $platform = Get-PlatformFromType $odataType
    Write-Host ('[{0}/{1}] {2}' -f $profileIndex, $configProfiles.Count, $profileName)

    $settingRows = New-Object System.Collections.Generic.List[object]
    foreach ($key in @($configProfile.Keys)) {
        if ($SkipProperties -contains $key -or $key -like '*@odata*') { continue }
        Add-SettingRows -Value $configProfile[$key] -Name ([string]$key) -Target $settingRows
    }
    foreach ($settingRow in $settingRows) {
        $rows.Add([pscustomobject]@{
            PolicyName  = $profileName
            Platform    = $platform
            ProfileType = $profileType
            SettingName = $settingRow.Name
            Value       = $settingRow.Value
        })
    }
}

$csvPath = Join-Path $OutputPath ('DeviceConfigurations_{0}.csv' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
if ($rows.Count -gt 0) {
    $rows.ToArray() | Sort-Object PolicyName, SettingName | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
}
else {
    'PolicyName,Platform,ProfileType,SettingName,Value' | Out-File -FilePath $csvPath -Encoding utf8
}

Write-Host ''
Write-Host ('Exported {0} settings from {1} profiles to: {2}' -f $rows.Count, $configProfiles.Count, $csvPath)
