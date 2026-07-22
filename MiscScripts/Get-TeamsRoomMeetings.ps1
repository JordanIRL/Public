#requires -Version 7.0
#requires -Modules Microsoft.Graph.Authentication

<#
.SYNOPSIS
    Retrieves Microsoft Teams meetings from a room mailbox for the previous and next 14 days.

.DESCRIPTION
    Uses the Microsoft Graph v1.0 calendarView endpoint to retrieve every occurrence,
    exception, and single-instance event in a 28-day window centered on AsOf. The
    script returns events whose isOnlineMeeting property is true and whose
    onlineMeetingProvider is teamsForBusiness.

    Every standard event property returned by Microsoft Graph is preserved. For events
    with attachments, the script also retrieves every attachment page and returns the
    attachment objects alongside the event. Custom and legacy extended properties are
    not generically enumerable and are not included unless Microsoft Graph returns them
    as standard event properties.

    The result reflects the copy stored in the room mailbox. Exchange resource-booking
    settings can remove a meeting's original subject, body, or attachments before the
    event is stored, and Microsoft Graph cannot reconstruct removed content.

.PARAMETER TenantId
    Microsoft Entra tenant GUID to authenticate against.

.PARAMETER RoomUserId
    The room mailbox's Microsoft Entra object ID or user principal name. An SMTP alias
    that is not also the user principal name is not a supported Graph user identifier.

.PARAMETER AsOf
    The instant at the center of the report window. The default is the current time.
    The script queries from AsOf minus 14 days through AsOf plus 14 days.

.PARAMETER TimeZone
    Outlook time-zone name used for event start and end values in the response. The
    default is UTC. Examples include GMT Standard Time and Pacific Standard Time.

.PARAMETER PageSize
    Number of events requested per calendarView page. Microsoft Graph permits 1 through
    1000. All pages are retrieved regardless of this value.

.PARAMETER Environment
    Microsoft Graph cloud environment. The calendar APIs used by this script support
    Global, USGov, USGovDoD, and China.

.PARAMETER ClientId
    Optional application ID for an approved public-client app registration.

.PARAMETER ExpectedAccount
    Optional user principal name that must match the signed-in administrator.

.PARAMETER UseDeviceCode
    Uses delegated device-code authentication instead of interactive browser authentication.

.OUTPUTS
    PSCustomObject. The report contains the room identifier, UTC window, response time
    zone, count, and a Meetings array. Each Meetings element contains the complete Graph
    event object and its attachment objects.

.EXAMPLE
    ./Get-TeamsRoomMeetings.ps1 -TenantId '00000000-0000-0000-0000-000000000000' -RoomUserId 'boardroom@contoso.com'

.EXAMPLE
    ./Get-TeamsRoomMeetings.ps1 -TenantId '00000000-0000-0000-0000-000000000000' -RoomUserId 'boardroom@contoso.com' -TimeZone 'GMT Standard Time' -ExpectedAccount 'admin@contoso.com' -UseDeviceCode

.NOTES
    Required delegated Microsoft Graph scope: Calendars.Read.Shared.

    No Microsoft Entra administrator role is inherently required. The signed-in user
    must have Exchange calendar-folder permission on the room mailbox. Reviewer is the
    minimum practical permission for full non-private event details. Viewing private
    event details additionally requires CanViewPrivateItems. Tenant consent policy can
    still require an administrator to approve the delegated scope.
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
    [Alias('RoomEmailAddress', 'RoomEmail')]
    [ValidateScript({
        if ([string]::IsNullOrWhiteSpace($_)) {
            throw 'RoomUserId must not be empty or whitespace.'
        }
        if ($_.Trim() -eq [guid]::Empty.ToString()) {
            throw 'RoomUserId must not be the empty GUID.'
        }
        $true
    })]
    [string] $RoomUserId,

    [Parameter()]
    [datetimeoffset] $AsOf = [datetimeoffset]::UtcNow,

    [Parameter()]
    [ValidateScript({
        if ([string]::IsNullOrWhiteSpace($_)) {
            throw 'TimeZone must not be empty or whitespace.'
        }
        if ($_ -match '[\r\n"]') {
            throw 'TimeZone must not contain quotes or line breaks.'
        }
        $true
    })]
    [string] $TimeZone = 'UTC',

    [Parameter()]
    [ValidateRange(1, 1000)]
    [int] $PageSize = 1000,

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

function Get-ObjectPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $InputObject,

        [Parameter(Mandatory)]
        [string] $Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return ,$InputObject[$Name]
        }
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $property) {
        return ,$property.Value
    }

    return $null
}

function Invoke-GraphPagedGet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $InitialUri,

        [Parameter(Mandatory)]
        [hashtable] $Headers,

        [Parameter(Mandatory)]
        [string] $OperationDescription
    )

    $nextUri = $InitialUri

    while (-not [string]::IsNullOrWhiteSpace($nextUri)) {
        try {
            $page = Invoke-MgGraphRequest -Method GET -Uri $nextUri -Headers $Headers -ErrorAction Stop
        }
        catch {
            $message = "$OperationDescription failed: $($_.Exception.Message)"
            throw [InvalidOperationException]::new($message, $_.Exception)
        }

        $items = Get-ObjectPropertyValue -InputObject $page -Name 'value'
        if ($null -eq $items) {
            throw [InvalidDataException]::new("$OperationDescription returned a response without a value collection.")
        }

        foreach ($item in @($items)) {
            $item
        }

        $nextLink = Get-ObjectPropertyValue -InputObject $page -Name '@odata.nextLink'
        $nextUri = if ($null -eq $nextLink) { $null } else { [string] $nextLink }
    }
}

$requiredScopes = @(
    'Calendars.Read.Shared'
)

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

