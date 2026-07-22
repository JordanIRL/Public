#requires -Version 7.0
#requires -Modules Microsoft.Graph.Authentication

<#
.SYNOPSIS
    Resolves available Microsoft Graph metadata for a Microsoft Loop-related link.

.DESCRIPTION
    Encodes an HTTPS link for the Microsoft Graph v1.0 Shares API and returns the
    caller-visible drive item, sharing permission, and version metadata. The
    script uses redeemSharingLinkIfNecessary so access is guaranteed only for
    the duration of the request rather than explicitly redeeming the link.

    The Shares API supports OneDrive and SharePoint sharing URLs. An arbitrary
    Loop application URL or a SharePoint Embedded Loop link might not be
    resolvable by a delegated guest application. Such cases return structured
    UnsupportedOrInaccessible coverage rather than incomplete link details.

.PARAMETER TenantId
    Microsoft Entra tenant GUID to authenticate against.

.PARAMETER LoopLink
    HTTPS OneDrive, SharePoint, or Loop-related link to examine.

.PARAMETER Environment
    Microsoft Graph cloud environment.

.PARAMETER ClientId
    Optional application ID for an approved public-client app registration.

.PARAMETER ExpectedAccount
    Optional user principal name that must match the signed-in administrator.

.PARAMETER UseDeviceCode
    Use delegated device-code authentication instead of interactive browser authentication.

.OUTPUTS
    A Tenant.LoopLinkDetails object containing Item, Permissions, Versions,
    SharingMetadata, Coverage, and AccessFindings properties.

.EXAMPLE
    ./Get-LoopLinkDetails.ps1 -TenantId '00000000-0000-0000-0000-000000000000' -LoopLink 'https://contoso.sharepoint.com/:f:/s/example/...'

.NOTES
    Required delegated Microsoft Graph scope: Files.ReadWrite.
    Files.ReadWrite is the least delegated permission documented for GET /shares.
    The signed-in user must be permitted to use the supplied sharing link or
    already have access to the item.
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
        if (-not $_.IsAbsoluteUri -or $_.Scheme -ne 'https') {
            throw 'LoopLink must be an absolute HTTPS URI.'
        }
        $true
    })]
    [uri] $LoopLink,

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

function ConvertTo-SharesApiId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [uri] $Uri
    )

    $bytes = [Text.Encoding]::UTF8.GetBytes($Uri.AbsoluteUri)
    $base64 = [Convert]::ToBase64String($bytes)
    return 'u!' + $base64.TrimEnd('=').Replace('/', '_').Replace('+', '-')
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

function ConvertTo-IdentitySummary {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $IdentitySet
    )

    if ($null -eq $IdentitySet) {
        return $null
    }

    foreach ($identityType in @('user', 'group', 'application', 'device', 'siteUser', 'siteGroup')) {
        $identity = Get-PropertyValue -InputObject $IdentitySet -Name $identityType
        if ($null -eq $identity) {
            continue
        }

        return [pscustomobject] [ordered] @{
            Type              = $identityType
            Id                = Get-PropertyValue -InputObject $identity -Name 'id'
            DisplayName       = Get-PropertyValue -InputObject $identity -Name 'displayName'
            UserPrincipalName = Get-PropertyValue -InputObject $identity -Name 'userPrincipalName'
            Email             = Get-PropertyValue -InputObject $identity -Name 'email'
            LoginName         = Get-PropertyValue -InputObject $identity -Name 'loginName'
        }
    }

    return $null
}

