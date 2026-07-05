# Microsoft Teams Town halls: controlling what attendees see

## Purpose

This document explains how to control what attendees see during all-company Microsoft Teams Town halls, so the right speaker and content are visible at the right time.

Teams active-speaker behaviour is not enough for a polished all-company event. Shared content, attendee layouts, and presenter behaviour can all affect what people see. The attendee view should therefore be managed deliberately using **Manage what attendees see**, rather than left to automatic speaker focus.

## Scope and assumptions

- **Audience size:** ~600 attendees average. Well within Town hall's default capacity (10,000) — no capacity packs or Events Services coordination required.
- **Client:** Microsoft Teams desktop or mobile app only. No browser-based attendees in scope.
- **Format:** Internal all-company broadcast.

## Event format

All-company broadcasts should be created as **Teams Town halls**.

Town hall is designed for one-to-many delivery and provides the production controls needed to manage the attendee view.

**Teams Live Events retirement.** Microsoft is retiring the Teams Live Events experience on **30 June 2026**. Live Events scheduled before that date will continue to run through **28 February 2027**, but no new Live Events should be scheduled. Town halls are the replacement for all large-scale broadcast scenarios.

## Town hall roles and capacity

Town halls use four roles. The ability to control the attendee view is configurable per event:

| Role | Capability | Limit |
|---|---|---|
| **Organiser** | Schedules the event, configures meeting options, has full production control. Chooses which other users have control of production tools | 1 |
| **Co-organiser** | Same production control as organiser during the event. Standard place to put the person running production | Up to 10 |
| **Presenter** | Can present content and appear on screen. Organiser can optionally grant production tool control to specific presenters | Up to 100 (including external) |
| **Attendee** | View-only. Cannot present, cannot share, mic and camera forced off. Cannot rename themselves | Up to 10,000 (default) |

**Production tools control is configurable.** The organiser explicitly chooses which named organisers, co-organisers, *and/or presenters* can control production tools. Anyone with this permission can start the event, manage what attendees see, and end the event. By default, the practical setup is: the organiser is the on-camera host, and a co-organiser runs production.

In this document, **co-organiser controlling production tools** is the standard term for the person running the live feed.

## Notable features unavailable in Town halls

Town halls are deliberately stripped down compared to standard Teams meetings. Plan around these gaps:

- **PowerPoint Live** — not supported. Presenters must use **screen sharing** or **window sharing** to present slides. Open PowerPoint in Slideshow mode and share the window.
- **Whiteboard** — not supported.
- **Breakout rooms** — not supported.
- **Lobby** — there is no lobby in Town halls. Presenters and co-organisers join via the green room; attendees join straight in (mic and camera forced off).
- **Language interpretation, CART captions, real-time text** — not supported. AI-generated live captions are available.
- **Attendee renaming** — attendees cannot rename themselves.

## Core feature: Manage what attendees see

Microsoft's **Manage what attendees see** feature lets the user controlling production tools choose which presenters and shared content are visible to attendees.

Source: https://support.microsoft.com/en-us/office/manage-what-attendees-see-in-microsoft-teams-19bfd690-8122-49f4-bc04-c2c5f69b4e16

In a Town hall, the setting lives under **Meeting options > Production tools > Manage what attendees see**. The setting is **on by default**, but the mode should be confirmed before going live.

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
| **Customize screen** | Town hall layouts (Dynamic, single-person, multi-person), name tag colours, and backgrounds. Dynamic layout supports up to 7 video feeds on screen |

## Recommended Town hall setup

| Setting | Recommendation |
|---|---|
| Manage what attendees see | Confirm mode: **On** for standard events, **On with preview** for high-stakes events |
| Who can present | Specific named presenters only |
| Co-organisers | Add at least one co-organiser to run production; add a second as backup |
| Production assignment | Identify which co-organiser is controlling production tools. Their only job is the live feed |
| Green room | Use it, so presenters and content can be checked before the event starts |
| Attendee cameras | Off (forced off, cannot be enabled in Town halls) |
| Attendee microphones | Off (forced off, cannot be enabled in Town halls) |
| Q&A | Enable in moderated mode. Q&A is the primary attendee participation channel and one of the main reasons to use Town halls |
| Chat | Town hall chat (the attendee comment stream) is available; enable if it supports the event. Organisers/co-organisers/presenters have a separate Event group chat for production coordination |
| Recording | Recording is **automatic by default** in Town halls; can be turned off. Recordings expire after 30 days by default (extendable to 60). Recordings are published through the event itself and can be made available as VOD |

## Admin centre settings to standardise

Town halls are enabled by default at tenant level. Use Teams admin policies (**Meetings > Events Policies**) to refine who can use them and how.

| Objective | Admin recommendation |
|---|---|
| Limit untrained use | Restrict Town hall creation to a defined group of trained organisers via `AllowTownhalls` in the events policy |
| Restrict attendance to org users | Set `EventAccessType` to `EveryoneInCompanyExcludingGuests` to prevent public Town halls |
| Standardise presenting rights | Default new events to specific named presenters only |
| Limit presenter capabilities | Use `Limit presenter role permissions` to reduce what presenters can do by default |
| Encourage managed production | Document **Manage what attendees see** as the standard for all large presentation-led sessions |
| Pre-event preparation | Use green room for all Town halls |
| Recording governance | Confirm recording is allowed by policy; set expiration policy in line with retention requirements |

## Production workflow

The co-organiser running production should be a different person from the on-camera host.

**Before the event:**

