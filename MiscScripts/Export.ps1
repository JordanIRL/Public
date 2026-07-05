#Requires -Version 5.1
<#
.SYNOPSIS
    Exports Intune Settings Catalog policy settings to CSV.

.DESCRIPTION
    Connects to Microsoft Graph (beta) and exports every setting from every
    Settings Catalog policy (deviceManagement/configurationPolicies) with
    human-readable setting names, category paths and choice values.
    Output is a timestamped CSV in the Export folder next to this script.

.PARAMETER PolicyName
    Only export policies whose name contains this text.

.PARAMETER OutputPath
    Folder to write the CSV to. Defaults to 'Export' next to this script.

.EXAMPLE
    .\Export.ps1

.EXAMPLE
    .\Export.ps1 -PolicyName 'Edge'
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$PolicyName,

    [string]$OutputPath = (Join-Path $PSScriptRoot 'Export')
)

$GraphRoot = 'https://graph.microsoft.com/beta/deviceManagement'
$Scope = 'DeviceManagementConfiguration.Read.All'
$SettingMeta = @{}
$CategoryPath = @{}

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

function Register-Categories {
    $info = @{}
    $uri = "$GraphRoot/configurationCategories?" + '$select=id,displayName,parentCategoryId'
    foreach ($category in @(Get-GraphCollection $uri)) {
        $id = [string](Get-Prop $category 'id')
        $parent = [string](Get-Prop $category 'parentCategoryId')
        if ($parent -eq '00000000-0000-0000-0000-000000000000' -or $parent -eq $id) { $parent = '' }
        if ($id) { $info[$id] = @{ Name = [string](Get-Prop $category 'displayName'); Parent = $parent } }
    }
    foreach ($id in $info.Keys) {
        $parts = @()
        $cursor = $id
        for ($i = 0; $cursor -and $info.ContainsKey($cursor) -and $i -lt 10; $i++) {
            $parts = @($info[$cursor].Name) + $parts
            if ($info[$cursor].Parent -eq $cursor) { break }
            $cursor = $info[$cursor].Parent
        }
        $CategoryPath[$id] = $parts -join ' > '
    }
}

function Ensure-Category([string]$CategoryId) {
    if (-not $CategoryId -or $CategoryPath.ContainsKey($CategoryId)) { return }
    try {
        $category = Invoke-GraphGet "$GraphRoot/configurationCategories/$CategoryId"
        if ($category -is [System.Collections.IDictionary] -and $category.ContainsKey('value')) { $category = $category['value'] }
        $name = [string](Get-Prop $category 'displayName')
        if ($name) {
            $parentId = [string](Get-Prop $category 'parentCategoryId')
            if ($parentId -and $parentId -ne $CategoryId -and $CategoryPath.ContainsKey($parentId)) {
                $name = '{0} > {1}' -f $CategoryPath[$parentId], $name
            }
            $CategoryPath[$CategoryId] = $name
        }
    }
    catch { }
}

function Register-Definition($Definition) {
    if ($Definition -is [System.Collections.IDictionary] -and $Definition.ContainsKey('value')) { $Definition = $Definition['value'] }
    $id = [string](Get-Prop $Definition 'id')
    if (-not $id) { return }

    if (-not $SettingMeta.ContainsKey($id)) {
        $SettingMeta[$id] = @{ Name = ''; CategoryId = ''; RootId = ''; Options = @{} }
    }

    $name = [string](Get-Prop $Definition 'displayName')
    $categoryId = [string](Get-Prop $Definition 'categoryId')
    $rootId = [string](Get-Prop $Definition 'rootDefinitionId')
    if ($name) { $SettingMeta[$id].Name = $name }
    if ($categoryId) { $SettingMeta[$id].CategoryId = $categoryId }
    if ($rootId) { $SettingMeta[$id].RootId = $rootId }

    foreach ($option in @(Get-Prop $Definition 'options')) {
        $optionId = [string](Get-Prop $option 'itemId')
        $optionName = [string](Get-Prop $option 'displayName')
        if (-not $optionName) { $optionName = [string](Get-Prop $option 'name') }
        if ($optionId -and $optionName) { $SettingMeta[$id].Options[$optionId] = $optionName }
    }
}