function ConvertTo-DriveItemSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $DriveItem
    )

    $file = Get-PropertyValue -InputObject $DriveItem -Name 'file'
    $hashes = Get-PropertyValue -InputObject $file -Name 'hashes'
    $folder = Get-PropertyValue -InputObject $DriveItem -Name 'folder'
    $package = Get-PropertyValue -InputObject $DriveItem -Name 'package'
    $parentReference = Get-PropertyValue -InputObject $DriveItem -Name 'parentReference'
    $sharePointIds = Get-PropertyValue -InputObject $DriveItem -Name 'sharepointIds'
    $createdBy = Get-PropertyValue -InputObject $DriveItem -Name 'createdBy'
    $lastModifiedBy = Get-PropertyValue -InputObject $DriveItem -Name 'lastModifiedBy'
    $name = [string] (Get-PropertyValue -InputObject $DriveItem -Name 'name')

    $loopExtension = if ([string]::IsNullOrWhiteSpace($name)) {
        $null
    }
    elseif ($name.EndsWith('.loop', [StringComparison]::OrdinalIgnoreCase)) {
        '.loop'
    }
    elseif ($name.EndsWith('.fluid', [StringComparison]::OrdinalIgnoreCase)) {
        '.fluid'
    }
    elseif ($name.EndsWith('.page', [StringComparison]::OrdinalIgnoreCase)) {
        '.page'
    }
    else {
        $null
    }

    [pscustomobject] [ordered] @{
        Id                    = Get-PropertyValue -InputObject $DriveItem -Name 'id'
        Name                  = $name
        IsRecognizedLoopFile  = $null -ne $loopExtension
        LoopFileExtension     = $loopExtension
        WebUrl                = Get-PropertyValue -InputObject $DriveItem -Name 'webUrl'
        SizeBytes             = Get-PropertyValue -InputObject $DriveItem -Name 'size'
        CreatedDateTime       = Get-PropertyValue -InputObject $DriveItem -Name 'createdDateTime'
        LastModifiedDateTime  = Get-PropertyValue -InputObject $DriveItem -Name 'lastModifiedDateTime'
        CreatedBy             = ConvertTo-IdentitySummary -IdentitySet $createdBy
        LastModifiedBy        = ConvertTo-IdentitySummary -IdentitySet $lastModifiedBy
        MimeType              = Get-PropertyValue -InputObject $file -Name 'mimeType'
        QuickXorHash          = Get-PropertyValue -InputObject $hashes -Name 'quickXorHash'
        Sha1Hash              = Get-PropertyValue -InputObject $hashes -Name 'sha1Hash'
        Sha256Hash            = Get-PropertyValue -InputObject $hashes -Name 'sha256Hash'
        ChildCount            = Get-PropertyValue -InputObject $folder -Name 'childCount'
        PackageType           = Get-PropertyValue -InputObject $package -Name 'type'
        DriveId               = Get-PropertyValue -InputObject $parentReference -Name 'driveId'
        ParentItemId          = Get-PropertyValue -InputObject $parentReference -Name 'id'
        ParentPath            = Get-PropertyValue -InputObject $parentReference -Name 'path'
        ParentDriveType       = Get-PropertyValue -InputObject $parentReference -Name 'driveType'
        ParentSiteId          = Get-PropertyValue -InputObject $parentReference -Name 'siteId'
        SharePointListItemId  = Get-PropertyValue -InputObject $sharePointIds -Name 'listItemId'
        SharePointListItemUid = Get-PropertyValue -InputObject $sharePointIds -Name 'listItemUniqueId'
        SharePointListId      = Get-PropertyValue -InputObject $sharePointIds -Name 'listId'
        SharePointSiteId      = Get-PropertyValue -InputObject $sharePointIds -Name 'siteId'
        SharePointSiteUrl     = Get-PropertyValue -InputObject $sharePointIds -Name 'siteUrl'
        SharePointTenantId    = Get-PropertyValue -InputObject $sharePointIds -Name 'tenantId'
        SharePointWebId       = Get-PropertyValue -InputObject $sharePointIds -Name 'webId'
        ETag                  = Get-PropertyValue -InputObject $DriveItem -Name 'eTag'
        CTag                  = Get-PropertyValue -InputObject $DriveItem -Name 'cTag'
    }
}

function ConvertTo-PermissionSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Permission
    )

    $identities = [Collections.Generic.List[object]]::new()
    $grantedTo = ConvertTo-IdentitySummary -IdentitySet (Get-PropertyValue -InputObject $Permission -Name 'grantedToV2')
    if ($null -ne $grantedTo) {
        $identities.Add($grantedTo)
    }
    foreach ($identitySet in @((Get-PropertyValue -InputObject $Permission -Name 'grantedToIdentitiesV2'))) {
        $identity = ConvertTo-IdentitySummary -IdentitySet $identitySet
        if ($null -ne $identity) {
            $identities.Add($identity)
        }
    }

    $link = Get-PropertyValue -InputObject $Permission -Name 'link'
    $invitation = Get-PropertyValue -InputObject $Permission -Name 'invitation'
    $inheritedFrom = Get-PropertyValue -InputObject $Permission -Name 'inheritedFrom'
    [pscustomobject] [ordered] @{
        Id                    = Get-PropertyValue -InputObject $Permission -Name 'id'
        Roles                 = @((Get-PropertyValue -InputObject $Permission -Name 'roles'))
        GrantedTo             = @($identities)
        LinkType              = Get-PropertyValue -InputObject $link -Name 'type'
        LinkScope             = Get-PropertyValue -InputObject $link -Name 'scope'
        LinkPreventsDownload  = Get-PropertyValue -InputObject $link -Name 'preventsDownload'
        LinkApplicationId     = Get-PropertyValue -InputObject $link -Name 'applicationId'
        InvitationEmail       = Get-PropertyValue -InputObject $invitation -Name 'email'
        InvitationSignInRequired = Get-PropertyValue -InputObject $invitation -Name 'signInRequired'
        ExpirationDateTime    = Get-PropertyValue -InputObject $Permission -Name 'expirationDateTime'
        HasPassword           = Get-PropertyValue -InputObject $Permission -Name 'hasPassword'
        InheritedFromDriveId  = Get-PropertyValue -InputObject $inheritedFrom -Name 'driveId'
        InheritedFromItemId   = Get-PropertyValue -InputObject $inheritedFrom -Name 'id'
    }
}

