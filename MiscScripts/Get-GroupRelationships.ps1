#Requires -Version 5.1
<#
.SYNOPSIS
    Maps every relationship of a single Entra ID security group.

.DESCRIPTION
    Takes a group display name (or object id) and reports everything the group
    is connected to:
      - Group nesting (parent groups, direct and inherited; child groups)
      - Owners, member counts and dynamic membership rule
      - Group-based licensing
      - Enterprise app role assignments
      - Intune assignments (include/exclude) across Settings Catalog policies,
        device configuration profiles, administrative templates, compliance
        policies, endpoint security intents, apps, app protection policies,
        app configuration policies, scripts, remediations and update profiles
      - Enrollment (enrollment configurations such as restrictions / ESP /
        Windows Hello, and Autopilot deployment profiles)
      - Intune role (RBAC) assignments
      - Conditional Access policies (included/excluded)

    Results are shown on screen and saved to a timestamped CSV in the Export
    folder next to this script. Sections that fail (e.g. missing permissions)
    are skipped with a warning instead of stopping the run.

    Scopes: Group.Read.All, DeviceManagementConfiguration.Read.All,
    DeviceManagementApps.Read.All and DeviceManagementServiceConfig.Read.All
    are required. DeviceManagementRBAC.Read.All, Policy.Read.All and
    Organization.Read.All enable the RBAC, Conditional Access and license-name
    sections.

.PARAMETER GroupName
    Display name of the group, or its object id (GUID).

.PARAMETER OutputPath
    Folder to write the CSV to. Defaults to 'Export' next to this script.

.EXAMPLE
    .\Get-GroupRelationships.ps1 'All Corporate Workstations'

.EXAMPLE
    .\Get-GroupRelationships.ps1 -GroupName 'f5f8a1c2-3b4d-4e5f-9a8b-7c6d5e4f3a2b'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$GroupName,

    [string]$OutputPath = (Join-Path $PSScriptRoot 'Export')
)

$Graph = 'https://graph.microsoft.com/beta'
$RequiredScopes = @('Group.Read.All', 'DeviceManagementConfiguration.Read.All', 'DeviceManagementApps.Read.All', 'DeviceManagementServiceConfig.Read.All')
$OptionalScopes = @('DeviceManagementRBAC.Read.All', 'Policy.Read.All', 'Organization.Read.All')

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

$rows = New-Object System.Collections.Generic.List[object]
function Add-Row {
    param([string]$Category, [string]$ItemType, [string]$ItemName, [string]$Relationship, [string]$Detail = '')
    $rows.Add([pscustomobject]@{
        Category     = $Category
        ItemType     = $ItemType
        ItemName     = $ItemName
        Relationship = $Relationship
        Detail       = $Detail
    })
}

function Get-EnrollmentTypeName([string]$ODataType) {
    switch -Wildcard ($ODataType) {
        '*windows10EnrollmentCompletionPageConfiguration' { return 'Enrollment status page' }
        '*deviceEnrollmentLimitConfiguration' { return 'Enrollment device limit' }
        '*deviceEnrollmentPlatformRestriction*' { return 'Enrollment platform restriction' }
        '*deviceEnrollmentWindowsHelloForBusinessConfiguration' { return 'Windows Hello for Business' }
    }
    return ($ODataType -replace '^#microsoft\.graph\.', '')
}

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    throw 'Microsoft.Graph.Authentication module not found. Install it with: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser'
}

Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

$context = Get-MgContext
$missingScopes = $RequiredScopes
if ($context -and $context.AuthType -eq 'Delegated') {
    $missingScopes = @($RequiredScopes | Where-Object {
        $context.Scopes -notcontains $_ -and $context.Scopes -notcontains ($_ -replace '\.Read\.', '.ReadWrite.')
    })
}
if ($missingScopes.Count -gt 0) {
    Connect-MgGraph -Scopes ($RequiredScopes + $OptionalScopes) -NoWelcome -ErrorAction Stop | Out-Null
}

