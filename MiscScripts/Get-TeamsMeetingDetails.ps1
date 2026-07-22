#requires -Version 7.0
#requires -Modules Microsoft.Graph.Authentication

<#
.SYNOPSIS
    Retrieves comprehensive Microsoft Teams meeting details from a join link.

.DESCRIPTION
    Signs in to Microsoft Graph with delegated permissions and resolves an online meeting by its
    exact join URL. The result includes the complete onlineMeeting resource, correlated calendar
    event details from every accessible /me calendar, attachment metadata, attendance-report
    metadata, transcript metadata, and recording metadata.

    Attendee identities are never emitted. The onlineMeeting participants object is replaced by
    organizer and co-organizer UPNs, and scheduled attendee count. A correlated calendar event
    can also expose the Exchange organizer address.
    Each correlated event replaces its attendees collection with counts grouped by attendee type
    and response. Attachment content bytes, transcript content, recording content, and individual
    attendance records are never downloaded. Attendance-report items carry an explicit warning
    that the endpoint can be channel-scoped because onlineMeeting does not expose a reliable
    channel-meeting discriminator.

    Artifact and calendar access are independently reported as Available, Partial, NoData,
    AccessDenied, NotFoundOrExpired, Throttled, ServiceError, or Unavailable. A failure in one of
    those optional Graph surfaces does not hide the core onlineMeeting result.

    The signed-in user must be the meeting organizer or an invited attendee to resolve the link.
    Additional meeting-level, policy, meeting-type, consent, and retention checks apply to the
    artifact endpoints.

.PARAMETER TenantId
    Microsoft Entra tenant GUID to authenticate against.

.PARAMETER MeetingLink
    Complete Microsoft Teams join URL. HTML-encoded ampersands are accepted. A link that was
    percent-encoded as one complete value is decoded once; percent-encoding inside a valid URL
    is preserved.

.PARAMETER SkipArtifacts
    Skip attendance-report, transcript, and recording metadata. Calendar-event correlation and
    attachment metadata are still retrieved. This removes the three artifact scopes from the
    delegated sign-in request.

.PARAMETER CalendarSearchStartUtc
    Optional inclusive UTC start for calendar-event correlation. Supply together with
    CalendarSearchEndUtc when a recurring series reuses the meeting link beyond the default
    onlineMeeting start/end window.

.PARAMETER CalendarSearchEndUtc
    Optional exclusive UTC end for calendar-event correlation. Supply together with
    CalendarSearchStartUtc. The end must be later than the start.

.PARAMETER Environment
    Microsoft Graph cloud environment. The onlineMeeting lookup used by this script is available
    in Global, US Government L4, and US Government L5 clouds.

.PARAMETER ClientId
    Optional application ID for an approved public-client app registration.

.PARAMETER ExpectedAccount
    Optional user principal name that must match the delegated sign-in account.

.PARAMETER UseDeviceCode
    Use delegated device-code authentication instead of an interactive browser prompt.

.OUTPUTS
    PSCustomObject containing Query, Meeting, CalendarCorrelation, ArtifactAccess, and Retrieval.

.EXAMPLE
    ./Get-TeamsMeetingDetails.ps1 -TenantId '00000000-0000-0000-0000-000000000000' `
        -MeetingLink 'https://teams.microsoft.com/l/meetup-join/...' `
        -ExpectedAccount 'alex@contoso.com'

.EXAMPLE
    ./Get-TeamsMeetingDetails.ps1 -TenantId '00000000-0000-0000-0000-000000000000' `
        -MeetingLink 'https://teams.microsoft.com/l/meetup-join/...' `
        -SkipArtifacts -UseDeviceCode

.NOTES
    Default delegated scopes: OnlineMeetings.Read, Calendars.Read,
    OnlineMeetingArtifact.Read.All, OnlineMeetingTranscript.Read.All, and
    OnlineMeetingRecording.Read.All. Transcript and recording scopes require administrator
    consent. With SkipArtifacts, only OnlineMeetings.Read and Calendars.Read are requested.
    Microsoft Entra administrator roles do not override meeting-level access checks.
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
            throw 'MeetingLink must not be empty or whitespace.'
        }
        $true
    })]
    [string] $MeetingLink,

    [Parameter()]
    [switch] $SkipArtifacts,

    [Parameter()]
    [datetimeoffset] $CalendarSearchStartUtc,

    [Parameter()]
    [datetimeoffset] $CalendarSearchEndUtc,

    [Parameter()]
    [ValidateSet('Global', 'USGov', 'USGovDoD')]
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
    if ($null -ne $property) {
        return $property.Value
    }

    return $null
}

function Get-ObjectPropertyNames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $InputObject
    )

    if ($InputObject -is [Collections.IDictionary]) {
        return @($InputObject.Keys)
    }

    return @($InputObject.PSObject.Properties.Name)
}

