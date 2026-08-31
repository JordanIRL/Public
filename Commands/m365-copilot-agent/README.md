# M365 PowerShell Admin — Copilot declarative agent

A Microsoft 365 Copilot agent built from [`m365-kb/`](../m365-kb/). It answers PowerShell administration questions with commands that were mechanically verified — cmdlet names checked against installed modules and Microsoft Learn, parameters checked against official parameter lists, every snippet parsed by the PowerShell parser.

**`m365-kb/` is the source of truth. Everything in `knowledge/` and `appPackage/declarativeAgent.json` is generated — edit the source, then rebuild.**

## Build

```bash
python3 build/build-agent.py && pwsh -NoProfile -File build/validate.ps1
```

`--mode embedded` bundles the knowledge into the app package instead of pointing at SharePoint.

## Layout

| Path | Hand-edited? | What it is |
|---|---|---|
| `appPackage/instructions.md` | **yes** | Agent behaviour, inlined into the manifest at build (≤8,000 chars) |
| `appPackage/editorial-answers.json` | **yes** | 22 curated Q&A pairs for facts that must never be wrong |
| `appPackage/declarativeAgent.source.json` | **yes** | Name, description, conversation starters, behaviour overrides |
| `appPackage/manifest.json` | **yes** | M365 app manifest |
| `appPackage/declarativeAgent.json` | no — generated | Resolved v1.8 manifest that ships |
| `appPackage/color.png`, `outline.png` | placeholders | Replace with real branding before publishing |
| `knowledge/*.txt` | no — generated | 10 knowledge files |
| `appPackage/build/agent.zip` | no — generated | Uploadable package |

## Why the content changed

The KB could not be used as-is. Each transformation below answers a documented platform constraint, and all are applied by `build/build-agent.py`.

**Tables became prose.** Microsoft states Copilot ["is currently unable to parse tables and other special formatting"](https://learn.microsoft.com/microsoft-365/copilot/extensibility/optimize-content-retrieval) in SharePoint content. `08-reference.md` was ~90% tables — 212 rows across the KB would have contributed almost nothing. Each row is now a self-contained sentence.

**Directives became statements of fact.** Microsoft [warns](https://learn.microsoft.com/microsoft-365/copilot/extensibility/declarative-agent-instructions) that knowledge-source content "is subject to cross-prompt injection attacks (XPIA) classifiers — directive-like language can be blocked, truncated, or sanitized at runtime." So "Never mix the two on one SessionId" became "Mixing the two on one SessionId caps the result at 10,000 records." The information survives; the imperative mood does not. Behavioural rules moved to `instructions.md`, which *is* trusted maker-authored content.

**Headings carry their workload.** Copilot retrieves chunks, not files. `### Grant full access to a mailbox` became `### Exchange Online — Grant full access to a mailbox` so a chunk retrieved in isolation still says which module it needs.

**Platform notes were generalised.** The KB was written for one macOS machine and `CLAUDE.md` says so. An agent serves whoever asks, so the Windows-only facts about `Connect-IPPSSession` and the SPO module are now stated per-platform, and `instructions.md` tells the agent to establish the user's OS before recommending either.

**`08-reference.md` split in two.** It grows once de-tabled. The split keeps every file under the 36,000-character retrieval limit and the set at exactly 10 files — the `EmbeddedKnowledge` maximum — so either deployment mode works.

## Guardrails

- **`discourage_model_knowledge: true`** — Microsoft's documented mechanism for keeping the model off its training data. This is the single most important setting here: the failure mode for a PowerShell agent is a confidently invented cmdlet, and this is what suppresses it.
- **No `WebSearch` capability.** It would reintroduce exactly the unverified content the KB exists to replace.
- **No `actions` / API plugin.** The agent explains commands; it does not run them against a tenant.
- Instructions require the module, connect cmdlet and permission on every answer, and a warning line above destructive commands.

## Verification

`build/validate.ps1` enforces:

1. **Command fidelity** — every command line in `m365-kb/` is compared against the generated files. Currently **610/610 preserved byte-for-byte**. Any drift fails the build, so the transformation cannot silently corrupt a verified command.
2. **Parse** — all 511 command blocks parse under the PowerShell parser.
3. **Limits** — instructions ≤8,000; description ≤1,000; starters ≤12; ≤10 files; each <36,000 chars and <1 MB.
4. **No tables**, **no residual imperatives**, **manifest references resolve**.

## Deploying

**SharePoint-hosted** (default; knowledge is versionable and updatable without repackaging):

1. Upload `knowledge/*.txt` to a SharePoint document library.
2. Put that library's URL in the `OneDriveAndSharePoint` → `items_by_url` entry in `declarativeAgent.source.json`, then rebuild.
3. Set a real `id` GUID and `developer` details in `manifest.json`; replace the placeholder icons.
4. Upload `appPackage/build/agent.zip` via the Microsoft 365 admin center (Integrated apps) or Microsoft 365 Agents Toolkit.

**Embedded** — `python3 build/build-agent.py --mode embedded` puts the 10 files in the zip. Self-contained, but knowledge updates need a repackage and republish.

Both require Copilot licences or metered usage; agents grounded in SharePoint or embedded files are not available on Web-search-only tenancies.

### Worth testing after upload

Ask it to (a) grant mailbox access — it should name the module, connect cmdlet and role; (b) do something in Purview — it should ask your OS first; (c) do something the KB does not cover — it should decline rather than invent; (d) offboard a leaver — it should keep the hold-before-delicensing order and flag the licence trap.

## Known limitations

- Icons are solid-colour placeholders that pass validation but are not branding.
- `manifest.json` ships a zero GUID and Contoso developer details; both must be set before publishing.
- The KB's prose claims (throttling numbers, retention windows) are researched but were not independently sourced, and no command has been executed against a live tenant.
- `build-agent.py` is Python rather than the PowerShell named in the original plan: the transformation is text processing, which Python does better. The fidelity gate stayed in PowerShell because it needs the real PowerShell parser.
