# Migrating a Microsoft Planner Basic Plan to Premium for an 80-Person Team

## Executive summary

The migration is feasible, but the **6,000-task plan cannot be converted intact into a single Planner Premium plan**. Microsoft’s current Basic Planner limit is 9,000 total tasks but only 3,000 active tasks, whereas a Premium plan has a **3,000-total-task ceiling**. Consequently, at least **3,001 of the present 6,000 tasks must be excluded from the Premium plan**. I recommend a production target of **no more than 2,700 tasks**, requiring removal, archival, consolidation or separation of at least **3,300 tasks** and leaving 10% headroom for new work during and immediately after cutover. citeturn14search0turn14search3turn16search0

The safest approach is **not** to treat “mark completed” as task reduction. Completion helps with Basic Planner's 3,000-*active*-task limit, but completed tasks still count against Premium's 3,000-*total*-task limit. Historical completed work should instead be exported to a governed repository, obsolete/duplicate items deleted after approval, repetitive low-value tasks consolidated where appropriate, and genuinely still-active work that does not belong in the Premium project separated into another plan. citeturn14search0turn14search3

Microsoft's conversion process is materially more than a licence upgrade. Conversion creates the Premium plan and, on a successful conversion, makes the old Basic plan read-only and archives it for **90 days**. The organisation can downgrade during that period, but downgrade restores the Basic plan to its exact pre-conversion state: **changes subsequently made in Premium are not automatically copied back**. If Microsoft detects incompatible source data, conversion can instead fall back to an import-type process that leaves the Basic plan unchanged and creates a Premium copy containing compatible data. citeturn14search2turn14search4

There is also an architectural break. Microsoft explicitly states that applications and workflows written for Basic Planner must be modified for Premium; moreover, the Microsoft Graph Planner API supports **Basic plans only**, not Premium plans or tasks. Any Power Automate flow, bespoke Graph script or third-party product built around Basic Planner must therefore be inventoried before conversion and either retired or redesigned, normally around Premium's Dataverse/Project Schedule APIs. citeturn16search0turn15search1turn20search0

The most consequential governance issue is easy to miss. Microsoft’s current Planner compliance documentation states that Purview **eDiscovery and history are supported for group-contained Basic plans but not Premium plans**, while integrated audit logs span plan types; it also states that Planner retention policy is not currently supported. Premium plan data is stored in Dataverse, while Planner file attachments reside in SharePoint. For any organisation with legal hold, regulated-record or investigation requirements, compliance approval should therefore be a **hard migration gate**, not a post-migration task. citeturn15search0

For the 80 users, purchasing 80 Premium licences is **not inherently necessary**. Users with qualifying Planner-in-Microsoft-365 entitlement can perform basic editing in a shared Premium plan; a paid Planner licence is needed for advanced Premium capabilities. Microsoft currently prices Planner Plan 1 at **£7.70 per user/month** and Planner and Project Plan 3 at **£23.10 per user/month**, paid yearly and excluding VAT. At current UK list price, licensing all 80 would therefore be approximately **£7,392/year ex VAT for Plan 1** or **£22,176/year ex VAT for Plan 3**. A role-based model is usually substantially cheaper. citeturn16search2turn17search0

**Recommended decision:** migrate a curated operational dataset of approximately 2,500–2,700 tasks; preserve the historical record separately; licence only users who require Premium features; rebuild integrations before cutover; use a representative pilot; and keep the 90-day Microsoft downgrade window as a contingency rather than treating it as a conventional backup.

The following details remain **unknown and must be resolved during discovery**: tenant type and cloud; current Microsoft 365 SKUs; whether the plan is shared with a Microsoft 365 group; exact active/completed-task counts; task-age profile; guests; legal holds and retention schedules; Power Automate flows; Graph/app registrations; Teams tabs and deep links; SharePoint Planner web parts; Loop task lists; Outlook calendar usage; recurring tasks; Power BI/Dataverse reporting; third-party integrations; attachment locations and permissions; required mobile functionality; Premium licence count; and the required cutover date. Conversion is specifically not available to GCC customers under Microsoft's current conversion documentation, making tenant type an immediate eligibility check. citeturn14search2

## Current constraints, product changes and licensing

### Limits that matter to this migration