function ConvertTo-NormalizedMeetingLink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Value
    )

    $candidate = [Net.WebUtility]::HtmlDecode($Value.Trim())
    $parsedUri = $null
    $isValidHttpsUri = [Uri]::TryCreate($candidate, [UriKind]::Absolute, [ref] $parsedUri) -and
        $parsedUri.Scheme -eq [Uri]::UriSchemeHttps -and
        -not [string]::IsNullOrWhiteSpace($parsedUri.Host)

    if (-not $isValidHttpsUri) {
        try {
            $candidate = [Uri]::UnescapeDataString($candidate)
        }
        catch {
            throw [ArgumentException]::new('MeetingLink is not a valid URI-encoded value.', $_.Exception)
        }

        $parsedUri = $null
        $isValidHttpsUri = [Uri]::TryCreate($candidate, [UriKind]::Absolute, [ref] $parsedUri) -and
            $parsedUri.Scheme -eq [Uri]::UriSchemeHttps -and
            -not [string]::IsNullOrWhiteSpace($parsedUri.Host)
    }

    if (-not $isValidHttpsUri) {
        throw [ArgumentException]::new('MeetingLink must be a complete HTTPS URL.')
    }

    return $candidate
}

function Test-MeetingLinkMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ExpectedLink,

        [Parameter()]
        [AllowEmptyString()]
        [string] $CandidateLink
    )

    if ([string]::IsNullOrWhiteSpace($CandidateLink)) {
        return $false
    }
    if ($ExpectedLink -ceq [Net.WebUtility]::HtmlDecode($CandidateLink.Trim())) {
        return $true
    }

    $expectedUri = $null
    $candidateUri = $null
    if (-not [Uri]::TryCreate($ExpectedLink, [UriKind]::Absolute, [ref] $expectedUri) -or
        -not [Uri]::TryCreate([Net.WebUtility]::HtmlDecode($CandidateLink.Trim()), [UriKind]::Absolute, [ref] $candidateUri)) {
        return $false
    }

    return [Uri]::Compare(
        $expectedUri,
        $candidateUri,
        [UriComponents]::AbsoluteUri,
        [UriFormat]::SafeUnescaped,
        [StringComparison]::OrdinalIgnoreCase
    ) -eq 0
}

function ConvertTo-RelativeGraphUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Uri
    )

    $absoluteUri = $null
    if (-not [Uri]::TryCreate($Uri, [UriKind]::Absolute, [ref] $absoluteUri)) {
        return $Uri
    }

    if ($absoluteUri.Scheme -ne [Uri]::UriSchemeHttps -or
        -not $absoluteUri.AbsolutePath.StartsWith('/v1.0/', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Microsoft Graph returned an unexpected paging URI: '$Uri'."
    }

    return $absoluteUri.PathAndQuery
}

function Get-GraphCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Uri,

        [Parameter()]
        [Collections.IDictionary] $Headers
    )

    $items = [Collections.Generic.List[object]]::new()
    $requestUri = $Uri

    while (-not [string]::IsNullOrWhiteSpace($requestUri)) {
        $requestParameters = @{
            Method      = 'GET'
            Uri         = $requestUri
            OutputType  = 'PSObject'
            ErrorAction = 'Stop'
        }
        if ($null -ne $Headers -and $Headers.Count -gt 0) {
            $requestParameters.Headers = $Headers
        }

        $response = Invoke-MgGraphRequest @requestParameters
        $pageItems = Get-ObjectPropertyValue -InputObject $response -Name 'value'
        foreach ($item in @($pageItems)) {
            if ($null -ne $item) {
                $items.Add($item)
            }
        }

        $nextLink = Get-ObjectPropertyValue -InputObject $response -Name '@odata.nextLink'
        $requestUri = if ([string]::IsNullOrWhiteSpace([string] $nextLink)) {
            $null
        }
        else {
            ConvertTo-RelativeGraphUri -Uri ([string] $nextLink)
        }
    }

    return $items.ToArray()
}

