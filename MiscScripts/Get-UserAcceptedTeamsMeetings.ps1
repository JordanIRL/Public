#requires -Version 7.0
#requires -Modules Microsoft.Graph.Authentication

<#
.SYNOPSIS
    Retrieves Microsoft Teams meetings a user accepted during the preceding 14 days.

.DESCRIPTION
    Signs in to Microsoft Graph with delegated permissions, reads the target user's calendar
    view, and returns non-cancelled Teams meetings whose current event response is accepted.
    By default, the target user's primary calendar is scanned and fully paged. CalendarSelection
    All is available only when the target resolves to the signed-in user; foreign/shared calendars
    in that user's calendar collection are excluded by owner identity.

    "Accepted" is based on event.responseStatus.response. It does not prove the user attended
    the meeting. Tentative responses are excluded unless IncludeTentativelyAccepted is supplied.
    Organizer-owned events have the response value "organizer" and are not classified as
    accepted meetings.

    Delegated access to another user's calendar requires Exchange calendar sharing or delegate
    access. A Microsoft Entra administrator role alone does not grant mailbox access. Use
    UseSharedCalendarAccess only after the signed-in account has that resource authorization.
    Attendee collections are not requested or returned.

.PARAMETER TenantId
    Microsoft Entra tenant GUID to authenticate against.

.PARAMETER UserEmail
    User principal name or primary mail address whose calendar is queried. Without
    UseSharedCalendarAccess, it must resolve to the delegated sign-in account.

.PARAMETER DaysBack
    Number of complete 24-hour periods before retrieval time to include. The default is 14.

.PARAMETER IncludeTentativelyAccepted
    Include Teams meetings whose response is tentativelyAccepted as well as accepted.

.PARAMETER CalendarSelection
    Primary scans the target user's primary calendar and is the default. All scans only calendars
    owned by the target and is supported only when the target is the signed-in user.

.PARAMETER UseSharedCalendarAccess
    Request Calendars.Read.Shared and User.ReadBasic.All, and allow UserEmail to differ from the
    signed-in account. Only the target's primary calendar is supported for another user. That
    calendar must already be shared with, or delegated to, the signed-in account.

.PARAMETER Environment
    Microsoft Graph cloud environment.

.PARAMETER ClientId
    Optional application ID for an approved public-client app registration.

.PARAMETER ExpectedAccount
    Optional user principal name that must match the delegated sign-in account.

.PARAMETER UseDeviceCode
    Use delegated device-code authentication instead of an interactive browser prompt.

.OUTPUTS
    PSCustomObject containing Query, CalendarAccess, Meetings, and Retrieval properties.

.EXAMPLE
    ./Get-UserAcceptedTeamsMeetings.ps1 `
        -TenantId '00000000-0000-0000-0000-000000000000' `
        -UserEmail 'alex@contoso.com' -ExpectedAccount 'alex@contoso.com'

