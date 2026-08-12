# Migration Architecture: Upgrading Microsoft Planner from Basic to Dataverse Premium

## System Architecture and Key Technical Boundaries

Transitioning a Microsoft Planner plan from Basic to Premium moves the data layer from an isolated Microsoft 365 microservice to Microsoft Dataverse (`msdyn_projecttask` tables). This transition unlocks dynamic Gantt timelines, Finish-to-Start/SS/FF/SF dependencies, milestones, and custom fields. However, Dataverse imposes strict system constraints that require immediate remediation before cutover.

| Dimension | Basic Plan (Current State) | Premium Plan (Target State) | Technical Impact & Remediation |
| --- | --- | --- | --- |
| **Max Task Cap** | 9,000 tasks | 3,000 tasks (Hard Ceiling) | **6,000 tasks must be reduced by >50%** to stay under the 3,000 cap. |
| **Data Storage** | M365 Microservice Store | Dataverse Relational Engine | Unlocks advanced scheduling; requires Dataverse environment access. |
| **Cap Breach Behavior** | Disables new task creation | Silent drop of tasks >3,000 during import | Critical risk: Tasks exceeding 3,000 are omitted without warning. |
| **Custom Fields** | Basic UI metadata/labels | 10 flat fields max | Limited to text, date, number, boolean, or single-choice. |
| **Checklist Limit** | 20 items per task card | 20 items per task card | Key mechanism to collapse micro-tasks into parent items. |
| **Automation API** | Standard Planner Connector / Graph API | Project Schedule API via Dataverse | All Power Automate flows require re-authoring. |
| **Licensing (80 Users)** | Included in M365 suites | Tiered Hybrid (M365 Base + Plan 1/3/5) | ~80% of users require **$0 incremental license spend**. |

---

## Task Reduction Strategy (6,000 to <2,500 Target)

To prevent silent task drops during Dataverse ingestion, total plan volume must be reduced beneath a **2,500-task target**. Operating at 2,500 tasks maintains a 500-task buffer for project expansion.

1. **Historical Archival (Estimated ~2,000 Task Reduction)**
   * Filter and extract all tasks completed more than 90 days ago using Microsoft Graph API endpoints (`/v1.0/planner/tasks`).
   * Export legacy data into a dedicated SharePoint Online list or SQL database for historical auditing, then purge them from the active plan.

2. **Checklist Aggregation (Estimated ~1,500 Task Reduction)**
   * Identify sequential, atomic sub-steps currently created as individual task cards.
   * Merge up to 20 related micro-tasks into a single parent task using task checklists.

3. **Program Decomposition (Estimated ~1,000 Task Reduction)**
   * If volume remains high, split remaining core work streams across logical boundaries into 2–3 sub-plans (e.g., *Phase 1 Execution* and *Phase 2 Operations*).
   * Aggregate these sub-plans using the **Planner Portfolios** view to maintain executive visibility.

---

## Upgrade Mechanics and Fallback Safeguards

Upgrades are initiated inside the Planner app by a user holding a Planner Plan 3 or Plan 5 license (*More options (...) -> Add premium views*).

* **In-Place Upgrade (Standard Path)**: If task volume is <3,000 and data is compatible, the plan converts directly in-place. All M365 Group access permissions are maintained. The original Basic plan enters a **90-day read-only archive**; administrators can trigger a complete downgrade within this 90-day window if needed.
* **Fallback Import Flow (Data Incompatibility Path)**: If data validation fails or custom fields conflict, the original Basic plan remains active and untouched. A copied Premium instance is generated for the initiating user only. The administrator must remediate the basic plan, re-assign team security roles, and complete cutover.

---

## Integration Engineering and API Remediation

Legacy Power Automate flows and Graph API integrations targeting standard Planner endpoints will immediately break post-migration.

* **Power Automate Cloud Flows**: Must be updated to use the Dataverse connector. Direct database updates to calculated schedule fields are blocked; flows must execute the **Project Schedule API** via unbound Dataverse actions.
* **Operation Set Staging**: Workflow steps must:
  1. Call `msdyn_CreateOperationSetV1` to open a transaction boundary.
  2. Queue task changes using `msdyn_CreateProjectTaskV1` or update actions referencing the `OperationSetId`.
  3. Call `msdyn_ExecuteOperationSetV1` to process and commit changes to the schedule.

---

## Cost-Optimized Tiered Licensing Architecture

Assigning high-tier licenses to all 80 users is unnecessary. Deploy a hybrid model to minimize software spend:

* **Tier 1: Project Managers & Administrators (3–5 Users)**
  * **License**: Planner & Project Plan 3 / Plan 5 (~$30–$55/user/month).
  * **Rights**: Baseline creation, Schedule API execution, critical path analysis, custom field creation, portfolio management.
* **Tier 2: Workstream Leads & Schedulers (10–15 Users)**
  * **License**: Planner Plan 1 (~$10/user/month).
  * **Rights**: Full editing of Gantt timelines, dependencies, milestone management, and task assignments.
* **Tier 3: Team Members & Contributors (60–65 Users)**
  * **License**: Standard Microsoft 365 Base Edit Access (E3/E5) (**$0 Incremental Cost**).
  * **Rights**: Open shared Premium plans in Teams, mark tasks complete, update % completion, edit dates, add notes, and re-assign tasks.

---

## 5-Phase Execution Roadmap

1. **Phase 1: Telemetry Audit**: Export task JSON via Graph API to inventory active vs. completed tasks, Power Automate dependencies, and custom fields.
2. **Phase 2: Task Cleansing**: Purge tasks completed >90 days ago to SharePoint archive; collapse micro-tasks into checklists until total tasks are <2,500.
3. **Phase 3: Integration Staging**: Re-author Power Automate flows using Project Schedule API Operation Sets; test dry-run upgrade in a sandbox environment.
4. **Phase 4: Production Cutover**: Execute conversion during off-hours; verify Dataverse ingestion logs; switch Power Automate flow environments.
5. **Phase 5: Governance**: Validate team member basic edit rights in Teams; hook Premium plan into executive Portfolio dashboards.

---

## Stakeholder Meeting Talking Points

* **Value & Experience**: *"Upgrading to Premium gives our team interactive Gantt timelines, dependency tracking, and executive portfolio reporting directly inside Microsoft Teams, without changing where people work day-to-day."*
* **Task Cleanup**: *"Premium Planner uses an enterprise scheduling engine capped at 3,000 active tasks per project to ensure instant speed. We are archiving old, completed items to secure storage and consolidating minor sub-steps into clean checklists, making our live plan faster and easier to navigate."*
* **Budget Efficiency**: *"We do not need to buy expensive software licenses for all 80 team members. By leveraging Microsoft's hybrid licensing model, over 80% of our team will update deliverables using our existing Microsoft 365 subscriptions at zero added software cost."*
* **Risk Control & Safety Net**: *"All cutover activities will occur off-hours. Background automations are being re-engineered to prevent workflow interruptions, and Microsoft maintains a 90-day automatic rollback backup of our original plan for complete peace of mind."*
