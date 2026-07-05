# Microsoft Teams best practices for large all-company calls

## Executive summary

For a 10–15 presenter, approximately 550-attendee all-company Microsoft Teams session, the key design issue is that Teams does **not** provide a single tenant-level switch that automatically forces every attendee to see “the current speaker beside the shared PowerPoint or screen” in a broadcast-style composition.

Standard Teams meetings use dynamic layouts and active-speaker highlighting, and PowerPoint Live can improve the slide-led experience. However, for a polished company broadcast, the more reliable approach is to use **producer-led stage management** with **Manage what attendees see**, especially in **Town hall** or **Webinar** formats.

The recommended direction is:

- Use **Town hall** for executive updates, all-company broadcasts, and events where stage control matters most.
- Use **Webinar** when you need a structured event with some engagement, registration, or attendee controls, but less of a full broadcast feel.
- Use a **standard Teams meeting** only when attendee interaction is genuinely important and you can accept that attendee layouts are partly client-driven.
- Avoid designing new events around **Teams Live Events**, because Microsoft has positioned them as a legacy path with retirement scheduled for July 2026.

For slide-led sessions, **PowerPoint Live** should usually be the default in normal meetings because it gives presenters notes and audience signals and can be more efficient than standard screen sharing. For highly produced Town halls, use it carefully because PowerPoint Live can bypass some preview-style production workflows and recordings may not capture all PowerPoint Live media, animations, or annotations exactly as expected.

The operational answer is therefore not “turn on auto-focus.” It is: **choose the right Teams event type, restrict who can present, assign a producer, use Manage what attendees see, rehearse in the green room, standardise presenter behaviour, and monitor quality after each event.**

---

## 1. Recommended event format

| Format | Best use | Speaker/content control | Recommendation for this scenario |
|---|---|---|---|
| **Teams meeting** | Interactive internal meetings | Dynamic layout and active speaker behaviour, but attendee view remains partly user/client controlled | Use only if attendee interaction matters more than production polish |
| **Webinar** | Structured presentation with attendee controls | Better event wrapper and attendee management than a normal meeting | Good option for structured internal sessions |
| **Town hall** | One-to-many company broadcast | Best fit for producer-led control using Manage what attendees see and preview-style workflows | **Recommended default for all-company calls** |
| **Live Event** | Legacy broadcast model | Legacy production workflow | Avoid for new designs in 2026 |

### Practical recommendation

For your all-company calls, use **Town hall** as the default format when the audience is mostly watching and the business priority is a clean, controlled stage. Use **standard Teams meetings** only for calls where the audience must actively participate with meeting-style interaction.

---

## 2. The active-speaker concern

The IT Manager’s concern is valid: in a large multi-presenter session, relying on Teams to automatically focus the correct speaker alongside shared content can create an inconsistent experience.

What Teams can do:

- Highlight active speakers.
- Dynamically adapt meeting layout.
- Let users customise their own meeting view.
- Let presenters use PowerPoint Live layouts.
- Let organisers/producers manage what attendees see in supported meeting, webinar, and Town hall scenarios.

What Teams should **not** be assumed to do:

- Automatically create a fully managed “broadcast programme feed” for every attendee.
- Reliably switch between 10–15 presenters beside slides without producer input.
- Override every attendee’s local view preference in a normal meeting.

### Best-practice answer

For a polished broadcast, appoint a **producer** and use **Manage what attendees see** rather than expecting automatic active-speaker switching to solve the problem.

---

## 3. Recommended operating model

For each all-company event:

- **Organiser:** Owns the event invite, options, recording, and post-event follow-up.
- **Co-organisers:** 2–3 trusted backups from IT, internal comms, or AV.
- **Producer:** Owns stage management, presenter transitions, and what attendees see.
- **Presenters:** Named in advance. Only active presenters should have presenter rights.
- **Audience:** Joins as attendees. Cameras and microphones should normally be disabled unless interaction is planned.

### Presenter flow

1. Producer opens green room early.
2. Presenters join early and test microphone, camera, lighting, and content.
3. Producer confirms who is live, who is next, and who is sharing.
4. Only one presenter shares at a time.
5. Producer uses Manage what attendees see to bring the correct speaker/content live.
6. Non-speaking presenters stay muted and off-stage.

---

## 4. Admin settings and policy recommendations

