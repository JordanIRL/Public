#Requires -Version 5.1
<#
.SYNOPSIS
    Exports Intune configurations via Microsoft Graph (delegated, read-only) and produces a
    hygiene report identifying duplicated, redundant, unassigned and stale configuration.

.DESCRIPTION
    Connects to Microsoft Graph with delegated (interactive) authentication using read-only
    scopes, exports every major Intune configuration type, then analyses the results:

      - Exact duplicates        : policies of the same type whose settings are identical
                                  (names/descriptions ignored, so renamed copies are caught)
      - Duplicate names         : different policies sharing the same display name
      - Unassigned ("not in use"): policies with no assignments at all
      - Exclude-only            : policies whose only assignments are exclusions
      - Effectively unassigned  : policies whose only include targets are empty groups
      - Missing groups          : assignments pointing at deleted groups
      - Stale                   : unassigned policies untouched for longer than -StaleDays
      - Empty policies          : settings catalog policies with zero settings
      - Unused filters          : assignment filters not referenced by any assignment
      - Setting overlaps        : the same settings-catalog setting configured in multiple
                                  assigned policies (conflict/redundancy candidates)

    Configuration types collected (Graph beta endpoint):
      Settings Catalog, Device Configuration profiles (templates), Administrative Templates,
      Compliance policies, Endpoint Security intents, PowerShell scripts, macOS shell scripts,
      Remediations, App Protection (iOS/Android/Windows), App Configuration (managed apps +
      managed devices), Applications, Autopilot profiles, Enrollment configurations,
      Windows Feature/Quality/Driver update profiles, Assignment filters.

    Output (everything lands in -OutputPath):
      IntuneAudit.xlsx : one workbook, one sheet per report (Findings, Inventory,
                         Assignments, Duplicates, SettingOverlaps, PolicySettings, Filters),
                         with AutoFilter enabled and group/policy/setting display names
                         instead of GUIDs
      Summary.md       : human-readable run summary
      RawExport\*.json : full raw Graph export per type - only with -IncludeRawExport

.PARAMETER OutputPath
    Folder for all output. Default: .\IntuneAudit_<timestamp>

.PARAMETER IncludeRawExport
    Also write the full raw Graph JSON per configuration type to RawExport\ (useful as a
    point-in-time backup or for deep inspection). Off by default.

.PARAMETER StaleDays
    Policies unmodified for more than this many days are considered stale. Default 180.

.PARAMETER Quick
    Skip the deep per-policy fetches (settings bodies, script content). Much faster on large
    tenants, but exact-duplicate detection and setting-overlap analysis are skipped for the
    types that need a deep fetch.

.PARAMETER SkipGroupResolution
    Skip resolving assignment group names and member counts (fewer Graph calls, but the
    empty-group and deleted-group analysis is skipped).

.PARAMETER UseDeviceCode
    Use device-code sign-in instead of the browser pop-up (useful over SSH / headless).

.PARAMETER Categories
    Limit collection to specific categories. Default: All.

.EXAMPLE
    .\Invoke-IntuneConfigAudit.ps1

.EXAMPLE
    .\Invoke-IntuneConfigAudit.ps1 -OutputPath C:\Temp\IntuneAudit -StaleDays 90

.EXAMPLE
    .\Invoke-IntuneConfigAudit.ps1 -Quick -Categories SettingsCatalog,DeviceConfigurations

.NOTES
    Read-only: the script only ever issues GET requests (plus directoryObjects/getByIds,
    a read-only POST used to resolve group names in bulk).
    Required delegated scopes (admin consent required, signed-in user needs an Intune role):
      DeviceManagementConfiguration.Read.All, DeviceManagementApps.Read.All,
      DeviceManagementServiceConfig.Read.All, DeviceManagementScripts.Read.All, Group.Read.All
#>
[CmdletBinding()]
param(
    [string]$OutputPath,

    [int]$StaleDays = 180,

    [switch]$Quick,

    [switch]$SkipGroupResolution,

    [switch]$UseDeviceCode,

    [switch]$IncludeRawExport,

    [ValidateSet('All', 'SettingsCatalog', 'DeviceConfigurations', 'AdminTemplates',
        'CompliancePolicies', 'EndpointSecurity', 'Scripts', 'Remediations', 'AppProtection',
        'AppConfiguration', 'Applications', 'Autopilot', 'EnrollmentConfigurations', 'WindowsUpdates')]
    [string[]]$Categories = @('All')
)

$GraphBeta = 'https://graph.microsoft.com/beta'
$GraphV1   = 'https://graph.microsoft.com/v1.0'

# Keys stripped before hashing policy bodies, so that renamed/recreated copies still match.
$script:VolatileKeys = @(
    'id', 'createdDateTime', 'lastModifiedDateTime', 'modifiedDateTime', 'version',
    '@odata.context', '@odata.count', '@odata.nextLink', '@odata.id',
    'assignments', 'roleScopeTagIds', 'supportsScopeTags', 'settingCount', 'isAssigned',
    'creationSource', 'priorityMetaData', 'deployedAppCount', 'priority',
    'displayName', 'name', 'description', 'presentation@odata.bind',
    'uploadState', 'publishingState', 'size', 'dependentAppCount', 'supersededAppCount',
    'supersedingAppCount', 'usedLicenseCount', 'totalLicenseCount',
    'settingDefinitions'   # display metadata fetched alongside settings; not configuration
)

# settingDefinitionId -> @{ Name = display name; Options = @{ optionItemId -> option display name }; CategoryId }
$script:SettingDefMeta = @{}
# categoryId -> portal category path, e.g. 'Defender' or 'Administrative Templates > Printers'
$script:CategoryPathById = @{}

#region ---- Helper functions -----------------------------------------------------------------

function Get-Prop {
    param($Item, [string]$Name)
    if ($null -eq $Item) { return $null }
    if ($Item -is [System.Collections.IDictionary]) {
        if ($Item.ContainsKey($Name)) { return $Item[$Name] }
        return $null
    }
    return $Item.$Name
}

function Invoke-GraphRequestWithRetry {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [string]$Method = 'GET',
        $Body,
        [hashtable]$Headers,
        [int]$MaxAttempts = 6
    )
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            $params = @{ Method = $Method; Uri = $Uri; OutputType = 'HashTable'; ErrorAction = 'Stop' }
            if ($Headers) { $params['Headers'] = $Headers }
            if ($null -ne $Body) {
                $params['Body'] = $Body
                $params['ContentType'] = 'application/json'
            }
            return Invoke-MgGraphRequest @params
        }
        catch {
            $msg = $_.Exception.Message
            $retryable = $msg -match '429|TooManyRequests|throttl|timed?\s?out|temporarily|502|503|504|InternalServerError|ServiceUnavailable|BadGateway|GatewayTimeout'
            if ($retryable -and $attempt -lt $MaxAttempts) {
                $delay = [math]::Min(60, [int][math]::Pow(2, $attempt) * 2)
                Write-Verbose "Retrying ($attempt/$MaxAttempts) after ${delay}s - $Uri : $msg"
                Start-Sleep -Seconds $delay
                continue
            }
            throw
        }
    }
}

function Get-GraphCollection {
    param([Parameter(Mandatory)][string]$Uri, [hashtable]$Headers)
    $list = New-Object System.Collections.Generic.List[object]
    $next = $Uri
    while ($next) {
        $resp = Invoke-GraphRequestWithRetry -Uri $next -Headers $Headers
        if ($resp -is [System.Collections.IDictionary] -and $resp.ContainsKey('value')) {
            foreach ($v in @($resp['value'])) { $list.Add($v) }
            $next = Get-Prop $resp '@odata.nextLink'
        }
        else {
            $list.Add($resp)
            $next = $null
        }
    }
    # Emit items via the pipeline; callers collect with @(...). Returning the List itself
    # (",$list") makes @() yield a single element containing the List.
    return $list
}

function ConvertTo-CanonicalStructure {
    # Recursively sorts keys and strips volatile/instance-specific keys so two policies with
    # the same effective configuration produce the same JSON, regardless of creation order.
    param($InputObject)
    if ($InputObject -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        $keys = @($InputObject.Keys | ForEach-Object { [string]$_ } | Sort-Object)
        foreach ($key in $keys) {
            if ($script:VolatileKeys -contains $key) { continue }
            $ordered[$key] = ConvertTo-CanonicalStructure -InputObject $InputObject[$key]
        }
        return $ordered
    }
    if ($null -eq $InputObject -or $InputObject -is [string] -or $InputObject -is [System.ValueType]) {
        return $InputObject
    }
    if ($InputObject -is [System.Collections.IEnumerable]) {
        $arr = @()
        foreach ($el in $InputObject) { $arr += , (ConvertTo-CanonicalStructure -InputObject $el) }
        return , $arr
    }
    return $InputObject
}

