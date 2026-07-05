# Microsoft Teams all-company calls: recommended setup and operating model

## Purpose

This guidance is for large internal Microsoft Teams sessions, such as all-company calls with hundreds of attendees and a small group of presenters. The main concern is whether Teams can reliably keep the current speaker in focus, especially when PowerPoint or screen sharing is also live.

The practical answer is that Teams should not be treated like an automatic broadcast director. In normal meetings, Teams uses dynamic layouts and active-speaker behaviour, but the final attendee view can still vary by client, device, meeting layout, and user choice. For a polished all-company call, the better approach is to run the session as a managed production, with a producer controlling which presenters and shared content are visible to attendees.

The recommended model is:

- Use **Town hall** for company-wide broadcasts.
- Use **Manage what attendees see**, ideally with **On with preview** where available.
- Assign a dedicated producer to manage the live attendee view.
- Restrict presenting rights to named presenters only.
- Use the green room for rehearsal and presenter readiness.
- Use PowerPoint Live selectively, not automatically, because it can behave differently from managed preview workflows.

## Recommended event format

For an all-company session where most people are watching rather than actively participating, **Teams Town hall** should normally be the default format. It is designed for one-to-many communication and gives organisers better production controls than a normal Teams meeting.

A standard Teams meeting is still useful when the audience needs to participate actively, but it is less suitable when the priority is a consistent, broadcast-style experience. A webinar sits between the two: it gives more structure than a meeting, but Town hall is usually the stronger fit for executive updates, quarterly calls, leadership briefings, and company-wide presentations.

| Format | Best fit | Recommendation |
|---|---|---|
| **Standard Teams meeting** | Interactive collaboration, open discussion, working sessions | Use when audience participation matters more than production control |
| **Teams Webinar** | Structured presentation with attendee management, registration, and controlled engagement | Use for training, launches, or structured sessions where some audience engagement is needed |
| **Teams Town hall** | One-to-many internal broadcast with presenter and content control | Recommended default for all-company calls |
| **Teams Live Event** | Legacy broadcast format | Avoid for new designs in 2026, as Microsoft has moved the strategic direction to Town halls |

## The active-speaker issue

The concern is valid. With multiple presenters, a large audience, and shared slides or screens, relying on Teams to automatically highlight the right person at the right moment can lead to an inconsistent attendee experience.

Teams can identify active speakers and adjust layouts dynamically, but that is not the same as producing a broadcast feed. In a normal meeting, attendees can often change their own layout, some client experiences differ, and shared content can dominate the screen. This means the current speaker may not always appear in the way leadership, internal communications, or the event team expects.

The best-practice solution is not to look for a single admin setting that forces automatic speaker focus. The better solution is to use a **producer-led event model** where the event team decides what the audience sees.

## Use “Manage what attendees see” as the core production control

Microsoft’s **Manage what attendees see in Microsoft Teams** guidance is central to this recommendation.

Source: https://support.microsoft.com/en-us/office/manage-what-attendees-see-in-microsoft-teams-19bfd690-8122-49f4-bc04-c2c5f69b4e16

This feature allows organisers and production-tool controllers to decide which people and shared content are visible to attendees. For company-wide calls, it is the closest native Teams capability to a controlled broadcast stage.

Important operational points:

- In a **meeting**, the organiser should set **Who can present** to **Specific people**, choose the presenters, and then enable **Manage what attendees see** under **Production tools**.
- In a **webinar**, the setting is available under **Engagement**.
- In a **town hall**, Microsoft provides options under **Production tools > Manage what attendees see**. The most useful option for polished events is **On with preview**.
- With **On with preview**, the producer can queue presenters and shared content before sending them live.
- The **Live feed** shows what attendees are currently seeing.
- Presenters can be brought on screen or taken off screen from the **Manage screen** pane.
- Taking someone off screen does not automatically mute them, so audio discipline still matters.
- For events with several presenters, the producer can pin presenters in the Manage screen pane to find the next speaker more easily.
- Shared content can also be managed from the same production workflow.

A key caveat is PowerPoint Live. Microsoft notes that when a PowerPoint Live session is started, the PowerPoint appears live to everyone immediately. For highly produced events, this matters because PowerPoint Live may not follow the same preview-and-send-live workflow as other shared content.

## Recommended operating model

A successful all-company call needs clear roles. The event should not depend on the meeting organiser also presenting, watching chat, handling Q&A, changing layouts, admitting speakers, and troubleshooting quality issues.

Recommended roles:

| Role | Responsibility |
|---|---|
| **Organiser** | Owns the event setup, invite, permissions, recording, and post-event follow-up |
| **Co-organisers** | Provide backup control and continuity if the organiser has an issue |
| **Producer** | Manages what attendees see, controls speaker transitions, and keeps the event running smoothly |
| **Moderator** | Manages Q&A, chat, audience questions, and escalation to presenters |
| **Presenters** | Deliver their sections and follow the agreed runbook |
| **IT support** | Monitors quality, handles access or device issues, and supports presenters if needed |

For high-visibility all-company calls, there should be at least one dedicated producer and, where Q&A or chat is enabled, one dedicated moderator. For critical events, add a backup producer.

## Recommended admin and policy configuration

The admin goal is to make the desired behaviour the default for large events, rather than relying on every organiser to configure the session correctly each time.

