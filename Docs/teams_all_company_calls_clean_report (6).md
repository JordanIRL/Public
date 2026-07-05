# Microsoft Teams all-company calls: controlling what attendees see

## Purpose

This document focuses on one question: **how do we make sure attendees see the right speaker and the right content at the right time in a large Microsoft Teams session?**

The key point is that standard Teams active-speaker behaviour is not enough for a polished all-company call. Teams can highlight or prioritise active speakers, but that does not guarantee a consistent broadcast-style view for every attendee, especially when PowerPoint or screen sharing is involved.

For a controlled attendee experience, use a production-led setup built around **Manage what attendees see**.

## Recommended approach

For large internal broadcasts, use:

1. **Teams Town hall** as the default format.
2. **Manage what attendees see** to control the attendee view.
3. **On with preview** where available, so content and presenters can be prepared before going live.
4. A dedicated **producer** to manage the live feed.
5. Restricted presenter permissions so only intended presenters and production staff can affect the attendee view.

The goal is to stop relying on Teams to automatically choose the right visual layout and instead make the attendee view intentional.

## Why automatic active-speaker focus is not enough

In a standard Teams meeting, the visible layout can vary depending on:

- Whether content is being shared.
- Whether PowerPoint Live is being used.
- The attendee’s device and Teams client.
- The attendee’s selected layout.
- The number of people with cameras on.
- Whether a presenter is speaking, sharing, or both.

This means the current speaker may not always appear where expected, may be visually secondary to shared content, or may not be shown consistently to all attendees.

For high-visibility all-company sessions, the safer model is to manage the attendee view directly.

## Event format recommendation

| Format | Attendee-view control | Recommendation |
|---|---|---|
| **Teams Town hall** | Strongest native fit for producer-led control | **Recommended default** |
| **Teams Webinar** | Useful attendee controls; suitable for structured sessions | Use when a webinar format is specifically needed |
| **Standard Teams meeting** | More dependent on dynamic layouts and attendee choices | Use only when interaction matters more than visual control |
| **Teams Live Event** | Legacy broadcast approach | Avoid for new designs in 2026 |

For most all-company broadcasts, **Town hall** is the best fit because it is designed for one-to-many delivery and gives organisers stronger production controls.

## Core feature: Manage what attendees see

Microsoft’s **Manage what attendees see in Microsoft Teams** guidance is the central source for this approach.

Source: https://support.microsoft.com/en-us/office/manage-what-attendees-see-in-microsoft-teams-19bfd690-8122-49f4-bc04-c2c5f69b4e16

This feature lets organisers and production-tool controllers choose which presenters and shared content are visible to attendees.

### How it applies by event type

| Event type | How to use it |
|---|---|
| **Meeting** | Set **Who can present** to **Specific people**, choose the presenters, then enable **Manage what attendees see** under **Production tools** |
| **Webinar** | Enable it under **Engagement** |
| **Town hall** | Use **Production tools > Manage what attendees see**; where available, choose **On with preview** |

### Key production concepts

| Concept | Meaning |
|---|---|
| **Live feed** | What attendees are currently seeing |
| **Manage screen pane** | The control area used to bring presenters or content on screen, or take them off screen |
| **On with preview** | Allows the producer to prepare the next presenter or content before attendees see it |
| **Send live** | Pushes the prepared presenter or content to the attendee view |
| **Pinning presenters** | Helps the producer keep important presenters easy to find during events with multiple speakers |

## Recommended Town hall configuration

For a presentation-led all-company call, use the following setup:

| Setting | Recommendation |
|---|---|
| Event type | **Town hall** |
| Manage what attendees see | **On with preview** where available |
| Who can present | Specific named presenters and production staff only |
| Co-organisers | Add backup organisers who can manage the event if needed |
| Producer | Assign a named person to control the live feed |
| Green room | Enable, so presenters and content can be checked before the event starts |
| Attendee cameras | Off, unless there is a deliberate reason to show attendees |
| Attendee microphones | Off, unless audience participation is part of the format |
| Q&A/chat | Use only if it supports the event format; it should not distract from view control |
| Recording | Enabled if the event needs to be available afterwards |

The important settings for visual control are **Manage what attendees see**, **On with preview**, **Who can present**, and **Green room**.

## Admin centre settings to standardise

Use Teams admin settings and event policies to make this setup repeatable for organisers.

| Objective | Admin recommendation |
|---|---|
| Make the right event type available | Enable Town halls for the users who organise all-company events |
| Avoid untrained use | Limit Town hall/Webinar creation to trained organisers if appropriate |
| Prevent unintended people affecting the view | Standardise presenting rights so only organisers, co-organisers, or specific presenters can present |
| Support managed production | Encourage or require **Manage what attendees see** for large presentation-led sessions |
| Support pre-event preparation | Use the **green room** for large events |
| Reduce visual clutter | Disable attendee cameras unless attendees are intended to appear on screen |
| Avoid accidental screen control | Disable attendee ability to request or give screen control for large events |
| Keep slide options available | Keep PowerPoint Live available, but document when it should and should not be used |

## Producer workflow for controlling the attendee view

The producer is responsible for what attendees see. This role should be separate from the main host wherever possible.

### Before the event

- Open the event early.
- Confirm **Manage what attendees see** is enabled.
- Confirm whether **On with preview** is being used.
- Check the presenter list in the Manage screen pane.
- Pin key presenters if useful.
- Confirm the first live view: host only, host plus content, or content only.
- Confirm the running order of presenters and shared content.
- Test how PowerPoint or screen sharing will appear to attendees.

