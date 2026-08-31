#!/usr/bin/env python3
"""
Generate Copilot declarative-agent knowledge files from m365-kb/.

m365-kb/ is the source of truth. Everything in ../knowledge/ is generated.
Run:  python3 build/build-agent.py [--mode sharepoint|embedded]

Transformations (see plan / README for rationale):
  1. Tables -> labelled prose      (Copilot cannot parse tables)
  2. Directives -> factual prose   (knowledge sources are XPIA-sanitised)
  3. Workload stamped on headings  (retrieved chunks must be self-contained)
  4. Fences -> indented commands   (command text preserved byte-for-byte)
  5. Platform notes generalised    (agent serves any OS, not just macOS)
"""

import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(os.path.dirname(ROOT), "m365-kb")
OUT = os.path.join(ROOT, "knowledge")

# --------------------------------------------------------------------------
# File map: (source, dest, workload label, header lines, section filter)
# 08-reference.md splits in two: it grows once de-tabled.
# --------------------------------------------------------------------------

REF_PART1 = [
    "Modules",
    "Cmdlet noun map — Exchange Online",
    "Cmdlet noun map — Purview (Connect-IPPSSession)",
    "Cmdlet noun map — Teams",
    "Cmdlet noun map — SharePoint / OneDrive",
    "Cmdlet noun map — Entra / Graph",
    "Graph delegated scopes by task",
    "Admin roles by workload",
    "Licence SKUs",
]

FILES = [
    ("00-setup-and-connect.md", "01-connect-and-modules.txt", "Setup and connection",
     "Installing modules, connecting to each workload with an interactive MFA admin account, Graph scopes, PnP app registration, multiple sessions.", None),
    ("01-exchange-online.md", "02-exchange-online.txt", "Exchange Online",
     "Mailboxes, mailbox settings, permissions, shared/room/equipment mailboxes, calendars, auto-replies, forwarding, distribution groups, mail flow, message trace, EOP protection, auditing.", None),
    ("02-teams.md", "03-teams.txt", "Microsoft Teams",
     "Teams and channel lifecycle, membership, policies and batch policy assignment, meeting settings, guest and external access, apps, Teams Phone, reporting.", None),
    ("03-sharepoint-onedrive.md", "04-sharepoint-onedrive.txt", "SharePoint Online and OneDrive",
     "Tenant administration, sites, permissions and sharing, lists and libraries, files and folders, OneDrive, search and reporting, term store, pages.", None),
    ("04-security-compliance.md", "05-purview-compliance.txt", "Microsoft Purview (Security and Compliance)",
     "Audit log search, content search and purge, eDiscovery cases and holds, retention, sensitivity labels, DLP, information barriers, alerts.", None),
    ("05-microsoft-graph.md", "06-graph-identity.txt", "Microsoft Graph and Entra ID",
     "Querying Graph correctly, users, groups, licensing, devices, sign-in and audit logs, applications and service principals, directory roles, Conditional Access, raw requests.", None),
    ("06-recipes.md", "07-cross-workload-recipes.txt", "Cross-workload recipes",
     "Multi-module procedures: new-hire provisioning, leaver offboarding, licence inventory, permission audits, storage and governance reports, export and bulk patterns.", None),
    ("07-troubleshooting.md", "08-troubleshooting.txt", "Troubleshooting",
     "Connection failures, PnP app registration errors, Graph consent and scopes, throttling, silently truncated results, empty properties, slow scripts, propagation delays, restoring deleted objects.", None),
    ("08-reference.md", "09-reference-scopes-roles-skus.txt", "Reference: modules, cmdlet map, scopes, roles, licence SKUs",
     "Which module manages what, which cmdlet to reach for by task, least-privilege Graph delegated scopes, admin roles per workload, licence SKU part numbers.", REF_PART1),
    ("08-reference.md", "10-reference-filters-kql-recordtypes.txt", "Reference: audit RecordTypes, OData filters, KQL, PowerShell idioms",
     "Search-UnifiedAuditLog RecordType and Operation values, Graph OData filter patterns and which need advanced query, KQL for content search, PowerShell idioms, documentation links.", "NOT_PART1"),
]