function Register-Definitions($Definitions) {
    foreach ($definition in @($Definitions)) { Register-Definition $definition }
}

function Ensure-Definition([string]$DefinitionId, [string]$PolicyId, [string]$SettingId) {
    if (-not $DefinitionId) { return }
    if ($SettingMeta.ContainsKey($DefinitionId) -and ($SettingMeta[$DefinitionId].CategoryId -or $SettingMeta[$DefinitionId].RootId)) { return }

    $uris = @()
    if ($PolicyId -and $SettingId) {
        $uris += "$GraphRoot/configurationPolicies/$PolicyId/settings/$SettingId/settingDefinitions/$DefinitionId"
    }
    $uris += "$GraphRoot/configurationSettings/$DefinitionId"

    foreach ($uri in $uris) {
        try {
            Register-Definition (Invoke-GraphGet $uri)
            return
        }
        catch { }
    }
}

function Get-SettingName([string]$DefinitionId) {
    if ($SettingMeta[$DefinitionId] -and $SettingMeta[$DefinitionId].Name) { return [string]$SettingMeta[$DefinitionId].Name }
    return $DefinitionId
}

function Get-SettingCategory([string]$DefinitionId, [string]$PolicyId, [string]$SettingId) {
    if (-not $DefinitionId) { return '' }
    Ensure-Definition -DefinitionId $DefinitionId -PolicyId $PolicyId -SettingId $SettingId

    $definition = $SettingMeta[$DefinitionId]
    if (-not $definition) { return '' }

    $categoryId = $definition.CategoryId
    if ($categoryId -and -not $CategoryPath.ContainsKey($categoryId)) { Ensure-Category $categoryId }
    if ($categoryId -and $CategoryPath.ContainsKey($categoryId)) { return [string]$CategoryPath[$categoryId] }

    if ($definition.RootId -and $definition.RootId -ne $DefinitionId) {
        return Get-SettingCategory -DefinitionId $definition.RootId -PolicyId $PolicyId -SettingId $SettingId
    }

    return ''
}
function Resolve-Choice([string]$DefinitionId, [string]$Value) {
    if ([string]::IsNullOrEmpty($Value)) { return '' }
    if ($SettingMeta[$DefinitionId] -and $SettingMeta[$DefinitionId].Options.ContainsKey($Value)) { return [string]$SettingMeta[$DefinitionId].Options[$Value] }
    if ($DefinitionId -and $Value.StartsWith($DefinitionId + '_')) { return $Value.Substring($DefinitionId.Length + 1) }
    return $Value
}