- Confirm the **Manage what attendees see** mode (On vs On with preview).
- Confirm the co-organiser running production has been granted control of production tools.
- Check the presenter list in the Manage screen pane.
- Pin key presenters in the Manage screen pane.
- Decide the first live view: host only, host plus content, or content only.
- Confirm the running order of presenters and shared content.
- Choose the **Customize screen** layout (Dynamic, single-person, multi-person; max 7 video feeds).
- Have each presenter test screen/window sharing with their actual slides. PowerPoint Live is not supported in Town halls.

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

If a presenter starts sharing their screen while another presenter is live, Teams will automatically take the live presenter's content off screen and replace it with the new share in the Manage screen pane. Only users with control of production tools can bring the new share back on screen.

This means a presenter can unintentionally bump the current live view by clicking Share. Mitigations:

- Brief all presenters before the event: do not click Share unless cued.
- Keep the co-organiser focused on the Manage screen pane during transitions.
- Use On with preview mode for events where this risk matters.

## Content sharing in Town halls

Presenters share content using **Share screen** or **Share window** in Teams meeting controls. PowerPoint Live and Whiteboard are not available in Town halls.

| Content type | Recommended method | Notes |
|---|---|---|
| Slides | Window share — open PowerPoint in Slideshow mode and share the slideshow window | Avoid screen share for slides; window share is more reliable and avoids accidentally exposing the presenter's desktop |
| Live demo of an app | Window share of the specific app | Window share prevents notification pop-ups from being visible |
| Demo across multiple apps | Screen share | Brief the presenter to clear their desktop and disable notifications first |
| Video clip | Window share with **Include sound** enabled | Test playback before going live; video can be unpredictable |

## Visual plan by agenda section

Decide the intended visual layout before the event starts.

| Segment type | Recommended attendee view |
|---|---|
| Host introduction | Host on screen, single-person layout |
| Executive update with slides | Presenter plus shared content |
| Slide-only section | Shared content as the main focus |
| Two people on screen together (e.g. host + executive) | Multi-person layout, both pinned in Manage screen pane |
| Panel discussion | Selected speakers on screen only; avoid showing inactive panellists |
| Q&A | Host/moderator plus the answering speaker |
| Closing remarks | Host or final speaker on screen |

## Final recommendation

Treat attendee view as something to be **produced**, not something Teams will optimise automatically.

Recommended model:

1. Use **Teams Town hall** (Live Events is retiring 30 June 2026).
2. Confirm the **Manage what attendees see** mode for the event (default is **On**; use **On with preview** for high-stakes events).
3. Assign a co-organiser to run production. Their only job is the live feed.
4. Restrict presenting rights to specific named people.
5. Brief presenters: use window share for slides; do not click Share unless cued.
6. Plan the intended visual layout for each agenda section.
7. Use the **Live feed** as the source of truth.

Key principle: **control the attendee view intentionally rather than relying on automatic active-speaker focus.**

## Source list

- Microsoft Learn: Meetings, webinars, and town halls feature comparison — https://learn.microsoft.com/en-us/microsoftteams/meeting-webinar-town-hall-feature-comparison
- Microsoft Learn: Plan for Teams town halls — https://learn.microsoft.com/en-us/microsoftteams/plan-town-halls
- Microsoft Learn: Manage who can schedule and attend town halls — https://learn.microsoft.com/en-us/microsoftteams/set-up-town-halls
- Microsoft Learn: Overview of meetings, webinars, and town halls — https://learn.microsoft.com/en-us/microsoftteams/overview-meetings-webinars-town-halls
- Microsoft Support: Manage what attendees see in Microsoft Teams — https://support.microsoft.com/en-us/office/manage-what-attendees-see-in-microsoft-teams-19bfd690-8122-49f4-bc04-c2c5f69b4e16
- Microsoft Support: Switch from Microsoft Teams live events to town halls — https://support.microsoft.com/en-us/office/switch-from-microsoft-teams-live-events-to-town-halls-c71bf6e2-ece1-4809-900e-51271f39ac72
- Microsoft Support: Get started with town hall in Microsoft Teams — https://support.microsoft.com/en-us/office/get-started-with-town-hall-in-microsoft-teams-33baf0c6-0283-4c15-9617-3013e8d4804f
- Microsoft Support: Control town hall production tools — https://support.microsoft.com/en-us/office/control-town-hall-production-tools-in-microsoft-teams-8a19026b-43d1-45e3-b306-35610d83e5f1
- Microsoft Support: Schedule a town hall in Microsoft Teams — https://support.microsoft.com/en-us/office/schedule-a-town-hall-in-microsoft-teams-d493b5cc-9f61-4dac-8027-d837dafb7a4c
- Microsoft Support: Manage town hall recordings — https://support.microsoft.com/en-us/office/manage-town-hall-recordings-in-microsoft-teams-88ac3af7-db67-4556-a202-b73a1d6c2e46
- Microsoft Support: Using the green room — https://support.microsoft.com/en-us/office/green-room-for-teams-meetings-5b744652-789f-42da-ad56-78a68e8460d5
- Microsoft Support: Tips for producing large meetings and events — https://support.microsoft.com/en-us/office/tips-for-producing-large-meetings-and-events-in-microsoft-teams-c8b1f6c2-dc7c-4265-85cd-3a0bd301e7d7
- Microsoft Learn: Manage meeting chat for Microsoft Teams town halls — https://learn.microsoft.com/en-us/microsoftteams/town-hall-chat
