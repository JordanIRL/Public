#requires -Version 7.0
#requires -Modules Microsoft.Graph.Authentication

<#
.SYNOPSIS
    Reports caller-visible Microsoft Loop workspace evidence associated with a user.

.DESCRIPTION
    Uses delegated Microsoft Graph v1.0 requests to discover Microsoft Loop
    SharePoint Embedded container types, enumerate active containers visible to
    the signed-in caller, and match permissions in that caller-visible set to the
    supplied user or the user's transitive group memberships.

    Microsoft Graph delegated list-containers returns only containers where the
    signed-in caller is a direct member. It excludes containers visible to the caller
    through a group and containers belonging only to the target user. This result is
    therefore always a partial diagnostic, never an all-workspaces inventory.

    The result includes explicit coverage records. A delegated guest application
    cannot receive the Microsoft Loop container-type permission required to read
    workspace files, pages, item-level share mappings, or recycle-bin contents.
    Those surfaces are therefore returned as NotAvailable and are never inferred.

.PARAMETER TenantId
    Microsoft Entra tenant GUID to authenticate against.

.PARAMETER UserPrincipalName
    User principal name or primary mail address whose Loop workspace access is examined.

.PARAMETER Environment
    Microsoft Graph cloud environment.

.PARAMETER ClientId
    Optional application ID for an approved public-client app registration.

.PARAMETER ExpectedAccount
    Optional user principal name that must match the signed-in administrator.

.PARAMETER UseDeviceCode
    Use delegated device-code authentication instead of interactive browser authentication.

.OUTPUTS
    A Tenant.LoopUserInventory object containing User, Workspaces, Coverage, and
    AccessFindings properties.

.EXAMPLE
    ./Get-UserLoopInventory.ps1 -TenantId '00000000-0000-0000-0000-000000000000' -UserPrincipalName 'alex@contoso.com'

.EXAMPLE
    ./Get-UserLoopInventory.ps1 -TenantId '00000000-0000-0000-0000-000000000000' -UserPrincipalName 'alex@contoso.com' -UseDeviceCode -ExpectedAccount 'admin@contoso.com'

.NOTES
    Required delegated Microsoft Graph scopes:
      FileStorageContainerTypeReg.Manage.All
      FileStorageContainer.Manage.All
      GroupMember.Read.All
      User.Read.All

    Required role: SharePoint Embedded Administrator or Global Administrator.
    Microsoft Loop workspaces are a commercial-cloud service even though some
    SharePoint Embedded administration APIs are present in national clouds.
#>

[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({
        if ($_ -eq [guid]::Empty) {
            throw 'TenantId must not be the empty GUID.'
        }
        $true
    })]
    [guid] $TenantId,

    [Parameter(Mandatory)]
    [ValidateScript({
        if ([string]::IsNullOrWhiteSpace($_)) {
            throw 'UserPrincipalName must not be empty or whitespace.'
        }
        $true
    })]
    [string] $UserPrincipalName,

    [Parameter()]
    [ValidateSet('Global', 'USGov', 'USGovDoD', 'China')]
    [string] $Environment = 'Global',

    [Parameter()]
    [ValidateScript({
        if ($_ -eq [guid]::Empty) {
            throw 'ClientId must not be the empty GUID when supplied.'
        }
        $true
    })]
    [guid] $ClientId,

    [Parameter()]
    [ValidateScript({
        if ([string]::IsNullOrWhiteSpace($_)) {
            throw 'ExpectedAccount must not be empty or whitespace when supplied.'
        }
        $true
    })]
    [string] $ExpectedAccount,

    [Parameter()]
    [switch] $UseDeviceCode
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Get-PropertyValue {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return $InputObject[$Name]
        }
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Invoke-GraphCollectionGet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Uri,

        [Parameter()]
        [hashtable] $Headers = @{}
    )

    $nextLink = $Uri
    while (-not [string]::IsNullOrWhiteSpace($nextLink)) {
        $requestParameters = @{
            Method      = 'GET'
            Uri         = $nextLink
            Headers     = $Headers
            ErrorAction = 'Stop'
        }
        $page = Invoke-MgGraphRequest @requestParameters
        $values = Get-PropertyValue -InputObject $page -Name 'value'
        if ($null -ne $values) {
            foreach ($value in @($values)) {
                $value
            }
        }

        $nextLinkValue = Get-PropertyValue -InputObject $page -Name '@odata.nextLink'
        $nextLink = if ($null -eq $nextLinkValue) { $null } else { [string] $nextLinkValue }
    }
}