function Get-AllAccessibleCalendars {
    [CmdletBinding()]
    param()

    $calendarSelect = 'id,name,isDefaultCalendar,canEdit,canShare,canViewPrivateItems,color,hexColor,owner'
    $calendarList = [Collections.Generic.List[object]]::new()
    $calendarIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    $defaultGroupCalendars = @(Get-GraphCollection -Uri "/v1.0/me/calendars?`$select=$calendarSelect")
    foreach ($calendar in $defaultGroupCalendars) {
        $calendarId = [string] (Get-ObjectPropertyValue -InputObject $calendar -Name 'id')
        if ([string]::IsNullOrWhiteSpace($calendarId) -or $calendarIds.Add($calendarId)) {
            $calendarList.Add($calendar)
        }
    }

    $calendarGroups = @(Get-GraphCollection -Uri '/v1.0/me/calendarGroups?$select=id,name')
    foreach ($calendarGroup in $calendarGroups) {
        $calendarGroupId = [string] (Get-ObjectPropertyValue -InputObject $calendarGroup -Name 'id')
        if ([string]::IsNullOrWhiteSpace($calendarGroupId)) {
            throw 'Microsoft Graph returned a calendar group without an id.'
        }

        $encodedCalendarGroupId = [Uri]::EscapeDataString($calendarGroupId)
        $groupCalendars = @(
            Get-GraphCollection -Uri "/v1.0/me/calendarGroups/$encodedCalendarGroupId/calendars?`$select=$calendarSelect"
        )
        foreach ($calendar in $groupCalendars) {
            $calendarId = [string] (Get-ObjectPropertyValue -InputObject $calendar -Name 'id')
            if ([string]::IsNullOrWhiteSpace($calendarId) -or $calendarIds.Add($calendarId)) {
                $calendarList.Add($calendar)
            }
        }
    }

    return $calendarList.ToArray()
}

function ConvertTo-GraphAccessResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Exception] $Exception
    )

    $statusCode = $null
    $response = Get-ObjectPropertyValue -InputObject $Exception -Name 'Response'
    if ($null -ne $response) {
        $rawStatusCode = Get-ObjectPropertyValue -InputObject $response -Name 'StatusCode'
        if ($null -ne $rawStatusCode) {
            try {
                $statusCode = [int] $rawStatusCode
            }
            catch {
                $statusCode = $null
            }
        }
    }

    $status = switch ($statusCode) {
        401 { 'AccessDenied' }
        403 { 'AccessDenied' }
        404 { 'NotFoundOrExpired' }
        429 { 'Throttled' }
        { $null -ne $_ -and $_ -ge 500 } { 'ServiceError' }
        default { 'Unavailable' }
    }

    return [pscustomobject] [ordered] @{
        Status        = $status
        Message       = $Exception.Message
        StatusCode    = $statusCode
        ExceptionType = $Exception.GetType().FullName
        Items         = @()
    }
}

function Get-NotRequestedResult {
    [CmdletBinding()]
    param()

    return [pscustomobject] [ordered] @{
        Status        = 'NotRequested'
        Message       = 'Artifact lookup was skipped by -SkipArtifacts.'
        StatusCode    = $null
        ExceptionType = $null
        Items         = @()
    }
}

function ConvertTo-ArtifactMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('AttendanceReport', 'Transcript', 'Recording')]
        [string] $ArtifactType,

        [Parameter(Mandatory)]
        [object] $Item,

        [Parameter()]
        [string] $AttendanceCollectionScope = 'OnlineMeetingEndpoint'
    )

    switch ($ArtifactType) {
        'AttendanceReport' {
            return [pscustomobject] [ordered] @{
                Id                    = Get-ObjectPropertyValue -InputObject $Item -Name 'id'
                MeetingStartDateTime  = Get-ObjectPropertyValue -InputObject $Item -Name 'meetingStartDateTime'
                MeetingEndDateTime    = Get-ObjectPropertyValue -InputObject $Item -Name 'meetingEndDateTime'
                TotalParticipantCount = Get-ObjectPropertyValue -InputObject $Item -Name 'totalParticipantCount'
                ExternalEventInformation = @(Get-ObjectPropertyValue -InputObject $Item -Name 'externalEventInformation')
                SourceCollectionScope = $AttendanceCollectionScope
                TargetMeetingAttribution = 'ExpectedForNonChannelMeeting;UnverifiedIfChannelMeeting'
            }
        }
        'Transcript' {
            return [pscustomobject] [ordered] @{
                Id                   = Get-ObjectPropertyValue -InputObject $Item -Name 'id'
                MeetingId            = Get-ObjectPropertyValue -InputObject $Item -Name 'meetingId'
                CallId               = Get-ObjectPropertyValue -InputObject $Item -Name 'callId'
                ContentCorrelationId = Get-ObjectPropertyValue -InputObject $Item -Name 'contentCorrelationId'
                CreatedDateTime      = Get-ObjectPropertyValue -InputObject $Item -Name 'createdDateTime'
                EndDateTime          = Get-ObjectPropertyValue -InputObject $Item -Name 'endDateTime'
                MeetingOrganizer     = Get-ObjectPropertyValue -InputObject $Item -Name 'meetingOrganizer'
                TranscriptContentUrl = Get-ObjectPropertyValue -InputObject $Item -Name 'transcriptContentUrl'
            }
        }
        'Recording' {
            return [pscustomobject] [ordered] @{
                Id                  = Get-ObjectPropertyValue -InputObject $Item -Name 'id'
                MeetingId           = Get-ObjectPropertyValue -InputObject $Item -Name 'meetingId'
                CallId              = Get-ObjectPropertyValue -InputObject $Item -Name 'callId'
                ContentCorrelationId = Get-ObjectPropertyValue -InputObject $Item -Name 'contentCorrelationId'
                CreatedDateTime     = Get-ObjectPropertyValue -InputObject $Item -Name 'createdDateTime'
                EndDateTime         = Get-ObjectPropertyValue -InputObject $Item -Name 'endDateTime'
                MeetingOrganizer    = Get-ObjectPropertyValue -InputObject $Item -Name 'meetingOrganizer'
                RecordingContentUrl = Get-ObjectPropertyValue -InputObject $Item -Name 'recordingContentUrl'
            }
        }
    }
}