| Area | Basic Planner | Premium Planner | Migration implication |
|---|---:|---:|---|
| Total tasks per plan | 9,000 | **3,000** | 6,000 cannot fit in one Premium plan. citeturn14search0turn14search3 |
| Active tasks | 3,000 | Premium limit is expressed as 3,000 **total** tasks | Completing tasks alone cannot solve the conversion constraint. citeturn14search0turn14search3 |
| Buckets | 200 | No corresponding bucket limit is stated on Microsoft's current Premium limits page | Audit 200-bucket Basic ceiling; do not infer an undocumented Premium limit. citeturn14search0turn14search3 |
| Assignees/resources per task | 20 | 20 | Existing tasks with ≤20 assignees fit this dimension. citeturn14search0turn14search3 |
| Total Premium resources | n/a as a directly equivalent Basic limit | 300 | An 80-person team is comfortably inside the published Premium resource ceiling, subject to any additional resources/guests. citeturn14search3 |
| Basic checklist items | 20/task | — | Consolidating microtasks into Basic checklists is possible up to 20 items/task, but sacrifices independent task metadata. citeturn14search0 |
| Premium task links | — | 2,000/project; 20 predecessor+successor links/task | Relevant when dependencies are introduced after migration. citeturn14search3 |
| Premium custom fields | — | 10/project | Design custom metadata deliberately rather than recreating arbitrary source fields. citeturn14search3 |
| Premium goals | — | 10/project | Confirm whether business structure needs more than ten top-level goals. citeturn14search3 |
| Premium hierarchy | — | 10 levels | More than adequate for most work breakdown structures, but worth checking imported hierarchies. citeturn14search3 |
| Premium project duration | — | 3,650 days | Long-running programme plans need review. citeturn14search3 |

Microsoft's dedicated Premium limits documentation, updated July 2025, gives **300 total resources per project**. Some older Microsoft service-description material has historically shown a lower number, so the dedicated limits page should be treated as the current published engineering limit and rechecked immediately before production cutover because Microsoft also reserves the right to change Planner limits. citeturn14search0turn14search3

### Basic and Premium are not a simple superset relationship

Premium gives the capabilities most organisations migrate for: Timeline/Gantt, People view, dependencies, milestones, custom fields, conditional colouring, critical path, coloured buckets, backlog/sprints, goals, custom calendars and task history, although actual access to some features depends on the user's paid subscription. citeturn16search0turn17search0

However, Microsoft's current comparison still lists several **Basic-only** capabilities: Schedule view, Planner-to-Outlook calendar, the SharePoint Planner web part/full-page integration, Teams Mobile Tasks support, recurring tasks and adding plans to Loop. Premium task conversations are supported, but Microsoft says the Premium plan must be added to a Teams channel for conversations. These gaps must be treated as migration requirements rather than assumed to “come along” automatically. citeturn16search0

Recurring tasks are particularly important. Current Basic Planner can generate the next recurrence when the prior occurrence is completed, whereas Microsoft's downgrade guidance explicitly identifies recurring-task dependency as a reason a team might need to remain on Basic. Inventory recurring tasks before migration and decide whether to redesign their recurrence through automation, retain them in a Basic feeder plan, or replace them with another approved operating procedure. citeturn21search5turn14search4

### Recent changes that alter implementation assumptions

Microsoft has changed Planner substantially over the last eighteen months. The migration design should use the **current Planner experience**, not older Project-for-the-web assumptions.

| Change | Why it matters |
|---|---|
| **June 2025 – bulk editing for Basic plans.** Microsoft added multi-task updating in Grid view, making pre-migration triage of fields such as status, priority and assignments materially easier. It should be used for classification, but should not be mistaken for a documented mass-delete facility. citeturn19search0 |
| **August 2025 – transition to unified Planner.** Microsoft transitioned users away from the separate Project-for-the-web experience towards the unified Planner experience. Some older conversion documentation still contains Project-for-the-web redirection language, so test actual current URLs, tabs and deep links in the tenant rather than encoding the older behaviour. citeturn18search3turn20search22turn14search2 |
| **February 2026 – refreshed Basic Planner UI.** Microsoft began rolling out a modernised interface, improved navigation, responsive layouts, a Goals experience and task chat. Training and migration screenshots/runbooks should therefore be prepared against the tenant's actual current UI, not legacy Planner screenshots. citeturn18search4 |
| **June 2026 – current Planner licensing documentation refreshed.** Microsoft states Planner is included in eligible Microsoft 365/Office 365 suites for Basic use/basic editing of Premium, while Planner Plan 1 or Planner and Project Plan 3 supplies Premium capabilities. citeturn16search2 |
| **June 2026 – Planner Agent reached GA in Microsoft 365 Copilot.** AI functionality is a separate licensing/design consideration rather than a prerequisite for this migration. Microsoft's current UK pricing page states that Planner Agent requires Microsoft 365 Copilot, with additional Planner-related AI functionality associated with paid Planner plans. citeturn18search2turn17search0 |
| **30 September 2026 – Project Online retirement.** This is only weeks after the date of this report. Do not design new integration or rollback dependencies around Project Online simply because Planner and Project Plan 3 still contains legacy Project entitlements. Microsoft says Project desktop is unaffected. citeturn20search6 |

### Licence model for 80 users

A paid licence is required for a user to access Premium features, but Microsoft explicitly permits Planner-in-Microsoft-365 users to perform basic editing in Premium plans created by licensed users, including assigning tasks, changing dates and adding attachments. Planner Plan 1 is required for additional views such as Timeline, People and Goals; Planner and Project Plan 3 is needed for higher-end capabilities such as Assignments view and includes task history, baselines/critical path and more advanced project management functionality. citeturn17search0turn21search4

