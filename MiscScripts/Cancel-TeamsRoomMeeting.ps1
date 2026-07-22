#requires -Version 7.0
#requires -Modules Microsoft.Graph.Authentication

<#
.SYNOPSIS
    Releases a Teams room from a meeting or cancels the organizer's meeting for everyone.

.DESCRIPTION
    Performs one of two explicit Microsoft Graph v1.0 operations for a room-calendar
    event:

    ReleaseRoom declines the invitation from the room mailbox and sends the response to
    the organizer. It releases the room; it does not cancel the meeting for other people.

    CancelMeeting resolves the corresponding event in the Exchange organizer's mailbox,
    verifies that isOrganizer is true, and cancels the meeting for all attendees. Microsoft
    Graph always sends a cancellation message for this action. A Teams co-organizer is not
    the Exchange calendar organizer and cannot satisfy this check.

    A concrete occurrence or single-instance EventId from Get-TeamsRoomMeetings.ps1 is
    required. For a recurring meeting, SelectedEvent affects only that occurrence;
    EntireSeries resolves and acts on the series master. The script refuses series-master
    input so that an occurrence is always available for deterministic cross-mailbox
    correlation and post-operation verification.

    Discovery, organizer correlation, target resolution, and a final target re-read occur
    before ShouldProcess. The mutation is not wrapped in a custom retry. A successful
    operation returns HTTP 202 Accepted, after which the script performs bounded read-only
    verification and reports whether the change became visible during that interval.

.PARAMETER TenantId
    Microsoft Entra tenant GUID to authenticate against.

.PARAMETER RoomUserId
    The room mailbox's Microsoft Entra object ID or user principal name. An SMTP alias
    that is not also the user principal name is not a supported Graph user identifier.

.PARAMETER EventId
    Immutable room-calendar event ID returned by Get-TeamsRoomMeetings.ps1. Supply a
    single instance, occurrence, or exception ID, not a series-master ID.

.PARAMETER Operation
    ReleaseRoom releases only the room. CancelMeeting cancels the organizer's meeting for
    every attendee and sends a cancellation message.

.PARAMETER RecurrenceScope
    SelectedEvent acts only on the supplied single event or recurring occurrence.
    EntireSeries resolves and acts on the recurring series master. EntireSeries is invalid
    for a single-instance meeting.

.PARAMETER OrganizerUserId
    Optional Microsoft Entra object ID or user principal name for the organizer mailbox.
    When omitted, CancelMeeting uses the organizer email address stored on the room event.
    Supply this value when the organizer's SMTP address is not also their user principal
    name. The parameter is not valid with ReleaseRoom.

.PARAMETER OrganizerEventId
    Optional immutable ID of the corresponding concrete occurrence in the organizer's
    mailbox. When omitted, CancelMeeting searches a bounded organizer primary-calendar
    view and requires exactly one isOrganizer event with the same iCalUId. The supplied ID
    must be an organizer-mailbox event ID that the signed-in account can address directly as
    /users/{OrganizerUserId}/events/{OrganizerEventId}. Event IDs are mailbox-specific, so
    the room EventId and a recipient-local copy ID cannot be reused. Shared custom calendars
    that are available only through the recipient's local /me/calendars copy are unsupported.

.PARAMETER Comment
    Optional text sent with the room's decline response or the organizer's cancellation.

.PARAMETER VerificationAttempts
    Maximum number of read-only verification checks after Microsoft Graph accepts the
    mutation. The default is 4.

.PARAMETER VerificationDelaySeconds
    Delay between verification checks. The default is 2 seconds.

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
    PSCustomObject with operation status, exact source and target identities, HTTP status,
    request identifiers, and verification outcome.

.EXAMPLE
    ./Cancel-TeamsRoomMeeting.ps1 -TenantId '00000000-0000-0000-0000-000000000000' -RoomUserId 'boardroom@contoso.com' -EventId 'AAMkAG...' -Operation ReleaseRoom -RecurrenceScope SelectedEvent -WhatIf

