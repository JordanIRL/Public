<#
.SYNOPSIS
    Given a Teams meeting join link, returns details about the meeting by reading the ORGANIZER'S
    calendar event (delegated auth - works for meetings you are not part of). Reports the number of
    attendees and the organizer's email.

.DESCRIPTION
    The Teams onlineMeeting object (co-organizers, lobby, dial-in) is per-mailbox and cannot be read
    for other people's meetings with delegated auth. This script instead:
      1. Parses the organizer's object id (Oid) from the link's context (override with -OrganizerId).
      2. Parses the meeting thread id (19:meeting_...@thread.v2) from the link.
      3. Reads the organizer's calendar over a window and matches the event whose onlineMeeting join
         URL contains that thread id.

    Requirements (delegated): Calendars.Read + User.Read.All. Because this reads ANOTHER user's
    calendar, the signed-in admin must have access to the organizer's mailbox. Grant it once in
    Exchange Online, e.g.:
        Add-MailboxPermission -Identity <organizer> -User <you> -AccessRights FullAccess -AutoMapping:$false

    LIMITATION: a calendar event does not flag co-organizers - they appear as ordinary attendees. Use
    -ShowAttendees to dump the invitee list (name/email/type) so you can eyeball likely co-organizers.
    True co-organizer role data requires the app-only onlineMeeting API.

.PARAMETER MeetingLink   The raw Teams join URL. Paste the real link, not a Safe-Links wrapped one.
.PARAMETER OrganizerId   Object id or UPN of the organizer, if the link has no context.
.PARAMETER DaysBack/DaysForward  Calendar search window around today (default 90/90).
.PARAMETER SubjectLike   Optional wildcard to narrow the search (e.g. "*Budget*").
.PARAMETER ShowAttendees Dump the invitee list (name, email, type, response).

.EXAMPLE
    ./Get-MeetingByLink.ps1 -MeetingLink 'https://teams.microsoft.com/l/meetup-join/19%3ameeting_xxx%40thread.v2/0?context=...'

.EXAMPLE
    ./Get-MeetingByLink.ps1 -MeetingLink '<link>' -DaysBack 30 -DaysForward 30 -ShowAttendees
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$MeetingLink,
    [string]$OrganizerId,
    [int]$DaysBack = 90,
    [int]$DaysForward = 90,
    [string]$SubjectLike,
    [switch]$ShowAttendees,
    [string]$TimeZone = 'UTC'
)

. "$PSScriptRoot/../Common/GraphCommon.ps1"
Connect-GraphSession -Scopes @('Calendars.Read', 'User.Read.All')

$link = $MeetingLink.Trim()
$decoded = [uri]::UnescapeDataString($link)

# Organizer id: from the link's context unless overridden.
$tid = $null
if (-not $OrganizerId) {
    if ($link -match 'context=([^&\s]+)') {
        try {
            $ctx = [uri]::UnescapeDataString($Matches[1]) | ConvertFrom-Json
            $OrganizerId = $ctx.Oid
            $tid = $ctx.Tid
        } catch { }
    }
    if (-not $OrganizerId) { throw "Could not find the organizer id in the link. Re-run with -OrganizerId <upn-or-objectid>." }
}

# Meeting thread id, used to match the calendar event's join URL.
$threadId = $null
if ($decoded -match '(19:meeting_[A-Za-z0-9_\-]+@thread\.v2)') { $threadId = $Matches[1] }
if (-not $threadId) {
    Write-Warning "Could not parse a meeting thread id from the link; will match on the full join URL instead."
}

$organizer = Resolve-GraphUserId -User $OrganizerId
Write-Section "Teams meeting lookup (via organizer's calendar)"
Write-Host ("Organizer (from link) : {0} <{1}>" -f $organizer.DisplayName, $organizer.UserPrincipalName)
if ($tid) { Write-Host ("Tenant in link        : {0}" -f $tid) }