# --------------------------------------------------------------------------
# 1. Table -> prose templates, keyed by header row
# --------------------------------------------------------------------------

def t_want(c):      return f"To {c[0].rstrip('.')} — use {c[1]}"
def t_want_spo(c):  return f"To {c[0].rstrip('.')} — SPO module: {c[1]}. PnP: {c[2]}"
def t_code(c):      return f"Error {c[0]} means {c[1]}. Fix: {c[2]}"
def t_restore(c):   return f"{c[0]}: retention window {c[1]}. Restore with {c[2]}"
def t_retired(c):   return f"{c[0]} is retired. Replacement: {c[1]}"
def t_module(c):    return f"{c[0]} manages {c[1]}. Connect with {c[2]}. Disconnect or verify with {c[3]}"
def t_scope(c):     return f"For {c[0].rstrip('.')} — least-privilege delegated scope {c[1]}; Entra role usually needed: {c[2]}"
def t_role(c):      return f"{c[0]}: the admin role that works is {c[1]}. Read-only equivalent: {c[2]}"
def t_sku(c):       return f"{c[0]} has SkuPartNumber {c[1]} and SkuId {c[2]}"
def t_record(c):    return f"RecordType {c[0]} (Id {c[1]}) covers {c[2]}"
def t_ops(c):       return f"{c[0]} operations: {c[1]}"
def t_odata(c):     return f"{c[0]}. Example: {c[1]}. Requires advanced query (ConsistencyLevel eventual + CountVariable): {c[2]}"
def t_kql(c):       return f"To {c[0].rstrip('.')} — KQL: {c[1]}"
def t_docs(c):      return f"{c[0]}: {c[1]}"

TABLES = {
    ("I want to…", "Look at"): t_want,
    ("I want to…", "Look at (SPO)", "Look at (PnP)"): t_want_spo,
    ("Code", "Meaning", "Fix"): t_code,
    ("Object", "Window", "Restore with"): t_restore,
    ("Retired", "Replacement"): t_retired,
    ("Module (version)", "Manages", "Connect", "Disconnect / verify"): t_module,
    ("Task", "Least-privilege delegated scope", "Entra role usually needed"): t_scope,
    ("Workload", "Role that actually works", "Read-only equivalent"): t_role,
    ("Friendly name", "SkuPartNumber", "SkuId (GUID)"): t_sku,
    ("RecordType", "Id", "Covers"): t_record,
    ("Area", "Operation values"): t_ops,
    ("Pattern", "Example", "Advanced?"): t_odata,
    ("Goal", "KQL"): t_kql,
    ("Topic", "Link"): t_docs,
}


