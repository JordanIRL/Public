# Migrating a Microsoft Planner Basic Plan to Premium for an 80-Person Team

## Executive summary

The migration is feasible, but the current **6,000-task Basic plan cannot be converted intact into one Premium plan**. Microsoft currently documents a Basic limit of 9,000 total tasks and 3,000 active tasks, while Premium has a **3,000 total-task limit**.

Do not target 2,999 tasks. Use **2,700 tasks or fewer as the cutover target**, leaving roughly 10% headroom. From 6,000 tasks, this means archiving, deleting, consolidating or moving at least **3,300 tasks**.

Marking tasks complete does **not** solve the Premium limit: completed tasks still count toward Premium's 3,000 total-task ceiling.

The highest migration risk is not the conversion itself. It is the surrounding operating model. Microsoft explicitly states that applications and workflows built for Basic Planner require modification for Premium. The Microsoft Graph Planner API supports Basic plans, not Premium plans/tasks, so Graph scripts, Power Automate flows and third-party integrations must be inventoried and tested before cutover.

Premium is also not simply Basic plus extra features. Microsoft currently lists some capabilities as Basic-only, including Schedule view, Outlook calendar integration, SharePoint Planner web-part/full-page integration, recurring tasks, adding plans to Loop, and some mobile experiences. These must be checked against how the team works today.

**Recommended decision:** proceed only after a controlled discovery and pilot. Migrate approximately 2,500-2,700 current tasks, preserve required history separately, rebuild or replace integrations before cutover, license Premium features by role rather than automatically licensing all 80 users, and use Microsoft's downgrade capability as a contingency rather than treating it as a conventional backup.

---

## Confirmed Microsoft limits relevant to this migration

| Area | Basic | Premium | Migration impact |
|---|---:|---:|---|
| Total tasks per plan | 9,000 | **3,000** | 6,000 tasks cannot fit in one Premium plan |
| Active tasks | 3,000 | Limit is based on total tasks | Completing old tasks is insufficient |
| Basic buckets | 200 | Check current Premium design requirements | Review current bucket structure |
| Assignees per task | 20 | 20 | Existing heavily assigned tasks should be checked |
| Premium resources | n/a | 300 per project | 80-person team is within the published limit |
| Basic checklist items | 20 per task | Different Premium task model available | Useful only for genuine microtasks |
| Premium custom fields | n/a | 10 per project | Design metadata deliberately |
| Premium goals | n/a | 10 per project | Confirm business requirements |
| Premium hierarchy | n/a | 10 levels | Check any planned work breakdown structure |

Microsoft notes that Planner limits can change, so recheck the official limits immediately before production cutover.

---

## Ireland licensing position

Microsoft's Ireland list pricing currently shows:

| Licence | Ireland list price | Typical use |
|---|---:|---|
| Planner in qualifying Microsoft 365 | Included | Basic Planner and basic editing in shared Premium plans |
| Planner Plan 1 | **€8.70/user/month**, paid yearly, ex VAT | Timeline, dependencies, goals, People view, backlogs/sprints and other Premium planning features |
| Planner and Project Plan 3 | **€26.00/user/month**, paid yearly, ex VAT | Higher-end project capabilities including task history and advanced project-management functionality |

Illustrative annual list cost, excluding VAT:

| Premium users | Planner Plan 1 | Planner and Project Plan 3 |
|---:|---:|---:|
| 5 | €522 | €1,560 |
| 10 | €1,044 | €3,120 |
| 20 | €2,088 | €6,240 |
| 80 | €8,352 | €24,960 |

These are Microsoft Ireland public list prices, not necessarily your enterprise/CSP price.

**Do not assume all 80 users need a paid Premium licence.** Users with qualifying Microsoft 365 entitlement can perform basic editing in a shared Premium plan. Identify who actually needs Premium views and project-management features, then license by role.

Power Automate licensing is separate. Rebuilt integrations that use Premium or custom connectors may require Power Automate Premium or Process licensing. Assess this flow by flow.

