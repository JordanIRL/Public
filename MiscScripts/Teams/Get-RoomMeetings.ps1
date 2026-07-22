<#
.SYNOPSIS
    Retrieves the last 14 and next 14 days of calendar meetings for a Teams Room (or any mailbox),
    with full detail per meeting.

.DESCRIPTION
    Reads the room mailbox calendar with a calendarView, so recurring meetings are expanded into
    individual occurrences within the window. Returns rich per-meeting objects and prints a summary.

    Graph scopes (delegated): Calendars.Read, User.Read.All  (the signed-in admin needs read access to
    the room mailbox).

.PARAMETER RoomEmail
    SMTP/UPN of the Teams Room resource mailbox (e.g. room-boardroom@contoso.com).

.PARAMETER DaysBack / DaysForward
    Size of the window. Defaults: 14 back, 14 forward.

.PARAMETER TimeZone
    Windows time-zone id for displayed start/end times (e.g. "GMT Standard Time"). Default UTC.

.EXAMPLE
    ./Get-RoomMeetings.ps1 -RoomEmail room-boardroom@contoso.com

.EXAMPLE
    ./Get-RoomMeetings.ps1 -RoomEmail room1@contoso.com -TimeZone "GMT Standard Time"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RoomEmail,
    [int]$DaysBack = 14,
    [int]$DaysForward = 14,
    [string]$TimeZone = 'UTC'
)

. "$PSScriptRoot/../Common/GraphCommon.ps1"
Connect-GraphSession -Scopes @('Calendars.Read', 'User.Read.All')

$startUtc = (Get-Date).ToUniversalTime().AddDays(-$DaysBack)
$endUtc = (Get-Date).ToUniversalTime().AddDays($DaysForward)
$s = $startUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
$e = $endUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')

$select = @(
    'id', 'subject', 'start', 'end', 'isAllDay', 'isCancelled', 'showAs', 'sensitivity', 'importance',
    'organizer', 'attendees', 'location', 'locations', 'isOnlineMeeting', 'onlineMeetingProvider',
    'onlineMeeting', 'onlineMeetingUrl', 'seriesMasterId', 'type', 'recurrence', 'categories',
    'responseStatus', 'webLink', 'bodyPreview'
    # Note: createdDateTime/lastModifiedDateTime are intentionally omitted - calendarView does not
    # support them under $select (they would always come back null).
) -join ','

$enc = [uri]::EscapeDataString($RoomEmail)
$uri = "/v1.0/users/$enc/calendarView?startDateTime=$s&endDateTime=$e&`$select=$select&`$orderby=start/dateTime&`$top=100"
$headers = @{ Prefer = "outlook.timezone=`"$TimeZone`"" }

Write-Section "Meetings for $RoomEmail  ($($startUtc.ToString('yyyy-MM-dd')) -> $($endUtc.ToString('yyyy-MM-dd')) UTC)"

try {
    $events = Invoke-GraphPaged -Uri $uri -Headers $headers
} catch {
    throw "Failed to read calendar for '$RoomEmail'. Confirm the mailbox exists and the identity has Calendars.Read. $_"
}

$meetings = foreach ($ev in $events) {
    $required = @($ev.attendees | Where-Object { $_.type -eq 'required' }).Count
    $optional = @($ev.attendees | Where-Object { $_.type -eq 'optional' }).Count
    [pscustomobject]@{
        Subject          = $ev.subject
        Start            = $ev.start.dateTime
        End              = $ev.end.dateTime
        TimeZone         = $ev.start.timeZone
        Type             = $ev.type                       # singleInstance / occurrence / exception / seriesMaster
        IsAllDay         = $ev.isAllDay
        IsCancelled      = $ev.isCancelled
        ShowAs           = $ev.showAs
        Organizer        = $ev.organizer.emailAddress.address
        OrganizerName    = $ev.organizer.emailAddress.name
        AttendeeCount    = @($ev.attendees).Count
        Required         = $required
        Optional         = $optional
        RoomResponse     = $ev.responseStatus.response    # how the room replied (accepted/declined/...)
        IsOnlineMeeting  = $ev.isOnlineMeeting
        OnlineProvider   = $ev.onlineMeetingProvider
        JoinUrl          = $ev.onlineMeeting.joinUrl
        Location         = $ev.location.displayName
        Sensitivity      = $ev.sensitivity
        Importance       = $ev.importance
        Categories       = ($ev.categories -join '; ')
        Preview          = $ev.bodyPreview
        WebLink          = $ev.webLink
        EventId          = $ev.id
    }
}

if (-not $meetings) {
    Write-Host "No meetings found in the window." -ForegroundColor Yellow
    return
}

$meetings |
    Select-Object Start, End, Subject, Organizer, AttendeeCount, RoomResponse, IsOnlineMeeting, IsCancelled |
    Format-Table -AutoSize

Write-Host ("Total occurrences: {0}  |  Online: {1}  |  Cancelled: {2}" -f `
    $meetings.Count,
    (@($meetings | Where-Object IsOnlineMeeting).Count),
    (@($meetings | Where-Object IsCancelled).Count)) -ForegroundColor Green

# Emit full objects to the pipeline for export, e.g.  ... | Export-Csv rooms.csv -NoTypeInformation
$meetings
