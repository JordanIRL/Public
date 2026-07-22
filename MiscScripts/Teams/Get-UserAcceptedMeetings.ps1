<#
.SYNOPSIS
    Retrieves the meetings a user accepted over the last 14 days (Teams meetings by default).

.DESCRIPTION
    Reads the user's calendarView for the window and keeps events whose responseStatus.response is
    'accepted' (i.e. the user actively accepted the invite). Use -IncludeOrganized to also include
    meetings the user organized, and -IncludeAllAccepted to include accepted non-Teams meetings.

    Graph scope (delegated): Calendars.Read. To read another user's calendar the signed-in admin needs
    delegated/full-access rights to that mailbox.

.PARAMETER UserEmail
    UPN/SMTP of the user.

.EXAMPLE
    ./Get-UserAcceptedMeetings.ps1 -UserEmail jane@contoso.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$UserEmail,
    [int]$DaysBack = 14,
    [switch]$IncludeOrganized,
    [switch]$IncludeAllAccepted,
    [string]$TimeZone = 'UTC'
)

. "$PSScriptRoot/../Common/GraphCommon.ps1"
Connect-GraphSession -Scopes @('Calendars.Read')

$startUtc = (Get-Date).ToUniversalTime().AddDays(-$DaysBack)
$endUtc = (Get-Date).ToUniversalTime()
$s = $startUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
$e = $endUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')

$select = 'id,subject,start,end,organizer,attendees,isOnlineMeeting,onlineMeetingProvider,onlineMeeting,responseStatus,isCancelled,location,webLink'
$enc = [uri]::EscapeDataString($UserEmail)
$uri = "/v1.0/users/$enc/calendarView?startDateTime=$s&endDateTime=$e&`$select=$select&`$orderby=start/dateTime&`$top=100"
$headers = @{ Prefer = "outlook.timezone=`"$TimeZone`"" }

Write-Section "Accepted meetings for $UserEmail (last $DaysBack days)"

$events = Invoke-GraphPaged -Uri $uri -Headers $headers

$wanted = if ($IncludeOrganized) { @('accepted', 'organizer') } else { @('accepted') }

$meetings = foreach ($ev in $events) {
    if ($ev.responseStatus.response -notin $wanted) { continue }
    if (-not $IncludeAllAccepted -and -not $ev.isOnlineMeeting) { continue }
    [pscustomobject]@{
        Start          = $ev.start.dateTime
        End            = $ev.end.dateTime
        Subject        = $ev.subject
        Organizer      = $ev.organizer.emailAddress.address
        Response       = $ev.responseStatus.response
        RespondedTime  = $ev.responseStatus.time
        IsOnline       = $ev.isOnlineMeeting
        Provider       = $ev.onlineMeetingProvider
        AttendeeCount  = @($ev.attendees).Count
        IsCancelled    = $ev.isCancelled
        JoinUrl        = $ev.onlineMeeting.joinUrl
        Location       = $ev.location.displayName
        WebLink        = $ev.webLink
        EventId        = $ev.id
    }
}

if (-not $meetings) {
    Write-Host "No accepted meetings found in the window." -ForegroundColor Yellow
    return
}

$meetings | Select-Object Start, End, Subject, Organizer, Response, Provider, AttendeeCount |
    Format-Table -AutoSize
Write-Host ("Accepted meetings: {0}" -f $meetings.Count) -ForegroundColor Green
$meetings