function Invoke-ArtifactLookup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('AttendanceReport', 'Transcript', 'Recording')]
        [string] $ArtifactType,

        [Parameter(Mandatory)]
        [string] $Uri,

        [Parameter()]
        [string] $AttendanceCollectionScope = 'OnlineMeetingEndpoint'
    )

    try {
        $rawItems = @(Get-GraphCollection -Uri $Uri)
        $metadataItems = @(
            foreach ($rawItem in $rawItems) {
                ConvertTo-ArtifactMetadata -ArtifactType $ArtifactType -Item $rawItem `
                    -AttendanceCollectionScope $AttendanceCollectionScope
            }
        )

        return [pscustomobject] [ordered] @{
            Status        = if ($metadataItems.Count -gt 0) { 'Available' } else { 'NoData' }
            Message       = if ($ArtifactType -eq 'AttendanceReport') {
                'Microsoft Graph returns at most 50 recent reports. For a channel meeting this collection covers every meeting in the channel, so item attribution to the supplied link is not guaranteed.'
            }
            elseif ($metadataItems.Count -gt 0) {
                'Metadata retrieved. Identity-bearing records and content were not requested.'
            }
            else {
                'No metadata was returned. The artifact may not exist or may not yet be available.'
            }
            StatusCode    = 200
            ExceptionType = $null
            Items         = $metadataItems
        }
    }
    catch {
        return ConvertTo-GraphAccessResult -Exception $_.Exception
    }
}

function Get-ParticipantSummary {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Participants
    )

    $organizer = Get-ObjectPropertyValue -InputObject $Participants -Name 'organizer'
    $organizerUpn = Get-ObjectPropertyValue -InputObject $organizer -Name 'upn'
    $attendees = @(Get-ObjectPropertyValue -InputObject $Participants -Name 'attendees')
    $coOrganizerUpns = [Collections.Generic.List[string]]::new()

    foreach ($attendee in $attendees) {
        if ($null -eq $attendee) {
            continue
        }

        $role = [string] (Get-ObjectPropertyValue -InputObject $attendee -Name 'role')
        if ($role -ieq 'coorganizer') {
            $upn = [string] (Get-ObjectPropertyValue -InputObject $attendee -Name 'upn')
            if (-not [string]::IsNullOrWhiteSpace($upn) -and $upn -notin $coOrganizerUpns) {
                $coOrganizerUpns.Add($upn)
            }
        }
    }

    return [pscustomobject] [ordered] @{
        OrganizerUpn           = $organizerUpn
        CoOrganizerUpns        = $coOrganizerUpns.ToArray()
        ScheduledAttendeeCount = @($attendees | Where-Object { $null -ne $_ }).Count
        IdentityAddressNote    = 'Values come from participants.upn and are not guaranteed to equal primary SMTP addresses. A correlated calendar event can expose the Exchange organizer address.'
        AttendeeIdentityPolicy = 'Non-organizer attendee identities are intentionally omitted from this output.'
    }
}

function ConvertTo-SafeOnlineMeeting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $OnlineMeeting
    )

    $safeMeeting = [ordered] @{}
    foreach ($propertyName in @(Get-ObjectPropertyNames -InputObject $OnlineMeeting)) {
        if ([string] $propertyName -ieq 'participants') {
            $participants = Get-ObjectPropertyValue -InputObject $OnlineMeeting -Name ([string] $propertyName)
            $safeMeeting[[string] $propertyName] = Get-ParticipantSummary -Participants $participants
        }
        elseif ([string] $propertyName -notmatch '^(attendees|attendanceRecords)$') {
            $safeMeeting[[string] $propertyName] = Get-ObjectPropertyValue `
                -InputObject $OnlineMeeting -Name ([string] $propertyName)
        }
    }

    if (-not $safeMeeting.Contains('participants')) {
        $safeMeeting.participants = Get-ParticipantSummary -Participants $null
    }

    return [pscustomobject] $safeMeeting
}