function Get-StructureHash {
    param($Structure)
    if ($null -eq $Structure) { return $null }
    $json = ConvertTo-Json -InputObject $Structure -Depth 50 -Compress
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($json))
        return ([System.BitConverter]::ToString($bytes) -replace '-', '').Substring(0, 16)
    }
    finally { $sha.Dispose() }
}

function ConvertTo-DateTimeOrNull {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse([string]$Value, [ref]$parsed)) { return $parsed.ToUniversalTime() }
    return $null
}

function Get-PlatformFromODataType {
    param([string]$ODataType)
    if ([string]::IsNullOrEmpty($ODataType)) { return '' }
    switch -Regex ($ODataType) {
        'androidForWork|androidManagedStore|androidWork|androidDeviceOwner|androidEnterprise' { return 'Android (Enterprise)' }
        'aosp'                                                  { return 'Android (AOSP)' }
        'android'                                               { return 'Android' }
        'ios|iPad'                                              { return 'iOS/iPadOS' }
        'macOS|macOs'                                           { return 'macOS' }
        'windows|win32|officeSuite|microsoftEdge|webApp'        { return 'Windows' }
        'linux'                                                 { return 'Linux' }
        default                                                 { return '' }
    }
}

function ConvertTo-FriendlyTypeName {
    # '#microsoft.graph.windows10VpnConfiguration' -> 'Windows10 VPN Configuration'
    param([string]$ODataType)
    if ([string]::IsNullOrEmpty($ODataType)) { return '' }
    $t = $ODataType -replace '^#microsoft\.graph\.', ''
    $t = $t -creplace '([a-z0-9])([A-Z])', '$1 $2'
    $t = $t -creplace '([A-Z]+)([A-Z][a-z])', '$1 $2'
    $t = $t.Substring(0, 1).ToUpper() + $t.Substring(1)
    $acronyms = @{ 'Vpn' = 'VPN'; 'Wifi' = 'Wi-Fi'; 'Eap' = 'EAP'; 'Scep' = 'SCEP'; 'Pkcs' = 'PKCS'
                   'Vpp' = 'VPP'; 'Dep' = 'DEP'; 'Lob' = 'LOB'; 'Ios' = 'iOS'; 'Url' = 'URL'; 'Apn' = 'APN' }
    foreach ($k in $acronyms.Keys) { $t = $t -creplace ('\b' + $k + '\b'), $acronyms[$k] }
    return $t
}

function Format-CatalogPlatform {
    # Settings catalog 'platforms' values -> portal-style names ('windows10' -> 'Windows')
    param([string]$Platforms)
    if ([string]::IsNullOrEmpty($Platforms)) { return '' }
    $map = @{ 'windows10' = 'Windows'; 'macOS' = 'macOS'; 'iOS' = 'iOS/iPadOS'; 'android' = 'Android'
              'androidEnterprise' = 'Android (Enterprise)'; 'linux' = 'Linux'; 'none' = '' }
    $parts = @()
    foreach ($p in ($Platforms -split ',')) {
        $key = $p.Trim()
        if ($map.ContainsKey($key)) { if ($map[$key]) { $parts += $map[$key] } }
        elseif ($key) { $parts += $key }
    }
    return ($parts -join ', ')
}

function Register-SettingDefinitions {
    # Cache display names and choice-option labels from $expand=settingDefinitions.
    param($Definitions)
    foreach ($def in @($Definitions)) {
        if ($null -eq $def) { continue }
        $defKey = [string](Get-Prop $def 'id')
        if (-not $defKey -or $script:SettingDefMeta.ContainsKey($defKey)) { continue }
        $opts = @{}
        foreach ($o in @(Get-Prop $def 'options')) {
            $optId = [string](Get-Prop $o 'itemId')
            $optName = [string](Get-Prop $o 'displayName')
            if (-not $optName) { $optName = [string](Get-Prop $o 'name') }
            if ($optId -and $optName) { $opts[$optId] = $optName }
        }
        $script:SettingDefMeta[$defKey] = @{
            Name       = [string](Get-Prop $def 'displayName')
            Options    = $opts
            CategoryId = [string](Get-Prop $def 'categoryId')
        }
    }
}

function Get-SettingDisplayName {
    param([string]$DefId)
    $m = $script:SettingDefMeta[$DefId]
    if ($m -and $m.Name) { return [string]$m.Name }
    return $DefId
}

function Get-SettingCategory {
    # Portal category for a settings-catalog setting ('Defender', 'Firewall', ...).
    param([string]$DefId)
    $m = $script:SettingDefMeta[$DefId]
    if ($m -and $m.CategoryId -and $script:CategoryPathById.ContainsKey([string]$m.CategoryId)) {
        return [string]$script:CategoryPathById[[string]$m.CategoryId]
    }
    return ''
}

function Resolve-ChoiceOptionName {
    # Raw choice values look like '<settingDefinitionId>_1'; map to the option label.
    param([string]$DefId, [string]$RawValue)
    if ([string]::IsNullOrEmpty($RawValue)) { return '' }
    $m = $script:SettingDefMeta[$DefId]
    if ($m -and $m.Options.ContainsKey($RawValue)) { return [string]$m.Options[$RawValue] }
    if ($DefId -and $RawValue.StartsWith($DefId + '_')) { return $RawValue.Substring($DefId.Length + 1) }
    return $RawValue
}

function Expand-SettingInstance {
    # Flattens a settings-catalog setting instance (incl. nested children) into
    # rows of SettingDefinitionId / SettingName / Value / Depth.
    param($Instance, [int]$Depth = 0)
    $rows = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Instance) { return $rows }
    $type = [string](Get-Prop $Instance '@odata.type')
    $defId = [string](Get-Prop $Instance 'settingDefinitionId')
    $value = ''
    $children = @()
    switch -Wildcard ($type) {
        '*ChoiceSettingCollectionInstance' {
            $vals = @()
            foreach ($cv in @(Get-Prop $Instance 'choiceSettingCollectionValue')) {
                if ($null -eq $cv) { continue }
                $vals += Resolve-ChoiceOptionName -DefId $defId -RawValue ([string](Get-Prop $cv 'value'))
                $children += @(Get-Prop $cv 'children')
            }
            $value = $vals -join ', '
            break
        }
        '*ChoiceSettingInstance' {
            $cv = Get-Prop $Instance 'choiceSettingValue'
            $value = Resolve-ChoiceOptionName -DefId $defId -RawValue ([string](Get-Prop $cv 'value'))
            $children = @(Get-Prop $cv 'children')
            break
        }
        '*SimpleSettingCollectionInstance' {
            $value = (@(Get-Prop $Instance 'simpleSettingCollectionValue') | ForEach-Object { [string](Get-Prop $_ 'value') }) -join ', '
            break
        }
        '*SimpleSettingInstance' {
            $value = [string](Get-Prop (Get-Prop $Instance 'simpleSettingValue') 'value')
            break
        }
        '*GroupSettingCollectionInstance' {
            $groups = @(Get-Prop $Instance 'groupSettingCollectionValue')
            $value = '(settings group, {0} item(s))' -f $groups.Count
            foreach ($gv in $groups) { if ($null -ne $gv) { $children += @(Get-Prop $gv 'children') } }
            break
        }
        default { }
    }
    $rows.Add([pscustomobject]@{
        SettingDefinitionId = $defId
        SettingName         = Get-SettingDisplayName -DefId $defId
        Value               = $value
        Depth               = $Depth
    })
    foreach ($child in $children) {
        if ($null -eq $child) { continue }
        foreach ($r in @(Expand-SettingInstance -Instance $child -Depth ($Depth + 1))) { $rows.Add($r) }
    }
    return $rows
}