$requiredScopes = @('Files.ReadWrite')
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

    $shareId = ConvertTo-SharesApiId -Uri $LoopLink
    $shareHeaders = @{ Prefer = 'redeemSharingLinkIfNecessary' }
    $coverage = [Collections.Generic.List[object]]::new()
    $accessFindings = [Collections.Generic.List[object]]::new()

    $driveItem = $null
    try {
        $driveItem = Invoke-MgGraphRequest -Method GET -Uri "/v1.0/shares/$shareId/driveItem" -Headers $shareHeaders -ErrorAction Stop
    }
    catch {
        $failure = Get-SafeGraphFailure -ErrorRecord $_
        $coverage.Add([pscustomobject] [ordered] @{
            Surface = 'LinkResolution'
            Status  = 'UnsupportedOrInaccessible'
            Detail  = 'The Shares API could not resolve this URL for the signed-in user. It may be a Loop application URL, a SharePoint Embedded link, an unsupported sharing URL, or a link the caller cannot access.'
        })
        $coverage.Add([pscustomobject] [ordered] @{
            Surface = 'LoopSemanticContent'
            Status  = 'NotAvailable'
            Detail  = 'Microsoft Graph v1.0 does not expose Loop page semantics through the Shares API.'
        })
        $accessFindings.Add([pscustomobject] [ordered] @{
            Operation = 'ResolveShareLink'
            Status    = 'UnsupportedOrInaccessible'
            Failure   = $failure
        })

        return [pscustomobject] [ordered] @{
            PSTypeName       = 'Tenant.LoopLinkDetails'
            GeneratedAtUtc   = [datetime]::UtcNow
            TenantId         = $TenantId.Guid
            Environment      = $Environment
            InputHost        = $LoopLink.DnsSafeHost
            InputScheme      = $LoopLink.Scheme
            Item             = $null
            SharingMetadata  = $null
            Permissions      = @()
            Versions         = @()
            Coverage         = @($coverage)
            AccessFindings   = @($accessFindings)
            RequiredScopes   = @($requiredScopes)
        }
    }

    $coverage.Add([pscustomobject] [ordered] @{
        Surface = 'LinkResolution'
        Status  = 'Covered'
        Detail  = 'The Shares API resolved the URL with redeemSharingLinkIfNecessary; access is guaranteed only for the duration of this request.'
    })
    $coverage.Add([pscustomobject] [ordered] @{
        Surface = 'DriveItemMetadata'
        Status  = 'Covered'
        Detail  = 'Caller-visible Microsoft Graph driveItem metadata is included; temporary download URLs are deliberately excluded.'
    })
    $coverage.Add([pscustomobject] [ordered] @{
        Surface = 'LoopSemanticContent'
        Status  = 'NotAvailable'
        Detail  = 'Microsoft Graph v1.0 does not expose Loop page/component structure or semantic content through the Shares API.'
    })

    $sharingMetadata = $null
    try {
        $sharedDriveItem = Invoke-MgGraphRequest -Method GET -Uri "/v1.0/shares/$shareId" -Headers $shareHeaders -ErrorAction Stop
        $owner = ConvertTo-IdentitySummary -IdentitySet (Get-PropertyValue -InputObject $sharedDriveItem -Name 'owner')
        $sharingPermission = Get-PropertyValue -InputObject $sharedDriveItem -Name 'permission'
        $sharingMetadata = [pscustomobject] [ordered] @{
            Name       = Get-PropertyValue -InputObject $sharedDriveItem -Name 'name'
            Owner      = $owner
            Permission = if ($null -eq $sharingPermission) { $null } else { ConvertTo-PermissionSummary -Permission $sharingPermission }
        }
        $coverage.Add([pscustomobject] [ordered] @{
            Surface = 'SharingMetadata'
            Status  = 'Covered'
            Detail  = 'Caller-visible sharedDriveItem owner and permission metadata are included without returning the sharing URL or share token.'
        })
    }
    catch {
        $failure = Get-SafeGraphFailure -ErrorRecord $_
        $accessFindings.Add([pscustomobject] [ordered] @{
            Operation = 'ReadSharedDriveItem'
            Status    = 'Partial'
            Failure   = $failure
        })
        $coverage.Add([pscustomobject] [ordered] @{
            Surface = 'SharingMetadata'
            Status  = 'Unknown'
            Detail  = 'The item resolved, but the sharedDriveItem metadata request did not succeed.'
        })
    }

    $itemSummary = ConvertTo-DriveItemSummary -DriveItem $driveItem
    $driveId = [string] (Get-PropertyValue -InputObject $itemSummary -Name 'DriveId')
    $itemId = [string] (Get-PropertyValue -InputObject $itemSummary -Name 'Id')
    $permissions = @()
    $versions = @()

    if ([string]::IsNullOrWhiteSpace($driveId) -or [string]::IsNullOrWhiteSpace($itemId)) {
        $coverage.Add([pscustomobject] [ordered] @{
            Surface = 'Permissions'
            Status  = 'NotAvailable'
            Detail  = 'The resolved item did not expose both a drive ID and item ID required for the documented permissions endpoint.'
        })
        $coverage.Add([pscustomobject] [ordered] @{
            Surface = 'VersionHistory'
            Status  = 'NotAvailable'
            Detail  = 'The resolved item did not expose both a drive ID and item ID required for the documented versions endpoint.'
        })
    }
    else {
        $encodedDriveId = [Uri]::EscapeDataString($driveId)
        $encodedItemId = [Uri]::EscapeDataString($itemId)

        try {
            $permissionUri = "/v1.0/drives/$encodedDriveId/items/$encodedItemId/permissions"
            $permissions = @(
                Invoke-GraphCollectionGet -Uri $permissionUri |
                    ForEach-Object { ConvertTo-PermissionSummary -Permission $_ }
            )
            $coverage.Add([pscustomobject] [ordered] @{
                Surface = 'Permissions'
                Status  = 'Covered'
                Detail  = 'Permissions visible to the caller are included. Microsoft Graph can return limited permission information to callers who are not item owners.'
            })
        }
        catch {
            $failure = Get-SafeGraphFailure -ErrorRecord $_
            $accessFindings.Add([pscustomobject] [ordered] @{
                Operation = 'ListItemPermissions'
                Status    = 'Inaccessible'
                Failure   = $failure
            })
            $coverage.Add([pscustomobject] [ordered] @{
                Surface = 'Permissions'
                Status  = 'Inaccessible'
                Detail  = 'The signed-in user could resolve the item but could not list its permissions.'
            })
        }

        try {
            $versionUri = "/v1.0/drives/$encodedDriveId/items/$encodedItemId/versions"
            $versions = @(
                Invoke-GraphCollectionGet -Uri $versionUri |
                    ForEach-Object {
                        $publication = Get-PropertyValue -InputObject $_ -Name 'publication'
                        [pscustomobject] [ordered] @{
                            Id                   = Get-PropertyValue -InputObject $_ -Name 'id'
                            LastModifiedDateTime = Get-PropertyValue -InputObject $_ -Name 'lastModifiedDateTime'
                            LastModifiedBy       = ConvertTo-IdentitySummary -IdentitySet (Get-PropertyValue -InputObject $_ -Name 'lastModifiedBy')
                            SizeBytes            = Get-PropertyValue -InputObject $_ -Name 'size'
                            PublicationLevel     = Get-PropertyValue -InputObject $publication -Name 'level'
                            PublicationVersionId = Get-PropertyValue -InputObject $publication -Name 'versionId'
                        }
                    }
            )
            $coverage.Add([pscustomobject] [ordered] @{
                Surface = 'VersionHistory'
                Status  = 'Covered'
                Detail  = 'Every version page returned by Microsoft Graph was retrieved.'
            })
        }
        catch {
            $failure = Get-SafeGraphFailure -ErrorRecord $_
            $accessFindings.Add([pscustomobject] [ordered] @{
                Operation = 'ListItemVersions'
                Status    = 'Inaccessible'
                Failure   = $failure
            })
            $coverage.Add([pscustomobject] [ordered] @{
                Surface = 'VersionHistory'
                Status  = 'Inaccessible'
                Detail  = 'The signed-in user could resolve the item but could not list its versions.'
            })
        }
    }

    [pscustomobject] [ordered] @{
        PSTypeName       = 'Tenant.LoopLinkDetails'
        GeneratedAtUtc   = [datetime]::UtcNow
        TenantId         = $TenantId.Guid
        Environment      = $Environment
        InputHost        = $LoopLink.DnsSafeHost
        InputScheme      = $LoopLink.Scheme
        Item             = $itemSummary
        SharingMetadata  = $sharingMetadata
        Permissions      = @($permissions)
        Versions         = @($versions)
        Coverage         = @($coverage)
        AccessFindings   = @($accessFindings)
        RequiredScopes   = @($requiredScopes)
    }
}
catch {
    $message = "Loop link inspection failed for host '$($LoopLink.DnsSafeHost)': $($_.Exception.Message)"
    throw [InvalidOperationException]::new($message, $_.Exception)
}
finally {
    if ($connected) {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
}