function Get-EventAttendeeSummary {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Attendees
    )

    $typeCounts = [ordered] @{
        Required = 0
        Optional = 0
        Resource = 0
        Other    = 0
    }
    $responseCounts = [ordered] @{
        Accepted             = 0
        TentativelyAccepted  = 0
        Declined             = 0
        NotResponded         = 0
        None                 = 0
        Other                = 0
    }
    $attendeeArray = @($Attendees | Where-Object { $null -ne $_ })

    foreach ($attendee in $attendeeArray) {
        $attendeeType = [string] (Get-ObjectPropertyValue -InputObject $attendee -Name 'type')
        switch -Regex ($attendeeType) {
            '^required$' { $typeCounts.Required++; break }
            '^optional$' { $typeCounts.Optional++; break }
            '^resource$' { $typeCounts.Resource++; break }
            default { $typeCounts.Other++ }
        }

        $statusObject = Get-ObjectPropertyValue -InputObject $attendee -Name 'status'
        $response = [string] (Get-ObjectPropertyValue -InputObject $statusObject -Name 'response')
        switch -Regex ($response) {
            '^accepted$' { $responseCounts.Accepted++; break }
            '^tentativelyAccepted$' { $responseCounts.TentativelyAccepted++; break }
            '^declined$' { $responseCounts.Declined++; break }
            '^notResponded$' { $responseCounts.NotResponded++; break }
            '^none$' { $responseCounts.None++; break }
            default { $responseCounts.Other++ }
        }
    }

    return [pscustomobject] [ordered] @{
        ScheduledAttendeeCount = $attendeeArray.Count
        TypeCounts              = [pscustomobject] $typeCounts
        ResponseCounts          = [pscustomobject] $responseCounts
        AttendeeIdentityPolicy  = 'Attendee names and addresses are intentionally omitted.'
    }
}

function ConvertTo-AttachmentMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Attachment
    )

    return [pscustomobject] [ordered] @{
        AttachmentType      = Get-ObjectPropertyValue -InputObject $Attachment -Name '@odata.type'
        Id                  = Get-ObjectPropertyValue -InputObject $Attachment -Name 'id'
        Name                = Get-ObjectPropertyValue -InputObject $Attachment -Name 'name'
        ContentType         = Get-ObjectPropertyValue -InputObject $Attachment -Name 'contentType'
        Size                = Get-ObjectPropertyValue -InputObject $Attachment -Name 'size'
        IsInline            = Get-ObjectPropertyValue -InputObject $Attachment -Name 'isInline'
        LastModifiedDateTime = Get-ObjectPropertyValue -InputObject $Attachment -Name 'lastModifiedDateTime'
        ContentBytesFetched = $false
    }
}

function Get-AttachmentMetadataResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $EventId,

        [Parameter(Mandatory)]
        [bool] $HasAttachments
    )

    if (-not $HasAttachments) {
        return [pscustomobject] [ordered] @{
            Status        = 'NoData'
            Message       = 'The event reports no attachments.'
            StatusCode    = 200
            ExceptionType = $null
            Items         = @()
        }
    }

    try {
        $encodedEventId = [Uri]::EscapeDataString($EventId)
        $select = [Uri]::EscapeDataString('id,name,contentType,size,isInline,lastModifiedDateTime')
        $uri = "/v1.0/me/events/$encodedEventId/attachments?`$select=$select"
        $attachments = @(Get-GraphCollection -Uri $uri)
        $metadata = @(
            foreach ($attachment in $attachments) {
                ConvertTo-AttachmentMetadata -Attachment $attachment
            }
        )

        return [pscustomobject] [ordered] @{
            Status        = if ($metadata.Count -gt 0) { 'Available' } else { 'NoData' }
            Message       = if ($metadata.Count -gt 0) {
                'Attachment metadata retrieved without content bytes.'
            }
            else {
                'The event indicated attachments, but Microsoft Graph returned no metadata.'
            }
            StatusCode    = 200
            ExceptionType = $null
            Items         = $metadata
        }
    }
    catch {
        return ConvertTo-GraphAccessResult -Exception $_.Exception
    }
}