$startUtc = (Get-Date).ToUniversalTime().AddDays(-$DaysBack)
$endUtc = (Get-Date).ToUniversalTime().AddDays($DaysForward)
$s = $startUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
$e = $endUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
$select = 'id,subject,start,end,organizer,attendees,location,isOnlineMeeting,onlineMeetingProvider,onlineMeeting,isCancelled,type,seriesMasterId,recurrence,sensitivity,webLink,bodyPreview'
$enc = [uri]::EscapeDataString($organizer.UserPrincipalName)
$uri = "/v1.0/users/$enc/calendarView?startDateTime=$s&endDateTime=$e&`$select=$select&`$orderby=start/dateTime&`$top=100"
$headers = @{ Prefer = "outlook.timezone=`"$TimeZone`"" }

try {
    $events = Invoke-GraphPaged -Uri $uri -Headers $headers
} catch {
    throw "Could not read $($organizer.UserPrincipalName)'s calendar. With delegated auth you need read access to that mailbox (e.g. Add-MailboxPermission ... -AccessRights FullAccess). $_"
}

$hits = foreach ($ev in $events) {
    if ($SubjectLike -and $ev.subject -notlike $SubjectLike) { continue }
    $join = $ev.onlineMeeting.joinUrl
    if (-not $join) { continue }
    $joinDecoded = [uri]::UnescapeDataString($join)
    $isHit = if ($threadId) { $joinDecoded -like "*$threadId*" } else { $joinDecoded -eq $decoded -or $join -eq $link }
    if ($isHit) { $ev }
}

if (-not $hits) {
    Write-Warning @"
No calendar event matched that link on $($organizer.UserPrincipalName) within the last $DaysBack / next $DaysForward days.
Try:
  * widening the window (-DaysBack / -DaysForward),
  * confirming you have read access to the organizer's mailbox,
  * or checking the link is the raw Teams join URL.
"@
    return
}

# A recurring series expands into multiple occurrences that share the same join URL - report once.
$first = $hits | Select-Object -First 1
$att = @($first.attendees)
$required = @($att | Where-Object { $_.type -eq 'required' })
$optional = @($att | Where-Object { $_.type -eq 'optional' })
$resource = @($att | Where-Object { $_.type -eq 'resource' })
$accepted = @($att | Where-Object { $_.status.response -eq 'accepted' })

$detail = [pscustomobject]@{
    Subject            = $first.subject
    Start              = $first.start.dateTime
    End                = $first.end.dateTime
    TimeZone           = $first.start.timeZone
    OrganizerEmail     = $first.organizer.emailAddress.address
    OrganizerName      = $first.organizer.emailAddress.name
    AttendeeCount      = $att.Count
    Required           = $required.Count
    Optional           = $optional.Count
    Resource           = $resource.Count
    AcceptedCount      = $accepted.Count
    IsOnlineMeeting    = $first.isOnlineMeeting
    OnlineProvider     = $first.onlineMeetingProvider
    JoinUrl            = $first.onlineMeeting.joinUrl
    Location           = $first.location.displayName
    IsCancelled        = $first.isCancelled
    IsRecurring        = [bool]$first.seriesMasterId -or ($first.type -in 'occurrence', 'seriesMaster', 'exception')
    OccurrencesInWindow= @($hits).Count
    Sensitivity        = $first.sensitivity
    Preview            = $first.bodyPreview
    WebLink            = $first.webLink
    EventId            = $first.id
}
$detail | Format-List

Write-Host ("Attendees on invite: {0}  (required {1}, optional {2}, resource {3}; accepted {4})" -f `
        $att.Count, $required.Count, $optional.Count, $resource.Count, $accepted.Count) -ForegroundColor Green
Write-Host ("Organizer: {0}" -f $detail.OrganizerEmail) -ForegroundColor Green
Write-Host "Note: a calendar event does not flag co-organizers - they are among the attendees above. True" -ForegroundColor DarkYellow
Write-Host "      co-organizer role data requires the app-only onlineMeeting API." -ForegroundColor DarkYellow

if ($ShowAttendees) {
    Write-Section "Invitees (eyeball for likely co-organizers)"
    $att | ForEach-Object {
        [pscustomobject]@{
            Name     = $_.emailAddress.name
            Email    = $_.emailAddress.address
            Type     = $_.type
            Response = $_.status.response
        }
    } | Format-Table -AutoSize
}

$detail