def split_row(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def convert_tables(text):
    lines = text.split("\n")
    out, i = [], 0
    while i < len(lines):
        # a table = header row, separator row, then data rows
        if (lines[i].lstrip().startswith("|")
                and i + 1 < len(lines)
                and re.match(r"^\|[\s:-]*-{2,}[\s:|-]*\|?\s*$", lines[i + 1].strip())):
            header = tuple(split_row(lines[i]))
            fmt = TABLES.get(header)
            i += 2
            rows = []
            while i < len(lines) and lines[i].lstrip().startswith("|"):
                cells = split_row(lines[i])
                if fmt and len(cells) == len(header):
                    rows.append("- " + fmt(cells).rstrip(".") + ".")
                else:  # generic fallback keeps every column labelled
                    parts = [f"{header[n]}: {c}" for n, c in enumerate(cells[1:], start=1)
                             if n < len(header) and c]
                    rows.append("- " + cells[0] + (" — " + "; ".join(parts) if parts else "") + ".")
                i += 1
            out.extend(rows)
            continue
        out.append(lines[i])
        i += 1
    return "\n".join(out)


# --------------------------------------------------------------------------
# 2. Directive -> factual. Exact strings only: no regex mangling of content.
# --------------------------------------------------------------------------

DIRECTIVES = [
    ("Never run this while the module is imported in the current session — close PowerShell and reopen first.",
     "Running this while the module is imported in the current session fails; PowerShell has to be closed and reopened first."),
    ("Do not confuse this cmdlet with `Register-PnPEntraIDApp` — that one builds a certificate-based app for unattended app-only access.",
     "`Register-PnPEntraIDApp` is a different cmdlet: it builds a certificate-based app for unattended app-only access."),
    ("Do not copy `-ClientId` onto EXO, Teams, SPO, or Graph connects.",
     "`-ClientId` applies only to PnP connects; the EXO, Teams, SPO and Graph connect cmdlets do not take it."),
    ("The other M365 modules need neither — do not copy `-ClientId` onto them.",
     "The other M365 modules need neither; `-ClientId` does not apply to them."),
    ("Never run `Update-Module` on a module already imported in the session; reopen PowerShell first.",
     "`Update-Module` on a module already imported in the session fails; PowerShell has to be reopened first."),
    ("Never run `Update-Module` on a module already imported in the session — close and reopen PowerShell first.",
     "`Update-Module` on a module already imported in the session fails; PowerShell has to be closed and reopened first."),
    ("Never run `Update-Module MicrosoftTeams` while the module is imported.",
     "`Update-Module MicrosoftTeams` fails while the module is imported."),
    ("Always pass `-ResultSize Unlimited` for inventories.",
     "Without `-ResultSize Unlimited`, inventories stop at the 1,000-object default."),
    ("Use `-PropertySets` / `-Properties`; avoid `-PropertySets All`.",
     "Named `-PropertySets` / `-Properties` values retrieve only what is needed; `-PropertySets All` pulls every property and is slow."),
    ("Use `-Properties` for named fields; avoid `-PropertySets All`, which pulls everything and is slow.",
     "`-Properties` retrieves named fields; `-PropertySets All` pulls everything and is slow."),
    ("Prefer server-side `-Filter` over `Where-Object`; the latter enumerates the whole tenant first and is a throttling magnet.",
     "Server-side `-Filter` runs on the server; `Where-Object` enumerates the whole tenant first and is a throttling magnet."),
    ("`Get-PSSession` never shows Exchange Online connections — use `Get-ConnectionInformation`.",
     "`Get-PSSession` never shows Exchange Online connections; `Get-ConnectionInformation` shows them."),
    ("`Get-Team -DisplayName` / `-MailNickName` are case-sensitive substring filters, not exact matches — always check `GroupId` before acting.",
     "`Get-Team -DisplayName` / `-MailNickName` are case-sensitive substring filters, not exact matches, so more than one team can match; checking `GroupId` before acting identifies the right one."),
    ("Always set `-PageSize` on lists over 5,000 items — it pages under the list view threshold instead of throwing.",
     "On lists over 5,000 items `-PageSize` pages under the list view threshold; without it the call throws."),
    ("`ReturnLargeSet` caps at 50,000 records per session and returns unsorted, duplicate-prone pages — always de-duplicate.",
     "`ReturnLargeSet` caps at 50,000 records per session and returns unsorted, duplicate-prone pages, so the result set needs de-duplicating."),
    ("Never mix `ReturnLargeSet` and `ReturnNextPreviewPage` on one SessionId or you are capped at 10,000.",
     "Mixing `ReturnLargeSet` and `ReturnNextPreviewPage` on one SessionId caps the result at 10,000 records."),
    ("Never mix the two on one `SessionId`.",
     "Mixing the two on one `SessionId` caps the result at 10,000 records."),
    ("Avoid spaces in `-Name` if you will attach searches with `New-ComplianceSearch -Case`.",
     "Spaces in `-Name` break attaching searches with `New-ComplianceSearch -Case`."),
    ("Never pipe a list into `Set-LabelPolicy` with `ForEach-Object` when adding or removing locations; pass all values in one call.",
     "Piping a list into `Set-LabelPolicy` with `ForEach-Object` triggers a full sync per call and gets throttled; passing all values in one call avoids that."),
    ("Double the single quote; do not backslash it.",
     "A single quote is escaped by doubling it, not by backslashing it."),
    ("Never pipe `Format-*` into `Export-Csv`.",
     "Piping `Format-*` into `Export-Csv` writes format objects instead of data."),
    ("`Format-Table` truncation looks exactly like missing data; never pipe `Format-*` into `Export-Csv`.",
     "`Format-Table` truncation looks exactly like missing data, and piping `Format-*` into `Export-Csv` writes format objects instead of data."),
    ("Hand `$pw` to the new hire out of band; never commit it.",
     "`$pw` is handed to the new hire out of band; committing it to source control exposes the credential."),
    ("Prefer group-based licensing where you have it and skip this entirely.",
     "Group-based licensing replaces this step entirely where it is available."),
    ("With no `-Identity` this runs across the whole tenant in one call — do not loop `Get-EXOMailbox` into it.",
     "With no `-Identity` this runs across the whole tenant in one call; looping `Get-EXOMailbox` into it is redundant and far slower."),
    ("If you still get throttled, lower `-PageSize`, stop polling in loops, and never fire parallel calls at the same resource.",
     "Where throttling persists, the mitigations are a lower `-PageSize`, no polling loops, and no parallel calls against the same resource."),
    ("SCC cmdlets do not exist until you connect; you cannot inspect them with `Get-Command` offline, and `Get-Help` is empty unless you connect Exchange Online with `-LoadCmdletHelp`.",
     "SCC cmdlets are generated at connect time, so `Get-Command` cannot inspect them offline, and `Get-Help` is empty unless Exchange Online was connected with `-LoadCmdletHelp`."),
    ("Beta cmdlets (`Get-MgBeta*`) come from a separate module and can change without notice — do not build scheduled jobs on them if v1.0 covers the call.",
     "Beta cmdlets (`Get-MgBeta*`) come from a separate module and can change without notice, so they are a poor basis for scheduled jobs where v1.0 covers the call."),
    ("`-NoTypeInformation` is the default in PowerShell 7 but not in Windows PowerShell 5.1 — always pass it so the file is the same either way.",
     "`-NoTypeInformation` is the default in PowerShell 7 but not in Windows PowerShell 5.1; passing it explicitly makes the output identical on both."),
    ("`Update-DistributionGroupMember` **replaces** the whole membership on every call — never loop it over chunks or you keep only the last one; seed with one call, then add the rest individually.",
     "`Update-DistributionGroupMember` **replaces** the whole membership on every call, so looping it over chunks keeps only the last chunk. The working pattern is one seeding call followed by individual `Add-DistributionGroupMember` calls."),
    ("PnP.PowerShell 3.x is the only module here that requires your own Entra app registration; do not copy `-ClientId` onto the other four.",
     "PnP.PowerShell 3.x is the only module here that requires its own Entra app registration; `-ClientId` does not apply to the other four."),
]

# Second-person phrasing, applied after the exact replacements above.
SECOND_PERSON = [
    (r"\bwithout it you get 500 rows max and must page with\b", "without it only 500 rows return, and paging uses"),
    (r"\byou must \*\*keep an Exchange Online Plan 2 licence\*\*", "an Exchange Online Plan 2 licence must be kept"),
    (r"Always pass `-All`, and name what you need in `-Property`",
     "Without `-All` only the first page returns, and properties not named in `-Property` are absent"),
    (r"\bPrefer `Get-EXO\*` over `Get-Mailbox`/`Get-Recipient` for bulk reads and control output with `-Properties`; never use `-PropertySets All`\.",
     "`Get-EXO*` is faster than `Get-Mailbox`/`Get-Recipient` for bulk reads and output is controlled with `-Properties`; `-PropertySets All` pulls everything and is slow."),
    (r"\bso always revoke too\b", "so revoking sessions is also required"),
    (r"\bcheck the size before delicensing\b", "the size determines whether a licence is still required"),
]

# --------------------------------------------------------------------------
# 5. Platform generalisation — the KB was written for one macOS machine.
# --------------------------------------------------------------------------

PLATFORM = [
    ("`Connect-IPPSSession` (Purview) does not work in PowerShell 7 on macOS or Linux, and `Microsoft.Online.SharePoint.PowerShell` cannot be installed there at all. Reach SharePoint via PnP or Graph, and run compliance work from Windows.",
     "`Connect-IPPSSession` (Purview) works in Windows PowerShell 5.1 and in PowerShell 7 on Windows only; it is unavailable in PowerShell 7 on macOS or Linux. `Microsoft.Online.SharePoint.PowerShell` is Windows-only and cannot be installed on macOS or Linux. On those platforms SharePoint is reachable via PnP.PowerShell or Microsoft Graph, and Purview work requires a Windows host."),
    ("`Connect-IPPSSession` does not work in PowerShell 7 on macOS or Linux, and `Microsoft.Online.SharePoint.PowerShell` will not install there at all.",
     "`Connect-IPPSSession` works on Windows only and is unavailable in PowerShell 7 on macOS or Linux. `Microsoft.Online.SharePoint.PowerShell` is Windows-only and will not install on macOS or Linux."),
    ("On macOS/Linux you cannot reach Security & Compliance PowerShell or the SPO module at all — use PnP/Graph for SharePoint and run Purview work from Windows.",
     "On macOS and Linux, Security & Compliance PowerShell and the SPO module are unavailable. PnP.PowerShell and Microsoft Graph cover SharePoint there, and Purview work requires a Windows host."),
]


def de_imperative(text):
    for old, new in DIRECTIVES + PLATFORM:
        text = text.replace(old, new)
    for pat, rep in SECOND_PERSON:
        text = re.sub(pat, rep, text)
    return text


# --------------------------------------------------------------------------
# 3 + 4. Headings and code fences
# --------------------------------------------------------------------------

def stamp_and_fence(text, workload):
    lines = text.split("\n")
    out, in_fence, buf = [], False, []
    for line in lines:
        if line.strip().startswith("```"):
            if not in_fence:
                in_fence, buf = True, []
            else:
                in_fence = False
                out.append("Command:" if len(buf) == 1 else "Commands:")
                out.extend("    " + b for b in buf)
                out.append("")
            continue
        if in_fence:
            buf.append(line)
            continue
        if line.startswith("### "):
            out.append(f"### {workload} — {line[4:]}")
        else:
            out.append(line)
    return "\n".join(out)


def select_sections(text, sections):
    """Keep (or drop) top-level ## sections for the 08-reference split."""
    if sections is None:
        return text
    invert = sections == "NOT_PART1"
    out, keeping, started = [], False, False
    for line in text.split("\n"):
        if line.startswith("## "):
            started = True
            keeping = ((line[3:].strip() in REF_PART1) != invert)
        if started and keeping:
            out.append(line)
    return "\n".join(out)


def clean(text):
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip() + "\n"


def build_header(workload, scope, src, first_lines):
    return (
        f"Microsoft 365 PowerShell knowledge base — {workload}\n"
        f"Scope of this document: {scope}\n"
        f"{first_lines}\n"
        f"Source: m365-kb/{src} (generated file — edit the source, not this)\n"
        f"{'=' * 70}\n"
    )


# --------------------------------------------------------------------------
# Agent manifest assembly + placeholder icons
# --------------------------------------------------------------------------

SHAREPOINT_URL_PLACEHOLDER = "https://contoso.sharepoint.com/sites/M365PowerShellKB/Shared%20Documents/knowledge"


def capabilities_for(mode, knowledge_files):
    if mode == "embedded":
        return [
            {"name": "EmbeddedKnowledge",
             "files": [{"file": f"knowledge/{n}"} for n in knowledge_files]},
            {"name": "CodeInterpreter"},
        ]
    return [
        {"name": "OneDriveAndSharePoint",
         "items_by_url": [{"url": SHAREPOINT_URL_PLACEHOLDER}]},
        {"name": "CodeInterpreter"},
    ]


def build_manifest(mode, knowledge_files):
    app = os.path.join(ROOT, "appPackage")
    src = json.load(open(os.path.join(app, "declarativeAgent.source.json"), encoding="utf-8"))

    src["instructions"] = open(os.path.join(app, "instructions.md"), encoding="utf-8").read().strip()

    ea = json.load(open(os.path.join(app, "editorial-answers.json"), encoding="utf-8"))
    src["editorial_answers"] = {"answers": ea["answers"]}

    src["capabilities"] = capabilities_for(mode, knowledge_files)

    out = os.path.join(app, "declarativeAgent.json")
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(src, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    return src


def png(path, size, rgba):
    """Minimal solid-colour PNG so the package passes icon validation."""
    import struct, zlib
    r, g, b, a = rgba
    raw = b"".join(b"\x00" + bytes([r, g, b, a]) * size for _ in range(size))

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    with open(path, "wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n")
        fh.write(chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)))
        fh.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        fh.write(chunk(b"IEND", b""))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["sharepoint", "embedded"], default="sharepoint")
    args = ap.parse_args()

    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".txt"):
            os.remove(os.path.join(OUT, f))

    written = []
    for src, dest, workload, scope, sections in FILES:
        raw = open(os.path.join(SRC, src), encoding="utf-8").read()

        # keep the source's own module/connect line as retrieval context
        body_lines = raw.split("\n")
        intro = next((l for l in body_lines[1:6] if l.strip() and not l.startswith("#")), "")

        text = select_sections(raw, sections)
        text = convert_tables(text)
        text = de_imperative(text)
        text = stamp_and_fence(text, workload)
        text = re.sub(r"^# .*\n", "", text, count=1)      # drop original H1
        text = clean(text)

        full = build_header(workload, scope, src, intro) + "\n" + text
        path = os.path.join(OUT, dest)
        open(path, "w", encoding="utf-8").write(full)
        written.append((dest, len(full)))

    print(f"Generated {len(written)} knowledge files ({args.mode} mode)\n")
    over = 0
    for name, size in written:
        flag = ""
        if size > 36000:
            flag, over = "  <-- OVER 36,000 CHAR SHAREPOINT LIMIT", over + 1
        print(f"  {name:<44} {size:>7,} chars{flag}")
    total = sum(s for _, s in written)
    print(f"\n  {'TOTAL':<44} {total:>7,} chars")
    if len(written) > 10:
        print(f"\nERROR: {len(written)} files exceeds the EmbeddedKnowledge limit of 10.")
        return 1
    if over:
        print(f"\nERROR: {over} file(s) over the 36,000-character SharePoint limit.")
        return 1

    # ---- agent manifest ----
    da = build_manifest(args.mode, [n for n, _ in written])
    print(f"\nBuilt appPackage/declarativeAgent.json ({args.mode} mode)")
    print(f"  instructions          {len(da['instructions']):>7,} / 8,000 chars")
    print(f"  description           {len(da['description']):>7,} / 1,000 chars")
    print(f"  conversation_starters {len(da['conversation_starters']):>7} / 12")
    print(f"  editorial_answers     {len(da['editorial_answers']['answers']):>7} / 300")
    print(f"  capabilities          {', '.join(c['name'] for c in da['capabilities'])}")

    # ---- placeholder icons (required for package validation) ----
    app = os.path.join(ROOT, "appPackage")
    for name, size, rgba in (("color.png", 192, (15, 108, 189, 255)),
                             ("outline.png", 32, (255, 255, 255, 0))):
        p = os.path.join(app, name)
        if not os.path.exists(p):
            png(p, size, rgba)
            print(f"  wrote placeholder {name} ({size}x{size})")

    # ---- zip: paths inside the archive must mirror the manifest's refs ----
    import zipfile
    build_dir = os.path.join(app, "build")
    os.makedirs(build_dir, exist_ok=True)
    zip_path = os.path.join(build_dir, "agent.zip")
    members = ["manifest.json", "declarativeAgent.json", "color.png", "outline.png"]
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for m in members:
            z.write(os.path.join(app, m), m)
        if args.mode == "embedded":
            for name, _ in written:
                z.write(os.path.join(OUT, name), f"knowledge/{name}")
    n = len(members) + (len(written) if args.mode == "embedded" else 0)
    print(f"\nPackaged appPackage/build/agent.zip  ({n} files, {os.path.getsize(zip_path):,} bytes)")
    if args.mode == "sharepoint":
        print("  knowledge/ is NOT in the zip - upload those 10 files to SharePoint and")
        print("  set the OneDriveAndSharePoint items_by_url in declarativeAgent.source.json.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