function ConvertTo-SafeCalendarEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Event,

        [Parameter(Mandatory)]
        [object] $AttachmentMetadata
    )

    $safeEvent = [ordered] @{}
    foreach ($propertyName in @(Get-ObjectPropertyNames -InputObject $Event)) {
        if ([string] $propertyName -ieq 'attendees') {
            $attendees = Get-ObjectPropertyValue -InputObject $Event -Name ([string] $propertyName)
            $safeEvent.AttendeeSummary = Get-EventAttendeeSummary -Attendees $attendees
        }
        else {
            $safeEvent[[string] $propertyName] = Get-ObjectPropertyValue `
                -InputObject $Event -Name ([string] $propertyName)
        }
    }
    if (-not $safeEvent.Contains('AttendeeSummary')) {
        $safeEvent.AttendeeSummary = Get-EventAttendeeSummary -Attendees $null
    }
    $safeEvent.AttachmentMetadata = $AttachmentMetadata

    return [pscustomobject] $safeEvent
}

function Get-CalendarCorrelation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $OnlineMeeting,

        [Parameter(Mandatory)]
        [string] $JoinUrl,

        [Parameter()]
        [switch] $UseExplicitWindow,

        [Parameter()]
        [datetimeoffset] $WindowStartUtc,

        [Parameter()]
        [datetimeoffset] $WindowEndUtc
    )

    $windowSource = if ($UseExplicitWindow) {
        'ExplicitParameters'
    }
    else {
        'OnlineMeetingStartEndPlusOneDay'
    }
    $recurrenceNotice = 'A Teams recurring series can reuse one join URL. Calendar correlation is complete only within the reported search window.'

    if ($UseExplicitWindow) {
        $windowStart = $WindowStartUtc.ToUniversalTime()
        $windowEnd = $WindowEndUtc.ToUniversalTime()
    }
    else {
        $startText = [string] (Get-ObjectPropertyValue -InputObject $OnlineMeeting -Name 'startDateTime')
        $endText = [string] (Get-ObjectPropertyValue -InputObject $OnlineMeeting -Name 'endDateTime')
        $meetingStart = [DateTimeOffset]::MinValue
        $meetingEnd = [DateTimeOffset]::MinValue
        $startValid = [DateTimeOffset]::TryParse(
            $startText,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal,
            [ref] $meetingStart
        )
        $endValid = [DateTimeOffset]::TryParse(
            $endText,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal,
            [ref] $meetingEnd
        )

        if (-not $startValid) {
            return [pscustomobject] [ordered] @{
                Status           = 'Unavailable'
                Message          = 'The onlineMeeting did not contain a parseable startDateTime for calendar correlation. Supply an explicit calendar search window to override it.'
                WindowStartUtc   = $null
                WindowEndUtc     = $null
                WindowSource     = $windowSource
                RecurrenceNotice = $recurrenceNotice
                Calendars        = @()
                Events           = @()
            }
        }
        if (-not $endValid -or $meetingEnd -le $meetingStart) {
            $meetingEnd = $meetingStart.AddHours(1)
        }

        $windowStart = $meetingStart.AddDays(-1).ToUniversalTime()
        $windowEnd = $meetingEnd.AddDays(1).ToUniversalTime()
    }
    try {
        $calendars = @(Get-AllAccessibleCalendars)
    }
    catch {
        $access = ConvertTo-GraphAccessResult -Exception $_.Exception
        return [pscustomobject] [ordered] @{
            Status         = $access.Status
            Message        = "Calendar discovery failed: $($access.Message)"
            WindowStartUtc = $windowStart
            WindowEndUtc   = $windowEnd
            WindowSource   = $windowSource
            RecurrenceNotice = $recurrenceNotice
            Calendars      = @()
            Events         = @()
        }
    }

    $encodedStart = [Uri]::EscapeDataString(
        $windowStart.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    )
    $encodedEnd = [Uri]::EscapeDataString(
        $windowEnd.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    )
    $headers = @{ Prefer = 'outlook.timezone="UTC", include-unknown-enum-members' }
    $calendarAccess = [Collections.Generic.List[object]]::new()
    $matchingEvents = [Collections.Generic.List[object]]::new()
    $successfulCalendars = 0
    $failedCalendars = 0
    $failedAttachmentLookups = 0

    foreach ($calendar in $calendars) {
        $calendarId = [string] (Get-ObjectPropertyValue -InputObject $calendar -Name 'id')
        $calendarName = Get-ObjectPropertyValue -InputObject $calendar -Name 'name'
        if ([string]::IsNullOrWhiteSpace($calendarId)) {
            $failedCalendars++
            $calendarAccess.Add([pscustomobject] [ordered] @{
                CalendarId   = $calendarId
                CalendarName = $calendarName
                Status       = 'Unavailable'
                EventCount   = $null
                MatchCount   = $null
                Message      = 'Microsoft Graph returned a calendar without an id.'
                StatusCode   = $null
            })
            continue
        }

        $encodedCalendarId = [Uri]::EscapeDataString($calendarId)
        $viewUri = "/v1.0/me/calendars/$encodedCalendarId/calendarView" +
            "?startDateTime=$encodedStart&endDateTime=$encodedEnd"

        try {
            $events = @(Get-GraphCollection -Uri $viewUri -Headers $headers)
            $successfulCalendars++
            $calendarMatchCount = 0

            foreach ($event in $events) {
                $eventOnlineMeeting = Get-ObjectPropertyValue -InputObject $event -Name 'onlineMeeting'
                $eventJoinUrl = [string] (Get-ObjectPropertyValue -InputObject $eventOnlineMeeting -Name 'joinUrl')
                $legacyJoinUrl = [string] (Get-ObjectPropertyValue -InputObject $event -Name 'onlineMeetingUrl')
                $isMatch = (Test-MeetingLinkMatch -ExpectedLink $JoinUrl -CandidateLink $eventJoinUrl) -or
                    (Test-MeetingLinkMatch -ExpectedLink $JoinUrl -CandidateLink $legacyJoinUrl)
                if (-not $isMatch) {
                    continue
                }

                $calendarMatchCount++
                $eventId = [string] (Get-ObjectPropertyValue -InputObject $event -Name 'id')
                $hasAttachments = [bool] (Get-ObjectPropertyValue -InputObject $event -Name 'hasAttachments')
                $attachmentResult = if ([string]::IsNullOrWhiteSpace($eventId)) {
                    [pscustomobject] [ordered] @{
                        Status        = 'Unavailable'
                        Message       = 'The correlated event did not include an id.'
                        StatusCode    = $null
                        ExceptionType = $null
                        Items         = @()
                    }
                }
                else {
                    Get-AttachmentMetadataResult -EventId $eventId -HasAttachments $hasAttachments
                }
                if ($attachmentResult.Status -notin @('Available', 'NoData')) {
                    $failedAttachmentLookups++
                }

                $matchingEvents.Add((ConvertTo-SafeCalendarEvent `
                    -Event $event -AttachmentMetadata $attachmentResult))
            }

            $calendarAccess.Add([pscustomobject] [ordered] @{
                CalendarId   = $calendarId
                CalendarName = $calendarName
                Status       = 'Available'
                EventCount   = $events.Count
                MatchCount   = $calendarMatchCount
                Message      = 'Calendar view retrieved and fully paged.'
                StatusCode   = 200
            })
        }
        catch {
            $failedCalendars++
            $access = ConvertTo-GraphAccessResult -Exception $_.Exception
            $calendarAccess.Add([pscustomobject] [ordered] @{
                CalendarId   = $calendarId
                CalendarName = $calendarName
                Status       = $access.Status
                EventCount   = $null
                MatchCount   = $null
                Message      = $access.Message
                StatusCode   = $access.StatusCode
            })
        }
    }

    $overallStatus = if (($failedCalendars -gt 0 -and $successfulCalendars -gt 0) -or
        $failedAttachmentLookups -gt 0) {
        'Partial'
    }
    elseif ($failedCalendars -gt 0) {
        'Unavailable'
    }
    elseif ($matchingEvents.Count -gt 0) {
        'Available'
    }
    else {
        'NoData'
    }
    $message = switch ($overallStatus) {
        'Partial' { 'Some calendar or attachment metadata could not be read; matching results may be incomplete.' }
        'Unavailable' { 'No discovered calendar could be read.' }
        'Available' { 'One or more calendar events matched the Teams join URL.' }
        default { 'Accessible calendars were searched, but no event matched the Teams join URL.' }
    }

    return [pscustomobject] [ordered] @{
        Status         = $overallStatus
        Message        = $message
        WindowStartUtc = $windowStart
        WindowEndUtc   = $windowEnd
        WindowSource   = $windowSource
        RecurrenceNotice = $recurrenceNotice
        Calendars      = $calendarAccess.ToArray()
        Events         = $matchingEvents.ToArray()
    }
}