# --- Resolve the group ---
$parsedGuid = [guid]::Empty
if ([guid]::TryParse($GroupName, [ref]$parsedGuid)) {
    try { $group = Invoke-GraphGet "$Graph/groups/$GroupName" }
    catch { throw ("Group with object id '{0}' was not found: {1}" -f $GroupName, $_.Exception.Message) }
}
else {
    $escapedName = $GroupName -replace "'", "''"
    $filterValue = [uri]::EscapeDataString("displayName eq '$escapedName'")
    $candidates = @(Get-GraphCollection ("$Graph/groups?" + '$filter=' + $filterValue))
    if ($candidates.Count -eq 0) {
        $startsValue = [uri]::EscapeDataString("startswith(displayName,'$escapedName')")
        $suggestions = @(Get-GraphCollection ("$Graph/groups?" + '$top=10&$filter=' + $startsValue))
        $suggestionText = (@($suggestions | ForEach-Object { [string](Get-Prop $_ 'displayName') } | Select-Object -First 10)) -join ', '
        if ($suggestionText) { throw ("Group '{0}' not found. Similar groups: {1}" -f $GroupName, $suggestionText) }
        throw ("Group '{0}' not found." -f $GroupName)
    }
    if ($candidates.Count -gt 1) {
        $candidateText = (@($candidates | ForEach-Object { '{0} ({1})' -f (Get-Prop $_ 'displayName'), (Get-Prop $_ 'id') })) -join '; '
        throw ("Multiple groups named '{0}' found: {1}. Re-run with the object id." -f $GroupName, $candidateText)
    }
    $group = $candidates[0]
}

$groupId = [string](Get-Prop $group 'id')
$groupDisplayName = [string](Get-Prop $group 'displayName')
$groupTypes = @(Get-Prop $group 'groupTypes')
$groupTypeLabel = 'Distribution'
if ($groupTypes -contains 'Unified') { $groupTypeLabel = 'Microsoft 365' }
elseif (Get-Prop $group 'securityEnabled') { $groupTypeLabel = 'Security' }
$membershipType = 'Assigned'
if ($groupTypes -contains 'DynamicMembership') { $membershipType = 'Dynamic' }
$membershipRule = [string](Get-Prop $group 'membershipRule')

Write-Host ''
Write-Host ('Group           : {0}' -f $groupDisplayName)
Write-Host ('Object id       : {0}' -f $groupId)
Write-Host ('Group type      : {0}' -f $groupTypeLabel)
Write-Host ('Membership type : {0}' -f $membershipType)
if ($membershipRule) { Write-Host ('Membership rule : {0}' -f $membershipRule) }
Write-Host ('Synced from AD  : {0}' -f $(if (Get-Prop $group 'onPremisesSyncEnabled') { 'Yes' } else { 'No' }))
Write-Host ''

if ($membershipRule) { Add-Row 'Membership' 'Dynamic rule' $membershipRule 'Defines membership' }

# --- Owners ---
Write-Host 'Checking owners and members...'
try {
    foreach ($owner in @(Get-GraphCollection "$Graph/groups/$groupId/owners")) {
        $ownerName = [string](Get-Prop $owner 'displayName')
        if (-not $ownerName) { $ownerName = [string](Get-Prop $owner 'id') }
        Add-Row 'Group' 'Owner' $ownerName 'Owned by' ([string](Get-Prop $owner 'userPrincipalName'))
    }
}
catch { Write-Warning ('Could not read owners: {0}' -f $_.Exception.Message) }

