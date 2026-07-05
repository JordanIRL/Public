# Microsoft Teams all-company calls: recommended setup and operating model

## Purpose

This guidance is for large internal Microsoft Teams sessions where most attendees are watching and a smaller group of presenters are speaking or sharing content.

The main issue is that Teams should not be relied on to automatically produce a polished broadcast view where the current speaker is always shown correctly beside PowerPoint or shared content. Standard Teams meetings use dynamic layouts and active-speaker behaviour, but attendee views can still vary by client, device, layout, and user choice.

For a consistent all-company experience, run the session as a **managed production**:

- Use **Teams Town hall** as the default format.
- Enable **Manage what attendees see**.
- Use **On with preview** where available.
- Assign a dedicated **producer** to control the live attendee view.
- Restrict presenting to named presenters.
- Use the **green room** for rehearsal and readiness checks.
- Use **PowerPoint Live** deliberately, not automatically.

## Recommended event format

| Format | Best fit | Use for all-company calls? |
|---|---|---|
| **Teams Town hall** | One-to-many broadcasts with production controls | **Default recommendation** |
| **Teams Webinar** | Structured sessions with attendee management and controlled engagement | Use when registration, Q&A, or a webinar-style format is needed |
| **Standard Teams meeting** | Interactive meetings and open discussion | Use only when audience participation matters more than production control |
| **Teams Live Event** | Legacy broadcast format | Avoid for new designs in 2026 |

For most company-wide updates, leadership briefings, quarterly calls, and internal broadcasts, **Town hall** is the strongest fit because it gives the organiser and producer better control over what attendees see.

## Why active-speaker focus is not enough

The concern about speaker focus is valid. In a large session with multiple presenters and shared content, automatic active-speaker behaviour can be inconsistent. Shared slides or screen content may dominate the view, attendees may have different layouts, and not every client behaves identically.

The best-practice answer is not a single admin switch that forces automatic speaker focus. The better approach is to use **producer-led attendee view management** so the event team controls which presenter or content is live.

## Core control: Manage what attendees see

Microsoft’s **Manage what attendees see in Microsoft Teams** feature is the key native control for this scenario.

Source: https://support.microsoft.com/en-us/office/manage-what-attendees-see-in-microsoft-teams-19bfd690-8122-49f4-bc04-c2c5f69b4e16

It allows organisers and production-tool controllers to bring presenters and shared content **on screen** or **off screen** for attendees.

Key points:

- In a **meeting**, set **Who can present** to **Specific people**, choose the presenters, then enable **Manage what attendees see** under **Production tools**.
- In a **webinar**, the setting is available under **Engagement**.
- In a **town hall**, use **Production tools > Manage what attendees see**.
- For polished events, use **On with preview** where available.
- **On with preview** lets the producer queue presenters or content before selecting **Send live**.
- The **Live feed** shows what attendees are currently seeing.
- The **Manage screen** pane is used to bring presenters on screen or take them off screen.
- Taking someone off screen does **not** mute them, so presenters still need to manage audio carefully.
- Producers can pin key presenters in the Manage screen pane to make transitions easier.
- Shared content can be managed through the same workflow.

Important PowerPoint Live caveat: Microsoft notes that when a PowerPoint Live session starts, the PowerPoint appears live to everyone immediately. For highly produced events, this can bypass the preview-and-send-live workflow, so PowerPoint Live should be tested and used deliberately.

## Recommended operating model

Do not expect the organiser to present, manage Q&A, change the live view, monitor speakers, and troubleshoot at the same time. Assign clear roles.

| Role | Responsibility |
|---|---|
| **Organiser** | Creates the event, sets options, owns recording and follow-up |
| **Co-organisers** | Provide backup control if the organiser has an issue |
| **Producer** | Controls what attendees see and manages speaker/content transitions |
| **Moderator** | Manages Q&A, chat, and audience questions if enabled |
| **Presenters** | Deliver their sections and follow the agreed cues |
| **IT support** | Helps with access, Teams settings, and presenter issues if needed |

For important all-company calls, have at least one dedicated producer. If Q&A or chat is enabled, assign a separate moderator.

## Admin and policy recommendations

Use Teams admin settings and event policies to make the right setup easy and repeatable.

| Objective | Recommended configuration |
|---|---|
| Control event creation | Limit Town hall/Webinar creation to trained organisers if appropriate |
| Prevent accidental presenting | Set presenting rights to organisers, co-organisers, or specific named presenters |
| Standardise production control | Use **Manage what attendees see** for large presentation-led events |
| Allow rehearsal | Use the **green room** for all-company calls |
| Reduce audience disruption | Disable attendee microphones and cameras unless interaction is planned |
| Preserve slide options | Keep **PowerPoint Live** available, but train organisers on when to use it |
| Avoid control problems | Disable attendee ability to request or give screen control for large events |
| Protect internal events | Use internal-only access unless external guests are required |

## Event setup checklist

| Area | Recommended setting |
|---|---|
| Event type | Town hall unless Webinar or standard meeting is clearly more appropriate |
| Presenting rights | Specific named presenters only |
| Co-organisers | At least two named backups for important events |
| Producer | Named and available for rehearsal and live delivery |
| Moderator | Named if Q&A or chat is enabled |
| Green room | On |
| Manage what attendees see | On; use **On with preview** where appropriate |
| Attendee microphones | Off unless live participation is planned |
| Attendee cameras | Off for broadcast-style sessions |
| Recording | Enabled and owned by a named organiser |
| Q&A/chat | Moderated, structured, or disabled by design |
| Slide ownership | One deck owner or one content operator |
| Backup plan | Backup presenter and backup sharing method agreed |