$scopeList = [Collections.Generic.List[string]]::new()
$scopeList.Add('OnlineMeetings.Read')
$scopeList.Add('Calendars.Read')
if (-not $SkipArtifacts) {
    $scopeList.Add('OnlineMeetingArtifact.Read.All')
    $scopeList.Add('OnlineMeetingTranscript.Read.All')
    $scopeList.Add('OnlineMeetingRecording.Read.All')
}
$requiredScopes = @($scopeList | Select-Object -Unique)

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

try {
    $hasCalendarSearchStart = $PSBoundParameters.ContainsKey('CalendarSearchStartUtc')
    $hasCalendarSearchEnd = $PSBoundParameters.ContainsKey('CalendarSearchEndUtc')
    if ($hasCalendarSearchStart -xor $hasCalendarSearchEnd) {
        throw 'CalendarSearchStartUtc and CalendarSearchEndUtc must be supplied together.'
    }
    if ($hasCalendarSearchStart -and $CalendarSearchEndUtc -le $CalendarSearchStartUtc) {
        throw 'CalendarSearchEndUtc must be later than CalendarSearchStartUtc.'
    }

    $normalizedMeetingLink = ConvertTo-NormalizedMeetingLink -Value $MeetingLink

    Connect-MgGraph @connectParameters | Out-Null
    $connected = $true

    $graphContext = Get-MgContext
    if ($null -eq $graphContext -or $graphContext.AuthType -ne 'Delegated') {
        throw 'Microsoft Graph did not establish a delegated authentication context.'
    }
    if ([string] $graphContext.TenantId -ne $TenantId.Guid) {
        throw "Authenticated to tenant '$($graphContext.TenantId)' instead of '$($TenantId.Guid)'."
    }
    if ([string] $graphContext.ContextScope -ne 'Process') {
        throw "Microsoft Graph used context scope '$($graphContext.ContextScope)' instead of 'Process'."
    }
    if ([string] $graphContext.Environment -ne $Environment) {
        throw "Microsoft Graph used environment '$($graphContext.Environment)' instead of '$Environment'."
    }
    if ($PSBoundParameters.ContainsKey('ClientId') -and
        [string] $graphContext.ClientId -ne $ClientId.Guid) {
        throw "Microsoft Graph used client '$($graphContext.ClientId)' instead of '$($ClientId.Guid)'."
    }
    if ($PSBoundParameters.ContainsKey('ExpectedAccount') -and
        [string] $graphContext.Account -ne $ExpectedAccount.Trim()) {
        throw "Signed in as '$($graphContext.Account)' instead of '$($ExpectedAccount.Trim())'."
    }

    $missingScopes = @(
        $requiredScopes | Where-Object { $_ -notin @($graphContext.Scopes) }
    )
    if ($missingScopes.Count -gt 0) {
        throw "The delegated token is missing required scope(s): $($missingScopes -join ', ')."
    }

    $odataLink = $normalizedMeetingLink.Replace("'", "''")
    $encodedFilter = [Uri]::EscapeDataString("JoinWebUrl eq '$odataLink'")
    $lookupUri = "/v1.0/me/onlineMeetings?`$filter=$encodedFilter"
    $lookupHeaders = @{ Prefer = 'include-unknown-enum-members' }
    $meetings = @(Get-GraphCollection -Uri $lookupUri -Headers $lookupHeaders)

    if ($meetings.Count -eq 0) {
        throw 'No accessible online meeting matched the supplied join URL. The signed-in user must be the organizer or an invited attendee.'
    }
    if ($meetings.Count -gt 1) {
        throw "Microsoft Graph returned $($meetings.Count) meetings for one join URL; refusing to select an ambiguous result."
    }

    $meeting = $meetings[0]
    $meetingId = [string] (Get-ObjectPropertyValue -InputObject $meeting -Name 'id')
    if ([string]::IsNullOrWhiteSpace($meetingId)) {
        throw 'Microsoft Graph returned an online meeting without an id.'
    }
    $encodedMeetingId = [Uri]::EscapeDataString($meetingId)

    $calendarCorrelationParameters = @{
        OnlineMeeting = $meeting
        JoinUrl       = $normalizedMeetingLink
    }
    if ($hasCalendarSearchStart) {
        $calendarCorrelationParameters.UseExplicitWindow = $true
        $calendarCorrelationParameters.WindowStartUtc = $CalendarSearchStartUtc
        $calendarCorrelationParameters.WindowEndUtc = $CalendarSearchEndUtc
    }
    $calendarCorrelation = Get-CalendarCorrelation @calendarCorrelationParameters
    if ($SkipArtifacts) {
        $attendanceResult = Get-NotRequestedResult
        $transcriptResult = Get-NotRequestedResult
        $recordingResult = Get-NotRequestedResult
    }
    else {
        $attendanceResult = Invoke-ArtifactLookup -ArtifactType AttendanceReport `
            -Uri "/v1.0/me/onlineMeetings/$encodedMeetingId/attendanceReports"
        $transcriptResult = Invoke-ArtifactLookup -ArtifactType Transcript `
            -Uri "/v1.0/me/onlineMeetings/$encodedMeetingId/transcripts"
        $recordingResult = Invoke-ArtifactLookup -ArtifactType Recording `
            -Uri "/v1.0/me/onlineMeetings/$encodedMeetingId/recordings"
    }

    [pscustomobject] [ordered] @{
        Query = [pscustomobject] [ordered] @{
            MeetingLink     = $normalizedMeetingLink
            SignedInAccount = [string] $graphContext.Account
            TenantId        = [string] $graphContext.TenantId
            Environment     = [string] $graphContext.Environment
            RequiredScopes  = $requiredScopes
            ArtifactsSkipped = [bool] $SkipArtifacts
        }
        Meeting = ConvertTo-SafeOnlineMeeting -OnlineMeeting $meeting
        CalendarCorrelation = $calendarCorrelation
        ArtifactAccess = [pscustomobject] [ordered] @{
            AttendanceReports = $attendanceResult
            Transcripts       = $transcriptResult
            Recordings        = $recordingResult
        }
        Retrieval = [pscustomobject] [ordered] @{
            RetrievedAtUtc          = [DateTimeOffset]::UtcNow
            AttendeeIdentitiesShown = $false
            AttachmentContentFetched = $false
            ArtifactContentFetched  = $false
        }
    }
}
catch {
    $message = "Teams meeting detail retrieval failed: $($_.Exception.Message)"
    throw [InvalidOperationException]::new($message, $_.Exception)
}
finally {
    if ($connected) {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
}