---

## Basic versus Premium: functionality that must be checked

Premium adds the capabilities most teams migrate for, including Timeline/Gantt, dependencies, milestones, custom fields, conditional colouring, People view, critical path, backlogs/sprints, goals and custom calendars. Exact capability depends on the user's licence.

However, Microsoft's current comparison identifies several Basic-only capabilities. Before migration, specifically check whether the team depends on:

- Recurring tasks
- Schedule view
- Planner-to-Outlook calendar integration
- SharePoint Planner web part/full-page integration
- Plans embedded in Loop
- Teams/mobile workflows
- Existing task conversation behaviour

Do not approve production migration until a replacement or accepted loss has been agreed for every business-critical Basic-only feature.

---

# Migration plan

## Phase 1 - Discovery and baseline

Create a complete inventory before changing the plan.

Record:

- Basic plan ID and associated Microsoft 365 group
- Plan and group owners
- All members and guests
- Current Microsoft 365 and Planner licences
- Total and active task counts
- Completed-task age profile
- Buckets and labels
- Recurring tasks
- Attachments, comments, checklists and external references
- Teams tabs and links
- Outlook calendar use
- SharePoint Planner web parts
- Loop usage
- Power Automate flows
- Graph scripts/app registrations
- Power BI/reporting dependencies
- Third-party integrations
- Any compliance, retention, legal-hold or eDiscovery requirements

Take an initial **Planner Export to Excel** and, while the plan is still Basic, a richer API-level snapshot if required for technical reconstruction or audit evidence.

### Exit criterion

Nothing proceeds until every integration and business-critical Planner feature has an owner and disposition.

---

## Phase 2 - Decide what belongs in Premium

Every one of the 6,000 tasks should receive one disposition:

- **Migrate** - current work that belongs in the Premium plan
- **Archive** - history that must be retained but does not need to remain live in Planner
- **Move** - valid work belonging to another plan/workstream
- **Consolidate** - genuine microtasks that can safely become checklist/subtask-level work
- **Delete** - duplicate, test or obsolete material approved for deletion
- **Review** - business owner decision required

Do not delete based on age alone unless that rule is consistent with the organisation's retention policy.

### Target

- Microsoft hard Premium limit: **3,000 total tasks**
- Recommended cutover ceiling: **2,700 total tasks**
- Preferred operating range at migration: **2,500-2,700 tasks**

From 6,000 tasks, reaching 2,700 requires removing **3,300 tasks** from the migration population.

---

## Phase 3 - Archive and reduce

Preferred order:

1. Export and preserve required historical information.
2. Delete approved duplicates/test/obsolete tasks.
3. Move genuinely separate active work into an appropriate plan.
4. Consolidate only true microtasks where loss of individual task metadata is acceptable.
5. Reconcile the remaining task population against the approved manifest.

Do not use "mark complete" as the reduction strategy because completed tasks still count against Premium's total-task limit.

For evidence-sensitive data, preserve more than a spreadsheet if required. Planner attachments reside in SharePoint, while Premium plan data uses Dataverse, so attachment preservation and task-data preservation should be treated separately.

---

## Phase 4 - Rebuild and test integrations

This is a hard migration gate.

| Current dependency | Premium concern | Action |
|---|---|---|
| Microsoft Graph Planner API | Does not support Premium plans/tasks | Redesign rather than changing the plan ID |
| Power Automate using Basic Planner | Existing workflows may not work unchanged | Rebuild using the supported Premium/Dataverse architecture and test licensing |
| Third-party Planner integration | May depend on Basic Planner Graph APIs | Obtain written vendor confirmation of Premium support |
| Teams tab/deep links | Location/behaviour can change | Re-pin and validate |
| SharePoint Planner web part | Listed as Basic-only | Replace the user experience if required |
| Outlook Planner calendar | Listed as Basic-only | Replace or formally accept loss |
| Loop | Premium support differs | Redesign affected workflow |
| Recurring tasks | Listed as Basic-only | Replace recurrence process before migration |
| Power BI/custom reporting | Premium is Dataverse-backed | Repoint and retest data model/security |