.EXAMPLE
    ./Cancel-TeamsRoomMeeting.ps1 -TenantId '00000000-0000-0000-0000-000000000000' -RoomUserId 'boardroom@contoso.com' -EventId 'AAMkAG...' -Operation CancelMeeting -RecurrenceScope EntireSeries -Comment 'Cancelled by the facilities team.' -WhatIf

.EXAMPLE
    ./Cancel-TeamsRoomMeeting.ps1 -TenantId '00000000-0000-0000-0000-000000000000' -RoomUserId 'boardroom@contoso.com' -EventId 'AAMkAG...' -Operation ReleaseRoom -RecurrenceScope SelectedEvent -Confirm

.NOTES
    Required delegated Microsoft Graph scopes: Calendars.ReadWrite and
    Calendars.ReadWrite.Shared. The action API documents Calendars.ReadWrite, while direct
    access to another mailbox's shared or delegated calendar requires
    Calendars.ReadWrite.Shared.

    No Microsoft Entra administrator role is inherently required. The signed-in user must
    have Exchange Editor or delegate access to each target calendar. Private event detail
    additionally requires CanViewPrivateItems. CancelMeeting cannot cancel a meeting whose
    actual organizer mailbox is external or otherwise inaccessible to the signed-in user.
    OrganizerEventId can identify a secondary/custom organizer-calendar event only when that
    organizer-mailbox event is directly addressable; a recipient-local shared-calendar ID is
    not valid on the organizer-mailbox route.
#>

[CmdletBinding(PositionalBinding = $false, SupportsShouldProcess, ConfirmImpact = 'High')]
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

    [Parameter(Mandatory)]
    [ValidateScript({
        if ([string]::IsNullOrWhiteSpace($_)) {
            throw 'EventId must not be empty or whitespace.'
        }
        $true
    })]
    [string] $EventId,

    [Parameter(Mandatory)]
    [ValidateSet('ReleaseRoom', 'CancelMeeting')]
    [string] $Operation,

    [Parameter(Mandatory)]
    [ValidateSet('SelectedEvent', 'EntireSeries')]
    [string] $RecurrenceScope,

    [Parameter()]
    [ValidateScript({
        if ([string]::IsNullOrWhiteSpace($_)) {
            throw 'OrganizerUserId must not be empty or whitespace when supplied.'
        }
        if ($_.Trim() -eq [guid]::Empty.ToString()) {
            throw 'OrganizerUserId must not be the empty GUID.'
        }
        $true
    })]
    [string] $OrganizerUserId,

    [Parameter()]
    [ValidateScript({
        if ([string]::IsNullOrWhiteSpace($_)) {
            throw 'OrganizerEventId must not be empty or whitespace when supplied.'
        }
        $true
    })]
    [string] $OrganizerEventId,

    [Parameter()]
    [AllowEmptyString()]
    [string] $Comment = '',

    [Parameter()]
    [ValidateRange(1, 10)]
    [int] $VerificationAttempts = 4,

    [Parameter()]
    [ValidateRange(1, 30)]
    [int] $VerificationDelaySeconds = 2,

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

function Invoke-GraphGet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Uri,

        [Parameter(Mandatory)]
        [hashtable] $Headers,

        [Parameter(Mandatory)]
        [string] $OperationDescription
    )

    try {
        Invoke-MgGraphRequest -Method GET -Uri $Uri -Headers $Headers -ErrorAction Stop
    }
    catch {
        $message = "$OperationDescription failed: $($_.Exception.Message)"
        throw [InvalidOperationException]::new($message, $_.Exception)
    }
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
        $page = Invoke-GraphGet -Uri $nextUri -Headers $Headers -OperationDescription $OperationDescription
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