function ConvertTo-AssignmentInfo {
    param($Assignment)
    $target = Get-Prop $Assignment 'target'
    if ($null -eq $target) { return $null }
    $type = [string](Get-Prop $target '@odata.type')
    $kind = 'Unknown'
    $groupId = $null
    switch -Wildcard ($type) {
        '*allDevicesAssignmentTarget'        { $kind = 'AllDevices'; break }
        '*allLicensedUsersAssignmentTarget'  { $kind = 'AllUsers'; break }
        '*exclusionGroupAssignmentTarget'    { $kind = 'ExcludeGroup'; $groupId = Get-Prop $target 'groupId'; break }
        '*groupAssignmentTarget'             { $kind = 'IncludeGroup'; $groupId = Get-Prop $target 'groupId'; break }
        default                              { $kind = $type;          $groupId = Get-Prop $target 'groupId' }
    }
    $filterId = Get-Prop $target 'deviceAndAppManagementAssignmentFilterId'
    if ($filterId -eq '00000000-0000-0000-0000-000000000000') { $filterId = $null }
    [pscustomobject]@{
        Kind       = $kind
        GroupId    = $groupId
        FilterId   = $filterId
        FilterMode = Get-Prop $target 'deviceAndAppManagementAssignmentFilterType'
        AppIntent  = Get-Prop $Assignment 'intent'
    }
}

function Export-CsvReport {
    param([object[]]$Rows, [string]$Path)
    if ($null -ne $Rows -and @($Rows).Count -gt 0) {
        @($Rows) | Export-Csv -Path $Path -NoTypeInformation -Encoding UTF8
        Write-Host ("  {0,-26} {1} row(s)" -f (Split-Path $Path -Leaf), @($Rows).Count) -ForegroundColor Gray
    }
    else {
        Write-Host ("  {0,-26} nothing to report" -f (Split-Path $Path -Leaf)) -ForegroundColor DarkGray
    }
}

#endregion

#region ---- Connect ---------------------------------------------------------------------------

if (-not $OutputPath) {
    $OutputPath = Join-Path -Path (Get-Location).Path -ChildPath ('IntuneAudit_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
}

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    throw 'Microsoft.Graph.Authentication module not found. Install it with: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser'
}
if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    throw 'ImportExcel module not found (required for the xlsx report). Install it with: Install-Module ImportExcel -Scope CurrentUser'
}
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

# Read-only delegated scopes. DeviceManagementScripts.Read.All is required for the script /
# remediation endpoints since the July 2025 Graph permission split.
$RequiredScopes = @(
    'DeviceManagementConfiguration.Read.All'
    'DeviceManagementApps.Read.All'
    'DeviceManagementServiceConfig.Read.All'
    'DeviceManagementScripts.Read.All'
    'Group.Read.All'
)

Write-Host ''
Write-Host '=== Intune Configuration Audit ===' -ForegroundColor White
$ctx = Get-MgContext
$needConnect = $true
if ($ctx -and $ctx.AuthType -eq 'Delegated') {
    $missing = @($RequiredScopes | Where-Object { $ctx.Scopes -notcontains $_ })
    if ($missing.Count -eq 0) { $needConnect = $false }
}
if ($needConnect) {
    Write-Host 'Signing in to Microsoft Graph (delegated, read-only scopes)...' -ForegroundColor Cyan
    Connect-MgGraph -Scopes $RequiredScopes -NoWelcome -UseDeviceCode:$UseDeviceCode -ErrorAction Stop
    $ctx = Get-MgContext
}
Write-Host ("Connected as {0} (tenant {1})" -f $ctx.Account, $ctx.TenantId) -ForegroundColor Green

$null = New-Item -ItemType Directory -Path $OutputPath -Force
$rawDir = Join-Path $OutputPath 'RawExport'
if ($IncludeRawExport) { $null = New-Item -ItemType Directory -Path $rawDir -Force }

#endregion

#region ---- Collection specs ------------------------------------------------------------------

$dm  = "$GraphBeta/deviceManagement"
$dam = "$GraphBeta/deviceAppManagement"

# DeepMode: how exact-duplicate hashes are computed.
#   BodyHash       - hash the list item body (no extra calls)
#   CatalogSettings- fetch /settings per policy (settings catalog)
#   AdminTemplate  - fetch /definitionValues per policy (administrative templates)
#   IntentSettings - fetch /settings per intent (endpoint security)
#   ItemDetailHash - fetch the single item (scripts: list omits script content)
#   None           - no content hash (applications)
$specs = @(
    [pscustomobject]@{ Key = 'SettingsCatalog';        Group = 'SettingsCatalog';          Label = 'Settings Catalog policies';            BaseUri = "$dm/configurationPolicies";               NameProp = 'name';        DeepMode = 'CatalogSettings'; PlatformMode = 'PlatformsProp'; NoExpand = $false }
    [pscustomobject]@{ Key = 'DeviceConfigurations';   Group = 'DeviceConfigurations';     Label = 'Device configuration profiles';        BaseUri = "$dm/deviceConfigurations";                NameProp = 'displayName'; DeepMode = 'BodyHash';        PlatformMode = 'ODataType';     NoExpand = $false }
    [pscustomobject]@{ Key = 'AdminTemplates';         Group = 'AdminTemplates';           Label = 'Administrative templates';             BaseUri = "$dm/groupPolicyConfigurations";           NameProp = 'displayName'; DeepMode = 'AdminTemplate';   PlatformMode = 'Windows';       NoExpand = $false }
    [pscustomobject]@{ Key = 'CompliancePolicies';     Group = 'CompliancePolicies';       Label = 'Compliance policies';                  BaseUri = "$dm/deviceCompliancePolicies";            NameProp = 'displayName'; DeepMode = 'BodyHash';        PlatformMode = 'ODataType';     NoExpand = $false }
    [pscustomobject]@{ Key = 'EndpointSecurity';       Group = 'EndpointSecurity';         Label = 'Endpoint security intents';            BaseUri = "$dm/intents";                             NameProp = 'displayName'; DeepMode = 'IntentSettings';  PlatformMode = 'Template';      NoExpand = $true }
    [pscustomobject]@{ Key = 'PlatformScripts';        Group = 'Scripts';                  Label = 'PowerShell scripts';                   BaseUri = "$dm/deviceManagementScripts";             NameProp = 'displayName'; DeepMode = 'ItemDetailHash';  PlatformMode = 'Windows';       NoExpand = $false }
    [pscustomobject]@{ Key = 'MacShellScripts';        Group = 'Scripts';                  Label = 'macOS shell scripts';                  BaseUri = "$dm/deviceShellScripts";                  NameProp = 'displayName'; DeepMode = 'ItemDetailHash';  PlatformMode = 'macOS';         NoExpand = $false }
    [pscustomobject]@{ Key = 'Remediations';           Group = 'Remediations';             Label = 'Remediations (health scripts)';        BaseUri = "$dm/deviceHealthScripts";                 NameProp = 'displayName'; DeepMode = 'ItemDetailHash';  PlatformMode = 'Windows';       NoExpand = $false }
    [pscustomobject]@{ Key = 'AppProtectionIOS';       Group = 'AppProtection';            Label = 'App protection (iOS)';                 BaseUri = "$dam/iosManagedAppProtections";           NameProp = 'displayName'; DeepMode = 'BodyHash';        PlatformMode = 'iOS/iPadOS';    NoExpand = $false }
    [pscustomobject]@{ Key = 'AppProtectionAndroid';   Group = 'AppProtection';            Label = 'App protection (Android)';             BaseUri = "$dam/androidManagedAppProtections";       NameProp = 'displayName'; DeepMode = 'BodyHash';        PlatformMode = 'Android';       NoExpand = $false }
    [pscustomobject]@{ Key = 'AppProtectionWindows';   Group = 'AppProtection';            Label = 'App protection (Windows)';             BaseUri = "$dam/windowsManagedAppProtections";       NameProp = 'displayName'; DeepMode = 'BodyHash';        PlatformMode = 'Windows';       NoExpand = $false }
    [pscustomobject]@{ Key = 'AppConfigManagedApps';   Group = 'AppConfiguration';         Label = 'App configuration (managed apps)';     BaseUri = "$dam/targetedManagedAppConfigurations";   NameProp = 'displayName'; DeepMode = 'BodyHash';        PlatformMode = '';              NoExpand = $false }
    [pscustomobject]@{ Key = 'AppConfigManagedDevices'; Group = 'AppConfiguration';        Label = 'App configuration (managed devices)';  BaseUri = "$dam/mobileAppConfigurations";            NameProp = 'displayName'; DeepMode = 'BodyHash';        PlatformMode = 'ODataType';     NoExpand = $false }
    [pscustomobject]@{ Key = 'Applications';           Group = 'Applications';             Label = 'Applications';                         BaseUri = "$dam/mobileApps";                         NameProp = 'displayName'; DeepMode = 'None';            PlatformMode = 'ODataType';     NoExpand = $false }
    [pscustomobject]@{ Key = 'Autopilot';              Group = 'Autopilot';                Label = 'Autopilot deployment profiles';        BaseUri = "$dm/windowsAutopilotDeploymentProfiles";  NameProp = 'displayName'; DeepMode = 'BodyHash';        PlatformMode = 'Windows';       NoExpand = $false }
    [pscustomobject]@{ Key = 'EnrollmentConfigurations'; Group = 'EnrollmentConfigurations'; Label = 'Enrollment configurations';          BaseUri = "$dm/deviceEnrollmentConfigurations";      NameProp = 'displayName'; DeepMode = 'BodyHash';        PlatformMode = 'ODataType';     NoExpand = $false }
    [pscustomobject]@{ Key = 'FeatureUpdates';         Group = 'WindowsUpdates';           Label = 'Windows feature update profiles';      BaseUri = "$dm/windowsFeatureUpdateProfiles";        NameProp = 'displayName'; DeepMode = 'BodyHash';        PlatformMode = 'Windows';       NoExpand = $false }
    [pscustomobject]@{ Key = 'QualityUpdates';         Group = 'WindowsUpdates';           Label = 'Windows quality update profiles';      BaseUri = "$dm/windowsQualityUpdateProfiles";        NameProp = 'displayName'; DeepMode = 'BodyHash';        PlatformMode = 'Windows';       NoExpand = $false }
    [pscustomobject]@{ Key = 'DriverUpdates';          Group = 'WindowsUpdates';           Label = 'Windows driver update profiles';       BaseUri = "$dm/windowsDriverUpdateProfiles";         NameProp = 'displayName'; DeepMode = 'BodyHash';        PlatformMode = 'Windows';       NoExpand = $false }
)