function Expand-Setting {
    param($Instance, [string]$PolicyName, [string]$Platform, [string]$PolicyId, [string]$SettingId, [System.Collections.Generic.List[object]]$Rows, [string]$InheritedCategory = '')
    if ($null -eq $Instance) { return }

    $type = [string](Get-Prop $Instance '@odata.type')
    $definitionId = [string](Get-Prop $Instance 'settingDefinitionId')
    $settingCategory = Get-SettingCategory -DefinitionId $definitionId -PolicyId $PolicyId -SettingId $SettingId
    if (-not $settingCategory) { $settingCategory = $InheritedCategory }
    $value = ''
    $children = @()
    $emitRow = $true

    switch -Wildcard ($type) {
        '*ChoiceSettingCollectionInstance' {
            $values = @()
            foreach ($choice in @(Get-Prop $Instance 'choiceSettingCollectionValue')) {
                $values += Resolve-Choice $definitionId ([string](Get-Prop $choice 'value'))
                $children += @(Get-Prop $choice 'children')
            }
            $value = $values -join ', '
        }
        '*ChoiceSettingInstance' {
            $choice = Get-Prop $Instance 'choiceSettingValue'
            $value = Resolve-Choice $definitionId ([string](Get-Prop $choice 'value'))
            $children = @(Get-Prop $choice 'children')
        }
        '*SimpleSettingCollectionInstance' {
            $value = (@(Get-Prop $Instance 'simpleSettingCollectionValue') | ForEach-Object { [string](Get-Prop $_ 'value') }) -join ', '
        }
        '*SimpleSettingInstance' {
            $value = [string](Get-Prop (Get-Prop $Instance 'simpleSettingValue') 'value')
        }
        '*GroupSettingCollectionInstance' {
            foreach ($group in @(Get-Prop $Instance 'groupSettingCollectionValue')) { $children += @(Get-Prop $group 'children') }
            $emitRow = $false
        }
        '*GroupSettingInstance' {
            $children = @(Get-Prop (Get-Prop $Instance 'groupSettingValue') 'children')
            $emitRow = $false
        }
        '*SettingGroupCollectionInstance' {
            foreach ($group in @(Get-Prop $Instance 'settingGroupCollectionValue')) { $children += @(Get-Prop $group 'children') }
            $emitRow = $false
        }
        '*SettingGroupInstance' {
            $children = @(Get-Prop (Get-Prop $Instance 'settingGroupValue') 'children')
            $emitRow = $false
        }
    }

    if ($emitRow) {
        $Rows.Add([pscustomobject]@{
            PolicyName      = $PolicyName
            Platform        = $Platform
            SettingCategory = $settingCategory
            SettingName     = Get-SettingName $definitionId
            Value           = $value
        })
    }

    foreach ($child in $children) { Expand-Setting -Instance $child -PolicyName $PolicyName -Platform $Platform -PolicyId $PolicyId -SettingId $SettingId -Rows $Rows -InheritedCategory $settingCategory }
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

Write-Host 'Loading setting categories...'
Register-Categories

Write-Host 'Loading configuration policies...'
$policies = @(Get-GraphCollection ("$GraphRoot/configurationPolicies?" + '$select=id,name,platforms'))
if ($PolicyName) {
    $policies = @($policies | Where-Object { ([string](Get-Prop $_ 'name')) -like "*$PolicyName*" })
}
if ($policies.Count -eq 0) {
    if ($PolicyName) { Write-Warning "No policies found matching '*$PolicyName*'." }
    else { Write-Warning 'No Settings Catalog policies found in this tenant.' }
}

$policyIndex = 0
$failedPolicies = 0
foreach ($policy in $policies) {
    $policyIndex++
    $policyId = [string](Get-Prop $policy 'id')
    $policyDisplayName = [string](Get-Prop $policy 'name')
    if (-not $policyDisplayName) { $policyDisplayName = $policyId }
    $platform = [string](Get-Prop $policy 'platforms')
    Write-Host ('[{0}/{1}] {2}' -f $policyIndex, $policies.Count, $policyDisplayName)

    try {
        $uri = "$GraphRoot/configurationPolicies/$policyId/settings?" + '$expand=settingDefinitions'
        try { $settings = @(Get-GraphCollection $uri) }
        catch { $settings = @(Get-GraphCollection "$GraphRoot/configurationPolicies/$policyId/settings") }

        foreach ($setting in $settings) { Register-Definitions (Get-Prop $setting 'settingDefinitions') }
        foreach ($setting in $settings) {
            Expand-Setting -Instance (Get-Prop $setting 'settingInstance') -PolicyName $policyDisplayName -Platform $platform -PolicyId $policyId -SettingId ([string](Get-Prop $setting 'id')) -Rows $rows
        }
    }
    catch {
        $failedPolicies++
        Write-Warning ("Skipping policy '{0}': {1}" -f $policyDisplayName, $_.Exception.Message)
    }
}

$csvPath = Join-Path $OutputPath ('PolicySettings_{0}.csv' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm'))
if ($rows.Count -gt 0) {
    $rows.ToArray() | Sort-Object PolicyName, SettingCategory, SettingName | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
}
else {
    'PolicyName,Platform,SettingCategory,SettingName,Value' | Out-File -FilePath $csvPath -Encoding utf8
}

Write-Host ''
Write-Host ('Exported {0} settings from {1} of {2} policies to: {3}' -f $rows.Count, ($policies.Count - $failedPolicies), $policies.Count, $csvPath)
if ($failedPolicies -gt 0) { Write-Warning ('{0} policies could not be exported (see warnings above).' -f $failedPolicies) }