function ConvertTo-UtcDateTimeOffset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $DateTimeTimeZone,

        [Parameter(Mandatory)]
        [string] $PropertyDescription
    )

    $dateTimeText = [string] (Get-ObjectPropertyValue -InputObject $DateTimeTimeZone -Name 'dateTime')
    if ([string]::IsNullOrWhiteSpace($dateTimeText)) {
        throw [InvalidDataException]::new("Microsoft Graph returned no $PropertyDescription dateTime value.")
    }

    [datetimeoffset] $parsedValue = [datetimeoffset]::MinValue
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    $parsed = [datetimeoffset]::TryParse(
        $dateTimeText,
        [Globalization.CultureInfo]::InvariantCulture,
        $styles,
        [ref] $parsedValue
    )

    if (-not $parsed) {
        throw [InvalidDataException]::new("Microsoft Graph returned an invalid $PropertyDescription dateTime value.")
    }

    return $parsedValue.ToUniversalTime()
}

function Get-GraphCalendarEventMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $UserId,

        [Parameter(Mandatory)]
        [object] $ReferenceEvent,

        [Parameter(Mandatory)]
        [hashtable] $Headers,

        [Parameter(Mandatory)]
        [string] $OperationDescription
    )

    $iCalUId = [string] (Get-ObjectPropertyValue -InputObject $ReferenceEvent -Name 'iCalUId')
    if ([string]::IsNullOrWhiteSpace($iCalUId)) {
        throw [InvalidDataException]::new('Microsoft Graph returned no iCalUId for deterministic event correlation.')
    }

    $startObject = Get-ObjectPropertyValue -InputObject $ReferenceEvent -Name 'start'
    $endObject = Get-ObjectPropertyValue -InputObject $ReferenceEvent -Name 'end'
    $startUtc = ConvertTo-UtcDateTimeOffset -DateTimeTimeZone $startObject -PropertyDescription 'event start'
    $endUtc = ConvertTo-UtcDateTimeOffset -DateTimeTimeZone $endObject -PropertyDescription 'event end'
    $queryStartUtc = $startUtc.AddDays(-1)
    $queryEndUtc = $endUtc.AddDays(1)

    $encodedUserId = [Uri]::EscapeDataString($UserId)
    $encodedStart = [Uri]::EscapeDataString($queryStartUtc.ToString('o', [Globalization.CultureInfo]::InvariantCulture))
    $encodedEnd = [Uri]::EscapeDataString($queryEndUtc.ToString('o', [Globalization.CultureInfo]::InvariantCulture))
    $calendarViewUri = "/v1.0/users/$encodedUserId/calendar/calendarView?startDateTime=$encodedStart&endDateTime=$encodedEnd&`$top=1000"

    $matches = [Collections.Generic.List[object]]::new()
    $matchedEventIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $events = @(
        Invoke-GraphPagedGet -InitialUri $calendarViewUri -Headers $Headers -OperationDescription $OperationDescription
    )

    foreach ($event in $events) {
        $candidateIcalUId = [string] (Get-ObjectPropertyValue -InputObject $event -Name 'iCalUId')
        if ([string]::Equals($candidateIcalUId, $iCalUId, [StringComparison]::Ordinal)) {
            $candidateEventId = [string] (Get-ObjectPropertyValue -InputObject $event -Name 'id')
            if ([string]::IsNullOrWhiteSpace($candidateEventId) -or $matchedEventIds.Add($candidateEventId)) {
                $matches.Add($event)
            }
        }
    }

    return $matches.ToArray()
}