A sensible role model is therefore:

| User cohort | Likely entitlement | Indicative rationale |
|---|---|---|
| Most of the 80 contributors | Existing qualifying Microsoft 365 licence | Update normal task fields without buying 80 Premium seats. citeturn16search2turn17search0 |
| Workstream leads / schedulers | Planner Plan 1 | Timeline, People, Goals and structured Premium planning. citeturn17search0 |
| Programme/project managers needing advanced scheduling/history | Planner and Project Plan 3 | Task history, Assignments view, baselines/critical path and more advanced dependencies. citeturn17search0turn17search1 |
| Automation service owners | Planner licence **plus separate Power Platform assessment** | Planner licensing must not be assumed to license arbitrary Premium/custom Power Automate connectors. citeturn20search3turn20search7 |

At UK list prices current on **12 August 2026**, illustrative annual ex-VAT costs are:

| Premium users | Plan 1 | Plan 3 |
|---:|---:|---:|
| 5 | £462 | £1,386 |
| 10 | £924 | £2,772 |
| 20 | £1,848 | £5,544 |
| 80 | £7,392 | £22,176 |

These figures use Microsoft's £7.70 and £23.10 per-user/month annual-subscription list prices; enterprise agreements, CSP pricing and discounts may differ. citeturn17search0

For Power Automate, a rebuilt flow that uses premium/custom connectors may require Power Automate Premium licensing or a Process licence. Microsoft states that Power Automate Premium includes premium connectors, while a Process licence assigned to a cloud flow allows that flow to use standard, premium and custom connectors for organisational users. Licensing should therefore be assessed **flow by flow**, particularly where Premium Planner/Dataverse is combined with SharePoint, SQL, custom APIs or third-party systems. citeturn20search3turn20search7

## Task reduction, archival and compliance design

### Recommended reduction target

Do not aim for 2,999. A plan landing one task below its absolute technical ceiling has no operating margin and could exceed the cap through normal task creation during cutover.

**Recommended migration acceptance threshold: ≤2,700 tasks.**

Starting with 6,000 tasks:

- absolute minimum reduction to get below 3,000 = **3,001 tasks**;
- recommended reduction to 2,700 = **3,300 tasks**;
- a more conservative 2,500-task target = **3,500 tasks**.

The 2,700 recommendation is an implementation control rather than a Microsoft requirement; Microsoft's published hard Premium limit remains 3,000 total tasks. citeturn14search3

The first audit should calculate at least: total tasks, active/completed counts, completed age distribution, tasks created/updated in the last 30/90/365 days, orphaned assignees, unassigned tasks, duplicates, tasks without meaningful descriptions or dates, recurring-series tasks, tasks with attachments, comments/task chat, checklists, external references and automation-created tasks. With 6,000 total tasks under the current Basic limit, the active count should also be explicitly checked against Basic's 3,000-active-task ceiling. citeturn14search0

### Reduction options

| Strategy | Appropriate use | Advantages | Principal drawbacks | Recommendation |
|---|---|---|---|---|
| **Governed export + remove from live plan** | Old/completed work retained for audit/reference | Highest task-count reduction; low operational overhead; can preserve structured metadata | Historical items cease to be interactive Planner tasks; richer evidence needs more than a simple spreadsheet | **Primary archive strategy** |
| **Separate Basic archive plan** | A small subset of historical tasks must remain navigable as Planner tasks | Familiar UI; can preserve more Planner context | Moving to another plan is operationally expensive; UI Move supports a single task at a time; some metadata changes across plans | Use selectively. citeturn21search0 |
| **Split current work into multiple plans** | 3,000+ tasks are genuinely still operational | No arbitrary deletion; clearer workstream boundaries | Fragmented reporting, governance and integration; multiple plans to maintain | Prefer over destructive deletion if business scope genuinely exceeds one project |
| **Consolidate microtasks into checklists/subtasks** | Many tasks are merely steps of one deliverable | Large reduction with retained operational detail | Individual task dates, assignees, history and reporting granularity may be lost; Basic checklist has 20-item limit | Use on genuinely granular work only. citeturn14search0 |
| **Delete duplicates/test/obsolete tasks** | No retention or business value | Fast, cleanest dataset | Destructive; wrong classification can destroy evidence | Only against signed-off deletion manifest |
| **Mark complete only** | Work is finished but record still belongs in plan | Easy | **Does not solve Premium total-task ceiling** | Insufficient by itself. citeturn14search0turn14search3 |

The preferred combination is **export/archive + approved deletion + selective consolidation + scope splitting**. Attempting to “compress” thousands of legitimate historical records into checklists merely to satisfy a product limit would compromise traceability.