# --- Direct members (every member listed by name) ---
$userCount = 0; $deviceCount = 0; $childGroupCount = 0; $otherCount = 0
try {
    foreach ($member in @(Get-GraphCollection ("$Graph/groups/$groupId/members?" + '$select=id,displayName&$top=999'))) {
        $memberName = [string](Get-Prop $member 'displayName')
        if (-not $memberName) { $memberName = [string](Get-Prop $member 'id') }
        $memberId = [string](Get-Prop $member 'id')
        switch -Wildcard ([string](Get-Prop $member '@odata.type')) {
            '*.user' {
                $userCount++
                Add-Row 'Membership' 'User' $memberName 'Member (direct)' $memberId
            }
            '*.device' {
                $deviceCount++
                Add-Row 'Membership' 'Device' $memberName 'Member (direct)' $memberId
            }
            '*.group' {
                $childGroupCount++
                Add-Row 'Group nesting' 'Child group' $memberName 'Contains (direct)' $memberId
            }
            default {
                $otherCount++
                Add-Row 'Membership' 'Other member' $memberName 'Member (direct)' $memberId
            }
        }
    }
    Add-Row 'Membership' 'Summary' 'Direct members' 'Contains' ('{0} users, {1} devices, {2} groups, {3} other' -f $userCount, $deviceCount, $childGroupCount, $otherCount)
}
catch { Write-Warning ('Could not read members: {0}' -f $_.Exception.Message) }

# --- Nesting (parents) ---
Write-Host 'Checking group nesting...'
try {
    $directParentIds = @{}
    foreach ($parent in @(Get-GraphCollection ("$Graph/groups/$groupId/memberOf/microsoft.graph.group?" + '$select=id,displayName'))) {
        $parentId = [string](Get-Prop $parent 'id')
        $directParentIds[$parentId] = $true
        Add-Row 'Group nesting' 'Parent group' ([string](Get-Prop $parent 'displayName')) 'Member of (direct)' $parentId
    }
    foreach ($parent in @(Get-GraphCollection ("$Graph/groups/$groupId/transitiveMemberOf/microsoft.graph.group?" + '$select=id,displayName'))) {
        $parentId = [string](Get-Prop $parent 'id')
        if (-not $directParentIds.ContainsKey($parentId)) {
            Add-Row 'Group nesting' 'Parent group' ([string](Get-Prop $parent 'displayName')) 'Member of (inherited)' $parentId
        }
    }
}
catch { Write-Warning ('Could not read group nesting: {0}' -f $_.Exception.Message) }

# --- Group-based licensing ---
$licenses = @(Get-Prop $group 'assignedLicenses')
if ($licenses.Count -gt 0) {
    Write-Host 'Checking licenses...'
    $skuMap = @{}
    try {
        foreach ($sku in @(Get-GraphCollection "$Graph/subscribedSkus")) {
            $skuMap[[string](Get-Prop $sku 'skuId')] = [string](Get-Prop $sku 'skuPartNumber')
        }
    }
    catch { Write-Warning 'Could not resolve license SKU names (requires Organization.Read.All); showing SKU ids.' }
    foreach ($license in $licenses) {
        $skuId = [string](Get-Prop $license 'skuId')
        $skuName = $skuId
        if ($skuMap.ContainsKey($skuId)) { $skuName = $skuMap[$skuId] }
        Add-Row 'Licensing' 'License' $skuName 'Assigned via this group' $skuId
    }
}

# --- Enterprise app role assignments ---
Write-Host 'Checking enterprise app assignments...'
try {
    foreach ($appRole in @(Get-GraphCollection "$Graph/groups/$groupId/appRoleAssignments")) {
        Add-Row 'Enterprise apps' 'App role assignment' ([string](Get-Prop $appRole 'resourceDisplayName')) 'Assigned to app'
    }
}
catch { Write-Warning ('Could not read enterprise app assignments: {0}' -f $_.Exception.Message) }