function Resolve-GraphEventTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $UserId,

        [Parameter(Mandatory)]
        [object] $SelectedEvent,

        [Parameter(Mandatory)]
        [ValidateSet('SelectedEvent', 'EntireSeries')]
        [string] $Scope,

        [Parameter(Mandatory)]
        [hashtable] $Headers
    )

    $eventType = [string] (Get-ObjectPropertyValue -InputObject $SelectedEvent -Name 'type')
    if ($Scope -eq 'SelectedEvent') {
        if ($eventType -eq 'seriesMaster') {
            throw [InvalidOperationException]::new('A series-master ID cannot be used with SelectedEvent. Supply a concrete occurrence ID.')
        }
        return $SelectedEvent
    }

    if ($eventType -eq 'singleInstance') {
        throw [InvalidOperationException]::new('EntireSeries cannot be used with a single-instance meeting.')
    }

    if ($eventType -eq 'seriesMaster') {
        return $SelectedEvent
    }

    if ($eventType -notin @('occurrence', 'exception')) {
        throw [InvalidDataException]::new("Microsoft Graph returned unsupported event type '$eventType'.")
    }

    $seriesMasterId = [string] (Get-ObjectPropertyValue -InputObject $SelectedEvent -Name 'seriesMasterId')
    if ([string]::IsNullOrWhiteSpace($seriesMasterId)) {
        throw [InvalidDataException]::new('Microsoft Graph returned no seriesMasterId for the recurring event.')
    }

    $encodedUserId = [Uri]::EscapeDataString($UserId)
    $encodedSeriesMasterId = [Uri]::EscapeDataString($seriesMasterId)
    $seriesMasterUri = "/v1.0/users/$encodedUserId/events/$encodedSeriesMasterId"
    $seriesMaster = Invoke-GraphGet -Uri $seriesMasterUri -Headers $Headers -OperationDescription "Retrieving series master '$seriesMasterId' from mailbox '$UserId'"
    $seriesMasterType = [string] (Get-ObjectPropertyValue -InputObject $seriesMaster -Name 'type')
    if ($seriesMasterType -ne 'seriesMaster') {
        throw [InvalidDataException]::new("Event '$seriesMasterId' was expected to be a series master but Microsoft Graph returned type '$seriesMasterType'.")
    }

    return $seriesMaster
}

function Get-GraphHeaderValue {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Headers,

        [Parameter(Mandatory)]
        [string] $Name
    )

    if ($null -eq $Headers) {
        return $null
    }

    if ($Headers -is [System.Collections.IDictionary]) {
        foreach ($key in $Headers.Keys) {
            if ([string]::Equals([string] $key, $Name, [StringComparison]::OrdinalIgnoreCase)) {
                return (@($Headers[$key]) -join ', ')
            }
        }
        return $null
    }

    $property = $Headers.PSObject.Properties |
        Where-Object { [string]::Equals($_.Name, $Name, [StringComparison]::OrdinalIgnoreCase) } |
        Select-Object -First 1
    if ($null -ne $property) {
        return (@($property.Value) -join ', ')
    }

    return $null
}

function Get-ExceptionStatusCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Exception] $Exception
    )

    $currentException = $Exception
    while ($null -ne $currentException) {
        $statusCode = Get-ObjectPropertyValue -InputObject $currentException -Name 'StatusCode'
        if ($null -ne $statusCode) {
            try {
                return [int] $statusCode
            }
            catch {
                return [string] $statusCode
            }
        }

        $response = Get-ObjectPropertyValue -InputObject $currentException -Name 'Response'
        $responseStatusCode = Get-ObjectPropertyValue -InputObject $response -Name 'StatusCode'
        if ($null -ne $responseStatusCode) {
            try {
                return [int] $responseStatusCode
            }
            catch {
                return [string] $responseStatusCode
            }
        }

        $currentException = $currentException.InnerException
    }

    return $null
}