$includeAll = $Categories -contains 'All'

#endregion

#region ---- Fetch -----------------------------------------------------------------------------

$collected = [ordered]@{}
$skippedCollections = @()

foreach ($spec in $specs) {
    if (-not $includeAll -and $Categories -notcontains $spec.Group) { continue }
    Write-Host ("Collecting {0}..." -f $spec.Label) -ForegroundColor Cyan
    $items = $null
    try {
        if ($spec.NoExpand) {
            $items = @(Get-GraphCollection -Uri $spec.BaseUri)
        }
        else {
            try {
                $items = @(Get-GraphCollection -Uri ($spec.BaseUri + '?$expand=assignments'))
            }
            catch {
                Write-Verbose ('expand=assignments rejected for {0}; fetching assignments per item' -f $spec.Key)
                $items = @(Get-GraphCollection -Uri $spec.BaseUri)
            }
        }
    }
    catch {
        Write-Warning ("Skipped {0}: {1}" -f $spec.Label, $_.Exception.Message)
        $skippedCollections += [pscustomobject]@{ Category = $spec.Key; Reason = $_.Exception.Message }
        continue
    }

    # Make sure every item carries its assignments (fallback to per-item calls when needed).
    foreach ($item in $items) {
        if (-not ($item -is [System.Collections.IDictionary])) { continue }
        if (-not $item.ContainsKey('assignments') -or $null -eq $item['assignments']) {
            $itemId = Get-Prop $item 'id'
            try {
                $item['assignments'] = @(Get-GraphCollection -Uri ("{0}/{1}/assignments" -f $spec.BaseUri, $itemId))
            }
            catch {
                $item['assignments'] = @()
            }
        }
    }

    $collected[$spec.Key] = @{ Spec = $spec; Items = $items }
    Write-Host ("  {0} item(s)" -f $items.Count) -ForegroundColor Gray

    # Raw export (full fidelity backup of what Graph returned, including assignments).
    if ($IncludeRawExport) {
        $rawPath = Join-Path $rawDir ($spec.Key + '.json')
        ConvertTo-Json -InputObject @($items) -Depth 50 | Out-File -FilePath $rawPath -Encoding utf8
    }
}

# Assignment filters (always fetched: cheap, and needed to resolve filter names).
$assignmentFilters = @()
try {
    Write-Host 'Collecting assignment filters...' -ForegroundColor Cyan
    $assignmentFilters = @(Get-GraphCollection -Uri "$dm/assignmentFilters")
    Write-Host ("  {0} item(s)" -f $assignmentFilters.Count) -ForegroundColor Gray
    if ($IncludeRawExport) {
        ConvertTo-Json -InputObject @($assignmentFilters) -Depth 50 | Out-File -FilePath (Join-Path $rawDir 'AssignmentFilters.json') -Encoding utf8
    }
}
catch {
    Write-Warning ("Could not fetch assignment filters: {0}" -f $_.Exception.Message)
}
$filterNamesById = @{}
foreach ($f in $assignmentFilters) { $filterNamesById[[string](Get-Prop $f 'id')] = [string](Get-Prop $f 'displayName') }

# Endpoint security template map (intent -> template name / platform).
$templateMap = @{}
if ($collected.Contains('EndpointSecurity')) {
    try {
        foreach ($t in @(Get-GraphCollection -Uri "$dm/templates")) {
            $templateMap[[string](Get-Prop $t 'id')] = [pscustomobject]@{
                Name     = [string](Get-Prop $t 'displayName')
                Platform = [string](Get-Prop $t 'platformType')
            }
        }
    }
    catch { Write-Verbose 'Could not fetch endpoint security templates.' }
}

#endregion

#region ---- Resolve groups and filters --------------------------------------------------------

$groupNames = @{}
$groupMemberCounts = @{}
$groupResolutionRan = $false

$allGroupIds = New-Object System.Collections.Generic.HashSet[string]
foreach ($entry in $collected.Values) {
    foreach ($item in $entry.Items) {
        foreach ($assignment in @(Get-Prop $item 'assignments')) {
            $info = ConvertTo-AssignmentInfo -Assignment $assignment
            if ($null -ne $info -and $info.GroupId) { $null = $allGroupIds.Add([string]$info.GroupId) }
        }
    }
}

if (-not $SkipGroupResolution -and $allGroupIds.Count -gt 0) {
    Write-Host ("Resolving {0} assignment group(s)..." -f $allGroupIds.Count) -ForegroundColor Cyan
    $groupResolutionRan = $true
    $idList = @($allGroupIds)

    # Names in bulk via getByIds (read-only POST), 1000 ids per call.
    for ($i = 0; $i -lt $idList.Count; $i += 1000) {
        $chunk = @($idList[$i..([math]::Min($i + 999, $idList.Count - 1))])
        try {
            $body = @{ ids = $chunk; types = @('group') } | ConvertTo-Json -Depth 5
            $resp = Invoke-GraphRequestWithRetry -Method 'POST' -Uri "$GraphV1/directoryObjects/getByIds" -Body $body
            foreach ($g in @(Get-Prop $resp 'value')) {
                $groupNames[[string](Get-Prop $g 'id')] = [string](Get-Prop $g 'displayName')
            }
        }
        catch {
            Write-Warning ("Group name resolution failed: {0}" -f $_.Exception.Message)
        }
    }

    # Transitive member counts (drives the empty-group analysis).
    $done = 0
    foreach ($gid in $idList) {
        $done++
        if (-not $groupNames.ContainsKey($gid)) { continue }  # deleted/inaccessible: no count call
        Write-Progress -Activity 'Resolving group member counts' -Status $groupNames[$gid] -PercentComplete (100 * $done / $idList.Count)
        try {
            $uri = "$GraphV1/groups/$gid/transitiveMembers" + '?$count=true&$top=1&$select=id'
            $resp = Invoke-GraphRequestWithRetry -Uri $uri -Headers @{ ConsistencyLevel = 'eventual' }
            $groupMemberCounts[$gid] = [int](Get-Prop $resp '@odata.count')
        }
        catch {
            $groupMemberCounts[$gid] = $null
        }
    }
    Write-Progress -Activity 'Resolving group member counts' -Completed
}

#endregion

#region ---- Deep analysis (content hashes, setting ids) ---------------------------------------

# Metadata is kept out of the raw items so RawExport stays a faithful copy of Graph.
$meta = @{}                 # "<Key>|<id>" -> @{ Hash; SettingCount; DefIds }
$catalogDefIds = @{}        # settings-catalog policyId -> string[] of settingDefinitionIds
$policySettingRows = New-Object System.Collections.Generic.List[object]   # one row per policy per setting