.EXAMPLE
    ./Get-UserAcceptedTeamsMeetings.ps1 `
        -TenantId '00000000-0000-0000-0000-000000000000' `
        -UserEmail 'casey@contoso.com' -ExpectedAccount 'calendar.admin@contoso.com' `
        -UseSharedCalendarAccess -CalendarSelection Primary -UseDeviceCode

.NOTES
    Delegated scopes for the signed-in user's calendars: Calendars.ReadBasic and User.Read.
    Delegated scopes for shared or delegated calendars: Calendars.Read.Shared and
    User.ReadBasic.All.
    Calendar sharing and delegate rights are Exchange resource authorization and must exist in
    addition to Microsoft Graph consent.
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
            throw 'UserEmail must not be empty or whitespace.'
        }
        try {
            $parsedAddress = [Net.Mail.MailAddress]::new($_.Trim())
            if ($parsedAddress.Address -ne $_.Trim()) {
                throw 'The normalized address differs from the supplied value.'
            }
        }
        catch {
            throw "UserEmail must be a valid email-style user principal name: $($_.Exception.Message)"
        }
        $true
    })]
    [string] $UserEmail,

    [Parameter()]
    [ValidateRange(1, 366)]
    [int] $DaysBack = 14,

    [Parameter()]
    [switch] $IncludeTentativelyAccepted,

    [Parameter()]
    [ValidateSet('All', 'Primary')]
    [string] $CalendarSelection = 'Primary',

    [Parameter()]
    [switch] $UseSharedCalendarAccess,

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

    $calendarSelect = 'id,name,isDefaultCalendar,owner,canViewPrivateItems'
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

function ConvertTo-CalendarAccessResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Calendar,

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
        404 { 'NotFound' }
        429 { 'Throttled' }
        { $null -ne $_ -and $_ -ge 500 } { 'ServiceError' }
        default { 'Unavailable' }
    }

    return [pscustomobject] [ordered] @{
        CalendarId    = Get-ObjectPropertyValue -InputObject $Calendar -Name 'id'
        CalendarName  = Get-ObjectPropertyValue -InputObject $Calendar -Name 'name'
        CalendarOwner = Get-ObjectPropertyValue -InputObject $Calendar -Name 'owner'
        IsDefault     = Get-ObjectPropertyValue -InputObject $Calendar -Name 'isDefaultCalendar'
        Status        = $status
        EventCount    = $null
        Message       = $Exception.Message
        StatusCode    = $statusCode
        ExceptionType = $Exception.GetType().FullName
    }
}

function Test-TeamsEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Event
    )

    $isOnlineMeeting = [bool] (Get-ObjectPropertyValue -InputObject $Event -Name 'isOnlineMeeting')
    if (-not $isOnlineMeeting) {
        return $false
    }

    $provider = [string] (Get-ObjectPropertyValue -InputObject $Event -Name 'onlineMeetingProvider')
    if ($provider -ieq 'teamsForBusiness') {
        return $true
    }

    $onlineMeeting = Get-ObjectPropertyValue -InputObject $Event -Name 'onlineMeeting'
    $joinUrl = [string] (Get-ObjectPropertyValue -InputObject $onlineMeeting -Name 'joinUrl')
    return $joinUrl -match '^https://(teams\.microsoft\.com|teams\.cloud\.microsoft|teams\.live\.com)/'
}

function ConvertTo-AcceptedMeetingRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $Event,

        [Parameter(Mandatory)]
        [object] $Calendar
    )

    $organizer = Get-ObjectPropertyValue -InputObject $Event -Name 'organizer'
    $organizerAddress = Get-ObjectPropertyValue -InputObject $organizer -Name 'emailAddress'
    $responseStatus = Get-ObjectPropertyValue -InputObject $Event -Name 'responseStatus'
    $start = Get-ObjectPropertyValue -InputObject $Event -Name 'start'
    $end = Get-ObjectPropertyValue -InputObject $Event -Name 'end'

    return [pscustomobject] [ordered] @{
        CalendarId              = Get-ObjectPropertyValue -InputObject $Calendar -Name 'id'
        CalendarName            = Get-ObjectPropertyValue -InputObject $Calendar -Name 'name'
        CalendarOwner           = Get-ObjectPropertyValue -InputObject $Calendar -Name 'owner'
        IsDefaultCalendar       = Get-ObjectPropertyValue -InputObject $Calendar -Name 'isDefaultCalendar'
        EventId                 = Get-ObjectPropertyValue -InputObject $Event -Name 'id'
        ICalUId                 = Get-ObjectPropertyValue -InputObject $Event -Name 'iCalUId'
        Subject                 = Get-ObjectPropertyValue -InputObject $Event -Name 'subject'
        StartDateTime           = Get-ObjectPropertyValue -InputObject $start -Name 'dateTime'
        StartTimeZone           = Get-ObjectPropertyValue -InputObject $start -Name 'timeZone'
        EndDateTime             = Get-ObjectPropertyValue -InputObject $end -Name 'dateTime'
        EndTimeZone             = Get-ObjectPropertyValue -InputObject $end -Name 'timeZone'
        IsAllDay                = Get-ObjectPropertyValue -InputObject $Event -Name 'isAllDay'
        OriginalStart           = Get-ObjectPropertyValue -InputObject $Event -Name 'originalStart'
        OriginalStartTimeZone   = Get-ObjectPropertyValue -InputObject $Event -Name 'originalStartTimeZone'
        OriginalEndTimeZone     = Get-ObjectPropertyValue -InputObject $Event -Name 'originalEndTimeZone'
        EventType               = Get-ObjectPropertyValue -InputObject $Event -Name 'type'
        SeriesMasterId          = Get-ObjectPropertyValue -InputObject $Event -Name 'seriesMasterId'
        OrganizerName           = Get-ObjectPropertyValue -InputObject $organizerAddress -Name 'name'
        OrganizerEmail          = Get-ObjectPropertyValue -InputObject $organizerAddress -Name 'address'
        Response                = Get-ObjectPropertyValue -InputObject $responseStatus -Name 'response'
        ResponseTime            = Get-ObjectPropertyValue -InputObject $responseStatus -Name 'time'
        OnlineMeetingProvider   = Get-ObjectPropertyValue -InputObject $Event -Name 'onlineMeetingProvider'
        OnlineMeeting           = Get-ObjectPropertyValue -InputObject $Event -Name 'onlineMeeting'
        WebLink                 = Get-ObjectPropertyValue -InputObject $Event -Name 'webLink'
        Location                = Get-ObjectPropertyValue -InputObject $Event -Name 'location'
        Locations               = Get-ObjectPropertyValue -InputObject $Event -Name 'locations'
        ShowAs                  = Get-ObjectPropertyValue -InputObject $Event -Name 'showAs'
        Importance              = Get-ObjectPropertyValue -InputObject $Event -Name 'importance'
        Sensitivity             = Get-ObjectPropertyValue -InputObject $Event -Name 'sensitivity'
        Categories              = @(Get-ObjectPropertyValue -InputObject $Event -Name 'categories')
        HasAttachments          = Get-ObjectPropertyValue -InputObject $Event -Name 'hasAttachments'
        Recurrence              = Get-ObjectPropertyValue -InputObject $Event -Name 'recurrence'
        ResponseRequested       = Get-ObjectPropertyValue -InputObject $Event -Name 'responseRequested'
        AllowNewTimeProposals   = Get-ObjectPropertyValue -InputObject $Event -Name 'allowNewTimeProposals'
        HideAttendees           = Get-ObjectPropertyValue -InputObject $Event -Name 'hideAttendees'
        AttendeeIdentitiesShown = $false
    }
}

$targetUser = $UserEmail.Trim()
$requiredScopes = if ($UseSharedCalendarAccess) {
    @('Calendars.Read.Shared', 'User.ReadBasic.All')
}
else {
    @('Calendars.ReadBasic', 'User.Read')
}

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

    $targetUserRecord = if ($UseSharedCalendarAccess) {
        $escapedTarget = $targetUser.Replace("'", "''")
        $encodedFilter = [Uri]::EscapeDataString("userPrincipalName eq '$escapedTarget' or mail eq '$escapedTarget'")
        $matchingUsers = @(
            Get-GraphCollection -Uri "/v1.0/users?`$filter=$encodedFilter&`$select=id,displayName,userPrincipalName,mail"
        )
        if ($matchingUsers.Count -eq 0) {
            throw "No Microsoft Entra user matched UserEmail '$targetUser' as a userPrincipalName or primary mail address."
        }
        if ($matchingUsers.Count -gt 1) {
            throw "UserEmail '$targetUser' matched $($matchingUsers.Count) Microsoft Entra users; refusing an ambiguous calendar query."
        }
        $matchingUsers[0]
    }
    else {
        Invoke-MgGraphRequest -Method GET -Uri '/v1.0/me?$select=id,displayName,userPrincipalName,mail' -OutputType PSObject -ErrorAction Stop
    }

    $targetUserId = [string] (Get-ObjectPropertyValue -InputObject $targetUserRecord -Name 'id')
    $targetUserPrincipalName = [string] (Get-ObjectPropertyValue -InputObject $targetUserRecord -Name 'userPrincipalName')
    $targetPrimaryMail = [string] (Get-ObjectPropertyValue -InputObject $targetUserRecord -Name 'mail')
    if ([string]::IsNullOrWhiteSpace($targetUserId) -or [string]::IsNullOrWhiteSpace($targetUserPrincipalName)) {
        throw "Microsoft Graph returned an incomplete user identity for '$targetUser'."
    }

    $inputMatchesResolvedUser = (Test-StringEqual -Left $targetUser -Right $targetUserPrincipalName) -or
        (Test-StringEqual -Left $targetUser -Right $targetPrimaryMail)
    if (-not $inputMatchesResolvedUser) {
        throw "UserEmail '$targetUser' does not match the resolved user's userPrincipalName or primary mail address."
    }

    $isTargetSignedInUser = (Test-StringEqual -Left $graphContext.Account -Right $targetUserPrincipalName) -or
        (Test-StringEqual -Left $graphContext.Account -Right $targetPrimaryMail)
    if (-not $UseSharedCalendarAccess -and -not $isTargetSignedInUser) {
        throw "Signed in as '$($graphContext.Account)', but UserEmail resolved to '$targetUserPrincipalName'. Sign in as the target user or use -UseSharedCalendarAccess after Exchange sharing or delegation is configured."
    }
    if ($CalendarSelection -eq 'All' -and -not $isTargetSignedInUser) {
        throw 'CalendarSelection All is supported only for the signed-in user. For another user, share or delegate the primary calendar and use CalendarSelection Primary.'
    }

    $rangeEnd = [DateTimeOffset]::UtcNow
    $rangeStart = $rangeEnd.AddDays(-$DaysBack)
    $encodedUser = [Uri]::EscapeDataString($targetUserId)
    $calendarHeaders = @{ Prefer = 'outlook.timezone="UTC"' }

    $calendars = if ($CalendarSelection -eq 'Primary') {
        @(
            [pscustomobject] [ordered] @{
                id                = $null
                name              = 'Primary calendar'
                isDefaultCalendar = $true
                owner             = [pscustomobject] @{ address = $targetUserPrincipalName }
                canViewPrivateItems = $null
            }
        )
    }
    else {
        $discoveredCalendars = @(Get-AllAccessibleCalendars)
        @($discoveredCalendars | Where-Object {
            $calendarOwner = Get-ObjectPropertyValue -InputObject $_ -Name 'owner'
            $calendarOwnerAddress = [string] (Get-ObjectPropertyValue -InputObject $calendarOwner -Name 'address')
            (Test-StringEqual -Left $calendarOwnerAddress -Right $targetUserPrincipalName) -or
                (Test-StringEqual -Left $calendarOwnerAddress -Right $targetPrimaryMail) -or
                ([string]::IsNullOrWhiteSpace($calendarOwnerAddress) -and
                    [bool] (Get-ObjectPropertyValue -InputObject $_ -Name 'isDefaultCalendar'))
        })
    }

    if ($calendars.Count -eq 0) {
        throw "Microsoft Graph returned no calendars for '$targetUser'."
    }

    $selectProperties = @(
        'id', 'iCalUId', 'subject', 'start', 'end', 'isAllDay', 'originalStart', 'originalStartTimeZone',
        'originalEndTimeZone', 'organizer', 'responseStatus', 'isOnlineMeeting',
        'onlineMeetingProvider', 'onlineMeeting', 'isCancelled', 'type', 'seriesMasterId',
        'webLink', 'location', 'locations', 'showAs', 'importance', 'sensitivity',
        'categories', 'hasAttachments', 'recurrence', 'responseRequested',
        'allowNewTimeProposals', 'hideAttendees'
    ) -join ','
    $encodedStart = [Uri]::EscapeDataString($rangeStart.ToString('o', [Globalization.CultureInfo]::InvariantCulture))
    $encodedEnd = [Uri]::EscapeDataString($rangeEnd.ToString('o', [Globalization.CultureInfo]::InvariantCulture))
    $encodedSelect = [Uri]::EscapeDataString($selectProperties)

    $meetingRecords = [Collections.Generic.List[object]]::new()
    $calendarAccess = [Collections.Generic.List[object]]::new()
    $successfulCalendarCount = 0
    $firstCalendarException = $null

    foreach ($calendar in $calendars) {
        $calendarId = [string] (Get-ObjectPropertyValue -InputObject $calendar -Name 'id')
        $viewPath = if ([string]::IsNullOrWhiteSpace($calendarId)) {
            "/v1.0/users/$encodedUser/calendarView"
        }
        else {
            $encodedCalendarId = [Uri]::EscapeDataString($calendarId)
            "/v1.0/users/$encodedUser/calendars/$encodedCalendarId/calendarView"
        }
        $viewUri = "$viewPath`?startDateTime=$encodedStart&endDateTime=$encodedEnd&`$select=$encodedSelect"

        try {
            $events = @(Get-GraphCollection -Uri $viewUri -Headers $calendarHeaders)
            $successfulCalendarCount++
            $calendarAccess.Add([pscustomobject] [ordered] @{
                CalendarId    = Get-ObjectPropertyValue -InputObject $calendar -Name 'id'
                CalendarName  = Get-ObjectPropertyValue -InputObject $calendar -Name 'name'
                CalendarOwner = Get-ObjectPropertyValue -InputObject $calendar -Name 'owner'
                IsDefault     = Get-ObjectPropertyValue -InputObject $calendar -Name 'isDefaultCalendar'
                Status        = 'Available'
                EventCount    = $events.Count
                Message       = 'Calendar view retrieved and fully paged.'
                StatusCode    = 200
                ExceptionType = $null
            })

            foreach ($event in $events) {
                if ([bool] (Get-ObjectPropertyValue -InputObject $event -Name 'isCancelled')) {
                    continue
                }
                if (-not (Test-TeamsEvent -Event $event)) {
                    continue
                }

                $responseStatus = Get-ObjectPropertyValue -InputObject $event -Name 'responseStatus'
                $response = [string] (Get-ObjectPropertyValue -InputObject $responseStatus -Name 'response')
                $accepted = $response -ieq 'accepted' -or
                    ($IncludeTentativelyAccepted -and $response -ieq 'tentativelyAccepted')
                if (-not $accepted) {
                    continue
                }

                $meetingRecords.Add((ConvertTo-AcceptedMeetingRecord -Event $event -Calendar $calendar))
            }
        }
        catch {
            if ($null -eq $firstCalendarException) {
                $firstCalendarException = $_.Exception
            }
            $calendarAccess.Add((ConvertTo-CalendarAccessResult -Calendar $calendar -Exception $_.Exception))
        }
    }

    if ($successfulCalendarCount -eq 0) {
        throw [InvalidOperationException]::new(
            "Microsoft Graph could not read any selected calendar for '$targetUser'.",
            $firstCalendarException
        )
    }

    $sortedMeetings = @($meetingRecords.ToArray() | Sort-Object StartDateTime, Subject, EventId)
    [pscustomobject] [ordered] @{
        Query = [pscustomobject] [ordered] @{
            UserEmail                  = $targetUser
            ResolvedUserId             = $targetUserId
            ResolvedUserPrincipalName  = $targetUserPrincipalName
            ResolvedPrimaryMail        = $targetPrimaryMail
            RangeStartUtc              = $rangeStart
            RangeEndUtc                = $rangeEnd
            DaysBack                   = $DaysBack
            CalendarSelection          = $CalendarSelection
            IncludedResponses          = if ($IncludeTentativelyAccepted) {
                @('accepted', 'tentativelyAccepted')
            }
            else {
                @('accepted')
            }
            SignedInAccount            = [string] $graphContext.Account
            SharedCalendarAccess       = [bool] $UseSharedCalendarAccess
            RequiredScopes             = $requiredScopes
        }
        CalendarAccess = $calendarAccess.ToArray()
        Meetings = $sortedMeetings
        Retrieval = [pscustomobject] [ordered] @{
            RetrievedAtUtc             = [DateTimeOffset]::UtcNow
            CalendarsSucceeded         = $successfulCalendarCount
            CalendarsFailed            = $calendars.Count - $successfulCalendarCount
            MeetingCount               = $sortedMeetings.Count
            AcceptanceMeansAttendance  = $false
            AttendeeIdentitiesShown     = $false
        }
    }
}
catch {
    $message = "Accepted Teams meeting retrieval failed: $($_.Exception.Message)"
    throw [InvalidOperationException]::new($message, $_.Exception)
}
finally {
    if ($connected) {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
}