## Presenter guidance

Before the event, presenters should:

- Join from the Teams desktop app where possible.
- Use a stable connection and tested audio device.
- Close unnecessary apps and mute notifications.
- Check camera framing, lighting, and background.
- Join the green room early.
- Know who introduces them and who they hand back to.
- Avoid changing device, location, headset, or network immediately before going live.

During the event, presenters should:

- Stay muted until cued.
- Keep camera on only when speaking or about to speak.
- Avoid starting a share unless asked.
- Use clear hand-offs, such as “I’ll now hand back to the host.”
- Stop sharing at the end of their section unless told otherwise.
- Stay available after their section in case they are needed again.

## PowerPoint Live versus screen sharing

PowerPoint Live is usually best for normal slide-led presenting because it gives presenters notes, thumbnails, and a better slide experience. It can also be more efficient than screen sharing.

For highly produced all-company calls, choose the sharing method based on the content and production need.

| Scenario | Recommended method |
|---|---|
| Standard slide presentation | PowerPoint Live |
| Presenter needs notes or thumbnails | PowerPoint Live |
| Low-bandwidth presenter connection | PowerPoint Live may help |
| Live demo | Window sharing |
| Video-heavy presentation | Test first; window sharing is often safer |
| Complex animations or transitions | Window sharing after rehearsal |
| Producer needs preview before content goes live | Window sharing may be safer |
| Recording must capture exactly what is shown | Test carefully before using PowerPoint Live |

## Producer runbook

The producer is responsible for the audience view and should own the transitions between speakers and content.

Before the event:

- Open the event early.
- Confirm the green room is working.
- Check presenters have joined correctly.
- Confirm the running order.
- Confirm who is sharing content.
- Confirm the first presenter and first content source.
- Agree the cueing method with the host and presenters.

During the event:

- Keep the live feed aligned with the running order.
- Bring the correct presenter or content on screen.
- Remove presenters from screen when their section ends.
- Pin key presenters in the Manage screen pane if useful.
- Watch for muted speakers, unexpected sharing, camera issues, or poor audio.
- Keep a backup plan ready if a presenter or share fails.

Transition pattern:

1. Confirm the next presenter is ready.
2. Queue the presenter or content if using preview.
3. Send the correct view live.
4. Cue the presenter.
5. Remove the previous presenter or content when no longer needed.

## Final recommendation

For a polished all-company Teams call, do not rely on automatic active-speaker behaviour as the main control mechanism. Use a produced event model instead.

Recommended setup:

1. Use **Teams Town hall** by default.
2. Enable **Manage what attendees see**.
3. Use **On with preview** where available.
4. Assign a dedicated **producer**.
5. Use the **green room**.
6. Restrict presenting to **specific named people**.
7. Disable attendee cameras and microphones unless interaction is planned.
8. Use PowerPoint Live where it fits, but test it for highly produced events.
9. Keep a clear presenter runbook and transition process.

The key principle: **treat the event as a managed stage, not just a large meeting.**

## Source list

- Microsoft Support: Manage what attendees see in Microsoft Teams — https://support.microsoft.com/en-us/office/manage-what-attendees-see-in-microsoft-teams-19bfd690-8122-49f4-bc04-c2c5f69b4e16
- Microsoft Support: Meeting options in Microsoft Teams — https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e
- Microsoft Support: Tips for large meetings and events in Microsoft Teams — https://support.microsoft.com/en-us/office/tips-for-setting-up-large-meetings-and-events-in-microsoft-teams-ce2cdb9a-0546-43a4-bb55-34ab98ab6b16
- Microsoft Support: Using the green room in Microsoft Teams — https://support.microsoft.com/en-us/office/using-the-green-room-in-microsoft-teams-5b744652-789f-42da-ad56-78a68e8460d5
- Microsoft Support: PowerPoint Live in Microsoft Teams — https://support.microsoft.com/en-us/office/share-slides-in-microsoft-teams-meetings-with-powerpoint-live-fc5a5394-2159-419c-bc59-1f64c1f4e470
- Microsoft Learn: Plan for Teams meetings — https://learn.microsoft.com/en-us/microsoftteams/plan-meetings
- Microsoft Learn: Meeting policies and content sharing — https://learn.microsoft.com/en-us/microsoftteams/meeting-policies-content-sharing
- Microsoft Learn: Manage meeting presentation experience — https://learn.microsoft.com/en-us/microsoftteams/manage-meeting-presentation-experience
- Microsoft Learn: Set up webinars — https://learn.microsoft.com/en-us/microsoftteams/set-up-webinars
- Microsoft Learn: Set up town halls — https://learn.microsoft.com/en-us/microsoftteams/set-up-town-halls
- Microsoft Learn: Plan town halls — https://learn.microsoft.com/en-us/microsoftteams/plan-town-halls
- Microsoft Teams Blog: Introducing town halls and retiring Teams Live Events — https://techcommunity.microsoft.com/blog/microsoftteamsblog/introducing-town-halls-in-microsoft-teams-and-retiring-microsoft-teams-live-even/3925739