# Category display names for settings-catalog settings - the groupings shown in the
# portal ('Defender', 'Firewall', 'Device Lock', ...). One paged call; nested categories
# (e.g. under Administrative Templates) are resolved to a 'Parent > Child' path.
if (-not $Quick -and $collected.Contains('SettingsCatalog') -and @($collected['SettingsCatalog'].Items).Count -gt 0) {
    try {
        Write-Host 'Collecting setting category names...' -ForegroundColor Cyan
        $catUri = "$dm/configurationCategories?" + '$select=id,displayName,parentCategoryId'
        $catInfo = @{}
        foreach ($c in @(Get-GraphCollection -Uri $catUri)) {
            $catId = [string](Get-Prop $c 'id')
            $parentId = [string](Get-Prop $c 'parentCategoryId')
            if ($parentId -eq '00000000-0000-0000-0000-000000000000' -or $parentId -eq $catId) { $parentId = '' }
            if ($catId) { $catInfo[$catId] = @{ Name = [string](Get-Prop $c 'displayName'); Parent = $parentId } }
        }
        foreach ($catId in $catInfo.Keys) {
            $parts = @()
            $cursor = $catId
            $hops = 0
            while ($cursor -and $catInfo.ContainsKey($cursor) -and $hops -lt 10) {
                $parts = @($catInfo[$cursor].Name) + $parts
                $next = $catInfo[$cursor].Parent
                if ($next -eq $cursor) { break }
                $cursor = $next
                $hops++
            }
            $script:CategoryPathById[$catId] = ($parts -join ' > ')
        }
        Write-Host ("  {0} categories" -f $catInfo.Count) -ForegroundColor Gray
    }
    catch {
        Write-Warning ("Could not fetch setting categories (SettingCategory will be blank): {0}" -f $_.Exception.Message)
    }
}