Do not migrate production until every critical integration passes end-to-end testing.

---

## Phase 5 - Representative pilot

Do not make the 6,000-task production plan the first conversion test.

Create a representative Basic test plan containing examples of:

- Normal and multi-assignee tasks
- Attachments
- Checklists
- Labels
- Comments/task conversations
- Recurring tasks
- Unusual dates
- Guest assignments
- Teams integration
- Tasks created or updated by each automation

Convert the test plan and run UAT with actual business users.

### Minimum UAT acceptance

- Intended users can access the plan
- Licensed and unlicensed user behaviour matches expectations
- Task titles, status, dates, assignees and buckets are correct
- Critical attachments open with correct permissions
- Required Premium features work
- All critical automations work without duplication
- Teams links/tabs work
- Reporting works
- Mobile-dependent workflows are tested
- Archive/evidence package is approved

---

## Phase 6 - Production cutover

Use a short communicated edit freeze.

Cutover sequence:

1. Stop task-creating automations.
2. Freeze user edits.
3. Take final Excel/API evidence snapshot.
4. Confirm **2,700 tasks or fewer**.
5. Confirm no unresolved task dispositions.
6. Confirm business and compliance approval.
7. Confirm every critical replacement integration passed UAT.
8. Perform the Basic-to-Premium conversion in the current Planner experience.
9. Validate task counts, membership, permissions, attachments and representative records.
10. Update Teams tabs/bookmarks/documentation.
11. Re-enable only the new, tested integration paths.
12. Remove the edit freeze after validation.

The actual Microsoft conversion may be relatively quick. The preparation, data reduction and integration redesign are the substantial parts of the project.

---

## Phase 7 - Hypercare and rollback control

Microsoft's conversion process provides a downgrade/rollback path for a limited period, but it should **not** be treated as a normal backup. A downgrade returns the Basic plan to its pre-conversion state. Work subsequently performed in Premium is not automatically written back into that old Basic plan.

Use an initial **3-5 working day high-confidence hypercare period** and retain a daily Premium export/change record during that period.

Suggested rollback triggers:

- Material task-data mismatch
- Missing business-critical attachments
- Significant access failure
- Critical integration failure without a safe workaround
- Unresolved compliance issue
- Unacceptable operational performance

If rollback occurs, post-cutover Premium changes must be reconciled deliberately.

---

# Compliance gate

Planner Basic and Premium do not have identical storage and compliance characteristics. Premium plan data is Dataverse-backed, while attachments are stored in SharePoint. Microsoft's current Planner compliance documentation also distinguishes capabilities available for group-contained Basic plans and Premium plans.

Before deleting tasks or converting the plan, obtain a decision from the organisation's Records/Legal/Compliance owner covering:

- Retention period
- Legal holds
- Deletion eligibility
- Required archive fields
- Attachment preservation
- Archive location and permissions
- Later eDiscovery/investigation requirements

If the existing Basic plan is relied upon for a compliance capability that is not equivalent in Premium, treat that as a **go/no-go issue**, not a post-migration task.

---

# Non-technical stakeholder meeting talking points

### What is changing?

"We are moving the team's Planner from the standard task-management model to Premium so the team can use stronger project-management capabilities such as timelines, dependencies and workload planning."

### Why can't we simply switch it on?

"The existing plan contains about 6,000 tasks. Premium supports a maximum of 3,000 tasks in one plan, so we must first decide what current work belongs in the new plan and what historical work should be retained elsewhere."

### What are we proposing?

"We will migrate approximately 2,500-2,700 current tasks. This gives the new plan room to grow instead of starting immediately at Microsoft's maximum limit."

### Will historical information be lost?