$requiredScopes = @(
    'Calendars.ReadWrite',
    'Calendars.ReadWrite.Shared'
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
$normalizedEventId = $EventId.Trim()

try {
    if (
        $Operation -eq 'ReleaseRoom' -and
        ($PSBoundParameters.ContainsKey('OrganizerUserId') -or $PSBoundParameters.ContainsKey('OrganizerEventId'))
    ) {
        throw 'OrganizerUserId and OrganizerEventId are not valid with ReleaseRoom.'
    }

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

    $readHeaders = @{
        Prefer = 'outlook.timezone="UTC", outlook.body-content-type="html", IdType="ImmutableId"'
    }

    $encodedRoomUserId = [Uri]::EscapeDataString($normalizedRoomUserId)
    $encodedRoomEventId = [Uri]::EscapeDataString($normalizedEventId)
    $roomEventUri = "/v1.0/users/$encodedRoomUserId/events/$encodedRoomEventId"
    $roomEvent = Invoke-GraphGet -Uri $roomEventUri -Headers $readHeaders -OperationDescription "Retrieving room event '$normalizedEventId' from '$normalizedRoomUserId'"

    $roomEventType = [string] (Get-ObjectPropertyValue -InputObject $roomEvent -Name 'type')
    if ($roomEventType -eq 'seriesMaster') {
        throw 'EventId identifies a series master. Supply a concrete occurrence or exception ID returned by Get-TeamsRoomMeetings.ps1.'
    }
    if ($roomEventType -notin @('singleInstance', 'occurrence', 'exception')) {
        throw "Microsoft Graph returned unsupported room event type '$roomEventType'."
    }

    $isOnlineMeeting = [bool] (Get-ObjectPropertyValue -InputObject $roomEvent -Name 'isOnlineMeeting')
    $onlineMeetingProvider = [string] (Get-ObjectPropertyValue -InputObject $roomEvent -Name 'onlineMeetingProvider')
    if (-not $isOnlineMeeting -or $onlineMeetingProvider -ne 'teamsForBusiness') {
        throw 'The selected room event is not identified by Microsoft Graph as a Microsoft Teams meeting.'
    }

    $roomIsOrganizer = [bool] (Get-ObjectPropertyValue -InputObject $roomEvent -Name 'isOrganizer')
    $targetUserId = $null
    $selectedTargetEvent = $null

    if ($Operation -eq 'ReleaseRoom') {
        if ($roomIsOrganizer) {
            throw 'The room is the Exchange organizer and cannot decline its own meeting. Use CancelMeeting.'
        }

        $targetUserId = $normalizedRoomUserId
        $selectedTargetEvent = $roomEvent
    }
    else {
        if ($roomIsOrganizer) {
            if (
                $PSBoundParameters.ContainsKey('OrganizerUserId') -or
                $PSBoundParameters.ContainsKey('OrganizerEventId')
            ) {
                throw 'OrganizerUserId and OrganizerEventId must not be supplied because the room is the verified Exchange organizer.'
            }

            $targetUserId = $normalizedRoomUserId
            $selectedTargetEvent = $roomEvent
        }
        else {
            $organizer = Get-ObjectPropertyValue -InputObject $roomEvent -Name 'organizer'
            $organizerEmailAddress = Get-ObjectPropertyValue -InputObject $organizer -Name 'emailAddress'
            $organizerAddress = [string] (Get-ObjectPropertyValue -InputObject $organizerEmailAddress -Name 'address')

            if ($PSBoundParameters.ContainsKey('OrganizerUserId')) {
                $targetUserId = $OrganizerUserId.Trim()
            }
            elseif (-not [string]::IsNullOrWhiteSpace($organizerAddress)) {
                $targetUserId = $organizerAddress.Trim()
            }
            else {
                throw 'The room event contains no organizer address. Supply OrganizerUserId.'
            }

            if ($PSBoundParameters.ContainsKey('OrganizerEventId')) {
                $normalizedOrganizerEventId = $OrganizerEventId.Trim()
                $encodedOrganizerUserId = [Uri]::EscapeDataString($targetUserId)
                $encodedOrganizerEventId = [Uri]::EscapeDataString($normalizedOrganizerEventId)
                $organizerEventUri = "/v1.0/users/$encodedOrganizerUserId/events/$encodedOrganizerEventId"
                $selectedTargetEvent = Invoke-GraphGet -Uri $organizerEventUri -Headers $readHeaders -OperationDescription "Retrieving organizer event '$normalizedOrganizerEventId' from '$targetUserId'"

                $roomIcalUId = [string] (Get-ObjectPropertyValue -InputObject $roomEvent -Name 'iCalUId')
                $organizerIcalUId = [string] (Get-ObjectPropertyValue -InputObject $selectedTargetEvent -Name 'iCalUId')
                if (-not [string]::Equals($roomIcalUId, $organizerIcalUId, [StringComparison]::Ordinal)) {
                    throw 'OrganizerEventId does not have the same iCalUId as the selected room occurrence.'
                }
            }
            else {
                $organizerMatches = @(
                    Get-GraphCalendarEventMatch -UserId $targetUserId -ReferenceEvent $roomEvent -Headers $readHeaders -OperationDescription "Correlating the room occurrence in organizer mailbox '$targetUserId'"
                )
                $organizerMatches = @(
                    $organizerMatches | Where-Object {
                        [bool] (Get-ObjectPropertyValue -InputObject $_ -Name 'isOrganizer')
                    }
                )

                if ($organizerMatches.Count -eq 0) {
                    throw "No isOrganizer event with the selected occurrence's iCalUId was found in organizer mailbox '$targetUserId'."
                }
                if ($organizerMatches.Count -gt 1) {
                    throw "More than one isOrganizer event with the selected occurrence's iCalUId was found in organizer mailbox '$targetUserId'. Supply OrganizerEventId."
                }

                $selectedTargetEvent = $organizerMatches[0]
            }

            $targetIsOrganizer = [bool] (Get-ObjectPropertyValue -InputObject $selectedTargetEvent -Name 'isOrganizer')
            if (-not $targetIsOrganizer) {
                throw "The resolved event in mailbox '$targetUserId' is not the Exchange organizer copy."
            }
        }
    }

    $targetEvent = Resolve-GraphEventTarget -UserId $targetUserId -SelectedEvent $selectedTargetEvent -Scope $RecurrenceScope -Headers $readHeaders
    $targetEventId = [string] (Get-ObjectPropertyValue -InputObject $targetEvent -Name 'id')
    if ([string]::IsNullOrWhiteSpace($targetEventId)) {
        throw 'Microsoft Graph returned no ID for the resolved mutation target.'
    }

    $encodedTargetUserId = [Uri]::EscapeDataString($targetUserId)
    $encodedTargetEventId = [Uri]::EscapeDataString($targetEventId)
    $targetEventUri = "/v1.0/users/$encodedTargetUserId/events/$encodedTargetEventId"

    $targetBeforeMutation = Invoke-GraphGet -Uri $targetEventUri -Headers $readHeaders -OperationDescription "Re-reading target event '$targetEventId' from '$targetUserId'"
    $resolvedChangeKey = [string] (Get-ObjectPropertyValue -InputObject $targetEvent -Name 'changeKey')
    $currentChangeKey = [string] (Get-ObjectPropertyValue -InputObject $targetBeforeMutation -Name 'changeKey')
    if (
        -not [string]::IsNullOrWhiteSpace($resolvedChangeKey) -and
        -not [string]::IsNullOrWhiteSpace($currentChangeKey) -and
        $resolvedChangeKey -ne $currentChangeKey
    ) {
        throw 'The target event changed during discovery. Run the script again to review the current event before changing it.'
    }

    $subject = [string] (Get-ObjectPropertyValue -InputObject $targetBeforeMutation -Name 'subject')
    if ([string]::IsNullOrWhiteSpace($subject)) {
        $subject = '(no subject)'
    }
    $startObject = Get-ObjectPropertyValue -InputObject $targetBeforeMutation -Name 'start'
    $endObject = Get-ObjectPropertyValue -InputObject $targetBeforeMutation -Name 'end'
    $startUtc = ConvertTo-UtcDateTimeOffset -DateTimeTimeZone $startObject -PropertyDescription 'target event start'
    $endUtc = ConvertTo-UtcDateTimeOffset -DateTimeTimeZone $endObject -PropertyDescription 'target event end'

    $isAlreadyComplete = $false
    if ($Operation -eq 'CancelMeeting') {
        $targetIsOrganizer = [bool] (Get-ObjectPropertyValue -InputObject $targetBeforeMutation -Name 'isOrganizer')
        if (-not $targetIsOrganizer) {
            throw "The final target event in mailbox '$targetUserId' is not the Exchange organizer copy."
        }
        $isAlreadyComplete = [bool] (Get-ObjectPropertyValue -InputObject $targetBeforeMutation -Name 'isCancelled')
    }
    else {
        $responseStatus = Get-ObjectPropertyValue -InputObject $targetBeforeMutation -Name 'responseStatus'
        $response = [string] (Get-ObjectPropertyValue -InputObject $responseStatus -Name 'response')
        $isAlreadyComplete = $response -eq 'declined'
    }

    if ($isAlreadyComplete) {
        [pscustomobject] [ordered] @{
            PSTypeName          = 'Microsoft365.TeamsRoomMeetingOperationResult'
            Status              = 'Skipped'
            Operation           = $Operation
            RecurrenceScope     = $RecurrenceScope
            RoomUserId          = $normalizedRoomUserId
            SourceRoomEventId   = $normalizedEventId
            TargetUserId        = $targetUserId
            TargetEventId       = $targetEventId
            Subject             = $subject
            StartUtc            = $startUtc
            EndUtc              = $endUtc
            HttpStatusCode      = $null
            Verified            = $true
            VerificationChecks  = 0
            VerificationStatus  = 'AlreadyComplete'
            VerificationFailure = $null
            RequestId           = $null
            ClientRequestId     = $null
            CompletedAtUtc      = [datetimeoffset]::UtcNow
        }
        return
    }

    $targetDescription = "'$subject' from $($startUtc.ToString('o')) through $($endUtc.ToString('o')); mailbox '$targetUserId'; event '$targetEventId'; scope '$RecurrenceScope'"
    $actionDescription = if ($Operation -eq 'CancelMeeting') {
        'Cancel the organizer meeting for all attendees and send a cancellation message'
    }
    else {
        'Decline the room invitation and send the response to the organizer'
    }

    if (-not $PSCmdlet.ShouldProcess($targetDescription, $actionDescription)) {
        [pscustomobject] [ordered] @{
            PSTypeName          = 'Microsoft365.TeamsRoomMeetingOperationResult'
            Status              = if ($WhatIfPreference) { 'WhatIf' } else { 'Skipped' }
            Operation           = $Operation
            RecurrenceScope     = $RecurrenceScope
            RoomUserId          = $normalizedRoomUserId
            SourceRoomEventId   = $normalizedEventId
            TargetUserId        = $targetUserId
            TargetEventId       = $targetEventId
            Subject             = $subject
            StartUtc            = $startUtc
            EndUtc              = $endUtc
            HttpStatusCode      = $null
            Verified            = $false
            VerificationChecks  = 0
            VerificationStatus  = 'NotRun'
            VerificationFailure = $null
            RequestId           = $null
            ClientRequestId     = $null
            CompletedAtUtc      = [datetimeoffset]::UtcNow
        }
        return
    }

    $mutationName = if ($Operation -eq 'CancelMeeting') { 'cancel' } else { 'decline' }
    $mutationUri = "/v1.0/users/$encodedTargetUserId/events/$encodedTargetEventId/$mutationName"
    $body = if ($Operation -eq 'CancelMeeting') {
        @{}
    }
    else {
        @{ sendResponse = $true }
    }

    $trimmedComment = $Comment.Trim()
    if (-not [string]::IsNullOrWhiteSpace($trimmedComment)) {
        $body.comment = $trimmedComment
    }

    $clientRequestId = [guid]::NewGuid().Guid
    $mutationHeaders = @{
        Prefer                  = 'IdType="ImmutableId"'
        'client-request-id'     = $clientRequestId
        'return-client-request-id' = 'true'
    }
    $mutationStatusCode = $null
    $mutationResponseHeaders = $null

    try {
        Invoke-MgGraphRequest -Method POST -Uri $mutationUri -Headers $mutationHeaders -Body ($body | ConvertTo-Json -Depth 5 -Compress) -ContentType 'application/json' -StatusCodeVariable 'mutationStatusCode' -ResponseHeadersVariable 'mutationResponseHeaders' -ErrorAction Stop | Out-Null
    }
    catch {
        $message = "Microsoft Graph $mutationName failed for event '$targetEventId' in mailbox '$targetUserId' (client-request-id '$clientRequestId'): $($_.Exception.Message)"
        throw [InvalidOperationException]::new($message, $_.Exception)
    }

    if ([int] $mutationStatusCode -ne 202) {
        throw [InvalidOperationException]::new("Microsoft Graph $mutationName returned HTTP status '$mutationStatusCode' instead of 202 Accepted (client-request-id '$clientRequestId').")
    }

    $verified = $false
    $verificationChecks = 0
    $verificationStatus = 'NotObserved'
    $verificationFailure = $null
    for ($attempt = 1; $attempt -le $VerificationAttempts; $attempt++) {
        $verificationChecks = $attempt
        try {
            $verificationEvent = Invoke-GraphGet -Uri $targetEventUri -Headers $readHeaders -OperationDescription "Verifying target event '$targetEventId' in mailbox '$targetUserId'"

            if ($Operation -eq 'CancelMeeting') {
                $verified = [bool] (Get-ObjectPropertyValue -InputObject $verificationEvent -Name 'isCancelled')
            }
            else {
                $currentResponseStatus = Get-ObjectPropertyValue -InputObject $verificationEvent -Name 'responseStatus'
                $currentResponse = [string] (Get-ObjectPropertyValue -InputObject $currentResponseStatus -Name 'response')
                $verified = $currentResponse -eq 'declined'
            }
        }
        catch {
            $verificationStatusCode = Get-ExceptionStatusCode -Exception $_.Exception
            if ([string] $verificationStatusCode -eq '404') {
                $verified = $true
            }
            else {
                $verificationStatus = 'ReadFailed'
                $verificationFailure = [pscustomobject] [ordered] @{
                    ExceptionType  = $_.Exception.GetType().FullName
                    HttpStatusCode = $verificationStatusCode
                }
                break
            }
        }

        if ($verified -or $attempt -eq $VerificationAttempts) {
            if ($verified) {
                $verificationStatus = 'Verified'
            }
            break
        }

        Start-Sleep -Seconds $VerificationDelaySeconds
    }

    [pscustomobject] [ordered] @{
        PSTypeName          = 'Microsoft365.TeamsRoomMeetingOperationResult'
        Status              = 'Changed'
        Operation           = $Operation
        RecurrenceScope     = $RecurrenceScope
        RoomUserId          = $normalizedRoomUserId
        SourceRoomEventId   = $normalizedEventId
        TargetUserId        = $targetUserId
        TargetEventId       = $targetEventId
        Subject             = $subject
        StartUtc            = $startUtc
        EndUtc              = $endUtc
        HttpStatusCode      = [int] $mutationStatusCode
        Verified            = $verified
        VerificationChecks  = $verificationChecks
        VerificationStatus  = $verificationStatus
        VerificationFailure = $verificationFailure
        RequestId           = Get-GraphHeaderValue -Headers $mutationResponseHeaders -Name 'request-id'
        ClientRequestId     = $clientRequestId
        CompletedAtUtc      = [datetimeoffset]::UtcNow
    }
}
catch {
    $message = "Teams room meeting operation '$Operation' failed for room '$normalizedRoomUserId' and event '$normalizedEventId': $($_.Exception.Message)"
    throw [InvalidOperationException]::new($message, $_.Exception)
}
finally {
    if ($connected) {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
}