foreach ($entry in $collected.Values) {
    $spec = $entry.Spec
    $items = $entry.Items
    if ($items.Count -eq 0) { continue }

    $needsFetch = $spec.DeepMode -in @('CatalogSettings', 'AdminTemplate', 'IntentSettings', 'ItemDetailHash')
    if ($needsFetch -and $Quick) {
        Write-Host ("Skipping deep comparison for {0} (-Quick)" -f $spec.Label) -ForegroundColor DarkYellow
        continue
    }
    if ($spec.DeepMode -eq 'None') { continue }

    if ($needsFetch) { Write-Host ("Deep comparison: {0}..." -f $spec.Label) -ForegroundColor Cyan }
    $done = 0
    foreach ($item in $items) {
        $done++
        $itemId = [string](Get-Prop $item 'id')
        $itemName = [string](Get-Prop $item $spec.NameProp)
        $metaKey = "{0}|{1}" -f $spec.Key, $itemId
        if ($needsFetch) {
            Write-Progress -Activity ("Deep comparison: {0}" -f $spec.Label) -Status ("{0} of {1}" -f $done, $items.Count) -PercentComplete (100 * $done / $items.Count)
        }
        try {
            switch ($spec.DeepMode) {
                'BodyHash' {
                    $meta[$metaKey] = @{ Hash = Get-StructureHash (ConvertTo-CanonicalStructure $item); SettingCount = $null }
                }
                'CatalogSettings' {
                    # settingDefinitions carry the human-readable names/option labels; they are
                    # in VolatileKeys, so the duplicate hash is unaffected.
                    $settingsUri = ("{0}/{1}/settings?" -f $spec.BaseUri, $itemId) + '$expand=settingDefinitions'
                    try { $settings = @(Get-GraphCollection -Uri $settingsUri) }
                    catch { $settings = @(Get-GraphCollection -Uri ("{0}/{1}/settings" -f $spec.BaseUri, $itemId)) }
                    $sorted = @($settings | Sort-Object { [string](Get-Prop (Get-Prop $_ 'settingInstance') 'settingDefinitionId') })
                    $meta[$metaKey] = @{ Hash = Get-StructureHash (ConvertTo-CanonicalStructure $sorted); SettingCount = $settings.Count }
                    $defIds = @()
                    foreach ($s in $settings) {
                        Register-SettingDefinitions -Definitions @(Get-Prop $s 'settingDefinitions')
                        $defId = [string](Get-Prop (Get-Prop $s 'settingInstance') 'settingDefinitionId')
                        if ($defId) { $defIds += $defId }
                    }
                    $catalogDefIds[$itemId] = @($defIds | Sort-Object -Unique)
                    foreach ($s in $settings) {
                        foreach ($r in @(Expand-SettingInstance -Instance (Get-Prop $s 'settingInstance'))) {
                            $policySettingRows.Add([pscustomobject]@{
                                Category        = $spec.Key
                                PolicyName      = $itemName
                                SettingCategory = Get-SettingCategory -DefId $r.SettingDefinitionId
                                SettingName     = $r.SettingName
                                Value           = $r.Value
                                Depth           = $r.Depth
                            })
                        }
                    }
                }
                'AdminTemplate' {
                    $uri = ("{0}/{1}/definitionValues" -f $spec.BaseUri, $itemId) + '?$expand=definition($select=id,displayName,categoryPath),presentationValues'
                    $defValues = @(Get-GraphCollection -Uri $uri)
                    $shaped = @()
                    foreach ($dv in @($defValues | Sort-Object { [string](Get-Prop (Get-Prop $_ 'definition') 'id') })) {
                        $shaped += , ([ordered]@{
                            definitionId  = [string](Get-Prop (Get-Prop $dv 'definition') 'id')
                            enabled       = Get-Prop $dv 'enabled'
                            presentations = ConvertTo-CanonicalStructure (Get-Prop $dv 'presentationValues')
                        })
                    }
                    $meta[$metaKey] = @{ Hash = Get-StructureHash $shaped; SettingCount = $defValues.Count }
                    foreach ($dv in $defValues) {
                        $def = Get-Prop $dv 'definition'
                        $stateValue = 'Disabled'
                        if (Get-Prop $dv 'enabled') { $stateValue = 'Enabled' }
                        $defName = [string](Get-Prop $def 'displayName')
                        if (-not $defName) { $defName = [string](Get-Prop $def 'id') }
                        # categoryPath comes as '\Windows Components\Search'
                        $gpoCategory = ([string](Get-Prop $def 'categoryPath')).Trim('\')
                        if ($gpoCategory) { $gpoCategory = ($gpoCategory -split '\\') -join ' > ' }
                        $policySettingRows.Add([pscustomobject]@{
                            Category        = $spec.Key
                            PolicyName      = $itemName
                            SettingCategory = $gpoCategory
                            SettingName     = $defName
                            Value           = $stateValue
                            Depth           = 0
                        })
                    }
                }
                'IntentSettings' {
                    $settings = @(Get-GraphCollection -Uri ("{0}/{1}/settings" -f $spec.BaseUri, $itemId))
                    $sorted = @($settings | Sort-Object { [string](Get-Prop $_ 'definitionId') })
                    $meta[$metaKey] = @{ Hash = Get-StructureHash (ConvertTo-CanonicalStructure $sorted); SettingCount = $settings.Count }
                }
                'ItemDetailHash' {
                    $detail = Invoke-GraphRequestWithRetry -Uri ("{0}/{1}" -f $spec.BaseUri, $itemId)
                    $meta[$metaKey] = @{ Hash = Get-StructureHash (ConvertTo-CanonicalStructure $detail); SettingCount = $null }
                }
            }
        }
        catch {
            Write-Verbose ("Deep comparison failed for {0} {1}: {2}" -f $spec.Key, $itemId, $_.Exception.Message)
        }
    }
    if ($needsFetch) { Write-Progress -Activity ("Deep comparison: {0}" -f $spec.Label) -Completed }
}

#endregion

#region ---- Build inventory and assignment rows -----------------------------------------------

$now = [datetime]::UtcNow
$inventory = New-Object System.Collections.Generic.List[object]
$assignmentRows = New-Object System.Collections.Generic.List[object]
$usedFilterIds = New-Object System.Collections.Generic.HashSet[string]

foreach ($entry in $collected.Values) {
    $spec = $entry.Spec
    foreach ($item in $entry.Items) {
        $itemId = [string](Get-Prop $item 'id')
        $name = [string](Get-Prop $item $spec.NameProp)
        $policyType = ConvertTo-FriendlyTypeName ([string](Get-Prop $item '@odata.type'))
        if (-not $policyType -and $spec.Key -eq 'SettingsCatalog') { $policyType = 'Settings Catalog policy' }
        if (-not $policyType -and $spec.Key -eq 'EndpointSecurity') { $policyType = 'Endpoint security intent' }

        # Platform
        $platform = ''
        switch ($spec.PlatformMode) {
            'PlatformsProp' { $platform = Format-CatalogPlatform ([string](Get-Prop $item 'platforms')) }
            'ODataType'     { $platform = Get-PlatformFromODataType -ODataType ([string](Get-Prop $item '@odata.type')) }
            'Template'      {
                $tpl = $templateMap[[string](Get-Prop $item 'templateId')]
                if ($tpl) { $platform = $tpl.Platform; $policyType = 'Endpoint Security: ' + $tpl.Name }
            }
            default         { $platform = $spec.PlatformMode }
        }

        $created = ConvertTo-DateTimeOrNull (Get-Prop $item 'createdDateTime')
        $modified = ConvertTo-DateTimeOrNull (Get-Prop $item 'lastModifiedDateTime')
        $ageDays = $null
        if ($modified) { $ageDays = [int]($now - $modified).TotalDays }

        # Assignments
        $infos = @()
        foreach ($assignment in @(Get-Prop $item 'assignments')) {
            $info = ConvertTo-AssignmentInfo -Assignment $assignment
            if ($null -ne $info) { $infos += $info }
        }

        $includeGroupIds = @($infos | Where-Object { $_.Kind -eq 'IncludeGroup' } | ForEach-Object { [string]$_.GroupId })
        $excludeGroupIds = @($infos | Where-Object { $_.Kind -eq 'ExcludeGroup' } | ForEach-Object { [string]$_.GroupId })
        $targetsAllDevices = @($infos | Where-Object { $_.Kind -eq 'AllDevices' }).Count -gt 0
        $targetsAllUsers = @($infos | Where-Object { $_.Kind -eq 'AllUsers' }).Count -gt 0

        $missingGroupIds = @()
        $emptyGroupIds = @()
        if ($groupResolutionRan) {
            foreach ($gid in @($includeGroupIds + $excludeGroupIds | Sort-Object -Unique)) {
                if (-not $groupNames.ContainsKey($gid)) { $missingGroupIds += $gid }
            }
            foreach ($gid in $includeGroupIds) {
                if ($groupMemberCounts.ContainsKey($gid) -and $groupMemberCounts[$gid] -eq 0) { $emptyGroupIds += $gid }
            }
        }

        $resolveGroupName = {
            param($gid)
            if ($groupNames.ContainsKey($gid)) { return $groupNames[$gid] }
            if ($groupResolutionRan) { return "(missing group $gid)" }
            return $gid
        }
        $includeNames = @($includeGroupIds | ForEach-Object { & $resolveGroupName $_ })
        $excludeNames = @($excludeGroupIds | ForEach-Object { & $resolveGroupName $_ })

        $filtersUsedNames = @()
        foreach ($info in $infos) {
            if ($info.FilterId) {
                $null = $usedFilterIds.Add([string]$info.FilterId)
                $fname = $filterNamesById[[string]$info.FilterId]
                if (-not $fname) { $fname = [string]$info.FilterId }
                $filtersUsedNames += ("{0} ({1})" -f $fname, $info.FilterMode)
            }
        }

        $metaEntry = $meta["{0}|{1}" -f $spec.Key, $itemId]
        $contentHash = $null
        $settingCount = $null
        if ($metaEntry) { $contentHash = $metaEntry.Hash; $settingCount = $metaEntry.SettingCount }
        if ($null -eq $settingCount -and $spec.Key -eq 'SettingsCatalog') { $settingCount = Get-Prop $item 'settingCount' }

        $appIntents = @($infos | Where-Object { $_.AppIntent } | ForEach-Object { [string]$_.AppIntent } | Sort-Object -Unique)

        $row = [pscustomobject]@{
            Category           = $spec.Key
            PolicyType         = $policyType
            Id                 = $itemId
            Name               = $name
            Description        = [string](Get-Prop $item 'description')
            Platform           = $platform
            CreatedDateTime    = $created
            LastModified       = $modified
            AgeDays            = $ageDays
            IsAssigned         = ($infos.Count -gt 0)
            AssignmentCount    = $infos.Count
            TargetsAllDevices  = $targetsAllDevices
            TargetsAllUsers    = $targetsAllUsers
            IncludeGroupCount  = $includeGroupIds.Count
            ExcludeGroupCount  = $excludeGroupIds.Count
            IncludedGroups     = ($includeNames -join '; ')
            ExcludedGroups     = ($excludeNames -join '; ')
            AppAssignIntents   = ($appIntents -join '; ')
            FiltersUsed        = (@($filtersUsedNames | Sort-Object -Unique) -join '; ')
            SettingCount       = $settingCount
            ContentHash        = $contentHash
            DuplicateSetId     = ''
            Flags              = ''
            # used internally by the findings pass, removed before export
            _MissingGroupIds   = $missingGroupIds
            _EmptyGroupIds     = $emptyGroupIds
            _IncludeGroupIds   = $includeGroupIds
        }
        $inventory.Add($row)

        # One row per assignment for the Assignments report.
        foreach ($info in $infos) {
            $gName = ''
            $gCount = ''
            if ($info.GroupId) {
                $gName = & $resolveGroupName ([string]$info.GroupId)
                if ($groupMemberCounts.ContainsKey([string]$info.GroupId)) {
                    $c = $groupMemberCounts[[string]$info.GroupId]
                    if ($null -ne $c) { $gCount = $c } else { $gCount = 'unknown' }
                }
            }
            $fName = ''
            if ($info.FilterId) {
                $fName = $filterNamesById[[string]$info.FilterId]
                if (-not $fName) { $fName = [string]$info.FilterId }
            }
            $assignmentRows.Add([pscustomobject]@{
                Category         = $spec.Key
                PolicyName       = $name
                TargetType       = $info.Kind
                GroupName        = $gName
                GroupMemberCount = $gCount
                AppIntent        = $info.AppIntent
                FilterName       = $fName
                FilterMode       = $info.FilterMode
            })
        }
    }
}

#endregion

#region ---- Findings --------------------------------------------------------------------------

$findings = New-Object System.Collections.Generic.List[object]
$flagsByPolicy = @{}   # "<Category>|<Id>" -> [string[]] finding types

function Add-Finding {
    param([string]$Severity, [string]$Type, [string]$Category, [string]$PolicyName,
          [string]$PolicyId, [string]$Detail, [string]$Action)
    # PolicyId is kept as a parameter for internal flag-stamping but deliberately not
    # exported - reports use display names.
    $findings.Add([pscustomobject]@{
        Severity          = $Severity
        FindingType       = $Type
        Category          = $Category
        PolicyName        = $PolicyName
        Detail            = $Detail
        RecommendedAction = $Action
    })
    if ($PolicyId) {
        $k = "{0}|{1}" -f $Category, $PolicyId
        if (-not $flagsByPolicy.ContainsKey($k)) { $flagsByPolicy[$k] = @() }
        $flagsByPolicy[$k] = @($flagsByPolicy[$k]) + $Type
    }
}

# --- Per-policy assignment hygiene
foreach ($row in $inventory) {
    $isEnrollmentDefault = ($row.Category -eq 'EnrollmentConfigurations' -and $row.Id -like '*_Default*')

    if (-not $row.IsAssigned) {
        if (-not $isEnrollmentDefault) {
            $sev = 'Medium'
            $detail = 'No assignments - this configuration is not deployed to anything.'
            if ($row.Category -eq 'Applications') { $sev = 'Info' }
            elseif ($null -ne $row.AgeDays -and $row.AgeDays -gt $StaleDays) {
                $sev = 'High'
                $detail = ("No assignments and not modified for {0} days (threshold {1})." -f $row.AgeDays, $StaleDays)
            }
            Add-Finding -Severity $sev -Type 'Unassigned' -Category $row.Category -PolicyName $row.Name -PolicyId $row.Id `
                -Detail $detail -Action 'Review and delete if no longer needed, or assign it.'
        }
    }
    else {
        $hasIncludeTarget = ($row.TargetsAllDevices -or $row.TargetsAllUsers -or $row.IncludeGroupCount -gt 0)
        if (-not $hasIncludeTarget) {
            Add-Finding -Severity 'Medium' -Type 'ExcludeOnly' -Category $row.Category -PolicyName $row.Name -PolicyId $row.Id `
                -Detail 'Only exclusion assignments exist - the policy applies to nothing.' `
                -Action 'Add include targets or delete the policy.'
        }
        elseif ($groupResolutionRan -and -not $row.TargetsAllDevices -and -not $row.TargetsAllUsers -and $row.IncludeGroupCount -gt 0) {
            $countsKnown = $true
            $includeIds = @($row._IncludeGroupIds | ForEach-Object { [string]$_ })
            $nonEmpty = 0
            foreach ($gid in $includeIds) {
                if (-not $groupMemberCounts.ContainsKey($gid) -or $null -eq $groupMemberCounts[$gid]) { $countsKnown = $false }
                elseif ($groupMemberCounts[$gid] -gt 0) { $nonEmpty++ }
            }
            if ($countsKnown -and $nonEmpty -eq 0 -and $includeIds.Count -gt 0) {
                Add-Finding -Severity 'Medium' -Type 'EffectivelyUnassigned' -Category $row.Category -PolicyName $row.Name -PolicyId $row.Id `
                    -Detail ("All {0} include group(s) have zero transitive members." -f $includeIds.Count) `
                    -Action 'Populate the target groups or remove the policy.'
            }
            elseif (@($row._EmptyGroupIds).Count -gt 0) {
                $emptyNames = @(@($row._EmptyGroupIds) | ForEach-Object { if ($groupNames.ContainsKey($_)) { $groupNames[$_] } else { $_ } })
                Add-Finding -Severity 'Low' -Type 'EmptyGroupTarget' -Category $row.Category -PolicyName $row.Name -PolicyId $row.Id `
                    -Detail ("Include group(s) with zero members: {0}" -f ($emptyNames -join '; ')) `
                    -Action 'Check whether these groups should have members.'
            }
        }
    }

    if (@($row._MissingGroupIds).Count -gt 0) {
        Add-Finding -Severity 'Medium' -Type 'AssignedToMissingGroup' -Category $row.Category -PolicyName $row.Name -PolicyId $row.Id `
            -Detail ("Assignment references group id(s) that no longer resolve: {0}" -f (@($row._MissingGroupIds) -join '; ')) `
            -Action 'Remove the orphaned assignment(s).'
    }

    if ($null -ne $row.SettingCount -and [int]$row.SettingCount -eq 0 -and $row.Category -ne 'Applications') {
        Add-Finding -Severity 'Low' -Type 'EmptyPolicy' -Category $row.Category -PolicyName $row.Name -PolicyId $row.Id `
            -Detail 'The policy contains zero settings.' -Action 'Delete or finish configuring it.'
    }
}

# --- Exact duplicates (same category + same content hash)
$dupCounter = 0
$hashGroups = @($inventory | Where-Object { $_.ContentHash } | Group-Object -Property Category, ContentHash | Where-Object { $_.Count -gt 1 })
$duplicateRows = New-Object System.Collections.Generic.List[object]
foreach ($g in $hashGroups) {
    $dupCounter++
    $setId = 'DUP-{0:D3}' -f $dupCounter
    $members = @($g.Group)
    $assignedCount = @($members | Where-Object { $_.IsAssigned }).Count
    foreach ($m in $members) {
        $m.DuplicateSetId = $setId
        $others = @($members | Where-Object { $_.Id -ne $m.Id } | ForEach-Object { $_.Name })
        $sev = 'Medium'
        if ($assignedCount -ge 2) { $sev = 'High' }
        Add-Finding -Severity $sev -Type 'ExactDuplicate' -Category $m.Category -PolicyName $m.Name -PolicyId $m.Id `
            -Detail ("Identical configuration to: {0} (set {1}; {2} of {3} assigned)" -f ($others -join '; '), $setId, $assignedCount, $members.Count) `
            -Action 'Consolidate to a single policy and retire the copies.'
        $duplicateRows.Add([pscustomobject]@{
            DuplicateSetId  = $setId
            Category        = $m.Category
            PolicyName      = $m.Name
            IsAssigned      = $m.IsAssigned
            AssignmentCount = $m.AssignmentCount
            LastModified    = $m.LastModified
        })
    }
}

# --- Duplicate display names (different content, same name - confusing at minimum)
$nameGroups = @($inventory | Where-Object { $_.Name } |
    Group-Object -Property Category, { ([string]$_.Name).Trim().ToLowerInvariant() } |
    Where-Object { $_.Count -gt 1 })
foreach ($g in $nameGroups) {
    $members = @($g.Group)
    if (@($members | Where-Object { -not $_.DuplicateSetId }).Count -eq 0) { continue }  # already covered by ExactDuplicate
    foreach ($m in $members) {
        $stamp = ''
        if ($m.LastModified) { $stamp = ' (this copy last modified {0:yyyy-MM-dd})' -f $m.LastModified }
        Add-Finding -Severity 'Info' -Type 'DuplicateName' -Category $m.Category -PolicyName $m.Name -PolicyId $m.Id `
            -Detail ("{0} policies share this name{1}." -f $members.Count, $stamp) `
            -Action 'Rename to keep policies distinguishable.'
    }
}

# --- Unused assignment filters
foreach ($f in $assignmentFilters) {
    $fid = [string](Get-Prop $f 'id')
    if (-not $usedFilterIds.Contains($fid)) {
        Add-Finding -Severity 'Low' -Type 'UnusedFilter' -Category 'AssignmentFilters' -PolicyName ([string](Get-Prop $f 'displayName')) -PolicyId $fid `
            -Detail 'Assignment filter is not referenced by any assignment.' -Action 'Delete if no longer needed.'
    }
}

# --- Settings catalog: same setting configured in multiple assigned policies
$overlapRows = New-Object System.Collections.Generic.List[object]
if (-not $Quick -and $catalogDefIds.Count -gt 0) {
    $assignedCatalog = @{}
    foreach ($row in $inventory) {
        if ($row.Category -eq 'SettingsCatalog' -and $row.IsAssigned) { $assignedCatalog[$row.Id] = $row }
    }
    $policiesByDefId = @{}
    # ($polId, not $pid: $PID is a read-only automatic variable)
    foreach ($polId in $catalogDefIds.Keys) {
        if (-not $assignedCatalog.ContainsKey($polId)) { continue }
        foreach ($defId in $catalogDefIds[$polId]) {
            if (-not $policiesByDefId.ContainsKey($defId)) { $policiesByDefId[$defId] = @() }
            $policiesByDefId[$defId] = @($policiesByDefId[$defId]) + $polId
        }
    }
    $pairSharedCounts = @{}
    $pairExampleSetting = @{}
    foreach ($defId in $policiesByDefId.Keys) {
        $polIds = @($policiesByDefId[$defId] | Sort-Object -Unique)
        if ($polIds.Count -lt 2) { continue }
        # One row per policy so the report stays filterable (no packed cells).
        foreach ($polId in $polIds) {
            $overlapRows.Add([pscustomobject]@{
                SettingCategory      = Get-SettingCategory -DefId $defId
                SettingName          = Get-SettingDisplayName -DefId $defId
                ConfiguredInPolicies = $polIds.Count
                PolicyName           = $assignedCatalog[$polId].Name
                Platform             = $assignedCatalog[$polId].Platform
            })
        }
        for ($a = 0; $a -lt $polIds.Count - 1; $a++) {
            for ($b = $a + 1; $b -lt $polIds.Count; $b++) {
                $pairKey = "{0}|{1}" -f $polIds[$a], $polIds[$b]
                if (-not $pairSharedCounts.ContainsKey($pairKey)) {
                    $pairSharedCounts[$pairKey] = 0
                    $pairExampleSetting[$pairKey] = Get-SettingDisplayName -DefId $defId
                }
                $pairSharedCounts[$pairKey] = $pairSharedCounts[$pairKey] + 1
            }
        }
    }
    $topPairs = @($pairSharedCounts.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 50)
    foreach ($pair in $topPairs) {
        $ids = $pair.Key -split '\|'
        $p1 = $assignedCatalog[$ids[0]]
        $p2 = $assignedCatalog[$ids[1]]
        Add-Finding -Severity 'Info' -Type 'SettingOverlap' -Category 'SettingsCatalog' -PolicyName $p1.Name -PolicyId $p1.Id `
            -Detail ("Shares {0} setting(s) with '{1}' (e.g. '{2}') - potential conflict or redundancy. See the SettingOverlaps sheet." -f $pair.Value, $p2.Name, $pairExampleSetting[$pair.Key]) `
            -Action 'Review for conflicting values; consolidate where sensible.'
    }
    if ($pairSharedCounts.Count -gt 50) {
        Write-Host ("  Note: {0} overlapping policy pairs found; findings list the top 50 (full detail in SettingOverlaps.csv)" -f $pairSharedCounts.Count) -ForegroundColor DarkYellow
    }
}

# Stamp flags back onto inventory rows.
foreach ($row in $inventory) {
    $k = "{0}|{1}" -f $row.Category, $row.Id
    if ($flagsByPolicy.ContainsKey($k)) {
        $row.Flags = (@($flagsByPolicy[$k] | Sort-Object -Unique) -join '; ')
    }
}

#endregion

#region ---- Export ----------------------------------------------------------------------------

Write-Host ''
Write-Host 'Writing report workbook...' -ForegroundColor Cyan

$severityRank = @{ High = 1; Medium = 2; Low = 3; Info = 4 }
$sortedFindings = @($findings | Sort-Object -Property @{ Expression = { $severityRank[$_.Severity] } }, FindingType, Category, PolicyName)

# Ids and hashes are internal working data; reports carry display names only.
$inventoryExport = @($inventory | Select-Object -Property * -ExcludeProperty _MissingGroupIds, _EmptyGroupIds, _IncludeGroupIds, Id, ContentHash)

$filterRows = @()
foreach ($f in $assignmentFilters) {
    $fid = [string](Get-Prop $f 'id')
    $filterRows += [pscustomobject]@{
        Name        = [string](Get-Prop $f 'displayName')
        Platform    = [string](Get-Prop $f 'platform')
        Rule        = [string](Get-Prop $f 'rule')
        UsedByCount = @($assignmentRows | Where-Object { $_.FilterName -and ($_.FilterName -eq (Get-Prop $f 'displayName') -or $_.FilterName -eq $fid) }).Count
        InUse       = $usedFilterIds.Contains($fid)
    }
}

# Note: List variables are converted with .ToArray(), not @(): on PowerShell 7.6
# @($genericList) throws "Argument types do not match".
$overlapExport = @($overlapRows.ToArray() | Sort-Object -Property @{ Expression = 'ConfiguredInPolicies'; Descending = $true }, SettingName, PolicyName)
# Stable sort: settings keep their natural parent-then-children order within each policy.
$policySettingsExport = @($policySettingRows.ToArray() | Sort-Object -Property Category, PolicyName)

$sheets = [ordered]@{
    Findings        = $sortedFindings
    Inventory       = $inventoryExport
    Assignments     = $assignmentRows.ToArray()
    Duplicates      = $duplicateRows.ToArray()
    SettingOverlaps = $overlapExport
    PolicySettings  = $policySettingsExport
    Filters         = $filterRows
}
$xlsxPath = Join-Path $OutputPath 'IntuneAudit.xlsx'
try {
    if (Test-Path $xlsxPath) { Remove-Item $xlsxPath -Force }
    foreach ($sheetName in $sheets.Keys) {
        $rows = $sheets[$sheetName]
        if ($null -ne $rows -and @($rows).Count -gt 0) {
            @($rows) | Export-Excel -Path $xlsxPath -WorksheetName $sheetName -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow
            Write-Host ("  {0,-16} {1} row(s)" -f $sheetName, @($rows).Count) -ForegroundColor Gray
        }
        else {
            Write-Host ("  {0,-16} nothing to report" -f $sheetName) -ForegroundColor DarkGray
        }
    }
}
catch {
    # Don't lose the run if the workbook can't be written - dump CSVs instead.
    Write-Warning ("Excel export failed ({0}); writing CSV fallback to Reports\" -f $_.Exception.Message)
    $reportDir = Join-Path $OutputPath 'Reports'
    $null = New-Item -ItemType Directory -Path $reportDir -Force
    foreach ($sheetName in $sheets.Keys) {
        Export-CsvReport -Rows $sheets[$sheetName] -Path (Join-Path $reportDir ($sheetName + '.csv'))
    }
}

# Summary.md
$findingSummary = @($sortedFindings | Group-Object FindingType | Sort-Object Count -Descending)
$categorySummary = @($inventory | Group-Object Category)
$sb = New-Object System.Text.StringBuilder
$null = $sb.AppendLine('# Intune Configuration Audit')
$null = $sb.AppendLine('')
$null = $sb.AppendLine(("- **Run (UTC):** {0}" -f $now.ToString('yyyy-MM-dd HH:mm')))
$null = $sb.AppendLine(("- **Tenant:** {0}" -f $ctx.TenantId))
$null = $sb.AppendLine(("- **Account:** {0}" -f $ctx.Account))
$null = $sb.AppendLine(("- **Mode:** {0}{1}" -f $(if ($Quick) { 'Quick (no deep comparison)' } else { 'Full' }), $(if ($SkipGroupResolution) { ', group resolution skipped' } else { '' })))
$null = $sb.AppendLine(("- **Stale threshold:** {0} days" -f $StaleDays))
$null = $sb.AppendLine('')
$null = $sb.AppendLine('## Inventory')
$null = $sb.AppendLine('')
$null = $sb.AppendLine('| Category | Items | Unassigned | Duplicate sets |')
$null = $sb.AppendLine('|---|---:|---:|---:|')
foreach ($c in $categorySummary) {
    $unassigned = @($c.Group | Where-Object { -not $_.IsAssigned }).Count
    $dupSets = @($c.Group | Where-Object { $_.DuplicateSetId } | Group-Object DuplicateSetId).Count
    $null = $sb.AppendLine(("| {0} | {1} | {2} | {3} |" -f $c.Name, $c.Count, $unassigned, $dupSets))
}
$null = $sb.AppendLine('')
$null = $sb.AppendLine('## Findings')
$null = $sb.AppendLine('')
if ($findingSummary.Count -eq 0) {
    $null = $sb.AppendLine('No issues found.')
}
else {
    $null = $sb.AppendLine('| Finding | Count |')
    $null = $sb.AppendLine('|---|---:|')
    foreach ($fs in $findingSummary) { $null = $sb.AppendLine(("| {0} | {1} |" -f $fs.Name, $fs.Count)) }
}
$null = $sb.AppendLine('')
$oldestUnassigned = @($inventory | Where-Object { -not $_.IsAssigned -and $null -ne $_.AgeDays } | Sort-Object AgeDays -Descending | Select-Object -First 15)
if ($oldestUnassigned.Count -gt 0) {
    $null = $sb.AppendLine('## Oldest unassigned items (top cleanup candidates)')
    $null = $sb.AppendLine('')
    $null = $sb.AppendLine('| Category | Name | Last modified | Age (days) |')
    $null = $sb.AppendLine('|---|---|---|---:|')
    foreach ($o in $oldestUnassigned) {
        $null = $sb.AppendLine(("| {0} | {1} | {2:yyyy-MM-dd} | {3} |" -f $o.Category, $o.Name, $o.LastModified, $o.AgeDays))
    }
    $null = $sb.AppendLine('')
}
if ($skippedCollections.Count -gt 0) {
    $null = $sb.AppendLine('## Skipped collections')
    $null = $sb.AppendLine('')
    foreach ($s in $skippedCollections) { $null = $sb.AppendLine(("- {0}: {1}" -f $s.Category, $s.Reason)) }
    $null = $sb.AppendLine('')
}
$sb.ToString() | Out-File -FilePath (Join-Path $OutputPath 'Summary.md') -Encoding utf8

#endregion

#region ---- Console summary -------------------------------------------------------------------

Write-Host ''
Write-Host '=== Done ===' -ForegroundColor White
Write-Host ("Inventory : {0} configuration items across {1} categories" -f $inventory.Count, $categorySummary.Count)
Write-Host ("Findings  : {0} total" -f $sortedFindings.Count)
foreach ($sev in @('High', 'Medium', 'Low', 'Info')) {
    $count = @($sortedFindings | Where-Object { $_.Severity -eq $sev }).Count
    if ($count -gt 0) {
        $color = switch ($sev) { 'High' { 'Red' } 'Medium' { 'Yellow' } 'Low' { 'Gray' } default { 'DarkGray' } }
        Write-Host ("  {0,-6} : {1}" -f $sev, $count) -ForegroundColor $color
    }
}
Write-Host ''
Write-Host ("Output    : {0}" -f $xlsxPath) -ForegroundColor Green
Write-Host 'Quick look: open IntuneAudit.xlsx and start with the Findings sheet.' -ForegroundColor DarkGray
Write-Host ''

#endregion
