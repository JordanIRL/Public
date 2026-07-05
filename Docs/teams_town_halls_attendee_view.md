# Microsoft Teams Town halls: controlling what attendees see

## Purpose

This document explains how to control what attendees see during all-company Microsoft Teams Town halls, so the right speaker and content are visible at the right time.

Teams active-speaker behaviour is not enough for a polished all-company event. Shared content, PowerPoint Live, attendee layouts, and presenter behaviour can all affect what people see. The attendee view should therefore be managed deliberately using **Manage what attendees see**, rather than left to automatic speaker focus.

## Scope and assumptions

- **Audience size:** ~600 attendees average. Well within Town hall's default capacity (10,000) — no capacity packs or Events Services coordination required.
- **Client:** Microsoft Teams desktop or mobile app only. No browser-based attendees in scope.
- **Format:** Internal all-company broadcast.

## Event format

All-company broadcasts should be created as **Teams Town halls**.

Town hall is designed for one-to-many delivery and provides the production controls needed to manage the attendee view.

**Teams Live Events retirement.** Microsoft is retiring the Teams Live Events experience on **30 June 2026**. Live Events scheduled before that date will continue to run through **28 February 2027**, but no new Live Events should be scheduled. Town halls are the replacement for all large-scale broadcast scenarios.

## Town hall roles

Town halls use four roles. Understanding them matters because the ability to control the attendee view is tied to role:

| Role | Capability |
|---|---|
| **Organiser** | Schedules the event, configures meeting options, has full control of production tools |
| **Co-organiser** | Same control as organiser during the event; the standard place to put the person running production |
| **Presenter** | Can present content and appear on screen, but cannot control what attendees see |
| **Attendee** | View-only; cannot present, cannot share, mic and camera forced off when Manage what attendees see is on |

For all-company events, the on-camera host is typically the **organiser**, and a separate **co-organiser** runs production. This document refers to that person as the **co-organiser controlling production tools**, or just **the co-organiser** in context.

## Core feature: Manage what attendees see

Microsoft's **Manage what attendees see** feature lets organisers and co-organisers choose which presenters and shared content are visible to attendees.

Source: https://support.microsoft.com/en-us/office/manage-what-attendees-see-in-microsoft-teams-19bfd690-8122-49f4-bc04-c2c5f69b4e16

In a Town hall, the setting lives under **Meeting options > Production tools > Manage what attendees see**. The setting is **on by default** in Town halls, but the mode should be confirmed before going live.

| Mode | When to use |
|---|---|
| **Off** | Standard meeting-style behaviour. Not recommended for all-company events. |
| **On** *(default)* | Co-organiser brings presenters and content on/off screen. Changes are visible to attendees live as they happen. |
| **On with preview** | Co-organiser queues presenters and content in a preview feed, then uses **Send live** to push them to attendees. Recommended for high-stakes events. |

### Key concepts

| Concept | Meaning |
|---|---|
| **Live feed** | What attendees are currently seeing |
| **Manage screen pane** | The control area used to bring presenters or content on screen, or take them off screen |
| **Preview feed** | (On with preview mode only) Stage area for queuing the next visual state before sending it live |
| **Send live** | Pushes the prepared presenter or content from the preview feed to the attendee view |
| **Pinning presenters** | Keeps key presenters easy to find in the Manage screen pane during events with many speakers |
| **Customize screen** | Town hall layouts, name tag colours, and backgrounds applied to the attendee view |

## Recommended Town hall setup

| Setting | Recommendation |
|---|---|
| Manage what attendees see | Confirm mode: **On** for standard events, **On with preview** for high-stakes events |
| Who can present | Specific named presenters only |
| Co-organisers | Add at least one co-organiser to run production; add a second as backup |
| Production assignment | Identify which co-organiser is running production. Their only job is the live feed |
| Green room | Use it, so presenters and content can be checked before the event starts |
| Attendee cameras | Off (forced off when Manage what attendees see is on) |
| Attendee microphones | Off (forced off when Manage what attendees see is on) |
| Q&A | Enable in moderated mode. Q&A is the primary attendee participation channel and one of the main reasons to use Town halls |
| Chat | Enable if it supports the event; moderate during the event |
| Recording | Enable. Town hall recordings are managed through the event itself, not dropped to a user's OneDrive like standard meeting recordings |

## Admin centre settings to standardise

Use Teams admin policies to make the preferred setup repeatable across organisers.

| Objective | Admin recommendation |
|---|---|
| Make Town halls available | Enable Town halls for the users who organise all-company events |
| Limit untrained use | Restrict Town hall creation to a defined group of trained organisers |
| Standardise presenting rights | Default new events to specific named presenters only |
| Encourage managed production | Document **Manage what attendees see** as the standard for all large presentation-led sessions |
| Pre-event preparation | Use green room for all Town halls |
| Keep slide options available | Keep PowerPoint Live available, but document when it should and should not be used (see below) |

## Production workflow

The co-organiser running production should be a different person from the on-camera host.

**Before the event:**

- Confirm the **Manage what attendees see** mode (On vs On with preview).
- Confirm the co-organiser running production has access to production tools.
- Check the presenter list in the Manage screen pane.
- Pin key presenters in the Manage screen pane.
- Decide the first live view: host only, host plus content, or content only.
- Confirm the running order of presenters and shared content.
- Choose the **Customize screen** layout (e.g. Dynamic, single-person, multi-person).
- Test how PowerPoint or screen sharing will appear to attendees.

**During the event:**

- Keep the **Live feed** aligned with the running order.
- Bring the correct presenter or content on screen.
- Remove presenters or content when they are no longer part of the current visual focus.
- In On with preview mode, queue the next state in the **Preview feed** and use **Send live** for the transition.
- Block or recover from unexpected shares (see warning below).