# --- Intune assignments ---
$expandAssignments = '?$expand=assignments'
$AssignmentSources = @(
    @{ Label = 'Settings Catalog policy';            Uri = "$Graph/deviceManagement/configurationPolicies$expandAssignments"; NameProp = 'name' },
    @{ Label = 'Device configuration profile';       Uri = "$Graph/deviceManagement/deviceConfigurations$expandAssignments" },
    @{ Label = 'Administrative template';            Uri = "$Graph/deviceManagement/groupPolicyConfigurations$expandAssignments" },
    @{ Label = 'Compliance policy';                  Uri = "$Graph/deviceManagement/deviceCompliancePolicies$expandAssignments" },
    @{ Label = 'Endpoint security intent';           Uri = "$Graph/deviceManagement/intents$expandAssignments" },
    @{ Label = 'Application';                        Uri = ("$Graph/deviceAppManagement/mobileApps?" + '$filter=' + [uri]::EscapeDataString('isAssigned eq true') + '&$expand=assignments'); FallbackUri = "$Graph/deviceAppManagement/mobileApps$expandAssignments" },
    @{ Label = 'App protection policy (iOS)';        Uri = "$Graph/deviceAppManagement/iosManagedAppProtections$expandAssignments" },
    @{ Label = 'App protection policy (Android)';    Uri = "$Graph/deviceAppManagement/androidManagedAppProtections$expandAssignments" },
    @{ Label = 'App protection policy (Windows)';    Uri = "$Graph/deviceAppManagement/windowsManagedAppProtections$expandAssignments" },
    @{ Label = 'App config policy (managed apps)';   Uri = "$Graph/deviceAppManagement/targetedManagedAppConfigurations$expandAssignments" },
    @{ Label = 'App config policy (managed devices)'; Uri = "$Graph/deviceAppManagement/mobileAppConfigurations$expandAssignments" },
    @{ Label = 'PowerShell script';                  Uri = "$Graph/deviceManagement/deviceManagementScripts$expandAssignments" },
    @{ Label = 'macOS shell script';                 Uri = "$Graph/deviceManagement/deviceShellScripts$expandAssignments" },
    @{ Label = 'Remediation script';                 Uri = "$Graph/deviceManagement/deviceHealthScripts$expandAssignments" },
    @{ Label = 'Enrollment configuration';           Uri = "$Graph/deviceManagement/deviceEnrollmentConfigurations$expandAssignments"; Category = 'Enrollment'; TypeFromOData = $true },
    @{ Label = 'Autopilot deployment profile';       Uri = "$Graph/deviceManagement/windowsAutopilotDeploymentProfiles$expandAssignments"; Category = 'Enrollment' },
    @{ Label = 'Feature update profile';             Uri = "$Graph/deviceManagement/windowsFeatureUpdateProfiles$expandAssignments" },
    @{ Label = 'Quality update profile';             Uri = "$Graph/deviceManagement/windowsQualityUpdateProfiles$expandAssignments" },
    @{ Label = 'Driver update profile';              Uri = "$Graph/deviceManagement/windowsDriverUpdateProfiles$expandAssignments" }
)

$sourceIndex = 0
foreach ($source in $AssignmentSources) {
    $sourceIndex++
    Write-Host ('[{0}/{1}] Checking {2} assignments...' -f $sourceIndex, $AssignmentSources.Count, $source.Label)

    $items = $null
    $sourceError = $null
    try { $items = @(Get-GraphCollection $source.Uri) }
    catch {
        $sourceError = $_.Exception.Message
        if ($source.FallbackUri) {
            try { $items = @(Get-GraphCollection $source.FallbackUri); $sourceError = $null }
            catch { $sourceError = $_.Exception.Message }
        }
    }
    if ($sourceError) {
        Write-Warning ('Skipped {0}: {1}' -f $source.Label, $sourceError)
        continue
    }

    $nameProp = 'displayName'
    if ($source.NameProp) { $nameProp = $source.NameProp }
    $category = 'Intune assignment'
    if ($source.Category) { $category = $source.Category }

    foreach ($item in $items) {
        $itemName = [string](Get-Prop $item $nameProp)
        if (-not $itemName) { $itemName = [string](Get-Prop $item 'id') }
        $itemType = $source.Label
        if ($source.TypeFromOData) { $itemType = Get-EnrollmentTypeName ([string](Get-Prop $item '@odata.type')) }

        foreach ($assignment in @(Get-Prop $item 'assignments')) {
            $target = Get-Prop $assignment 'target'
            if ([string](Get-Prop $target 'groupId') -ne $groupId) { continue }
            $relationship = 'Included'
            if ([string](Get-Prop $target '@odata.type') -like '*exclusion*') { $relationship = 'Excluded' }
            Add-Row $category $itemType $itemName $relationship ([string](Get-Prop $assignment 'intent'))
        }
    }
}