function Get-SafeGraphFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Management.Automation.ErrorRecord] $ErrorRecord
    )

    $statusCode = Get-PropertyValue -InputObject $ErrorRecord.Exception -Name 'ResponseStatusCode'
    if ($null -eq $statusCode) {
        $statusCode = Get-PropertyValue -InputObject $ErrorRecord.Exception -Name 'StatusCode'
    }

    [pscustomobject] [ordered] @{
        ExceptionType = $ErrorRecord.Exception.GetType().FullName
        StatusCode    = if ($null -eq $statusCode) { $null } else { [string] $statusCode }
    }
}

function Get-PermissionIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Permission
    )

    $identitySets = [Collections.Generic.List[object]]::new()
    $singleIdentity = Get-PropertyValue -InputObject $Permission -Name 'grantedToV2'
    if ($null -ne $singleIdentity) {
        $identitySets.Add($singleIdentity)
    }

    $multipleIdentities = Get-PropertyValue -InputObject $Permission -Name 'grantedToIdentitiesV2'
    foreach ($identitySet in @($multipleIdentities)) {
        if ($null -ne $identitySet) {
            $identitySets.Add($identitySet)
        }
    }

    foreach ($identitySet in $identitySets) {
        foreach ($identityType in @('user', 'group')) {
            $identity = Get-PropertyValue -InputObject $identitySet -Name $identityType
            if ($null -eq $identity) {
                continue
            }

            [pscustomobject] [ordered] @{
                IdentityType     = $identityType
                Id               = Get-PropertyValue -InputObject $identity -Name 'id'
                DisplayName      = Get-PropertyValue -InputObject $identity -Name 'displayName'
                UserPrincipalName = Get-PropertyValue -InputObject $identity -Name 'userPrincipalName'
                Email            = Get-PropertyValue -InputObject $identity -Name 'email'
            }
        }
    }
}

function Test-StringEqual {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Left,

        [Parameter()]
        [AllowNull()]
        [object] $Right
    )

    if ($null -eq $Left -or $null -eq $Right) {
        return $false
    }

    return [string]::Equals(
        [string] $Left,
        [string] $Right,
        [StringComparison]::OrdinalIgnoreCase
    )
}

$requiredScopes = @(
    'FileStorageContainerTypeReg.Manage.All'
    'FileStorageContainer.Manage.All'
    'GroupMember.Read.All'
    'User.Read.All'
)

$loopOwningApplicationIds = @(
    'a187e399-0c36-4b98-8f04-1edc167a0996' # Loop Web
    '0922ef46-e1b9-4f7e-9134-9ad00547eb41' # Loop Mobile
)
$normalizedUserPrincipalName = $UserPrincipalName.Trim()
$connected = $false