### During the event

- Keep the **Live feed** aligned with the running order.
- Bring the correct presenter or content on screen.
- Remove presenters from screen when they are no longer part of the current visual focus.
- Use preview, where available, to prepare the next visual change before selecting **Send live**.
- Keep shared content and speaker visibility intentional rather than relying on automatic switching.
- Avoid allowing presenters to start unexpected shares that change the attendee view.

### Transition pattern

For each speaker or content change:

1. Identify the next visual state: speaker only, content only, or speaker plus content.
2. Queue the presenter or content in preview where available.
3. Select **Send live** when ready.
4. Confirm the **Live feed** matches what attendees should see.
5. Remove the previous presenter or content if it is no longer needed.

## Speaker and content layouts

For each section of the event, decide the intended visual layout in advance.

| Segment type | Recommended attendee view |
|---|---|
| Host introduction | Host on screen |
| Executive update with slides | Presenter plus PowerPoint or shared content |
| Slide-only section | Shared content as the main focus |
| Panel discussion | Selected speakers on screen; avoid showing inactive presenters |
| Q&A | Host/moderator plus relevant speaker, or panel view if intentional |
| Closing remarks | Host or final speaker on screen |

The production plan should define these visual states before the event starts. That makes it easier for the producer to manage the attendee view smoothly.

## PowerPoint Live and screen sharing

PowerPoint Live can be useful, but it should be chosen deliberately because it may affect how much control the producer has over what attendees see.

Microsoft notes that when a PowerPoint Live session starts, the PowerPoint appears live to everyone immediately. For highly produced events, this can bypass the preview-and-send-live workflow.

| Scenario | Recommended approach |
|---|---|
| Standard slide presentation | PowerPoint Live can work well |
| Presenter needs notes or slide thumbnails | PowerPoint Live is useful |
| Producer needs to preview content before it appears | Screen or window sharing may be safer |
| Live demo | Window sharing |
| Video-heavy content | Test first; screen/window sharing may be more predictable |
| Complex animations or transitions | Rehearse before choosing PowerPoint Live |
| Recording must capture exactly what attendees saw | Test the chosen method before the live event |

The decision should be based on the desired attendee view, not presenter preference alone.

## Practical event checklist

Before the event starts, confirm:

| Check | Done |
|---|---|
| Correct event type selected, preferably Town hall |  |
| **Manage what attendees see** enabled |  |
| **On with preview** selected where available |  |
| Producer assigned |  |
| Backup organiser or co-organiser assigned |  |
| Presenting rights restricted to named people |  |
| Green room enabled |  |
| Attendee cameras disabled unless intentionally required |  |
| Initial live view agreed |  |
| Running order mapped to visual states |  |
| PowerPoint Live vs screen sharing decision made |  |
| First presenter/content source checked in preview or rehearsal |  |
| Backup sharing method agreed |  |

## Final recommendation

For large all-company Teams sessions, treat attendee view as something to be **produced**, not something Teams will always optimise automatically.

The recommended model is:

1. Use **Teams Town hall** by default.
2. Enable **Manage what attendees see**.
3. Use **On with preview** where available.
4. Assign a dedicated **producer**.
5. Restrict presenting rights to specific named people.
6. Plan the intended visual layout for each agenda section.
7. Choose PowerPoint Live or screen sharing based on which gives the best attendee view.
8. Use the **Live feed** as the source of truth for what attendees are seeing.

The key principle: **control the attendee view intentionally rather than relying on automatic active-speaker focus.**

## Source list

- Microsoft Support: Manage what attendees see in Microsoft Teams — https://support.microsoft.com/en-us/office/manage-what-attendees-see-in-microsoft-teams-19bfd690-8122-49f4-bc04-c2c5f69b4e16
- Microsoft Support: Meeting options in Microsoft Teams — https://support.microsoft.com/en-us/office/meeting-options-in-microsoft-teams-53261366-dbd5-45f9-aae9-a70e6354f88e
- Microsoft Support: Tips for large meetings and events in Microsoft Teams — https://support.microsoft.com/en-us/office/tips-for-setting-up-large-meetings-and-events-in-microsoft-teams-ce2cdb9a-0546-43a4-bb55-34ab98ab6b16
- Microsoft Support: Using the green room in Microsoft Teams — https://support.microsoft.com/en-us/office/using-the-green-room-in-microsoft-teams-5b744652-789f-42da-ad56-78a68e8460d5
- Microsoft Support: PowerPoint Live in Microsoft Teams — https://support.microsoft.com/en-us/office/share-slides-in-microsoft-teams-meetings-with-powerpoint-live-fc5a5394-2159-419c-bc59-1f64c1f4e470
- Microsoft Learn: Meeting policies and content sharing — https://learn.microsoft.com/en-us/microsoftteams/meeting-policies-content-sharing
- Microsoft Learn: Manage meeting presentation experience — https://learn.microsoft.com/en-us/microsoftteams/manage-meeting-presentation-experience
- Microsoft Learn: Set up webinars — https://learn.microsoft.com/en-us/microsoftteams/set-up-webinars
- Microsoft Learn: Set up town halls — https://learn.microsoft.com/en-us/microsoftteams/set-up-town-halls
- Microsoft Learn: Plan town halls — https://learn.microsoft.com/en-us/microsoftteams/plan-town-halls
- Microsoft Teams Blog: Introducing town halls and retiring Teams Live Events — https://techcommunity.microsoft.com/blog/microsoftteamsblog/introducing-town-halls-in-microsoft-teams-and-retiring-microsoft-teams-live-even/3925739