$connected = $false
$normalizedRoomUserId = $RoomUserId.Trim()

try {
    Connect-MgGraph @connectParameters
    $connected = $true

    $graphContext = Get-MgContext
    if ($null -eq $graphContext -or $graphContext.AuthType -ne 'Delegated') {
        throw 'Microsoft Graph did not establish a delegated authentication context.'
    }

    if ([guid] $graphContext.TenantId -ne $TenantId) {
        throw "Authenticated to tenant '$($graphContext.TenantId)' instead of '$($TenantId.Guid)'."
    }

    if ($graphContext.ContextScope -ne 'Process') {
        throw "Microsoft Graph used context scope '$($graphContext.ContextScope)' instead of 'Process'."
    }

    if ($graphContext.Environment -ne $Environment) {
        throw "Microsoft Graph used environment '$($graphContext.Environment)' instead of '$Environment'."
    }

    if (
        $PSBoundParameters.ContainsKey('ClientId') -and
        [guid] $graphContext.ClientId -ne $ClientId
    ) {
        throw "Microsoft Graph used client '$($graphContext.ClientId)' instead of '$($ClientId.Guid)'."
    }

    if (
        $PSBoundParameters.ContainsKey('ExpectedAccount') -and
        $graphContext.Account -ne $ExpectedAccount.Trim()
    ) {
        throw "Signed in as '$($graphContext.Account)' instead of '$($ExpectedAccount.Trim())'."
    }

    $missingScopes = @(
        $requiredScopes | Where-Object { $_ -notin $graphContext.Scopes }
    )
    if ($missingScopes.Count -gt 0) {
        throw "The delegated token is missing required scope(s): $($missingScopes -join ', ')."
    }

    $asOfUtc = $AsOf.ToUniversalTime()
    $windowStartUtc = $asOfUtc.AddDays(-14)
    $windowEndUtc = $asOfUtc.AddDays(14)
    $encodedRoomUserId = [Uri]::EscapeDataString($normalizedRoomUserId)
    $encodedStart = [Uri]::EscapeDataString($windowStartUtc.ToString('o', [Globalization.CultureInfo]::InvariantCulture))
    $encodedEnd = [Uri]::EscapeDataString($windowEndUtc.ToString('o', [Globalization.CultureInfo]::InvariantCulture))

    $headers = @{
        Prefer = "outlook.timezone=`"$TimeZone`", outlook.body-content-type=`"html`", IdType=`"ImmutableId`""
    }

    $calendarViewUri = "/v1.0/users/$encodedRoomUserId/calendar/calendarView?startDateTime=$encodedStart&endDateTime=$encodedEnd&`$top=$PageSize"
    Write-Verbose "Retrieving the complete room calendar view from $($windowStartUtc.ToString('o')) through $($windowEndUtc.ToString('o'))."

    $events = @(
        Invoke-GraphPagedGet -InitialUri $calendarViewUri -Headers $headers -OperationDescription "Retrieving the calendar view for room '$normalizedRoomUserId'"
    )

    $teamsMeetings = [Collections.Generic.List[object]]::new()
    foreach ($event in $events) {
        $isOnlineMeeting = [bool] (Get-ObjectPropertyValue -InputObject $event -Name 'isOnlineMeeting')
        $onlineMeetingProvider = [string] (Get-ObjectPropertyValue -InputObject $event -Name 'onlineMeetingProvider')

        if (-not $isOnlineMeeting -or $onlineMeetingProvider -ne 'teamsForBusiness') {
            continue
        }

        $eventId = [string] (Get-ObjectPropertyValue -InputObject $event -Name 'id')
        if ([string]::IsNullOrWhiteSpace($eventId)) {
            throw [InvalidDataException]::new("Microsoft Graph returned a Teams meeting without an event ID for room '$normalizedRoomUserId'.")
        }

        $attachments = @()
        $hasAttachments = [bool] (Get-ObjectPropertyValue -InputObject $event -Name 'hasAttachments')
        if ($hasAttachments) {
            $encodedEventId = [Uri]::EscapeDataString($eventId)
            $attachmentSelect = [Uri]::EscapeDataString('id,name,contentType,size,isInline,lastModifiedDateTime')
            $attachmentUri = "/v1.0/users/$encodedRoomUserId/events/$encodedEventId/attachments?`$select=$attachmentSelect"
            $attachments = @(
                Invoke-GraphPagedGet -InitialUri $attachmentUri -Headers $headers -OperationDescription "Retrieving attachments for room event '$eventId'"
            )
        }

        $teamsMeetings.Add([pscustomobject] [ordered] @{
            PSTypeName  = 'Microsoft365.TeamsRoomMeeting'
            Event       = $event
            Attachments = $attachments
        })
    }

    $orderedMeetings = @(
        $teamsMeetings | Sort-Object {
            $start = Get-ObjectPropertyValue -InputObject $_.Event -Name 'start'
            [string] (Get-ObjectPropertyValue -InputObject $start -Name 'dateTime')
        }
    )

    [pscustomobject] [ordered] @{
        PSTypeName        = 'Microsoft365.TeamsRoomMeetingReport'
        RoomUserId        = $normalizedRoomUserId
        AsOfUtc           = $asOfUtc
        WindowStartUtc    = $windowStartUtc
        WindowEndUtc      = $windowEndUtc
        ResponseTimeZone  = $TimeZone
        RetrievedAtUtc    = [datetimeoffset]::UtcNow
        TeamsMeetingCount = $orderedMeetings.Count
        Meetings          = $orderedMeetings
    }
}
catch {
    $message = "Failed to retrieve Teams meetings for room '$normalizedRoomUserId': $($_.Exception.Message)"
    throw [InvalidOperationException]::new($message, $_.Exception)
}
finally {
    if ($connected) {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
}
