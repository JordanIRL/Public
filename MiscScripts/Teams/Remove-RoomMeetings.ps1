<#
.SYNOPSIS
    Cancels or declines meetings on a Teams Room mailbox. SAFE BY DEFAULT: it only previews
    matches until you pass -Execute.

.DESCRIPTION
    Finds meetings in the room's calendar within the window (and optional filters), then for each:
      * If the ROOM is the organizer  -> cancels the meeting (sends a cancellation to attendees).
      * If the room is only a resource attendee -> declines it (frees the room, notifies organizer).
        Use -HardDelete to instead delete the booking from the room calendar without notifying.

    Nothing is changed unless -Execute is supplied. The script also honours -WhatIf and prompts for
    confirmation per meeting (ConfirmImpact = High); suppress prompts with -Confirm:$false.

    Graph scope (delegated): Calendars.ReadWrite  (the signed-in admin needs write rights over the room mailbox).

    NOTE on recurring meetings: a match of Type 'seriesMaster' cancels/declines the WHOLE series;
    'occurrence' affects only that instance. The Type column is shown so you can decide.

.PARAMETER RoomEmail   SMTP/UPN of the room mailbox.
.PARAMETER SubjectLike Wildcard filter on subject (e.g. "*Townhall*").
.PARAMETER Organizer   Only meetings organized by this address.
.PARAMETER EventId     Operate on one specific event id (skips the window search). Use an id emitted
                       by this script's own listing (immutable id); a raw default id containing '/' will fail.
.PARAMETER Execute     Actually perform the cancel/decline. Omit to preview only.
.PARAMETER HardDelete  When the room is an attendee, delete the booking instead of declining.
.PARAMETER Comment     Message sent with the cancellation/decline.

.EXAMPLE
    # Preview everything in the next 30 days
    ./Remove-RoomMeetings.ps1 -RoomEmail room1@contoso.com -DaysForward 30

.EXAMPLE
    # Cancel a specific series, no per-item prompt
    ./Remove-RoomMeetings.ps1 -RoomEmail room1@contoso.com -SubjectLike '*Old Standup*' -Execute -Confirm:$false
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][string]$RoomEmail,
    [int]$DaysBack = 0,
    [int]$DaysForward = 90,
    [string]$SubjectLike,
    [string]$Organizer,
    [string]$EventId,
    [switch]$Execute,
    [switch]$HardDelete,
    [string]$Comment = 'This room booking has been cancelled by IT administration.'
)

. "$PSScriptRoot/../Common/GraphCommon.ps1"
Connect-GraphSession -Scopes @('Calendars.ReadWrite')

$encRoom = [uri]::EscapeDataString($RoomEmail)
$select = 'id,subject,start,end,type,isCancelled,organizer,seriesMasterId'
# Immutable ids are URL-safe base64url; default event ids can contain '/', which breaks them in the URL
# path (and %2F does not help - Graph still treats it as a separator). See README.
$immutable = @{ Prefer = 'IdType="ImmutableId"' }

# Build the candidate list.
if ($EventId) {
    $ev = Invoke-MgGraphRequest -Method GET -Uri "/v1.0/users/$encRoom/events/$EventId`?`$select=$select" -Headers $immutable -OutputType PSObject
    $events = @($ev)
} else {
    $startUtc = (Get-Date).ToUniversalTime().AddDays(-$DaysBack)
    $endUtc = (Get-Date).ToUniversalTime().AddDays($DaysForward)
    $s = $startUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $e = $endUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $uri = "/v1.0/users/$encRoom/calendarView?startDateTime=$s&endDateTime=$e&`$select=$select&`$orderby=start/dateTime&`$top=100"
    $events = Invoke-GraphPaged -Uri $uri -Headers $immutable
}

$targets = foreach ($ev in $events) {
    if ($ev.isCancelled) { continue }
    if ($SubjectLike -and $ev.subject -notlike $SubjectLike) { continue }
    if ($Organizer -and $ev.organizer.emailAddress.address -ne $Organizer) { continue }
    $roomIsOrganizer = $ev.organizer.emailAddress.address -eq $RoomEmail
    [pscustomobject]@{
        Start           = $ev.start.dateTime
        Subject         = $ev.subject
        Type            = $ev.type
        Organizer       = $ev.organizer.emailAddress.address
        RoomIsOrganizer = $roomIsOrganizer
        Action          = if ($roomIsOrganizer) { 'Cancel' } elseif ($HardDelete) { 'Delete' } else { 'Decline' }
        EventId         = $ev.id
    }
}

Write-Section "Room meeting removal for $RoomEmail"
if (-not $targets) { Write-Host "No matching meetings found." -ForegroundColor Yellow; return }

$targets | Select-Object Start, Subject, Type, Organizer, Action | Format-Table -AutoSize
Write-Host ("Matched {0} meeting(s)." -f @($targets).Count) -ForegroundColor Cyan

if (-not $Execute) {
    Write-Host "`nPREVIEW ONLY. Re-run with -Execute to perform the actions above." -ForegroundColor Yellow
    return
}

$results = foreach ($t in $targets) {
    $desc = "$($t.Action) '$($t.Subject)' ($($t.Start))"
    if (-not $PSCmdlet.ShouldProcess("$RoomEmail", $desc)) {
        [pscustomobject]@{ Subject = $t.Subject; Action = $t.Action; Status = 'Skipped' }
        continue
    }
    $base = "/v1.0/users/$encRoom/events/$($t.EventId)"
    try {
        switch ($t.Action) {
            'Cancel'  { Invoke-MgGraphRequest -Method POST -Uri "$base/cancel"  -Body @{ Comment = $Comment } | Out-Null }
            'Decline' { Invoke-MgGraphRequest -Method POST -Uri "$base/decline" -Body @{ Comment = $Comment; SendResponse = $true } | Out-Null }
            'Delete'  { Invoke-MgGraphRequest -Method DELETE -Uri $base | Out-Null }
        }
        [pscustomobject]@{ Subject = $t.Subject; Action = $t.Action; Status = 'Done' }
    } catch {
        [pscustomobject]@{ Subject = $t.Subject; Action = $t.Action; Status = "Failed: $($_.Exception.Message)" }
    }
}

$results | Format-Table -AutoSize
$results
