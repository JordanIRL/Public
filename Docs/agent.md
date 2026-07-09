Use **Copilot Studio**, configured as a zero-connection documentation agent.

You still sign in to create and use it, but do not give it an admin connection, Microsoft Graph permissions, tenant data, connectors, or actions. It will not be able to inspect or change Intune or Microsoft 365.

Copilot Studio is the better fit than normal Settings because it can use public Microsoft documentation as knowledge and let you turn off **Allow ungrounded responses**. Agent Builder is quicker, but Microsoft says it cannot completely block general model knowledge. [Agent Builder limitation](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/agent-builder-add-knowledge) · [Copilot Studio source controls](https://learn.microsoft.com/en-us/microsoft-copilot-studio/faqs-generative-answers)

Configure it like this:

1. Open [Copilot Studio](https://copilotstudio.microsoft.com/) and create an agent.

2. Under **Build → Knowledge**, add only these public sources:

   - `https://learn.microsoft.com/en-us/intune`
   - `https://learn.microsoft.com/en-us/microsoft-365`
   - `https://learn.microsoft.com/en-us/entra`
   - `https://learn.microsoft.com/en-us/graph`

3. Do not add Microsoft IQ/work data, SharePoint, OneDrive, Teams, email, uploaded files, connectors, tools, flows, or actions.

4. In the generative-answer settings, turn **Allow ungrounded responses** off.

5. Keep it private while you test it.

Paste these instructions:

```text
You are a read-only Microsoft 365, Intune, Entra ID and Microsoft Graph
documentation assistant.

Answer only from the configured official Microsoft Learn sources. Do not access,
request, infer or assume tenant-specific data. Do not claim to inspect, configure
or change a Microsoft 365 or Intune environment.

Give a concise answer, relevant portal or PowerShell/Graph steps where applicable,
prerequisites and risks for state-changing operations. Include direct Microsoft
Learn links supporting each answer. If the configured sources do not support an
answer, say so clearly.
```

This gives you a reusable “M365 & Intune Reference” agent without connecting it to your admin account. Public website knowledge sources are supported directly in Copilot Studio. [Microsoft’s setup guide](https://learn.microsoft.com/en-us/microsoft-copilot-studio/knowledge-add-public-website)

---

> There are a few enterprise-specific traps worth clearing before you create anything. I’m checking Microsoft’s current guidance on private sharing, data handling and Copilot Studio charging so I can separate genuine risks from harmless setup choices.
>
> <details><summary>Searched the web</summary>
>
> <details><summary>Searched the web</summary>
>
> - Searched the web for `site:learn.microsoft.com/en-us/microsoft-copilot-studio share agents private access unpublished environment security roles ...`
> - Searched the web for `site:learn.microsoft.com/en-us/microsoft-copilot-studio "private" agent "publish" maker ...`
> - Searched the web for `site:learn.microsoft.com/en-us/microsoft-365/copilot Agent Builder public website web search no charge Copilot Credits ...`
> - Searched the web for `site:learn.microsoft.com/en-us/microsoft-copilot-studio public website Bing query DPA data privacy cross geo ...`
>
> </details>
>
> </details>
</details>

Yes — in an enterprise tenant, “private” means **only you can use it**, not that it is invisible to authorised IT, security or compliance administrators.

For your first version, use **Microsoft 365 Copilot Agent Builder**, not Copilot Studio. A declarative agent grounded only in instructions and public websites is Microsoft’s lowest-cost, lowest-complexity route; it defaults to **Only you** sharing. [Microsoft guidance](https://learn.microsoft.com/en-us/copilot/agents) · [private-sharing setting](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/agent-builder-share-manage-agents)

| Area | Safe rule for your first agent |
|---|---|
| Visibility | Keep **Only you** selected; do not share, submit to the organisation catalogue, download a deployment package, or add channels. |
| Data | Never paste tenant names, device IDs, user details, logs, tickets, exports, screenshots, passwords or secrets into it. |
| Sources | Use only the four Microsoft Learn URLs; leave **Search all websites** off, **Reference people in organisation** off, and add no work content. |
| Access | No Graph, Intune, Microsoft 365, Power Automate or other connectors; no tools, actions, workflows or uploads. |
| Cost | Do not enable pay-as-you-go. Keep it public-web/instructions-only. |

Two important caveats:

- Private does not mean hidden from the organisation. Tenant administrators can inventory agent metadata and audit creation, changes, sharing and use. [Agent inventory](https://learn.microsoft.com/en-us/microsoft-copilot-studio/admin-agent-inventory) · [audit logging](https://learn.microsoft.com/en-us/microsoft-copilot-studio/admin-logging-copilot-studio)

- Public web grounding uses Bing. Keep prompts generic: Microsoft documents that website-grounding can send a rewritten query and conversational context to Bing, and personal data is not automatically redacted. [Public-web data flow](https://learn.microsoft.com/en-us/microsoft-copilot-studio/guidance/generative-ai-public-websites) · [web-search privacy](https://learn.microsoft.com/en-us/microsoft-copilot-studio/data-privacy-security-web-search)

Agent Builder is preferable here because Copilot Studio adds a Power Platform environment and, by default, stores its test and end-user transcripts in Dataverse. Microsoft 365 Copilot agents do not use those Dataverse transcripts, although normal Copilot audit and retention rules can still apply. [Transcript controls](https://learn.microsoft.com/en-us/microsoft-copilot-studio/admin-transcript-controls)

Use this additional instruction in the agent:

```text
Never request, process or infer tenant-specific information, personal data,
device identifiers, diagnostic logs, configuration exports, passwords or secrets.
Ask for a redacted, generic example instead.
```

One limitation: Agent Builder’s **Only use specified sources** setting prioritises your Microsoft Learn sources, but cannot fully block the model’s general knowledge. Require direct Microsoft Learn links in every answer, and treat uncited answers as unverified. [Microsoft’s limitation](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/agent-builder-add-knowledge)

Before creating it, send this to your Copilot/Power Platform owner if that is not you:

> I want a single-user Agent Builder agent limited to official Microsoft Learn public websites. It will have no work knowledge, uploads, connectors, actions, workflows, sharing or publishing. Please confirm public-web grounding is permitted, the applicable audit/retention policy, and that no pay-as-you-go billing applies.

> I like this Copilot plan, can you give me a single markdown doc with a full plan

<details><summary>4 previous messages</summary>

> I’ll turn the agreed approach into a single, self-contained plan, including the privacy, visibility, cost and approval controls so it can be used as an internal proposal.
>
> The workspace is empty, so I’m creating the plan as a standalone Markdown file at the repository root.
>
> <details><summary>Created a file, edited a file</summary>
>
> - Wrote `./M365-Intune-public-docs-agent-plan.md` (+250 -0)
> - Wrote `./M365-Intune-public-docs-agent-plan.md` (+10 -4)
> - Wrote `./M365-Intune-public-docs-agent-plan.md` (+1 -0)
>
> </details>
>
> The plan now includes the controlled build steps, approval wording, data rules, private-sharing checks, cost controls and a test/maintenance process. I’m doing a final consistency check before handing it over.
</details>

Created the full plan: [M365-Intune-public-docs-agent-plan.md](./M365-Intune-public-docs-agent-plan.md)

It covers private access, data handling, costs, approval checks, configuration, copy-paste instructions, testing, maintenance and future expansion controls. Formatting checks passed.

> .

<details><summary>1 previous message</summary>

> System error
>
> You've hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), visit https://chatgpt.com/codex/settings/usage to purchase more credits or try again at Jul 10th, 2026 4:17 AM.
</details>