# --- Intune role (RBAC) assignments ---
Write-Host 'Checking Intune role assignments...'
try {
    foreach ($roleAssignment in @(Get-GraphCollection "$Graph/deviceManagement/roleAssignments")) {
        $roleAssignmentId = [string](Get-Prop $roleAssignment 'id')
        $roleAssignmentName = [string](Get-Prop $roleAssignment 'displayName')
        $roleDetail = Invoke-GraphGet "$Graph/deviceManagement/roleAssignments/$roleAssignmentId"
        if (@(Get-Prop $roleDetail 'members') -contains $groupId) {
            Add-Row 'Intune RBAC' 'Role assignment' $roleAssignmentName 'Admin group (members)'
        }
        if (@(Get-Prop $roleDetail 'resourceScopes') -contains $groupId -or @(Get-Prop $roleDetail 'scopeMembers') -contains $groupId) {
            Add-Row 'Intune RBAC' 'Role assignment' $roleAssignmentName 'Scope group'
        }
    }
}
catch { Write-Warning ('Skipped Intune role assignments (requires DeviceManagementRBAC.Read.All): {0}' -f $_.Exception.Message) }

# --- Conditional Access ---
Write-Host 'Checking Conditional Access policies...'
try {
    foreach ($caPolicy in @(Get-GraphCollection "$Graph/identity/conditionalAccess/policies")) {
        $caUsers = Get-Prop (Get-Prop $caPolicy 'conditions') 'users'
        $caName = [string](Get-Prop $caPolicy 'displayName')
        $caState = 'State: ' + [string](Get-Prop $caPolicy 'state')
        if (@(Get-Prop $caUsers 'includeGroups') -contains $groupId) { Add-Row 'Conditional Access' 'CA policy' $caName 'Included' $caState }
        if (@(Get-Prop $caUsers 'excludeGroups') -contains $groupId) { Add-Row 'Conditional Access' 'CA policy' $caName 'Excluded' $caState }
    }
}
catch { Write-Warning ('Skipped Conditional Access (requires Policy.Read.All): {0}' -f $_.Exception.Message) }

# --- Output ---
$null = New-Item -ItemType Directory -Path $OutputPath -Force
$safeName = $groupDisplayName -replace '[^\w\-. ]', '_'
$csvPath = Join-Path $OutputPath ('GroupRelationships_{0}_{1}.csv' -f $safeName, (Get-Date -Format 'yyyy-MM-dd_HH-mm'))

$sorted = @()
if ($rows.Count -gt 0) { $sorted = @($rows.ToArray() | Sort-Object Category, ItemType, ItemName) }
if ($sorted.Count -gt 0) {
    $sorted | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
}
else {
    'Category,ItemType,ItemName,Relationship,Detail' | Out-File -FilePath $csvPath -Encoding utf8
}

Write-Host ''
if ($sorted.Count -gt 0) {
    $sorted | Format-Table Category, ItemType, ItemName, Relationship, Detail -AutoSize | Out-String -Width 260 | Write-Host
    Write-Host 'Relationship counts:'
    foreach ($categoryGroup in @($sorted | Group-Object Category | Sort-Object Name)) {
        Write-Host ('  {0}: {1}' -f $categoryGroup.Name, $categoryGroup.Count)
    }
}
else {
    Write-Host 'No relationships found for this group.'
}
Write-Host ''
Write-Host ('Saved {0} relationships to: {1}' -f $sorted.Count, $csvPath)