try {
    $connectParameters = @{
        Scopes       = $requiredScopes
        TenantId     = $TenantId.Guid
        Environment  = $Environment
        ContextScope = 'Process'
        NoWelcome    = $true
        ErrorAction  = 'Stop'
    }

    if ($PSBoundParameters.ContainsKey('ClientId')) {
        $connectParameters.ClientId = $ClientId.Guid
    }

    if ($UseDeviceCode) {
        $connectParameters.UseDeviceCode = $true
    }

    Connect-MgGraph @connectParameters
    $connected = $true

    $graphContext = Get-MgContext
    if ($null -eq $graphContext -or $graphContext.AuthType -ne 'Delegated') {
        throw 'Microsoft Graph did not establish a delegated authentication context.'
    }

    if (-not (Test-StringEqual -Left $graphContext.TenantId -Right $TenantId.Guid)) {
        throw "Authenticated to tenant '$($graphContext.TenantId)' instead of '$($TenantId.Guid)'."
    }

    if ($graphContext.ContextScope -ne 'Process') {
        throw "Microsoft Graph used context scope '$($graphContext.ContextScope)' instead of 'Process'."
    }

    if (-not (Test-StringEqual -Left $graphContext.Environment -Right $Environment)) {
        throw "Microsoft Graph used environment '$($graphContext.Environment)' instead of '$Environment'."
    }

    if (
        $PSBoundParameters.ContainsKey('ClientId') -and
        -not (Test-StringEqual -Left $graphContext.ClientId -Right $ClientId.Guid)
    ) {
        throw "Microsoft Graph used client '$($graphContext.ClientId)' instead of '$($ClientId.Guid)'."
    }

    if (
        $PSBoundParameters.ContainsKey('ExpectedAccount') -and
        -not (Test-StringEqual -Left $graphContext.Account -Right $ExpectedAccount)
    ) {
        throw "Signed in as '$($graphContext.Account)' instead of '$ExpectedAccount'."
    }

    $missingScopes = @(
        $requiredScopes | Where-Object { $_ -notin $graphContext.Scopes }
    )
    if ($missingScopes.Count -gt 0) {
        throw "The delegated token is missing required scope(s): $($missingScopes -join ', ')."
    }

    $escapedUserAddress = $normalizedUserPrincipalName.Replace("'", "''")
    $encodedUserFilter = [Uri]::EscapeDataString("userPrincipalName eq '$escapedUserAddress' or mail eq '$escapedUserAddress'")
    $matchingUsers = @(
        Invoke-GraphCollectionGet -Uri "/v1.0/users?`$filter=$encodedUserFilter&`$select=id,displayName,userPrincipalName,mail,accountEnabled,userType"
    )
    if ($matchingUsers.Count -eq 0) {
        throw "No Microsoft Entra user matched '$normalizedUserPrincipalName' as a userPrincipalName or primary mail address."
    }
    if ($matchingUsers.Count -gt 1) {
        throw "'$normalizedUserPrincipalName' matched $($matchingUsers.Count) Microsoft Entra users; refusing an ambiguous Loop query."
    }
    $user = $matchingUsers[0]

    $userId = [string] (Get-PropertyValue -InputObject $user -Name 'id')
    if ([string]::IsNullOrWhiteSpace($userId)) {
        throw "Microsoft Graph returned no object ID for '$normalizedUserPrincipalName'."
    }

    $groupIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $encodedUserId = [Uri]::EscapeDataString($userId)
    $groupUri = "/v1.0/users/$encodedUserId/transitiveMemberOf/microsoft.graph.group?`$select=id,displayName&`$top=999"
    foreach ($group in @(Invoke-GraphCollectionGet -Uri $groupUri)) {
        $groupId = Get-PropertyValue -InputObject $group -Name 'id'
        if (-not [string]::IsNullOrWhiteSpace([string] $groupId)) {
            $null = $groupIds.Add([string] $groupId)
        }
    }

    $registrationUri = "/v1.0/storage/fileStorage/containerTypeRegistrations?`$select=id,name,owningAppId,billingClassification,billingStatus,registeredDateTime,expirationDateTime,settings&`$top=200"
    $registrations = @(
        Invoke-GraphCollectionGet -Uri $registrationUri |
            Where-Object {
                $owningAppId = [string] (Get-PropertyValue -InputObject $_ -Name 'owningAppId')
                $loopOwningApplicationIds -contains $owningAppId
            }
    )

    $coverage = [Collections.Generic.List[object]]::new()
    $accessFindings = [Collections.Generic.List[object]]::new()
    $workspaces = [Collections.Generic.List[object]]::new()
    $itemLevelAccessSignals = [Collections.Generic.List[object]]::new()

    $coverage.Add([pscustomobject] [ordered] @{
        Surface = 'WorkspaceUniverse'
        Status  = 'NotAvailable'
        Detail  = 'Delegated list-containers returns only containers where the signed-in caller is a direct member. This script cannot establish all workspaces for an arbitrary target user.'
    })
    $coverage.Add([pscustomobject] [ordered] @{
        Surface = 'WorkspaceMetadata'
        Status  = if ($registrations.Count -gt 0) { 'Partial' } else { 'NotAvailable' }
        Detail  = if ($registrations.Count -gt 0) {
            'Active Loop container metadata and membership evidence are queried only within the signed-in caller direct-membership set.'
        }
        else {
            'No Microsoft Loop container type registration was visible in this tenant and cloud.'
        }
    })
    $coverage.Add([pscustomobject] [ordered] @{
        Surface = 'WorkspaceFilesAndPages'
        Status  = 'NotAvailable'
        Detail  = 'Loop workspace content requires FileStorageContainer.Selected plus Loop container-type permission; Microsoft documents guest-app access to the Loop container type as app-only.'
    })
    $coverage.Add([pscustomobject] [ordered] @{
        Surface = 'ContentRecycleBin'
        Status  = 'NotAvailable'
        Detail  = 'The SharePoint Embedded recycle-bin content API requires FileStorageContainer.Selected and Loop container-type permission, which are not available to this delegated guest application.'
    })
    $coverage.Add([pscustomobject] [ordered] @{
        Surface = 'DeletedWorkspaceAttribution'
        Status  = 'NotAvailable'
        Detail  = 'Microsoft Graph v1.0 does not document a deleted-container query filtered by an arbitrary user or a supported permission lookup on deleted containers.'
    })
    $coverage.Add([pscustomobject] [ordered] @{
        Surface = 'OneDriveAndSharePointLoopComponents'
        Status  = 'NotCovered'
        Detail  = 'This script inventories Loop workspace containers only. Loop components stored in OneDrive or ordinary SharePoint sites are separate resources.'
    })

    $containerCount = 0
    $permissionSuccessCount = 0
    $expandedPermissionSuccessCount = 0
    $expandedPermissionFailureCount = 0
    $containerEnumerationSuccessCount = 0
    $containerEnumerationFailureCount = 0
    foreach ($registration in $registrations) {
        $containerTypeId = [string] (Get-PropertyValue -InputObject $registration -Name 'id')
        if ([string]::IsNullOrWhiteSpace($containerTypeId)) {
            continue
        }

        $containerFilter = [Uri]::EscapeDataString("containerTypeId eq $containerTypeId")
        $containerUri = "/v1.0/storage/fileStorage/containers?`$filter=$containerFilter"
        try {
            $containers = @(Invoke-GraphCollectionGet -Uri $containerUri)
            $containerEnumerationSuccessCount++
        }
        catch {
            $containerEnumerationFailureCount++
            $failure = Get-SafeGraphFailure -ErrorRecord $_
            $accessFindings.Add([pscustomobject] [ordered] @{
                ContainerTypeId = $containerTypeId
                ContainerId     = $null
                Status          = 'Inaccessible'
                MatchBasis      = $null
                Roles           = @()
                IdentityId      = $null
                Failure         = $failure
                Detail          = 'Containers for this Loop container type could not be enumerated. Delegated list-containers calls also require the signed-in administrator to have a provisioned OneDrive.'
            })
            continue
        }

        foreach ($container in $containers) {
            $containerCount++
            $containerId = [string] (Get-PropertyValue -InputObject $container -Name 'id')
            if ([string]::IsNullOrWhiteSpace($containerId)) {
                continue
            }

            $encodedContainerId = [Uri]::EscapeDataString($containerId)
            $permissionUri = "/v1.0/storage/fileStorage/containers/$encodedContainerId/permissions"
            $containerPermissions = @()
            try {
                $containerPermissions = @(Invoke-GraphCollectionGet -Uri $permissionUri)
                $permissionSuccessCount++
            }
            catch {
                $failure = Get-SafeGraphFailure -ErrorRecord $_
                $accessFindings.Add([pscustomobject] [ordered] @{
                    ContainerId  = $containerId
                    Status       = 'Unknown'
                    MatchBasis   = $null
                    Roles        = @()
                    IdentityId   = $null
                    Failure      = $failure
                    Detail       = 'Container permissions could not be read, so association with the target user could not be determined.'
                })
                continue
            }

            $expandedPermissions = @()
            try {
                $expandedPermissions = @(
                    Invoke-GraphCollectionGet -Uri "$permissionUri`?includeAllContainerUsers=true"
                )
                $expandedPermissionSuccessCount++
            }
            catch {
                $expandedPermissionFailureCount++
                $failure = Get-SafeGraphFailure -ErrorRecord $_
                $accessFindings.Add([pscustomobject] [ordered] @{
                    ContainerId  = $containerId
                    Status       = 'ItemLevelSignalsInaccessible'
                    MatchBasis   = $null
                    Roles        = @()
                    IdentityId   = $null
                    Failure      = $failure
                    Detail       = 'The includeAllContainerUsers permission view could not be read. Container-scoped membership classification remains separate and available.'
                })
            }

            $matches = [Collections.Generic.List[object]]::new()
            $permissionSummaries = [Collections.Generic.List[object]]::new()
            $containerPermissionIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($permission in $containerPermissions) {
                $containerPermissionId = [string] (Get-PropertyValue -InputObject $permission -Name 'id')
                if (-not [string]::IsNullOrWhiteSpace($containerPermissionId)) {
                    $null = $containerPermissionIds.Add($containerPermissionId)
                }
                $permissionIdentities = @(Get-PermissionIdentity -Permission $permission)
                $permissionSummaries.Add([pscustomobject] [ordered] @{
                    PermissionId = $containerPermissionId
                    Roles        = @((Get-PropertyValue -InputObject $permission -Name 'roles'))
                    Identities   = @($permissionIdentities)
                    AccessScope  = 'Container'
                })

                foreach ($identity in $permissionIdentities) {
                    $identityId = Get-PropertyValue -InputObject $identity -Name 'Id'
                    $identityType = [string] (Get-PropertyValue -InputObject $identity -Name 'IdentityType')
                    $identityUpn = Get-PropertyValue -InputObject $identity -Name 'UserPrincipalName'
                    $identityEmail = Get-PropertyValue -InputObject $identity -Name 'Email'
                    $isDirectUser = $identityType -eq 'user' -and (
                        (Test-StringEqual -Left $identityId -Right $userId) -or
                        (Test-StringEqual -Left $identityUpn -Right $normalizedUserPrincipalName) -or
                        (Test-StringEqual -Left $identityEmail -Right $normalizedUserPrincipalName)
                    )
                    $isGroupMembership = $identityType -eq 'group' -and $groupIds.Contains([string] $identityId)

                    if (-not $isDirectUser -and -not $isGroupMembership) {
                        continue
                    }

                    $roles = @((Get-PropertyValue -InputObject $permission -Name 'roles'))
                    $match = [pscustomobject] [ordered] @{
                        MatchBasis      = if ($isDirectUser) { 'DirectUser' } else { 'TransitiveGroup' }
                        IdentityType    = $identityType
                        IdentityId      = $identityId
                        IdentityName    = Get-PropertyValue -InputObject $identity -Name 'DisplayName'
                        UserPrincipalName = $identityUpn
                        Email           = $identityEmail
                        Roles           = @($roles)
                        PermissionId    = $containerPermissionId
                        AccessScope     = 'Container'
                    }
                    $matches.Add($match)
                    $accessFindings.Add([pscustomobject] [ordered] @{
                        ContainerId = $containerId
                        Status      = 'Matched'
                        MatchBasis  = $match.MatchBasis
                        Roles       = $match.Roles
                        IdentityId  = $match.IdentityId
                        Failure     = $null
                        Detail      = 'A container permission entry matched the target user or one of the target user''s transitive groups.'
                    })
                }
            }

            $containerItemSignals = [Collections.Generic.List[object]]::new()
            foreach ($permission in $expandedPermissions) {
                $permissionId = [string] (Get-PropertyValue -InputObject $permission -Name 'id')
                if (-not [string]::IsNullOrWhiteSpace($permissionId) -and $containerPermissionIds.Contains($permissionId)) {
                    continue
                }

                foreach ($identity in @(Get-PermissionIdentity -Permission $permission)) {
                    $identityId = Get-PropertyValue -InputObject $identity -Name 'Id'
                    $identityType = [string] (Get-PropertyValue -InputObject $identity -Name 'IdentityType')
                    $identityUpn = Get-PropertyValue -InputObject $identity -Name 'UserPrincipalName'
                    $identityEmail = Get-PropertyValue -InputObject $identity -Name 'Email'
                    $isDirectUser = $identityType -eq 'user' -and (
                        (Test-StringEqual -Left $identityId -Right $userId) -or
                        (Test-StringEqual -Left $identityUpn -Right $normalizedUserPrincipalName) -or
                        (Test-StringEqual -Left $identityEmail -Right $normalizedUserPrincipalName)
                    )
                    $isGroupMembership = $identityType -eq 'group' -and $groupIds.Contains([string] $identityId)
                    if (-not $isDirectUser -and -not $isGroupMembership) {
                        continue
                    }

                    $signal = [pscustomobject] [ordered] @{
                        ContainerId       = $containerId
                        ContainerTypeId   = $containerTypeId
                        ContainerName     = Get-PropertyValue -InputObject $container -Name 'displayName'
                        MatchBasis        = if ($isDirectUser) { 'DirectUser' } else { 'TransitiveGroup' }
                        IdentityType      = $identityType
                        IdentityId        = $identityId
                        IdentityName      = Get-PropertyValue -InputObject $identity -Name 'DisplayName'
                        UserPrincipalName = $identityUpn
                        Email             = $identityEmail
                        Roles             = @((Get-PropertyValue -InputObject $permission -Name 'roles'))
                        PermissionId      = $permissionId
                        AccessScope       = 'ItemLevelOrNonContainer'
                        ItemMapping       = 'NotAvailable'
                    }
                    $containerItemSignals.Add($signal)
                    $itemLevelAccessSignals.Add($signal)
                    $accessFindings.Add([pscustomobject] [ordered] @{
                        ContainerId = $containerId
                        Status      = 'ItemLevelAccessSignal'
                        MatchBasis  = $signal.MatchBasis
                        Roles       = $signal.Roles
                        IdentityId  = $signal.IdentityId
                        Failure     = $null
                        Detail      = 'An includeAllContainerUsers-only permission matched the target. It is not classified as workspace membership, and Microsoft Graph does not identify the individual shared item.'
                    })
                }
            }

            if ($matches.Count -eq 0) {
                continue
            }

            $containerDetails = $container
            try {
                $containerDetails = Invoke-MgGraphRequest -Method GET -Uri "/v1.0/storage/fileStorage/containers/$encodedContainerId" -ErrorAction Stop
            }
            catch {
                $failure = Get-SafeGraphFailure -ErrorRecord $_
                $accessFindings.Add([pscustomobject] [ordered] @{
                    ContainerId = $containerId
                    Status      = 'Partial'
                    MatchBasis  = $null
                    Roles       = @()
                    IdentityId  = $null
                    Failure     = $failure
                    Detail      = 'The list response identified the workspace, but the detailed container metadata request failed.'
                })
            }

            $assignedLabel = Get-PropertyValue -InputObject $containerDetails -Name 'assignedSensitivityLabel'
            $viewpoint = Get-PropertyValue -InputObject $containerDetails -Name 'viewpoint'
            $workspaces.Add([pscustomobject] [ordered] @{
                ContainerId             = $containerId
                ContainerTypeId         = Get-PropertyValue -InputObject $containerDetails -Name 'containerTypeId'
                ContainerTypeName       = Get-PropertyValue -InputObject $registration -Name 'name'
                DisplayName             = Get-PropertyValue -InputObject $containerDetails -Name 'displayName'
                Description             = Get-PropertyValue -InputObject $containerDetails -Name 'description'
                CreatedDateTime         = Get-PropertyValue -InputObject $containerDetails -Name 'createdDateTime'
                Status                  = Get-PropertyValue -InputObject $containerDetails -Name 'status'
                LockState               = Get-PropertyValue -InputObject $containerDetails -Name 'lockState'
                EffectiveRole           = Get-PropertyValue -InputObject $viewpoint -Name 'effectiveRole'
                SensitivityLabelId      = Get-PropertyValue -InputObject $assignedLabel -Name 'labelId'
                SensitivityLabelName    = Get-PropertyValue -InputObject $assignedLabel -Name 'displayName'
                MembershipEvidence      = @($matches)
                ContainerPermissions    = @($permissionSummaries)
                ItemLevelAccessSignals  = @($containerItemSignals)
                ContainerMetadata       = $containerDetails
                FileAndPageInventory    = 'NotAvailable'
                ContentRecycleBin       = 'NotAvailable'
                ItemLevelShareMapping   = 'NotAvailable'
            })
        }
    }

    $coverage.Add([pscustomobject] [ordered] @{
        Surface = 'ItemLevelShareMapping'
        Status  = if ($expandedPermissionSuccessCount -gt 0) {
            'PartialSignalOnly'
        }
        elseif ($containerCount -gt 0) {
            'Inaccessible'
        }
        else {
            'NotAvailable'
        }
        Detail  = if ($expandedPermissionSuccessCount -gt 0) {
            'includeAllContainerUsers-only matches are returned separately as item-level access signals and never classified as workspace membership. Microsoft Graph does not identify the individual shared item.'
        }
        elseif ($expandedPermissionFailureCount -gt 0) {
            'The expanded permission view could not be read, so item-level access signals are unavailable.'
        }
        else {
            'No caller-visible container was available for item-level access signal evaluation.'
        }
    })

    $coverage.Add([pscustomobject] [ordered] @{
        Surface = 'ContainerEnumeration'
        Status  = if ($containerEnumerationFailureCount -eq 0 -and $containerEnumerationSuccessCount -gt 0) {
            'CallerDirectMembershipOnly'
        }
        elseif ($containerEnumerationSuccessCount -gt 0) {
            'Partial'
        }
        elseif ($registrations.Count -eq 0) {
            'NotAvailable'
        }
        else {
            'Inaccessible'
        }
        Detail  = if ($containerEnumerationFailureCount -gt 0) {
            'One or more Loop container types could not be enumerated. Verify FileStorageContainer.Manage.All, the administrator role, and that the signed-in administrator has a provisioned OneDrive.'
        }
        else {
            'All visible Loop container types were queried, but Microsoft Graph returned only containers where the signed-in caller is a direct member. Group-derived caller membership and target-only containers are excluded by the API.'
        }
    })

    if ($containerEnumerationFailureCount -gt 0 -and $containerEnumerationSuccessCount -eq 0) {
        $coverage.Add([pscustomobject] [ordered] @{
            Surface = 'WorkspaceMembership'
            Status  = 'Inaccessible'
            Detail  = 'No Loop container type could be enumerated, so workspace membership could not be evaluated.'
        })
    }
    elseif ($containerCount -gt 0 -and $permissionSuccessCount -eq 0) {
        $coverage.Add([pscustomobject] [ordered] @{
            Surface = 'WorkspaceMembership'
            Status  = 'AccessDeniedOrUnavailable'
            Detail  = 'Containers were returned, but no container permission request succeeded. Verify the operator role and delegated administrative permissions.'
        })
    }
    else {
        $coverage.Add([pscustomobject] [ordered] @{
            Surface = 'WorkspaceMembership'
            Status  = if ($registrations.Count -gt 0) { 'Partial' } else { 'NotAvailable' }
            Detail  = 'Target direct permissions and permissions assigned to target transitive groups were compared only inside the signed-in caller direct-membership container set. Hidden groups and target-only containers can be absent.'
        })
    }

    [pscustomobject] [ordered] @{
        PSTypeName       = 'Tenant.LoopUserInventory'
        GeneratedAtUtc   = [datetime]::UtcNow
        TenantId         = $TenantId.Guid
        Environment      = $Environment
        SignedInAccount  = [string] $graphContext.Account
        InventoryCompleteness = 'PartialCallerDirectMembershipOnly'
        User             = [pscustomobject] [ordered] @{
            Id                = $userId
            DisplayName       = Get-PropertyValue -InputObject $user -Name 'displayName'
            UserPrincipalName = Get-PropertyValue -InputObject $user -Name 'userPrincipalName'
            Mail              = Get-PropertyValue -InputObject $user -Name 'mail'
            AccountEnabled    = Get-PropertyValue -InputObject $user -Name 'accountEnabled'
            UserType          = Get-PropertyValue -InputObject $user -Name 'userType'
        }
        ContainerTypes    = @($registrations | ForEach-Object {
            [pscustomobject] [ordered] @{
                Id                    = Get-PropertyValue -InputObject $_ -Name 'id'
                Name                  = Get-PropertyValue -InputObject $_ -Name 'name'
                OwningApplicationId   = Get-PropertyValue -InputObject $_ -Name 'owningAppId'
                BillingClassification = Get-PropertyValue -InputObject $_ -Name 'billingClassification'
                BillingStatus         = Get-PropertyValue -InputObject $_ -Name 'billingStatus'
                RegisteredDateTime    = Get-PropertyValue -InputObject $_ -Name 'registeredDateTime'
                ExpirationDateTime    = Get-PropertyValue -InputObject $_ -Name 'expirationDateTime'
            }
        })
        Workspaces        = @($workspaces)
        MatchedWorkspaceCount = $workspaces.Count
        ItemLevelAccessSignals = @($itemLevelAccessSignals)
        ItemLevelAccessSignalCount = $itemLevelAccessSignals.Count
        ContainersExamined = $containerCount
        Coverage          = @($coverage)
        AccessFindings    = @($accessFindings)
        RequiredScopes    = @($requiredScopes)
        RequiredRole      = 'SharePoint Embedded Administrator or Global Administrator'
    }
}
catch {
    $message = "Loop workspace inventory failed for '$normalizedUserPrincipalName': $($_.Exception.Message)"
    throw [InvalidOperationException]::new($message, $_.Exception)
}
finally {
    if ($connected) {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
}