Microsoft now supports copying multiple Basic tasks, but moving between plans is still a single-task operation. When a task is copied to another plan, comments and task chat are not copied. When a task is *moved* to another plan in the same Microsoft 365 group, Microsoft states that comments, assignees and attachments are kept, but goals, labels and custom-column values are removed. Moving across groups also removes comments and can affect attachment access. Consequently, a same-group “archive plan” offers better fidelity than a cross-group move but remains awkward for thousands of tasks and should not be the default archival method. citeturn21search0

### Evidence and retention package

Before any deletion, create three artefacts:

**A native Planner Excel export** for business-readable review. Microsoft supports Export to Excel for both Basic and Premium plans. citeturn16search0

**A richer Basic-plan API extract** taken while Graph still has access, containing task IDs and task-detail data needed for reconstruction/audit. Microsoft Graph Planner supports Basic plans and exposes plan tasks plus their detail resources; after conversion it cannot be used to read Premium plan/tasks. citeturn15search1

**An approved deletion/archive manifest**, for example:

```csv
PlanId,TaskId,ETag,Title,Bucket,Status,CompletedDate,Assignees,RetentionClass,Disposition,Reason,EvidenceLocation,ApprovedBy,ApprovedDate
abc123,t-001,"W/""JzEtVGFzay...""","Legacy deployment","Closed",100,2024-02-14,"user@org.co.uk","Project-7Y","ArchiveDelete","Completed > retention cutoff","/Records/Planner/2026-08/export.json","ProgrammeOwner",2026-09-02
```

Store the evidence in an organisation-controlled repository such as a governed SharePoint records library, with the appropriate retention/sensitivity controls determined by the organisation's records policy. Planner attachments themselves are stored in SharePoint, while Premium task data resides in Dataverse; therefore attachment retention and Planner task-data retention must be considered separately. citeturn15search0

### Compliance gate

This migration changes the compliance surface. Microsoft's currently published Planner compliance page says:

- group-contained Basic plans support Purview eDiscovery and history;
- Premium plans currently do **not** receive that same Planner eDiscovery/history support;
- integrated audit logs operate across Planner plan types/containers;
- Planner retention policy is not currently supported;
- Premium plan data is stored in Dataverse;
- file attachments are stored in SharePoint. citeturn15search0

Therefore, before deletion or conversion, the organisation's Records/Legal/Compliance owner should sign off on: retention period, legal holds, deletion eligibility, evidentiary export fields, attachment preservation, where the exported evidence will be stored, who can access it and how later discovery requests will be serviced.

**A legal hold or regulatory requirement that depends on today's Basic-Plan Purview eDiscovery behaviour is a possible migration blocker** until an acceptable replacement control has been approved. That conclusion is an inference from Microsoft's documented difference in Purview support. citeturn15search0

## Step-by-step migration and integration reconfiguration

### Discovery and audit

**Establish technical eligibility.** Record tenant/cloud, Basic plan ID, Microsoft 365 group/container ID, plan owners, group owners, members/guests and licences. Confirm that the source is a Microsoft 365-group-shared Basic plan: Microsoft currently documents group-shared Basic plans as eligible for conversion, while Published Plans and Loop task-list plans cannot be converted. Conversion is not available in GCC under the published conversion procedure. citeturn14search2

**Freeze a baseline.** Capture the plan's current total and active task counts, bucket structure, label definitions, membership, recurring tasks, calendar settings and rate of new-task creation. Export Excel and take an API-level snapshot before cleanup.

**Build a task disposition dataset.** Assign every task one of: `Migrate`, `Archive`, `Consolidate`, `Move-to-other-plan`, `Delete`, `Needs-business-review`. No task should be deleted because of age alone unless the age rule corresponds to an approved retention/disposition policy.

**Inventory every integration by source-plan ID.** Search Power Automate solutions/flows, application registrations, Graph scripts, Teams tabs, SharePoint pages, Outlook calendar links, Loop pages, Power BI models and third-party platforms for the Basic plan ID or group ID.

**Identify Basic-only user behaviour.** Specifically interview owners of recurring tasks, Outlook calendar integration, SharePoint Planner web parts, Loop task lists and Teams mobile use because Microsoft's current feature matrix does not treat all of these as Premium equivalents. citeturn16search0

### Reduce the task set

Pause or temporarily gate automated processes that create tasks. Otherwise the cleanup target can drift while the team is reducing it.

Use Planner's Basic Grid bulk editing to normalise status, priority, owner and other classification fields where useful. Microsoft added bulk-edit capability to Basic plans in 2025. citeturn19search0

Run the approved archival/export process. Validate row/task counts and evidence files before deleting anything.

Consolidate true microtasks into a parent task/checklist only where business owners explicitly accept the loss of independent task-level granularity. A Basic Planner task has a maximum of 20 checklist items. citeturn14search0

Separate active work that belongs to a different project/workstream into another plan rather than deleting it merely to satisfy Premium's cap.