| Objective | Recommended configuration |
|---|---|
| Keep event creation controlled | Limit Town hall and Webinar creation to trained organisers, internal communications, IT, or executive support teams |
| Prevent accidental presenting | Use meeting options so only organisers, co-organisers, or specific named presenters can present |
| Support managed production | Enable and standardise use of **Manage what attendees see** for large events |
| Allow rehearsal | Enable and require the **green room** for all-company calls |
| Reduce audience disruption | Disable attendee microphones and cameras unless interaction is planned |
| Preserve slide capability | Keep **PowerPoint Live** available, but train organisers on when to use it |
| Avoid control issues | Disable attendee ability to request or give screen control for large events |
| Protect internal events | Use internal-only access unless external guests are specifically required |

## Event setup checklist

For each all-company call, the organiser should confirm the following before the invite is sent or updated.

| Area | Recommended setting |
|---|---|
| Event type | Town hall, unless there is a strong reason to use Webinar or a standard meeting |
| Presenting rights | Specific named presenters only |
| Co-organisers | At least two named backups |
| Producer | Named and available for rehearsal and live event |
| Moderator | Named if Q&A or chat is enabled |
| Green room | On |
| Manage what attendees see | On; use **On with preview** where appropriate |
| Attendee microphones | Off unless live audience participation is planned |
| Attendee cameras | Off for broadcast-style sessions |
| Recording | Enabled and assigned to a responsible owner |
| Q&A/chat | Moderated, structured, or disabled by design |
| Slide ownership | One deck owner or one content operator |
| Backup plan | Backup presenter and backup sharing method agreed |

## Presenter guidance

Presenters should be given simple, practical instructions. The goal is to reduce variables on the day of the event.

Before the event, presenters should:

- Join from the Teams desktop app where possible.
- Use a stable wired or managed Wi-Fi connection.
- Use a headset or approved room audio device.
- Close unnecessary applications and mute notifications.
- Check camera framing, lighting, and background.
- Join the green room early.
- Know who introduces them and who they hand back to.
- Avoid changing device, location, headset, or network immediately before going live.

During the event, presenters should:

- Stay muted until cued by the producer or host.
- Keep camera on only when they are speaking or about to speak.
- Avoid starting a share unless they have been asked to do so.
- Use clear hand-offs, for example: “I’ll now hand back to the host.”
- Stop sharing at the end of their section unless instructed otherwise.
- Stay available after their segment in case the producer needs them again.

## PowerPoint Live versus screen sharing

PowerPoint Live is often the best choice for ordinary slide-led meetings. It gives presenters access to notes, slide thumbnails, and a better presenting experience than simply sharing a full screen. It can also be more efficient than traditional screen sharing.

However, for highly produced all-company calls, PowerPoint Live should be used deliberately. If the producer needs to preview content before it appears to attendees, or if the deck contains important embedded video, complex animations, or content that must be captured exactly in the recording, standard screen or window sharing may be safer.

Recommended approach:

| Scenario | Best sharing method |
|---|---|
| Standard slide presentation | PowerPoint Live |
| Presenter needs notes and thumbnails | PowerPoint Live |
| Low-bandwidth presenter connection | PowerPoint Live may help |
| Live demo | Window sharing |
| Video-heavy presentation | Test both; often window sharing is safer |
| Complex animations or transitions | Window sharing after rehearsal |
| Producer needs preview before content goes live | Window sharing may be safer |
| Recording must capture exactly what is shown | Test carefully before using PowerPoint Live |

## Producer runbook

The producer owns the audience view. This is the role that solves the “current speaker is not in focus” problem.

Before the event starts, the producer should:

- Open the event early.
- Confirm the green room is working.
- Check that every presenter has joined with the correct device.
- Confirm the running order.
- Confirm who is sharing slides or screen content.
- Confirm the first presenter and first content source.
- Agree the cueing method with the host and presenters.

During the event, the producer should:

- Keep the live feed aligned with the running order.
- Bring the correct presenter or content on screen.
- Remove presenters from screen when their segment ends.
- Pin key presenters in the Manage screen pane if helpful.
- Watch for muted speakers, unexpected sharing, camera issues, or poor audio.
- Coordinate quietly with IT support if there are quality problems.
- Keep a backup plan ready if a presenter drops or content sharing fails.

For each transition, use a simple pattern:

1. Confirm the next presenter is ready.
2. Queue the presenter or content if using preview.
3. Send the correct view live.
4. Cue the presenter.
5. Remove the previous presenter or content when no longer needed.

## Final recommendation

The best way to improve large all-company Teams calls is to stop relying on automatic active-speaker behaviour as the main control mechanism. Use a produced event model instead.

For most all-company broadcasts, the recommended setup is:

1. Use **Teams Town hall**.
2. Enable **Manage what attendees see**.
3. Use **On with preview** where available.
4. Assign a dedicated **producer**.
5. Use the **green room** before the event starts.
6. Restrict presenting to **specific named people**.
7. Disable attendee cameras and microphones unless interaction is planned.
8. Use PowerPoint Live where it fits, but test it carefully for highly produced events.
9. Use Teams-certified devices or known-good presenter setups where practical.
10. Review every event afterwards and improve the runbook.

The key principle is simple: for a polished all-company call, Teams should be operated as a managed stage, not just opened as a large meeting.

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

