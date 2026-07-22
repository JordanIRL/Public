#requires -Version 7.0
#requires -Modules Microsoft.Graph.Authentication

<#
.SYNOPSIS
    Performs a read-only OneDrive health assessment for a Microsoft 365 user.

.DESCRIPTION
    Uses delegated Microsoft Graph v1.0 requests to examine the user's account,
    OneDrive-related license provisioning, Microsoft 365 usage and activity
    reports, report freshness, live drive/quota metadata, storage consumption,
    and relevant tenant service health.

    The script deliberately does not request the singular /users/{id}/drive because
    that read can provision a licensed user's OneDrive. It uses the documented plural
    /users/{id}/drives collection, which has no documented auto-provisioning behavior.
    Microsoft Graph v1.0 also has no
    documented API for OneDrive Sync Health device telemetry, Known Folder Move
    state, sync-client errors, or a OneDrive for Business recycle-bin inventory.
    These limitations are returned explicitly in Coverage.

.PARAMETER TenantId
    Microsoft Entra tenant GUID to authenticate against.

.PARAMETER UserPrincipalName
    User principal name or primary mail address to assess.

.PARAMETER ReportPeriod
    Supported Microsoft 365 report period. D7 is the default.

.PARAMETER MaxReportAgeDays
    Maximum acceptable age of the report refresh date before a warning is returned.

.PARAMETER Environment
    Microsoft Graph cloud environment. Usage reports and report settings are
    queried only in Global because the documented APIs are unavailable in
    national clouds.

.PARAMETER ClientId
    Optional application ID for an approved public-client app registration.

.PARAMETER ExpectedAccount
    Optional user principal name that must match the signed-in administrator.

.PARAMETER UseDeviceCode
    Use delegated device-code authentication instead of interactive browser authentication.

.OUTPUTS
    A Tenant.OneDriveHealthResult object containing OverallStatus, Checks,
    Evidence, Coverage, and AccessFindings properties.

.EXAMPLE
    ./Test-UserOneDriveHealth.ps1 -TenantId '00000000-0000-0000-0000-000000000000' -UserPrincipalName 'alex@contoso.com'

.EXAMPLE
    ./Test-UserOneDriveHealth.ps1 -TenantId '00000000-0000-0000-0000-000000000000' -UserPrincipalName 'alex@contoso.com' -ReportPeriod D30 -MaxReportAgeDays 4 -UseDeviceCode

.NOTES
    Required delegated Microsoft Graph scopes in Global:
      User.Read.All
      Files.Read.All
      LicenseAssignment.Read.All
      Reports.Read.All
      ReportSettings.Read.All
      ServiceHealth.Read.All

    Reports.Read.All and ReportSettings.Read.All are omitted outside Global.
    Practical roles: Directory Readers for license details and Reports Reader for
    per-user usage metrics. Delegated service communications also require the
    signed-in user to hold at least one Microsoft Entra administrator role.
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
    [ValidateSet('D7', 'D30', 'D90', 'D180')]
    [string] $ReportPeriod = 'D7',

    [Parameter()]
    [ValidateRange(1, 30)]
    [int] $MaxReportAgeDays = 3,

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

function Get-GraphCsvReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Uri,

        [Parameter(Mandatory)]
        [string] $IdentityColumn,

        [Parameter(Mandatory)]
        [string] $IdentityValue
    )

    $temporaryPath = [IO.Path]::Combine(
        [IO.Path]::GetTempPath(),
        "m365-report-$([guid]::NewGuid().ToString('N')).csv"
    )

    try {
        $requestParameters = @{
            Method         = 'GET'
            Uri            = $Uri
            OutputFilePath = $temporaryPath
            ErrorAction    = 'Stop'
        }
        Invoke-MgGraphRequest @requestParameters | Out-Null
        if (-not [IO.File]::Exists($temporaryPath)) {
            throw 'Microsoft Graph did not create the expected report download file.'
        }
        Import-Csv -LiteralPath $temporaryPath |
            Where-Object {
                Test-StringEqual -Left (Get-PropertyValue -InputObject $_ -Name $IdentityColumn) -Right $IdentityValue
            }
    }
    finally {
        if ([IO.File]::Exists($temporaryPath)) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function ConvertTo-HealthCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [ValidateSet('Pass', 'Warning', 'Fail', 'Unknown', 'Information')]
        [string] $Status,

        [Parameter(Mandatory)]
        [string] $Detail,

        [Parameter()]
        [AllowNull()]
        [object] $ObservedValue,

        [Parameter()]
        [AllowNull()]
        [object] $ExpectedValue
    )

    [pscustomobject] [ordered] @{
        Name          = $Name
        Status        = $Status
        Detail        = $Detail
        ObservedValue = $ObservedValue
        ExpectedValue = $ExpectedValue
    }
}

function ConvertTo-NullableInt64 {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string] $Value)) {
        return $null
    }

    $parsedValue = 0L
    $parsed = [long]::TryParse(
        [string] $Value,
        [Globalization.NumberStyles]::Integer,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref] $parsedValue
    )
    if ($parsed) {
        return $parsedValue
    }

    return $null
}

function ConvertTo-NullableDateTimeOffset {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string] $Value)) {
        return $null
    }

    $parsedValue = [datetimeoffset]::MinValue
    $parsed = [datetimeoffset]::TryParse(
        [string] $Value,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal,
        [ref] $parsedValue
    )
    if ($parsed) {
        return $parsedValue.ToUniversalTime()
    }

    return $null
}