**For each transition:**

1. Identify the next visual state: speaker only, content only, speaker plus content, or panel.
2. Queue the presenter or content in the preview feed (if using preview mode).
3. Select **Send live**.
4. Confirm the **Live feed** matches the intended attendee view.
5. Remove anything no longer needed.

### Warning: unexpected screen shares

If a presenter starts sharing their screen while another presenter is live, Microsoft Teams will automatically take the live presenter's content off screen and replace it with the new share in the Manage screen pane. Only organisers and co-organisers can bring the new share back on screen.

This means a presenter can unintentionally bump the current live view by clicking Share. Mitigations:

- Brief all presenters before the event: do not click Share unless cued.
- Keep the co-organiser focused on the Manage screen pane during transitions.
- Consider On with preview mode for events where this risk matters.

## Visual plan by agenda section

Decide the intended visual layout before the event starts.

| Segment type | Recommended attendee view |
|---|---|
| Host introduction | Host on screen, single-person layout |
| Executive update with slides | Presenter plus PowerPoint or shared content |
| Slide-only section | Shared content as the main focus |
| Two people on screen together (e.g. host + executive) | Multi-person layout, both pinned in Manage screen pane |
| Panel discussion | Selected speakers on screen only; avoid showing inactive panellists |
| Q&A | Host/moderator plus the answering speaker |
| Closing remarks | Host or final speaker on screen |

## PowerPoint Live and screen sharing

PowerPoint Live is useful, but it has a significant interaction with managed attendee view: when a PowerPoint Live session starts, **the PowerPoint appears live to everyone immediately**. This bypasses the preview-and-send-live workflow entirely.

If you are using **On with preview** mode to control transitions precisely, PowerPoint Live breaks that control for the moment the slides go live. For tightly produced events, prefer window or screen sharing.

| Scenario | Recommended approach |
|---|---|
| Standard slide presentation, no preview control needed | PowerPoint Live |
| Presenter needs notes or slide thumbnails | PowerPoint Live |
| Co-organiser must preview content before it appears | Screen or window sharing |
| Live demo | Window sharing |
| Video-heavy content | Test first; screen/window sharing is usually more predictable |
| Complex animations or transitions | Rehearse before choosing PowerPoint Live |
| Recording must capture exactly what attendees saw | Test the chosen method before the live event |

## Final recommendation

Treat attendee view as something to be **produced**, not something Teams will optimise automatically.

Recommended model:

1. Use **Teams Town hall** (Live Events is retiring 30 June 2026).
2. Confirm the **Manage what attendees see** mode for the event (default is **On**; use **On with preview** for high-stakes events).
3. Assign a co-organiser to run production. Their only job is the live feed.
4. Restrict presenting rights to specific named people.
5. Brief presenters: do not click Share unless cued.
6. Plan the intended visual layout for each agenda section.
7. Choose PowerPoint Live or screen sharing based on attendee-view control.
8. Use the **Live feed** as the source of truth.

Key principle: **control the attendee view intentionally rather than relying on automatic active-speaker focus.**

## Source list

- Microsoft Support: Manage what attendees see in Microsoft Teams — https://support.microsoft.com/en-us/office/manage-what-attendees-see-in-microsoft-teams-19bfd690-8122-49f4-bc04-c2c5f69b4e16
- Microsoft Support: Switch from Microsoft Teams live events to town halls — https://support.microsoft.com/en-us/office/switch-from-microsoft-teams-live-events-to-town-halls-c71bf6e2-ece1-4809-900e-51271f39ac72
- Microsoft Support: Get started with town hall in Microsoft Teams — https://support.microsoft.com/en-us/office/get-started-with-town-hall-in-microsoft-teams-33baf0c6-0283-4c15-9617-3013e8d4804f
- Microsoft Support: Control town hall production tools — https://support.microsoft.com/en-us/office/control-town-hall-production-tools-in-microsoft-teams-8a19026b-43d1-45e3-b306-35610d83e5f1
- Microsoft Support: Meeting options in Microsoft Teams — https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e
- Microsoft Support: Tips for large meetings and events in Microsoft Teams — https://support.microsoft.com/en-us/office/tips-for-setting-up-large-meetings-and-events-in-microsoft-teams-ce2cdb9a-0546-43a4-bb55-34ab98ab6b16
- Microsoft Support: Tips for producing large meetings and events — https://support.microsoft.com/en-us/office/tips-for-producing-large-meetings-and-events-in-microsoft-teams-c8b1f6c2-dc7c-4265-85cd-3a0bd301e7d7
- Microsoft Support: Using the green room in Microsoft Teams — https://support.microsoft.com/en-us/office/using-the-green-room-in-microsoft-teams-5b744652-789f-42da-ad56-78a68e8460d5
- Microsoft Support: PowerPoint Live in Microsoft Teams — https://support.microsoft.com/en-us/office/share-slides-in-microsoft-teams-meetings-with-powerpoint-live-fc5a5394-2159-419c-bc59-1f64c1f4e470
- Microsoft Learn: Set up town halls — https://learn.microsoft.com/en-us/microsoftteams/set-up-town-halls
- Microsoft Learn: Plan town halls — https://learn.microsoft.com/en-us/microsoftteams/plan-town-halls
- Microsoft Learn: Meeting policies and content sharing — https://learn.microsoft.com/en-us/microsoftteams/meeting-policies-content-sharing
- Microsoft Learn: Manage meeting presentation experience — https://learn.microsoft.com/en-us/microsoftteams/manage-meeting-presentation-experience