| Objective | Where to configure | Setting | Recommended baseline |
|---|---|---|---|
| Stop unplanned presenting | Teams admin centre → Meetings → Meeting policies | **Who can present** | Default to organiser/co-organiser control; for key events use **Specific people** |
| Prevent remote-control disruption | Teams admin centre → Meeting policies → Content sharing | **Participants can give or request control** | Off for large broadcast-style events |
| Prevent external control | Teams admin centre → Meeting policies → Content sharing | **External participants can give or request control** | Off unless explicitly needed |
| Keep PowerPoint Live available | Teams admin centre → Meeting policies → Content sharing | **PowerPoint Live** | On |
| Reduce oversharing | Teams admin centre → Meeting policies → Content sharing | **Screen sharing mode** | Prefer controlled sharing; consider app/window sharing guidance |
| Control attendee stage | Meeting/Webinar/Town hall options | **Manage what attendees see** | On for structured events; use preview where available |
| Improve rehearsal discipline | Meeting/Webinar/Town hall options | **Green room** | On for large all-company calls |
| Prevent attendee camera clutter | Event options | **Allow camera for attendees** | Off for presentation-led events |
| Control event creation | Teams admin centre → Meetings → Events policies | Webinar/Town hall creation rights | Limit to trained organisers/comms/IT users |
| Control event audience | Teams admin centre → Events policies | Event access type | Internal-only for all-company calls unless guests are required |
| Improve dense-office viewing | Teams admin / Event settings | Microsoft eCDN | Enable if many viewers join from the same offices |
| Improve Town hall resolution | Teams events policy | Town hall max resolution | Use 1080p only after network testing |

---

## 5. Suggested PowerShell starting points

Validate these in a pilot tenant or test policy before production rollout.

```powershell
# Inspect current baselines
Get-CsTeamsMeetingPolicy -Identity Global
Get-CsTeamsMeetingConfiguration -Identity Global

# Presenter-focused meeting policy for large internal broadcasts
Set-CsTeamsMeetingPolicy -Identity "AllHands-Presenters" `
  -AllowParticipantGiveRequestControl $False `
  -AllowExternalParticipantGiveRequestControl $False `
  -AllowPowerPointSharing $True `
  -AllowCloudRecording $True `
  -MediaBitRateKb 10000 `
  -StreamingAttendeeMode Enabled

# Events policy for internal all-company sessions
Set-CsTeamsEventsPolicy -Identity "AllHands-Events" `
  -AllowWebinars Enabled `
  -AllowTownhalls Enabled `
  -EventAccessType EveryoneInCompanyExcludingGuests `
  -RecordingForTownhall Enabled `
  -RecordingForWebinar Enabled `
  -UseMicrosoftECDN $True `
  -TownhallMaxResolution Max1080p