function Get-OverallHealthStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]] $Checks
    )

    $statuses = @($Checks | ForEach-Object { Get-PropertyValue -InputObject $_ -Name 'Status' })
    if ('Fail' -in $statuses) {
        return 'Fail'
    }
    if ('Warning' -in $statuses) {
        return 'Warning'
    }
    if ('Unknown' -in $statuses) {
        return 'Unknown'
    }
    return 'Pass'
}

$requiredScopes = @(
    'User.Read.All'
    'Files.Read.All'
    'LicenseAssignment.Read.All'
    'ServiceHealth.Read.All'
)
if ($Environment -eq 'Global') {
    $requiredScopes += @(
        'Reports.Read.All'
        'ReportSettings.Read.All'
    )
}

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
        throw "'$normalizedUserPrincipalName' matched $($matchingUsers.Count) Microsoft Entra users; refusing an ambiguous OneDrive assessment."
    }
    $user = $matchingUsers[0]
    $userId = [string] (Get-PropertyValue -InputObject $user -Name 'id')
    if ([string]::IsNullOrWhiteSpace($userId)) {
        throw "Microsoft Graph returned no object ID for '$normalizedUserPrincipalName'."
    }
    $resolvedUserPrincipalName = [string] (Get-PropertyValue -InputObject $user -Name 'userPrincipalName')
    if ([string]::IsNullOrWhiteSpace($resolvedUserPrincipalName)) {
        throw "Microsoft Graph returned no userPrincipalName for '$normalizedUserPrincipalName'."
    }

    $checks = [Collections.Generic.List[object]]::new()
    $coverage = [Collections.Generic.List[object]]::new()
    $accessFindings = [Collections.Generic.List[object]]::new()
    $licenseEvidence = [Collections.Generic.List[object]]::new()
    $driveEvidence = [Collections.Generic.List[object]]::new()
    $usageEvidence = $null
    $activityEvidence = $null
    $serviceEvidence = [Collections.Generic.List[object]]::new()

    $accountEnabled = Get-PropertyValue -InputObject $user -Name 'accountEnabled'
    $checks.Add((ConvertTo-HealthCheck -Name 'AccountEnabled' -Status $(if ($accountEnabled -eq $true) { 'Pass' } else { 'Fail' }) -Detail $(if ($accountEnabled -eq $true) { 'The Microsoft Entra user account is enabled.' } else { 'The Microsoft Entra user account is disabled.' }) -ObservedValue $accountEnabled -ExpectedValue $true))
    $coverage.Add([pscustomobject] [ordered] @{
        Surface = 'UserIdentity'
        Status  = 'Covered'
        Detail  = 'The target user was resolved through Microsoft Graph v1.0.'
    })

    $encodedUserId = [Uri]::EscapeDataString($userId)
    try {
        $licenseUri = "/v1.0/users/$encodedUserId/licenseDetails?`$select=id,skuId,skuPartNumber,servicePlans"
        $licenseDetails = @(Invoke-GraphCollectionGet -Uri $licenseUri)
        foreach ($license in $licenseDetails) {
            foreach ($plan in @((Get-PropertyValue -InputObject $license -Name 'servicePlans'))) {
                $planName = [string] (Get-PropertyValue -InputObject $plan -Name 'servicePlanName')
                if (
                    $planName -notmatch '(?i)^(SHAREPOINT|ONEDRIVE)' -or
                    $planName -match '(?i)^SHAREPOINTWAC'
                ) {
                    continue
                }
                $licenseEvidence.Add([pscustomobject] [ordered] @{
                    SkuId              = Get-PropertyValue -InputObject $license -Name 'skuId'
                    SkuPartNumber      = Get-PropertyValue -InputObject $license -Name 'skuPartNumber'
                    ServicePlanId      = Get-PropertyValue -InputObject $plan -Name 'servicePlanId'
                    ServicePlanName    = $planName
                    ProvisioningStatus = Get-PropertyValue -InputObject $plan -Name 'provisioningStatus'
                    AppliesTo          = Get-PropertyValue -InputObject $plan -Name 'appliesTo'
                })
            }
        }

        $successfulPlans = @($licenseEvidence | Where-Object { (Get-PropertyValue -InputObject $_ -Name 'ProvisioningStatus') -eq 'Success' })
        $problemPlans = @($licenseEvidence | Where-Object {
            (Get-PropertyValue -InputObject $_ -Name 'ProvisioningStatus') -notin @('Success', 'Disabled')
        })

        if ($licenseEvidence.Count -eq 0) {
            $checks.Add((ConvertTo-HealthCheck -Name 'OneDriveLicense' -Status 'Fail' -Detail 'No SharePoint- or OneDrive-named service plan was returned for the user.' -ObservedValue 0 -ExpectedValue 'At least one successful plan'))
        }
        elseif ($successfulPlans.Count -eq 0) {
            $checks.Add((ConvertTo-HealthCheck -Name 'OneDriveLicense' -Status 'Fail' -Detail 'OneDrive-related service plans were returned, but none has provisioningStatus Success.' -ObservedValue @($licenseEvidence) -ExpectedValue 'At least one successful plan'))
        }
        elseif ($problemPlans.Count -gt 0) {
            $checks.Add((ConvertTo-HealthCheck -Name 'OneDriveLicense' -Status 'Warning' -Detail 'At least one OneDrive-related plan is successful, but another relevant plan is pending or in an unexpected state.' -ObservedValue @($licenseEvidence) -ExpectedValue 'Relevant plans are Success or intentionally Disabled'))
        }
        else {
            $checks.Add((ConvertTo-HealthCheck -Name 'OneDriveLicense' -Status 'Pass' -Detail 'At least one OneDrive-related service plan is successfully provisioned.' -ObservedValue @($licenseEvidence) -ExpectedValue 'At least one successful plan'))
        }
        $coverage.Add([pscustomobject] [ordered] @{
            Surface = 'LicenseProvisioning'
            Status  = 'Covered'
            Detail  = 'Directly and group-assigned license details were evaluated.'
        })
    }
    catch {
        $failure = Get-SafeGraphFailure -ErrorRecord $_
        $checks.Add((ConvertTo-HealthCheck -Name 'OneDriveLicense' -Status 'Unknown' -Detail 'License details could not be read. Verify LicenseAssignment.Read.All and a supported directory role.' -ObservedValue $null -ExpectedValue 'Readable license details'))
        $coverage.Add([pscustomobject] [ordered] @{
            Surface = 'LicenseProvisioning'
            Status  = 'Inaccessible'
            Detail  = 'The licenseDetails request did not succeed.'
        })
        $accessFindings.Add([pscustomobject] [ordered] @{
            Operation = 'ReadLicenseDetails'
            Status    = 'Inaccessible'
            Failure   = $failure
        })
    }

    try {
        $driveSelect = 'id,name,driveType,webUrl,createdDateTime,lastModifiedDateTime,owner,quota,system'
        $drives = @(
            Invoke-GraphCollectionGet -Uri "/v1.0/users/$encodedUserId/drives?`$select=$driveSelect"
        )
        foreach ($drive in $drives) {
            $quota = Get-PropertyValue -InputObject $drive -Name 'quota'
            $quotaTotal = ConvertTo-NullableInt64 -Value (Get-PropertyValue -InputObject $quota -Name 'total')
            $quotaUsed = ConvertTo-NullableInt64 -Value (Get-PropertyValue -InputObject $quota -Name 'used')
            $quotaRemaining = ConvertTo-NullableInt64 -Value (Get-PropertyValue -InputObject $quota -Name 'remaining')
            $remainingPercent = $null
            if ($null -ne $quotaTotal -and $quotaTotal -gt 0 -and $null -ne $quotaRemaining) {
                $remainingPercent = [math]::Round(($quotaRemaining / $quotaTotal) * 100, 2)
            }

            $driveEvidence.Add([pscustomobject] [ordered] @{
                Id                      = Get-PropertyValue -InputObject $drive -Name 'id'
                Name                    = Get-PropertyValue -InputObject $drive -Name 'name'
                DriveType               = Get-PropertyValue -InputObject $drive -Name 'driveType'
                WebUrl                  = Get-PropertyValue -InputObject $drive -Name 'webUrl'
                CreatedDateTime         = Get-PropertyValue -InputObject $drive -Name 'createdDateTime'
                LastModifiedDateTime    = Get-PropertyValue -InputObject $drive -Name 'lastModifiedDateTime'
                Owner                   = Get-PropertyValue -InputObject $drive -Name 'owner'
                IsSystemDrive           = $null -ne (Get-PropertyValue -InputObject $drive -Name 'system')
                QuotaState              = Get-PropertyValue -InputObject $quota -Name 'state'
                QuotaTotalBytes         = $quotaTotal
                QuotaUsedBytes          = $quotaUsed
                QuotaRemainingBytes     = $quotaRemaining
                QuotaDeletedBytes       = ConvertTo-NullableInt64 -Value (Get-PropertyValue -InputObject $quota -Name 'deleted')
                QuotaRemainingPercent   = $remainingPercent
            })
        }

        $businessDrives = @($driveEvidence | Where-Object {
            (Get-PropertyValue -InputObject $_ -Name 'DriveType') -eq 'business' -and
            (Get-PropertyValue -InputObject $_ -Name 'IsSystemDrive') -ne $true
        })
        if ($businessDrives.Count -eq 0) {
            $checks.Add((ConvertTo-HealthCheck -Name 'LiveOneDrive' -Status 'Warning' -Detail 'The non-provisioning drives collection returned no non-system business drive for the user.' -ObservedValue 0 -ExpectedValue 'At least one business drive'))
        }
        else {
            $checks.Add((ConvertTo-HealthCheck -Name 'LiveOneDrive' -Status 'Pass' -Detail 'The non-provisioning drives collection returned a live non-system business drive.' -ObservedValue $businessDrives.Count -ExpectedValue 'At least one business drive'))

            $quotaStates = @($businessDrives | ForEach-Object { [string] (Get-PropertyValue -InputObject $_ -Name 'QuotaState') })
            if (@($quotaStates | Where-Object { $_ -ieq 'exceeded' }).Count -gt 0) {
                $checks.Add((ConvertTo-HealthCheck -Name 'LiveDriveQuotaState' -Status 'Fail' -Detail 'A live OneDrive reports quota state exceeded.' -ObservedValue $quotaStates -ExpectedValue 'normal'))
            }
            elseif (@($quotaStates | Where-Object { $_ -in @('nearing', 'critical') }).Count -gt 0) {
                $checks.Add((ConvertTo-HealthCheck -Name 'LiveDriveQuotaState' -Status 'Warning' -Detail 'A live OneDrive reports a nearing or critical quota state.' -ObservedValue $quotaStates -ExpectedValue 'normal'))
            }
            elseif (@($quotaStates | Where-Object { $_ -ieq 'normal' }).Count -eq $businessDrives.Count) {
                $checks.Add((ConvertTo-HealthCheck -Name 'LiveDriveQuotaState' -Status 'Pass' -Detail 'Every returned live OneDrive reports quota state normal.' -ObservedValue $quotaStates -ExpectedValue 'normal'))
            }
            else {
                $checks.Add((ConvertTo-HealthCheck -Name 'LiveDriveQuotaState' -Status 'Unknown' -Detail 'At least one live OneDrive did not return a recognized quota state.' -ObservedValue $quotaStates -ExpectedValue 'normal'))
            }

            $remainingPercentages = @($businessDrives | ForEach-Object {
                Get-PropertyValue -InputObject $_ -Name 'QuotaRemainingPercent'
            } | Where-Object { $null -ne $_ })
            if ($remainingPercentages.Count -eq 0) {
                $checks.Add((ConvertTo-HealthCheck -Name 'LiveDriveCapacity' -Status 'Unknown' -Detail 'The live drive response did not include usable quota totals and remaining bytes.' -ObservedValue $null -ExpectedValue 'More than 10 percent remaining'))
            }
            else {
                $minimumRemainingPercent = [double] ($remainingPercentages | Measure-Object -Minimum).Minimum
                if ($minimumRemainingPercent -le 1) {
                    $checks.Add((ConvertTo-HealthCheck -Name 'LiveDriveCapacity' -Status 'Fail' -Detail 'A live OneDrive has 1 percent or less quota remaining.' -ObservedValue $minimumRemainingPercent -ExpectedValue 'More than 10 percent remaining'))
                }
                elseif ($minimumRemainingPercent -le 10) {
                    $checks.Add((ConvertTo-HealthCheck -Name 'LiveDriveCapacity' -Status 'Warning' -Detail 'A live OneDrive has 10 percent or less quota remaining.' -ObservedValue $minimumRemainingPercent -ExpectedValue 'More than 10 percent remaining'))
                }
                else {
                    $checks.Add((ConvertTo-HealthCheck -Name 'LiveDriveCapacity' -Status 'Pass' -Detail 'Every returned live OneDrive has more than 10 percent quota remaining.' -ObservedValue $minimumRemainingPercent -ExpectedValue 'More than 10 percent remaining'))
                }
            }
        }
        $coverage.Add([pscustomobject] [ordered] @{
            Surface = 'LiveDriveAndQuota'
            Status  = 'Covered'
            Detail  = 'The plural /users/{id}/drives collection was queried without calling the auto-provisioning singular drive endpoint.'
        })
    }
    catch {
        $failure = Get-SafeGraphFailure -ErrorRecord $_
        $checks.Add((ConvertTo-HealthCheck -Name 'LiveOneDrive' -Status 'Unknown' -Detail 'Live drive and quota metadata could not be read. Delegated Files.Read.All does not override the signed-in user''s existing file access.' -ObservedValue $null -ExpectedValue 'Readable drive metadata'))
        $coverage.Add([pscustomobject] [ordered] @{
            Surface = 'LiveDriveAndQuota'
            Status  = 'Inaccessible'
            Detail  = 'The non-provisioning drives collection request did not succeed.'
        })
        $accessFindings.Add([pscustomobject] [ordered] @{
            Operation = 'ReadUserDrives'
            Status    = 'Inaccessible'
            Failure   = $failure
        })
    }

    $reportsCanBeMatched = $true
    $reportIdentityMappingState = 'Unknown'
    if ($Environment -ne 'Global') {
        $reportsCanBeMatched = $false
        $reportIdentityMappingState = 'NotAvailable'
        $coverage.Add([pscustomobject] [ordered] @{
            Surface = 'OneDriveUsageReport'
            Status  = 'NotAvailable'
            Detail  = 'The documented OneDrive usage report API is available only in the Microsoft Graph Global service.'
        })
        $coverage.Add([pscustomobject] [ordered] @{
            Surface = 'OneDriveActivityReport'
            Status  = 'NotAvailable'
            Detail  = 'The documented OneDrive activity report API is available only in the Microsoft Graph Global service.'
        })
        $checks.Add((ConvertTo-HealthCheck -Name 'UsageReport' -Status 'Unknown' -Detail 'Per-user usage and capacity evidence is unavailable in the selected Graph cloud.' -ObservedValue $Environment -ExpectedValue 'Global'))
    }
    else {
        try {
            $reportSettings = Invoke-MgGraphRequest -Method GET -Uri '/v1.0/admin/reportSettings' -ErrorAction Stop
            $displayConcealedNames = Get-PropertyValue -InputObject $reportSettings -Name 'displayConcealedNames'
            if ($displayConcealedNames -eq $true) {
                $reportsCanBeMatched = $false
                $reportIdentityMappingState = 'Concealed'
                $coverage.Add([pscustomobject] [ordered] @{
                    Surface = 'ReportIdentityMapping'
                    Status  = 'BlockedByTenantSetting'
                    Detail  = 'The tenant conceals names in Microsoft 365 reports, so report rows cannot be reliably matched to the supplied user. The script does not change this tenant-wide setting.'
                })
                $checks.Add((ConvertTo-HealthCheck -Name 'UsageReportIdentity' -Status 'Unknown' -Detail 'Report identities are concealed by tenant policy.' -ObservedValue $true -ExpectedValue $false))
            }
            elseif ($displayConcealedNames -eq $false) {
                $reportIdentityMappingState = 'Visible'
                $coverage.Add([pscustomobject] [ordered] @{
                    Surface = 'ReportIdentityMapping'
                    Status  = 'Covered'
                    Detail  = 'The tenant report setting allows the target UPN to be matched to report rows.'
                })
            }
            else {
                $coverage.Add([pscustomobject] [ordered] @{
                    Surface = 'ReportIdentityMapping'
                    Status  = 'Unknown'
                    Detail  = 'The report settings response did not contain a usable displayConcealedNames value. A matching UPN can be used if present, but absence cannot be interpreted.'
                })
            }
        }
        catch {
            $failure = Get-SafeGraphFailure -ErrorRecord $_
            $coverage.Add([pscustomobject] [ordered] @{
                Surface = 'ReportIdentityMapping'
                Status  = 'Unknown'
                Detail  = 'Report settings could not be read. The reports will still be queried and matched if the target UPN is present.'
            })
            $accessFindings.Add([pscustomobject] [ordered] @{
                Operation = 'ReadReportSettings'
                Status    = 'Inaccessible'
                Failure   = $failure
            })
        }

        if ($reportsCanBeMatched) {
            try {
                $matchingUsageRows = @(
                    Get-GraphCsvReport -Uri "/v1.0/reports/getOneDriveUsageAccountDetail(period='$ReportPeriod')" `
                        -IdentityColumn 'Owner Principal Name' -IdentityValue $resolvedUserPrincipalName
                )
                $usageRow = @(
                    $matchingUsageRows |
                        Sort-Object @{ Expression = {
                            if ((Get-PropertyValue -InputObject $_ -Name 'Is Deleted') -eq 'False') { 0 } else { 1 }
                        } }
                ) | Select-Object -First 1

                if ($null -eq $usageRow) {
                    $usageNoMatchStatus = if ($reportIdentityMappingState -eq 'Visible') { 'Warning' } else { 'Unknown' }
                    $usageNoMatchDetail = if ($reportIdentityMappingState -eq 'Visible') {
                        'No matching OneDrive usage row was returned. The personal site may be unprovisioned, newly provisioned, unlicensed, deleted, or outside the report snapshot.'
                    }
                    else {
                        'No matching OneDrive usage row was returned, but the report identity-concealment setting is unknown. The absence cannot be attributed to OneDrive state.'
                    }
                    $checks.Add((ConvertTo-HealthCheck -Name 'UsageReport' -Status $usageNoMatchStatus -Detail $usageNoMatchDetail -ObservedValue 0 -ExpectedValue 1))
                    $coverage.Add([pscustomobject] [ordered] @{
                        Surface = 'OneDriveUsageReport'
                        Status  = if ($reportIdentityMappingState -eq 'Visible') { 'NoMatchingRow' } else { 'IdentityMappingUnknown' }
                        Detail  = if ($reportIdentityMappingState -eq 'Visible') {
                            'The report was downloaded successfully, but no row matched the target UPN.'
                        }
                        else {
                            'The report was downloaded successfully, but no row matched and report identity visibility could not be confirmed.'
                        }
                    })
                }
                else {
                    $reportRefreshDate = ConvertTo-NullableDateTimeOffset -Value (Get-PropertyValue -InputObject $usageRow -Name 'Report Refresh Date')
                    $storageUsedBytes = ConvertTo-NullableInt64 -Value (Get-PropertyValue -InputObject $usageRow -Name 'Storage Used (Byte)')
                    $storageAllocatedBytes = ConvertTo-NullableInt64 -Value (Get-PropertyValue -InputObject $usageRow -Name 'Storage Allocated (Byte)')
                    $isDeleted = (Get-PropertyValue -InputObject $usageRow -Name 'Is Deleted') -eq 'True'
                    $remainingPercent = $null
                    if ($null -ne $storageUsedBytes -and $null -ne $storageAllocatedBytes -and $storageAllocatedBytes -gt 0) {
                        $remainingPercent = [math]::Round((($storageAllocatedBytes - $storageUsedBytes) / $storageAllocatedBytes) * 100, 2)
                    }

                    $usageEvidence = [pscustomobject] [ordered] @{
                        ReportRefreshDate     = $reportRefreshDate
                        SiteUrl               = Get-PropertyValue -InputObject $usageRow -Name 'Site URL'
                        OwnerDisplayName      = Get-PropertyValue -InputObject $usageRow -Name 'Owner Display Name'
                        OwnerPrincipalName    = Get-PropertyValue -InputObject $usageRow -Name 'Owner Principal Name'
                        IsDeleted             = $isDeleted
                        LastActivityDate      = ConvertTo-NullableDateTimeOffset -Value (Get-PropertyValue -InputObject $usageRow -Name 'Last Activity Date')
                        FileCount             = ConvertTo-NullableInt64 -Value (Get-PropertyValue -InputObject $usageRow -Name 'File Count')
                        ActiveFileCount       = ConvertTo-NullableInt64 -Value (Get-PropertyValue -InputObject $usageRow -Name 'Active File Count')
                        StorageUsedBytes      = $storageUsedBytes
                        StorageAllocatedBytes = $storageAllocatedBytes
                        StorageRemainingPercent = $remainingPercent
                        ReportPeriod          = Get-PropertyValue -InputObject $usageRow -Name 'Report Period'
                    }

                    if ($isDeleted) {
                        $checks.Add((ConvertTo-HealthCheck -Name 'PersonalSiteDeleted' -Status 'Fail' -Detail 'The OneDrive usage report marks the personal site as deleted.' -ObservedValue $true -ExpectedValue $false))
                    }
                    else {
                        $checks.Add((ConvertTo-HealthCheck -Name 'PersonalSiteDeleted' -Status 'Pass' -Detail 'The OneDrive usage report does not mark the personal site as deleted.' -ObservedValue $false -ExpectedValue $false))
                    }

                    if ($null -eq $remainingPercent) {
                        $checks.Add((ConvertTo-HealthCheck -Name 'StorageCapacity' -Status 'Unknown' -Detail 'The report did not provide usable storage-used and storage-allocated values.' -ObservedValue $null -ExpectedValue 'More than 10 percent remaining'))
                    }
                    elseif ($storageUsedBytes -ge $storageAllocatedBytes -or $remainingPercent -le 1) {
                        $checks.Add((ConvertTo-HealthCheck -Name 'StorageCapacity' -Status 'Fail' -Detail 'OneDrive storage is exhausted or has 1 percent or less remaining.' -ObservedValue $remainingPercent -ExpectedValue 'More than 10 percent remaining'))
                    }
                    elseif ($remainingPercent -le 10) {
                        $checks.Add((ConvertTo-HealthCheck -Name 'StorageCapacity' -Status 'Warning' -Detail 'OneDrive storage has 10 percent or less remaining.' -ObservedValue $remainingPercent -ExpectedValue 'More than 10 percent remaining'))
                    }
                    else {
                        $checks.Add((ConvertTo-HealthCheck -Name 'StorageCapacity' -Status 'Pass' -Detail 'OneDrive storage has more than 10 percent remaining.' -ObservedValue $remainingPercent -ExpectedValue 'More than 10 percent remaining'))
                    }

                    if ($null -eq $reportRefreshDate) {
                        $checks.Add((ConvertTo-HealthCheck -Name 'UsageReportFreshness' -Status 'Unknown' -Detail 'The report refresh date could not be parsed.' -ObservedValue $null -ExpectedValue "No more than $MaxReportAgeDays days old"))
                    }
                    else {
                        $reportAgeDays = ([datetimeoffset]::UtcNow - $reportRefreshDate).TotalDays
                        if ($reportAgeDays -gt $MaxReportAgeDays) {
                            $checks.Add((ConvertTo-HealthCheck -Name 'UsageReportFreshness' -Status 'Warning' -Detail 'The usage report snapshot is older than the configured maximum age.' -ObservedValue ([math]::Round($reportAgeDays, 2)) -ExpectedValue "At most $MaxReportAgeDays days"))
                        }
                        else {
                            $checks.Add((ConvertTo-HealthCheck -Name 'UsageReportFreshness' -Status 'Pass' -Detail 'The usage report snapshot is within the configured maximum age.' -ObservedValue ([math]::Round($reportAgeDays, 2)) -ExpectedValue "At most $MaxReportAgeDays days"))
                        }
                    }

                    $coverage.Add([pscustomobject] [ordered] @{
                        Surface = 'OneDriveUsageReport'
                        Status  = 'Covered'
                        Detail  = 'The matching account row was evaluated for deletion, capacity, and report freshness.'
                    })
                }
            }
            catch {
                $failure = Get-SafeGraphFailure -ErrorRecord $_
                $checks.Add((ConvertTo-HealthCheck -Name 'UsageReport' -Status 'Unknown' -Detail 'The OneDrive usage report could not be downloaded or parsed.' -ObservedValue $null -ExpectedValue 'Readable report'))
                $coverage.Add([pscustomobject] [ordered] @{
                    Surface = 'OneDriveUsageReport'
                    Status  = 'Inaccessible'
                    Detail  = 'The usage report request did not succeed.'
                })
                $accessFindings.Add([pscustomobject] [ordered] @{
                    Operation = 'ReadOneDriveUsageReport'
                    Status    = 'Inaccessible'
                    Failure   = $failure
                })
            }

            try {
                $activityRow = @(
                    Get-GraphCsvReport -Uri "/v1.0/reports/getOneDriveActivityUserDetail(period='$ReportPeriod')" `
                        -IdentityColumn 'User Principal Name' -IdentityValue $resolvedUserPrincipalName
                ) | Select-Object -First 1

                if ($null -eq $activityRow) {
                    $coverage.Add([pscustomobject] [ordered] @{
                        Surface = 'OneDriveActivityReport'
                        Status  = if ($reportIdentityMappingState -eq 'Visible') { 'NoMatchingRow' } else { 'IdentityMappingUnknown' }
                        Detail  = if ($reportIdentityMappingState -eq 'Visible') {
                            'The activity report was downloaded successfully, but no row matched the target UPN.'
                        }
                        else {
                            'The activity report was downloaded successfully, but no row matched and report identity visibility could not be confirmed.'
                        }
                    })
                    $activityNoMatchStatus = if ($reportIdentityMappingState -eq 'Visible') { 'Information' } else { 'Unknown' }
                    $activityNoMatchDetail = if ($reportIdentityMappingState -eq 'Visible') {
                        'No matching activity row was returned. Lack of report activity is not proof of a sync problem.'
                    }
                    else {
                        'No matching activity row was returned, and report identity visibility could not be confirmed.'
                    }
                    $checks.Add((ConvertTo-HealthCheck -Name 'RecentActivity' -Status $activityNoMatchStatus -Detail $activityNoMatchDetail -ObservedValue 0 -ExpectedValue $null))
                }
                else {
                    $activityEvidence = [pscustomobject] [ordered] @{
                        ReportRefreshDate         = ConvertTo-NullableDateTimeOffset -Value (Get-PropertyValue -InputObject $activityRow -Name 'Report Refresh Date')
                        UserPrincipalName         = Get-PropertyValue -InputObject $activityRow -Name 'User Principal Name'
                        IsDeleted                 = (Get-PropertyValue -InputObject $activityRow -Name 'Is Deleted') -eq 'True'
                        DeletedDate               = ConvertTo-NullableDateTimeOffset -Value (Get-PropertyValue -InputObject $activityRow -Name 'Deleted Date')
                        LastActivityDate          = ConvertTo-NullableDateTimeOffset -Value (Get-PropertyValue -InputObject $activityRow -Name 'Last Activity Date')
                        ViewedOrEditedFileCount   = ConvertTo-NullableInt64 -Value (Get-PropertyValue -InputObject $activityRow -Name 'Viewed Or Edited File Count')
                        SyncedFileCount           = ConvertTo-NullableInt64 -Value (Get-PropertyValue -InputObject $activityRow -Name 'Synced File Count')
                        SharedInternallyFileCount = ConvertTo-NullableInt64 -Value (Get-PropertyValue -InputObject $activityRow -Name 'Shared Internally File Count')
                        SharedExternallyFileCount = ConvertTo-NullableInt64 -Value (Get-PropertyValue -InputObject $activityRow -Name 'Shared Externally File Count')
                        AssignedProducts          = Get-PropertyValue -InputObject $activityRow -Name 'Assigned Products'
                        ReportPeriod              = Get-PropertyValue -InputObject $activityRow -Name 'Report Period'
                    }
                    $coverage.Add([pscustomobject] [ordered] @{
                        Surface = 'OneDriveActivityReport'
                        Status  = 'Covered'
                        Detail  = 'The matching activity row is included as informational evidence; its synced-file count is not sync-client health telemetry.'
                    })
                    $checks.Add((ConvertTo-HealthCheck -Name 'RecentActivity' -Status 'Information' -Detail 'The most recent activity date and activity counts are included as context only.' -ObservedValue $activityEvidence.LastActivityDate -ExpectedValue $null))
                }
            }
            catch {
                $failure = Get-SafeGraphFailure -ErrorRecord $_
                $coverage.Add([pscustomobject] [ordered] @{
                    Surface = 'OneDriveActivityReport'
                    Status  = 'Inaccessible'
                    Detail  = 'The activity report request did not succeed.'
                })
                $accessFindings.Add([pscustomobject] [ordered] @{
                    Operation = 'ReadOneDriveActivityReport'
                    Status    = 'Inaccessible'
                    Failure   = $failure
                })
                $checks.Add((ConvertTo-HealthCheck -Name 'RecentActivity' -Status 'Information' -Detail 'The activity report was unavailable. Activity data is not required to determine sync-client health.' -ObservedValue $null -ExpectedValue $null))
            }
        }
    }

    try {
        $healthOverviews = @(Invoke-GraphCollectionGet -Uri '/v1.0/admin/serviceAnnouncement/healthOverviews')
        $serviceHealth = @($healthOverviews | Where-Object {
            [string] (Get-PropertyValue -InputObject $_ -Name 'service') -match '(?i)(OneDrive|SharePoint)'
        })

        $allIssues = @(Invoke-GraphCollectionGet -Uri '/v1.0/admin/serviceAnnouncement/issues')
        $activeIssues = @($allIssues | Where-Object {
            $issueText = @(
                Get-PropertyValue -InputObject $_ -Name 'service'
                Get-PropertyValue -InputObject $_ -Name 'feature'
                Get-PropertyValue -InputObject $_ -Name 'featureGroup'
                Get-PropertyValue -InputObject $_ -Name 'title'
                Get-PropertyValue -InputObject $_ -Name 'impactDescription'
            ) -join ' '
            $issueText -match '(?i)(OneDrive|SharePoint)' -and
            (Get-PropertyValue -InputObject $_ -Name 'isResolved') -ne $true
        })

        foreach ($service in $serviceHealth) {
            $serviceEvidence.Add([pscustomobject] [ordered] @{
                RecordType = 'HealthOverview'
                Id         = Get-PropertyValue -InputObject $service -Name 'id'
                Service    = Get-PropertyValue -InputObject $service -Name 'service'
                Status     = Get-PropertyValue -InputObject $service -Name 'status'
            })
        }
        foreach ($issue in $activeIssues) {
            $serviceEvidence.Add([pscustomobject] [ordered] @{
                RecordType          = 'ActiveIssue'
                Id                  = Get-PropertyValue -InputObject $issue -Name 'id'
                Service             = Get-PropertyValue -InputObject $issue -Name 'service'
                Feature             = Get-PropertyValue -InputObject $issue -Name 'feature'
                FeatureGroup        = Get-PropertyValue -InputObject $issue -Name 'featureGroup'
                Title               = Get-PropertyValue -InputObject $issue -Name 'title'
                Classification      = Get-PropertyValue -InputObject $issue -Name 'classification'
                Status              = Get-PropertyValue -InputObject $issue -Name 'status'
                StartDateTime       = Get-PropertyValue -InputObject $issue -Name 'startDateTime'
                LastModifiedDateTime = Get-PropertyValue -InputObject $issue -Name 'lastModifiedDateTime'
                ImpactDescription   = Get-PropertyValue -InputObject $issue -Name 'impactDescription'
            })
        }

        $nonOperationalServices = @($serviceHealth | Where-Object {
            (Get-PropertyValue -InputObject $_ -Name 'status') -ne 'serviceOperational'
        })
        if ($activeIssues.Count -gt 0 -or $nonOperationalServices.Count -gt 0) {
            $checks.Add((ConvertTo-HealthCheck -Name 'Microsoft365ServiceHealth' -Status 'Warning' -Detail 'Microsoft 365 reports a non-operational SharePoint/OneDrive status or an active related issue.' -ObservedValue $activeIssues.Count -ExpectedValue 0))
        }
        elseif ($serviceHealth.Count -eq 0) {
            $checks.Add((ConvertTo-HealthCheck -Name 'Microsoft365ServiceHealth' -Status 'Unknown' -Detail 'No SharePoint- or OneDrive-named service health overview was returned for this tenant.' -ObservedValue 0 -ExpectedValue 'At least one service'))
        }
        else {
            $checks.Add((ConvertTo-HealthCheck -Name 'Microsoft365ServiceHealth' -Status 'Pass' -Detail 'No active SharePoint/OneDrive issue or non-operational related service was returned.' -ObservedValue 0 -ExpectedValue 0))
        }
        $coverage.Add([pscustomobject] [ordered] @{
            Surface = 'TenantServiceHealth'
            Status  = 'Covered'
            Detail  = 'Every service-health and issue page returned by Microsoft Graph was examined.'
        })
    }
    catch {
        $failure = Get-SafeGraphFailure -ErrorRecord $_
        $checks.Add((ConvertTo-HealthCheck -Name 'Microsoft365ServiceHealth' -Status 'Unknown' -Detail 'Tenant service health could not be read. Verify ServiceHealth.Read.All and an eligible administrator role.' -ObservedValue $null -ExpectedValue 'Readable service health'))
        $coverage.Add([pscustomobject] [ordered] @{
            Surface = 'TenantServiceHealth'
            Status  = 'Inaccessible'
            Detail  = 'The service communications request did not succeed.'
        })
        $accessFindings.Add([pscustomobject] [ordered] @{
            Operation = 'ReadServiceHealth'
            Status    = 'Inaccessible'
            Failure   = $failure
        })
    }

    $coverage.Add([pscustomobject] [ordered] @{
        Surface = 'SyncClientTelemetry'
        Status  = 'NotAvailable'
        Detail  = 'Microsoft Graph v1.0 has no documented API for the OneDrive Sync Health device dashboard, sync errors, client version, or Known Folder Move state.'
    })
    $checks.Add((ConvertTo-HealthCheck -Name 'SyncClientTelemetry' -Status 'Unknown' -Detail 'Microsoft Graph cannot confirm device-level sync health, sync errors, client version, or Known Folder Move state.' -ObservedValue $null -ExpectedValue 'Healthy client telemetry'))
    $coverage.Add([pscustomobject] [ordered] @{
        Surface = 'OneDriveRecycleBin'
        Status  = 'NotAvailable'
        Detail  = 'Microsoft Graph v1.0 has no documented general recycle-bin enumeration API for OneDrive for Business.'
    })

    $checksArray = @($checks)
    [pscustomobject] [ordered] @{
        PSTypeName       = 'Tenant.OneDriveHealthResult'
        GeneratedAtUtc   = [datetime]::UtcNow
        OverallStatus    = Get-OverallHealthStatus -Checks $checksArray
        TenantId         = $TenantId.Guid
        Environment      = $Environment
        ReportPeriod     = $ReportPeriod
        User             = [pscustomobject] [ordered] @{
            Id                = $userId
            DisplayName       = Get-PropertyValue -InputObject $user -Name 'displayName'
            UserPrincipalName = Get-PropertyValue -InputObject $user -Name 'userPrincipalName'
            Mail              = Get-PropertyValue -InputObject $user -Name 'mail'
            AccountEnabled    = $accountEnabled
            UserType          = Get-PropertyValue -InputObject $user -Name 'userType'
        }
        Checks           = $checksArray
        Evidence         = [pscustomobject] [ordered] @{
            LicensePlans  = @($licenseEvidence)
            Drives         = @($driveEvidence)
            UsageReport   = $usageEvidence
            ActivityReport = $activityEvidence
            ServiceHealth = @($serviceEvidence)
        }
        Coverage         = @($coverage)
        AccessFindings   = @($accessFindings)
        RequiredScopes   = @($requiredScopes)
        RequiredRoles    = @(
            'Directory Readers for license details'
            'Reports Reader for per-user usage reports in Global'
            'At least one Microsoft Entra administrator role for delegated service communications'
        )
    }
}
catch {
    $message = "OneDrive health assessment failed for '$normalizedUserPrincipalName': $($_.Exception.Message)"
    throw [InvalidOperationException]::new($message, $_.Exception)
}
finally {
    if ($connected) {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
}