Delete only from an approved manifest and stop at a target of **≤2,700**, then run a second reconciliation against the baseline.

### Example Basic-plan Graph/PowerShell extraction and controlled deletion

The Microsoft Graph Planner API can be used **before** migration to query a Basic plan:

```http
GET /v1.0/planner/plans/{plan-id}/tasks
```

Microsoft documents that Planner resources use ETags and that PATCH/DELETE operations require the latest ETag through `If-Match`. Premium plans/tasks are explicitly unavailable through the Planner Graph API. citeturn15search1

A simplified PowerShell snapshot pattern is:

```powershell
# Microsoft Graph PowerShell SDK
Connect-MgGraph -Scopes "Tasks.ReadWrite","Group.Read.All"

$planId = "<BASIC-PLAN-ID>"
$uri = "https://graph.microsoft.com/v1.0/planner/plans/$planId/tasks"

$allTasks = @()

while ($uri) {
    $page = Invoke-MgGraphRequest -Method GET -Uri $uri
    $allTasks += $page.value
    $uri = $page.'@odata.nextLink'
}

# Preserve the raw task objects, including IDs and ETags.
$allTasks |
    ConvertTo-Json -Depth 20 |
    Set-Content ".\planner-basic-tasks.json" -Encoding UTF8

# Business-readable inventory.
$allTasks |
    Select-Object id, title, percentComplete, startDateTime,
                  dueDateTime, createdDateTime, '@odata.etag' |
    Export-Csv ".\planner-basic-tasks.csv" -NoTypeInformation -Encoding UTF8
```

For a high-fidelity archive, also query each task's `/details` resource to capture descriptions, checklists and reference information before deletion. API exports should be tested against throttling and error-handling requirements rather than executed as an uncontrolled one-off script. Microsoft documents the Graph Planner data model and ETag concurrency requirements. citeturn15search1

A deletion script should consume a *separately approved* CSV rather than selecting tasks inside the destructive script:

```powershell
$approved = Import-Csv ".\delete-approved.csv" |
    Where-Object { $_.Approved -eq "YES" }

foreach ($row in $approved) {
    if ([string]::IsNullOrWhiteSpace($row.TaskId) -or
        [string]::IsNullOrWhiteSpace($row.ETag)) {
        Write-Warning "Skipping incomplete row: $($row.Title)"
        continue
    }

    $headers = @{
        "If-Match" = $row.ETag
    }

    try {
        Invoke-MgGraphRequest `
            -Method DELETE `
            -Uri "https://graph.microsoft.com/v1.0/planner/tasks/$($row.TaskId)" `
            -Headers $headers

        Write-Host "Deleted approved task $($row.TaskId)"
    }
    catch {
        # Do not silently retry conflicts: re-read the task and investigate
        # because an ETag mismatch means the record changed after approval.
        Write-Warning "FAILED $($row.TaskId): $($_.Exception.Message)"
    }
}
```

This deliberately fails rather than overriding concurrency conflicts: an ETag mismatch is evidence that the task changed after the deletion decision and should be re-reviewed. Microsoft requires `If-Match` for Planner modifications/deletions and documents 409/412 conflict handling around ETags. citeturn15search1

For very large scripted operations, Microsoft Graph JSON batching supports grouping requests, but batch size is limited to 20 individual requests; throttling and retries still have to be engineered. citeturn9search22

### Reconfigure integrations before conversion

| Current dependency | Premium impact | Required action |
|---|---|---|
| **Microsoft Graph Planner API** | Cannot access Premium plans/tasks. citeturn15search1 | Replace Premium task operations with the supported Premium/Dataverse architecture; do not merely change a plan ID. |
| **Power Automate using Basic Planner** | Microsoft explicitly says workflows must be modified after conversion. citeturn14search2 | Rebuild/test with Premium's supported Dataverse/Project Schedule mechanism, preferably in solutions; Microsoft documents V2 Project Schedule APIs for Power Automate. citeturn20search0 |
| **Third-party app using Planner Graph** | Will lose Premium task API access. citeturn15search1 | Obtain vendor confirmation of Premium support before cutover; otherwise redesign or retire. |
| **Teams tab** | Premium is usable in Teams; conversations require plan added to a Teams channel. citeturn16search0 | Re-pin/validate tabs, permissions, task conversations and deep links after conversion. |
| **SharePoint Planner web part/full-page app** | Microsoft's feature comparison lists SharePoint integration as Basic-only. citeturn16search0 | Replace with approved navigation/link/reporting experience; separately retain attachment libraries and permissions. |
| **Loop plan/task list** | Premium plan cannot be added to Loop; Loop task-list plans are not eligible for direct conversion. citeturn16search0turn14search2 | Keep affected workload Basic or redesign its boundary. |
| **Outlook Planner calendar** | Listed as Basic-only. citeturn16search0 | Identify calendar-dependent users and replace the process before cutover. |
| **Recurring Basic tasks** | Listed as Basic-only in Microsoft's current Basic-v-Premium comparison. citeturn16search0 | Use a Basic feeder plan or approved automated recurrence design; test licensing carefully. |
| **Power BI/custom reporting** | Premium data is Dataverse-backed. citeturn15search0 | Repoint/test schema, security roles, refresh identities and downstream transformations. |

Where Power Automate redesign introduces premium or custom connectors, explicitly determine whether the flow is covered by a user Power Automate Premium licence or a flow-level Process licence. Microsoft states that the latter can license a cloud flow to use standard, premium and custom connectors for organisational users. citeturn20search3turn20search7

### Permissions and conversion

Ensure the underlying Microsoft 365 group has at least two accountable owners and reconcile its membership against the intended 80-person team. Conversion preserves access for users who already have access to the Basic plan, and Microsoft states that Microsoft 365-licensed users and guests can continue to work in the Premium plan subject to their permitted capabilities. citeturn14search2

Assign Premium licences **before UAT** to the people who will test Premium-specific capabilities. Avoid buying all 80 until the access matrix demonstrates the business requirement.

At cutover:

1. Stop task-creating automations.
2. Communicate a brief edit freeze.
3. Take the final Excel/API evidence snapshot.
4. Confirm total task count ≤2,700 and no unresolved disposition items.
5. Confirm Compliance sign-off.
6. Confirm all critical replacement integrations passed UAT.
7. Open the Basic plan in current Planner and invoke the Premium conversion option from the plan's Premium-view controls.
8. Monitor for either successful in-place conversion or Microsoft's incompatibility/import fallback.
9. Validate memberships, task counts and representative task fidelity.
10. Re-enable only the **new tested** integration paths. citeturn14search2

Microsoft says conversion itself can take only a few minutes; the significant effort is the preparation, data governance and integration redesign. citeturn14search2

## Testing, rollback, timeline and resources

### Test strategy

Do not make the 6,000-task production plan the first experiment. Build a representative test Basic plan containing samples of every important construct: multi-assignee tasks, attachments, checklists, labels, comments/task chat, recurring tasks, unusual dates, guest assignments, Teams integration and tasks produced by each automation.

A practical UAT acceptance standard is:

| Test | Proposed acceptance criterion |
|---|---|
| Task population | Production candidate ≤2,700; count reconciles to approved manifest |
| Core field fidelity | 100% of a statistically/operationally representative sample matches title, status, dates, assignees and bucket |
| Attachments | 100% of critical sample opens with correct permissions |
| Membership | All intended 80 users can reach plan; role/licence behaviour matches matrix |
| Premium capabilities | Licensed users can use required Timeline/People/Goals/dependency/history features appropriate to their licence |
| Power Automate | Every critical flow passes happy-path, error-path and duplicate-prevention tests |
| Teams | New tab/deep links and task conversations operate as intended |
| SharePoint | No broken business-critical link to supporting files |
| Third party | Vendor-supported integrations pass end-to-end |
| Compliance | Export is complete, access-controlled and signed off |
| Performance | Representative Grid/Board/Timeline usage acceptable with ~2,700 tasks |
| Mobile | Tested for any mobile-dependent user cohort because some Premium endpoints differ from Basic. citeturn16search0 |

### Rollback is a restore-to-cutover-state, not an undo button

Successful conversion gives a particularly useful 90-day contingency: Microsoft makes the Basic plan read-only/archive-held for 90 days and allows downgrade during that period. But Microsoft is explicit that downgrade restores the Basic plan to **the point at which it was upgraded**. Edits made afterwards in Premium must be copied back manually. citeturn14search2turn14search4

Accordingly, establish a short **high-confidence rollback period of approximately 3–5 working days**, even though Microsoft's technical downgrade window lasts 90 days. During hypercare, retain a daily Premium Excel export/change log. If a severe defect forces downgrade, use that evidence to reconcile post-cutover changes manually.

Suggested rollback triggers are: material conversion/import incompatibility; missing business-critical attachments; more than ~1% unexplained critical-field mismatches; inability of a significant user cohort to access the plan; failure of a core integration without an acceptable workaround; or discovery of an unresolved compliance problem. These thresholds are proposed project controls, not Microsoft product limits.

Do **not** plan on Microsoft Graph as the mechanism for exporting changed Premium tasks during rollback because Microsoft's Planner Graph API does not support Premium plans. Use Premium-supported export/Dataverse mechanisms instead. citeturn15search1turn16search0

### Illustrative schedule

The Mermaid timeline rendered with this report assumes work begins **Monday, 17 August 2026**, production conversion on **10 September 2026**, and a subsequent 90-day Microsoft downgrade window. The schedule is deliberately front-loaded around inventory, records decisions and integration work; those are much higher-risk than the few-minute conversion operation itself. Microsoft's Project Online retirement on 30 September 2026 is also a reason not to introduce new dependencies on that legacy service during this project. citeturn14search2turn20search6

A textual equivalent is:

| Period | Main activity | Exit criterion |
|---|---|---|
| 17–21 Aug | Discovery, licence, compliance and integration audit | Complete inventory and eligibility decision |
| 24–27 Aug | Archive/export pilot | Evidence package independently reconciled |
| 24 Aug–4 Sep | Integration rebuild in parallel | Critical replacements pass technical test |
| 26 Aug–4 Sep | Business classification and reduction | ≤2,700 approved production tasks |
| 3–9 Sep | Representative conversion test and UAT | Business/IT/Compliance go decision |
| 10 Sep | Production freeze, final export and conversion | Premium plan validated |
| 10–18 Sep | Hypercare | No unresolved severity-one defects |
| To 9 Dec approximately | Microsoft 90-day downgrade contingency | Formal closure after rollback period expires |

The final date of the 90-day period should be taken from the actual conversion timestamp shown by Microsoft rather than from this illustrative calendar. Microsoft states the Basic plan is held for 90 days after conversion. citeturn14search2

### Resource estimate

For an 80-person team and 6,000-task source, a realistic implementation is approximately **35–55 person-days**, excluding a major rewrite of an unsupported third-party system. This is a project estimate, not a Microsoft figure.

| Role | Estimated effort | Primary responsibility |
|---|---:|---|
| Project/change lead | 8–12 days | Governance, stakeholder decisions, cutover/change communications |
| Planner/Power Platform engineer | 12–18 days | Extraction, automation, Premium configuration, integration rebuild |
| Microsoft 365 / Entra / Teams admin | 3–5 days | Groups, ownership, licensing, Teams |
| Compliance/records specialist | 3–5 days | Retention, legal hold, export evidence, sign-off |
| Integration owners | 2–5 days each | Rebuild/test individual flows/apps |
| Business SMEs / UAT users | 8–16 days aggregate | Task disposition and acceptance |
| Service desk/training | 2–4 days | User communications and hypercare |

The largest schedule uncertainty is not the Microsoft conversion process; it is **human disposition of 3,300+ tasks plus unknown integration complexity**.

## Risks, stakeholder talking points and implementation checklist

### Principal risks and mitigations

| Risk | Likelihood / impact | Mitigation |
|---|---|---|
| **Task count remains too close to 3,000** | High / High | Target ≤2,700; freeze automated creation before final reconciliation. Premium hard limit is 3,000. citeturn14search3 |
| **Completed tasks are mistaken for “removed” tasks** | High / High | Measure total, not just active tasks; Premium ceiling counts total tasks. citeturn14search0turn14search3 |
| **Loss of legal/eDiscovery capability** | Medium–High / Very High | Compliance gate; preserve controlled evidence; validate legal-hold requirements because Microsoft currently distinguishes Basic and Premium Purview eDiscovery support. citeturn15search0 |
| **Power Automate stops after migration** | High where flows exist / High | Inventory by plan ID; rebuild before cutover using Premium-supported APIs; test licensing. Microsoft explicitly requires workflow modification. citeturn14search2turn20search0 |
| **Third-party/Graph app fails** | High if Graph-based / High | Vendor sign-off or replacement: Planner Graph does not expose Premium. citeturn15search1 |
| **Unexpected Basic-only feature loss** | Medium / Medium–High | Audit recurring tasks, Outlook calendar, SharePoint web parts, Loop and mobile use. citeturn16search0 |
| **Archive does not preserve enough evidence** | Medium / High | Native Excel + richer API extract + attachment inventory + signed manifest before deletion |
| **Cross-plan archive loses metadata** | Medium / Medium | Prefer governed export; Microsoft documents comments/labels/goals differences when copying/moving tasks. citeturn21search0 |
| **Rollback causes loss of post-cutover work** | Medium / High | Daily Premium export/change log during hypercare; downgrade restores pre-conversion state only. citeturn14search4 |
| **Over-licensing all 80 users** | Medium / Medium | Role-based licence matrix; ordinary M365 users retain basic edit capabilities in shared Premium plans. citeturn17search0turn16search2 |
| **Under-licensing automation** | Medium / High | Separate Power Automate licensing review for premium/custom connector use. citeturn20search3turn20search7 |
| **Outdated implementation instructions** | Medium / Medium | Test against actual tenant; Microsoft transitioned to unified Planner and refreshed its UI during 2025–26. citeturn18search3turn18search4 |
| **Building on Project Online just before retirement** | Low–Medium / High | Exclude Project Online from new design; it retires 30 September 2026. citeturn20search6 |

### Non-technical stakeholder talking points

- **This is a controlled clean-up as well as an upgrade.** The present Planner can contain 6,000 historical tasks, but Premium can hold only 3,000 in total; we therefore propose keeping roughly 2,700 current tasks and retaining older information separately. citeturn14search0turn14search3
- **Historical information will be retained according to policy before anything is deleted.** The archive will be reconciled and approved by business and compliance owners.
- **Not everybody needs a new Premium licence.** Most team members can continue routine task editing with qualifying Microsoft 365 licences; Premium licences should be assigned to users who require advanced planning capabilities. citeturn17search0
- **The principal technical risk is integration compatibility, not the Planner conversion itself.** Microsoft explicitly requires Basic Planner workflows and apps to be modified for Premium, and Graph Planner integrations cannot simply point at the Premium plan. citeturn14search2turn15search1
- **There is a Microsoft-backed 90-day downgrade option**, but it restores the old plan to its conversion-day state, so post-migration work must be separately captured during the initial support period. citeturn14search2turn14search4
- **Compliance is a go/no-go decision.** Microsoft's current documentation gives group-based Basic plans stronger Planner-specific Purview eDiscovery/history support than Premium plans, so Records/Legal approval is required before the move. citeturn15search0
- **A five-week preparation-and-cutover programme is realistic** under the assumptions in this report; the bulk of the work is deciding what to retain and rebuilding unknown integrations, rather than clicking the conversion control.

### Implementation checklist

**Governance and discovery**

- [ ] Confirm commercial/GCC/GCC High/DoD tenant and Premium conversion eligibility. citeturn14search2
- [ ] Record plan ID, group ID, owners, 80 members, guests and current licences.
- [ ] Count total versus active tasks and confirm bucket/task-limit compliance. citeturn14search0
- [ ] Inventory recurring tasks, Outlook calendar, Loop, SharePoint web parts and mobile requirements. citeturn16search0
- [ ] Inventory Power Automate, Graph scripts/app registrations, Teams tabs, reporting and third parties.
- [ ] Obtain Records/Legal decision on retention, eDiscovery and legal holds. citeturn15search0

**Data reduction**

- [ ] Capture initial Planner Excel export.
- [ ] Capture Basic Planner Graph/JSON export and attachment inventory. citeturn15search1
- [ ] Classify all 6,000 tasks.
- [ ] Pilot archive and independently reconcile task counts.
- [ ] Approve deletion manifest.
- [ ] Consolidate only genuinely granular work.
- [ ] Move/split current work that belongs in another plan.
- [ ] Pause automated task creation.
- [ ] Reduce source candidate to **≤2,700 total tasks**.
- [ ] Take final pre-conversion export and evidence hash/version.

**Licensing and integrations**

- [ ] Assign Plan 1/Plan 3 only to roles needing Premium functionality. citeturn17search0
- [ ] Review Power Automate Premium/Process licensing for rebuilt flows. citeturn20search3turn20search7
- [ ] Replace Basic Planner Graph integrations; Graph Planner does not support Premium. citeturn15search1
- [ ] Rebuild critical flows with Premium-supported Dataverse/Project Schedule APIs. citeturn20search0
- [ ] Obtain vendor certification for every third-party integration.
- [ ] Replace Basic-only SharePoint/Loop/calendar/recurrence processes where required. citeturn16search0
- [ ] Configure/test Teams channel and Premium-plan task conversations. citeturn16search0

**Testing and cutover**

- [ ] Convert representative test plan first.
- [ ] Complete field, attachment, permission, Teams, automation and mobile UAT.
- [ ] Obtain business, IT and Compliance go/no-go approvals.
- [ ] Apply production edit freeze.
- [ ] Verify final task total ≤2,700.
- [ ] Convert through current Planner Premium conversion controls. citeturn14search2
- [ ] Check for Microsoft's successful-conversion path versus incompatibility/import fallback. citeturn14search2
- [ ] Reconcile task/member counts and representative records.
- [ ] Re-enable only tested Premium-compatible integrations.
- [ ] Update Teams tabs, bookmarks, documentation and user guidance.

**Hypercare and closure**

- [ ] Retain daily Premium export/change log during the initial rollback period.
- [ ] Monitor automation failures, access errors and task-count growth.
- [ ] Keep downgrade criteria and named decision authority available.
- [ ] Remember that downgrade returns to **pre-conversion state**, not current Premium state. citeturn14search4
- [ ] Maintain archived evidence under the approved retention regime.
- [ ] Review Premium licence utilisation after 30–60 days.
- [ ] Close rollback contingency only after the Microsoft 90-day Basic-plan retention window expires. citeturn14search2

**Overall recommendation:** proceed, subject to the compliance gate and integration inventory, using **≤2,700 tasks as the cutover ceiling, a governed historical archive, role-based Premium licensing and pre-cutover rebuilding of every Basic Planner API/workflow dependency**. This design provides sufficient headroom beneath Microsoft's 3,000-task Premium limit, minimises unnecessary licence expenditure and preserves the strongest practical rollback path available under Microsoft's current Planner conversion model. citeturn14search2turn14search3turn15search0turn15search1turn17search0