```

Notes:

- Confirm parameter availability against your installed Teams PowerShell module.
- Confirm licensing before using Teams Premium features such as custom meeting templates or advanced event capabilities.
- Apply policies to a small organiser/presenter group first, then expand.

---

## 6. Meeting and event options checklist

Before each event:

| Setting | Recommended value |
|---|---|
| Format | Town hall for broadcast-style all-company calls |
| Who can present | Specific people, or only organisers/co-organisers |
| Co-organisers | 2–3 named backups |
| Green room | On |
| Manage what attendees see | On |
| Attendee cameras | Off for presentation-led sessions |
| Attendee microphones | Off unless Q&A requires live participation |
| Recording | On or assigned to a responsible organiser |
| Q&A/chat | Decide in advance: moderated Q&A, chat, or no open chat |
| Presenter list | Finalised before event day |
| Content owner | One deck owner or producer-controlled content source |
| Backup presenter | Named for each critical segment |

---

## 7. Presenter guidance

### Before the event

Presenters should:

- Join from the Teams desktop app, not a browser, unless there is a known reason not to.
- Use a wired or strong managed network connection where possible.
- Use a headset or approved room audio.
- Close unnecessary applications and notifications.
- Upload slides in advance where PowerPoint Live will be used.
- Avoid changing devices or locations immediately before going live.
- Join the green room early.

### During the event

Presenters should:

- Stay muted until cued.
- Keep camera on only when they are speaking or about to speak.
- Wait for the producer cue before speaking.
- Avoid taking over sharing unexpectedly.
- Use clear verbal hand-offs: “I’ll now hand back to Sarah.”
- Stop sharing when their segment is finished unless instructed otherwise.

### PowerPoint Live guidance

Use PowerPoint Live when:

- The content is a normal slide deck.
- Presenter notes are important.
- The presenter wants slide thumbnails and audience signals.
- Lower bandwidth usage is helpful.

Use normal screen/window sharing when:

- The slides include important video, animation, or complex transitions.
- The recording must capture the content exactly as displayed.
- The event producer needs full preview control before content goes live.
- The segment is a live demo rather than a slide presentation.

---

## 8. Producer runbook

The producer should own the live audience experience.

### Producer responsibilities

- Start the event early.
- Admit and brief presenters in the green room.
- Confirm the running order.
- Confirm who is sharing content.
- Keep only the correct presenter/content visible to attendees.
- Remove finished presenters from the attendee view where required.
- Monitor Q&A/chat if no separate moderator exists.
- Watch for muted speakers, wrong screen shares, poor audio, or presenter confusion.
- Coordinate with IT support if quality issues appear.

### Live transition pattern

1. Confirm next presenter is ready.
2. Bring their camera/content into the managed attendee view.
3. Cue them verbally or via side chat.
4. Keep previous presenter off-stage unless a panel discussion is intended.
5. After the segment, remove them from stage and cue the next transition.

---

## 9. Network and device best practices

### Network

For high-quality delivery:

- Prefer wired connections for presenters and Teams Rooms.
- Avoid VPN paths for real-time Teams media where possible.
- Implement Teams QoS end-to-end where the network supports it.
- Validate bandwidth from key offices before enabling 1080p Town halls.
- Use Microsoft eCDN where many attendees watch from the same office locations.

Typical Teams QoS markings to validate with the network team:

| Workload | Source port range | DSCP |
|---|---:|---:|
| Audio | 50000–50019 | 46 |
| Video | 50020–50039 | 34 |
| App/screen sharing | 50040–50059 | 18 |

### Devices and rooms

Use Teams-certified hardware for presenter rooms. For boardroom or studio-style delivery, consider Teams Rooms Pro with intelligent camera/audio features where appropriate.

Potentially relevant device categories:

- Teams Rooms on Windows or Android.
- Certified intelligent cameras.
- Certified speaker bars and room systems.
- Front-of-room displays arranged for natural presenter eye-line.
- Dedicated producer workstation with multiple monitors.

Important limitation: some multi-camera or room intelligence features are more relevant to ordinary Teams meetings than Town halls. Do not assume a room camera feature automatically becomes the Town hall broadcast view.

---

## 10. Monitoring and post-event review

After each event, IT should review:

- Presenter audio quality.
- Presenter video quality.
- Screen/app sharing quality.
- Poor network segments.
- Attendee feedback.
- Recording quality.
- Any moments where the wrong person/content was visible.
- Whether PowerPoint Live or screen sharing was the right choice for each segment.

Recommended tools and signals:

- Teams admin centre call/meeting quality data.
- Call Quality Dashboard trends.
- Event or Town hall insights where available.
- Microsoft eCDN analytics where used.
- Internal comms feedback from presenters and attendees.

The most useful operational metric is not just technical quality. It is whether the audience saw the correct person and content at the right time. Track this manually during the first few runs.

---

## 11. Rollout plan

### Phase 1 — Design

- Choose Town hall as the default all-company format.
- Define standard event roles: organiser, co-organiser, producer, moderator, presenters.
- Decide when to use PowerPoint Live versus screen/window sharing.
- Confirm licensing for Teams Premium, Town halls, eCDN, and Teams Rooms Pro.

### Phase 2 — Admin configuration

- Create dedicated meeting and event policies for all-company organisers/presenters.
- Restrict presenter rights and content control.
- Enable PowerPoint Live.
- Enable Town halls and Webinars only for trained users if appropriate.
- Configure eCDN and 1080p only after network validation.

### Phase 3 — Pilot

Run three pilots:

1. Standard meeting with PowerPoint Live.
2. Webinar with attendee view management.
3. Town hall with producer-managed attendee view.

Compare attendee experience, recording quality, support burden, and presenter confidence.

### Phase 4 — Standardise

- Publish an “All-company event” runbook.
- Train organisers and presenters.
- Create a reusable checklist.
- Use a template if Teams Premium is available.
- Build a post-event review process.

### Phase 5 — Improve

- Review quality data after every large event.
- Tune policies and network settings.
- Refine presenter guidance.
- Maintain a known-good room and device standard.

---

## 12. Final recommendation

For a 550-attendee all-company call with 10–15 presenters, the best-practice model is:

1. Use **Town hall** by default.
2. Assign a dedicated **producer**.
3. Turn on **Manage what attendees see**.
4. Use the **green room** for rehearsal and presenter readiness.
5. Restrict presenting to **specific people**.
6. Disable attendee cameras and microphones unless interaction is intentional.
7. Use **PowerPoint Live** for ordinary slide-led sections, but use screen/window sharing for animated, video-heavy, demo, or recording-critical sections.
8. Use Teams-certified rooms/devices for presenters.
9. Validate network, QoS, and eCDN before high-profile events.
10. Review quality and production issues after each event.

The key message for the IT Manager is: **do not try to solve this as an automatic active-speaker-focus problem. Solve it as a managed production workflow.**

---

## Plain source list

Key Microsoft pages used for the original research:

- Microsoft Teams meetings overview — https://learn.microsoft.com/en-us/microsoftteams/meetings-overview
- Plan for Teams meetings — https://learn.microsoft.com/en-us/microsoftteams/plan-meetings
- Meeting policies and content sharing — https://learn.microsoft.com/en-us/microsoftteams/meeting-policies-content-sharing
- Manage who can present and request control — https://learn.microsoft.com/en-us/microsoftteams/meeting-who-present-request-control
- Manage meeting presentation experience — https://learn.microsoft.com/en-us/microsoftteams/manage-meeting-presentation-experience
- Set up webinars — https://learn.microsoft.com/en-us/microsoftteams/set-up-webinars
- Set up town halls — https://learn.microsoft.com/en-us/microsoftteams/set-up-town-halls
- Plan town halls — https://learn.microsoft.com/en-us/microsoftteams/plan-town-halls
- Microsoft eCDN — https://learn.microsoft.com/en-us/microsoftteams/streaming-ecdn-enterprise-content-delivery-network
- Prepare your network for Teams — https://learn.microsoft.com/en-us/microsoftteams/prepare-network
- QoS in Teams — https://learn.microsoft.com/en-us/microsoftteams/qos-in-teams
- Monitor call quality and QoS — https://learn.microsoft.com/en-us/microsoftteams/monitor-call-quality-qos
- Call Quality Dashboard dimensions and measures — https://learn.microsoft.com/en-us/microsoftteams/dimensions-and-measures-available-in-call-quality-dashboard
- Enable 1080p video resolution for Town hall — https://learn.microsoft.com/en-us/microsoftteams/enable-1080p-video-resolution-town-hall
- Teams Rooms planning guidance — https://learn.microsoft.com/en-us/microsoftteams/rooms/room-planning-guidance
- Teams Rooms certified hardware — https://learn.microsoft.com/en-us/microsoftteams/rooms/certified-hardware
- Multi-Stream IntelliFrame — https://learn.microsoft.com/en-us/microsoftteams/devices/multistream-intelliframe
- Teams Rooms licensing — https://learn.microsoft.com/en-us/microsoftteams/rooms/rooms-licensing
- Custom meeting templates overview — https://learn.microsoft.com/en-us/microsoftteams/custom-meeting-templates-overview
- Create a custom meeting template — https://learn.microsoft.com/en-us/microsoftteams/create-custom-meeting-template
- Set-CsTeamsMeetingPolicy — https://learn.microsoft.com/en-us/powershell/module/microsoftteams/set-csteamsmeetingpolicy?view=teams-ps
- Set-CsTeamsEventsPolicy — https://learn.microsoft.com/en-us/powershell/module/microsoftteams/set-csteamseventspolicy?view=teams-ps
- Meeting options in Microsoft Teams — https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e
- Tips for large meetings and events — https://support.microsoft.com/en-us/office/tips-for-setting-up-large-meetings-and-events-in-microsoft-teams-ce2cdb9a-0546-43a4-bb55-34ab98ab6b16
- Green room in Microsoft Teams — https://support.microsoft.com/en-us/office/using-the-green-room-in-microsoft-teams-5b744652-789f-42da-ad56-78a68e8460d5
- Manage what attendees see — https://support.microsoft.com/en-us/office/manage-what-attendees-see-in-microsoft-teams-19bfd690-8122-49f4-bc04-c2c5f69b4e16
- PowerPoint Live in Teams — https://support.microsoft.com/en-us/office/share-slides-in-microsoft-teams-meetings-with-powerpoint-live-fc5a5394-2159-419c-bc59-1f64c1f4e470
- Presenter modes in Teams — https://support.microsoft.com/en-us/office/presenter-modes-in-microsoft-teams-a3599bcb-bb35-4e9c-8dbb-72775eb91e04
- Microsoft Teams adoption: meetings, webinars, and town halls — https://adoption.microsoft.com/en-us/microsoft-teams/meetings-webinars-and-town-halls/
- Microsoft Teams adoption: town halls — https://adoption.microsoft.com/en-us/microsoft-teams/meetings-webinars-and-town-halls/town-halls/
- Microsoft Teams blog: Town halls and Live Events retirement — https://techcommunity.microsoft.com/blog/microsoftteamsblog/introducing-town-halls-in-microsoft-teams-and-retiring-microsoft-teams-live-even/3925739