"No information approved for retention will be deliberately discarded. Historical information will be exported and retained under an agreed records process before any deletion takes place."

### What is the biggest risk?

"The biggest risk is the integrations around Planner. Some existing automations and applications use the Basic Planner architecture and cannot simply be pointed at Premium. We will identify and test those before migration."

### Will everyone need a new licence?

"Not necessarily. Many users can perform routine task editing with their existing qualifying Microsoft 365 entitlement. Paid Planner licences should be allocated to people who actually require Premium planning features."

### What changes might users notice?

"Premium is not identical to Basic. Some familiar functions, including recurring-task and calendar/embedding scenarios, differ or may not be available in the same way. We will identify any workflows the team relies on and agree replacements before cutover."

### How will we protect the business?

"We will test a representative plan first, preserve the source data, run a controlled edit freeze for cutover, validate the new plan before reopening it, and maintain a rollback contingency during the initial support period."

### What decisions do we need from stakeholders?

1. Agree what counts as current versus historical work.
2. Nominate business owners to classify ambiguous tasks.
3. Confirm which Premium capabilities are actually required.
4. Approve any replacement for Basic-only workflows.
5. Approve the archive/retention approach.
6. Approve the cutover window and short edit freeze.
7. Agree who has final go/no-go authority.

### What does success look like?

- No more than 2,700 tasks at cutover
- Required historical records preserved
- All 80 intended users have appropriate access
- Required Premium functionality works
- All critical integrations pass testing
- No business-critical attachment or data loss
- Licensing matches actual user roles
- Support issues are manageable during hypercare

---

# Go/no-go checklist

## Data

- [ ] Total and active task counts confirmed.
- [ ] All 6,000 tasks classified.
- [ ] Migration population is **2,700 or fewer**.
- [ ] Historical archive reconciled and approved.
- [ ] Attachment preservation confirmed.

## Users and licensing

- [ ] All members, owners and guests inventoried.
- [ ] Premium feature users identified.
- [ ] Planner licences assigned before UAT.
- [ ] Power Automate licensing reviewed separately.

## Integrations

- [ ] Power Automate flows inventoried.
- [ ] Graph scripts/app registrations inventoried.
- [ ] Third-party integrations confirmed Premium-compatible.
- [ ] Teams tabs/deep links tested.
- [ ] SharePoint, Outlook, Loop and recurring-task dependencies reviewed.
- [ ] Reporting integrations tested.

## Governance

- [ ] Records/Legal/Compliance approval obtained where required.
- [ ] Retention and deletion rules approved.
- [ ] Business owner signs off task disposition.
- [ ] Named go/no-go decision owner confirmed.

## Cutover

- [ ] Representative pilot completed.
- [ ] UAT passed.
- [ ] Final source export captured.
- [ ] Automations paused.
- [ ] Edit freeze communicated.
- [ ] Final task count confirmed.
- [ ] Premium conversion completed and validated.
- [ ] Only tested integrations re-enabled.
- [ ] Hypercare and rollback process active.

---

# Current official Microsoft references

- Microsoft Learn: **Microsoft Planner limits**
- Microsoft Support: **Compare Microsoft Planner basic vs. premium plans**
- Microsoft Ireland: **Planner plans and pricing**
- Microsoft Graph documentation: **Planner API overview and Planner resource support**
- Microsoft Support/Learn: **Basic-to-Premium conversion and downgrade guidance**
- Microsoft Learn: **Planner compliance and data-storage documentation**

## Final recommendation

Proceed with the migration, but treat it as a **data-governance and integration migration**, not a licence toggle.

The safest design is:

**6,000 source tasks -> governed archive and cleanup -> 2,500-2,700 live tasks -> representative Premium pilot -> integration UAT -> controlled production conversion -> 3-5 day hypercare -> ongoing task-count and licence governance.**

Recheck Microsoft's Planner limits, Basic/Premium feature comparison, conversion guidance and Ireland pricing immediately before the production change because Planner continues to evolve.