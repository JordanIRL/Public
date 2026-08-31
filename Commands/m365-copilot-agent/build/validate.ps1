<#
    Validates the generated Copilot agent package.

    Checks, in order of importance:
      1. Command fidelity  - every command in m365-kb/ survives into knowledge/ unchanged
      2. Parse             - every generated command still parses under the PowerShell parser
      3. Numeric limits    - schema v1.8 limits (instructions 8000, starters 12, files 10, 36000 chars)
      4. No tables         - Copilot cannot parse them
      5. Directive scan    - imperatives risk XPIA sanitisation in knowledge sources
      6. Package integrity - manifest references resolve

    Usage: pwsh -NoProfile -File build/validate.ps1
#>

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$kb   = Join-Path (Split-Path $root -Parent) 'm365-kb'
$know = Join-Path $root 'knowledge'
$app  = Join-Path $root 'appPackage'

$fail = 0
function Ok  ($m) { Write-Host "  PASS  $m" -ForegroundColor Green }
function Bad ($m) { Write-Host "  FAIL  $m" -ForegroundColor Red; $script:fail++ }
function Note($m) { Write-Host "        $m" -ForegroundColor DarkGray }

# ---------------------------------------------------------------- helpers
function Get-SourceCommands {
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($f in Get-ChildItem $kb -Filter *.md | Sort-Object Name) {
        $inFence = $false
        foreach ($line in Get-Content $f.FullName) {
            if ($line -match '^\s*```\s*(powershell|ps1|pwsh)\s*$') { $inFence = $true; continue }
            if ($inFence -and $line -match '^\s*```\s*$')            { $inFence = $false; continue }
            if ($inFence -and $line.Trim()) { $out.Add($line.Trim()) }
        }
    }
    return $out
}

function Get-GeneratedCommands {
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($f in Get-ChildItem $know -Filter *.txt | Sort-Object Name) {
        $inCmd = $false
        foreach ($line in Get-Content $f.FullName) {
            if ($line -match '^Commands?:\s*$') { $inCmd = $true; continue }
            if ($inCmd) {
                if ($line -match '^    \S' -or $line -match '^    \s*\S') { $out.Add($line.Trim()) }
                elseif (-not $line.Trim()) { $inCmd = $false }
                else { $inCmd = $false }
            }
        }
    }
    return $out
}

Write-Host "`n=== 1. COMMAND FIDELITY (m365-kb -> knowledge) ===" -ForegroundColor Cyan
$src = Get-SourceCommands
$gen = Get-GeneratedCommands
Note "source command lines: $($src.Count)   generated: $($gen.Count)"

$srcSorted = $src | Sort-Object
$genSorted = $gen | Sort-Object
$diff = Compare-Object -ReferenceObject $srcSorted -DifferenceObject $genSorted
if (-not $diff) {
    Ok "all $($src.Count) command lines preserved byte-for-byte"
} else {
    Bad "$($diff.Count) command line(s) differ between source and generated"
    $diff | Select-Object -First 15 | ForEach-Object {
        $tag = if ($_.SideIndicator -eq '<=') { 'LOST  ' } else { 'ADDED ' }
        Note "$tag $($_.InputObject)"
    }
}

Write-Host "`n=== 2. PARSE CHECK (generated commands) ===" -ForegroundColor Cyan
# Parse whole blocks, not single lines: multi-line recipes only parse as a unit.
function Get-GeneratedBlocks {
    $blocks = [System.Collections.Generic.List[string]]::new()
    foreach ($f in Get-ChildItem $know -Filter *.txt | Sort-Object Name) {
        $inCmd = $false; $buf = [System.Collections.Generic.List[string]]::new()
        foreach ($line in Get-Content $f.FullName) {
            if ($line -match '^Commands?:\s*$') {
                if ($buf.Count) { $blocks.Add($buf -join "`n"); $buf.Clear() }
                $inCmd = $true; continue
            }
            if ($inCmd) {
                if ($line -match '^    ') { $buf.Add($line.Substring(4)) }
                else { if ($buf.Count) { $blocks.Add($buf -join "`n"); $buf.Clear() }; $inCmd = $false }
            }
        }
        if ($buf.Count) { $blocks.Add($buf -join "`n") }
    }
    return $blocks
}
$blocks = Get-GeneratedBlocks
$parseErrs = 0; $placeholder = 0
foreach ($b in $blocks) {
    $e = $null
    [System.Management.Automation.Language.Parser]::ParseInput($b, [ref]$null, [ref]$e) | Out-Null
    if ($e) {
        if ($b -match '<[a-zA-Z][a-zA-Z0-9 _-]*>') { $placeholder++ }
        else { $parseErrs++; Note "PARSE: $($b -replace "`n", ' ; ')" }
    }
}
if ($parseErrs -eq 0) { Ok "$($blocks.Count) command blocks parse cleanly ($placeholder placeholder-token blocks ignored)" }
else { Bad "$parseErrs command block(s) fail to parse" }

Write-Host "`n=== 3. NUMERIC LIMITS (schema v1.8) ===" -ForegroundColor Cyan
$files = @(Get-ChildItem $know -Filter *.txt)
if ($files.Count -le 10) { Ok "$($files.Count) knowledge files (EmbeddedKnowledge max 10, SharePoint max 20)" }
else { Bad "$($files.Count) knowledge files exceeds the EmbeddedKnowledge limit of 10" }

$over = @($files | Where-Object { $_.Length -gt 36000 })
if (-not $over) { Ok "all knowledge files under 36,000 chars (largest $('{0:N0}' -f ($files | Measure-Object Length -Maximum).Maximum))" }
else { Bad "$($over.Count) file(s) over 36,000 chars: $($over.Name -join ', ')" }

$big = @($files | Where-Object { $_.Length -gt 1MB })
if (-not $big) { Ok "all knowledge files under the 1 MB EmbeddedKnowledge cap" } else { Bad "file(s) over 1 MB: $($big.Name -join ', ')" }

$daPath = Join-Path $app 'declarativeAgent.json'
if (Test-Path $daPath) {
    $da = Get-Content $daPath -Raw | ConvertFrom-Json
    foreach ($chk in @(
        @{ n = 'instructions'; v = $da.instructions.Length;      max = 8000 },
        @{ n = 'description';  v = $da.description.Length;       max = 1000 },
        @{ n = 'name';         v = $da.name.Length;              max = 100  })) {
        if ($chk.v -le $chk.max) { Ok "$($chk.n): $($chk.v) / $($chk.max) chars" }
        else { Bad "$($chk.n): $($chk.v) exceeds $($chk.max)" }
    }
    $cs = @($da.conversation_starters).Count
    if ($cs -le 12) { Ok "conversation_starters: $cs / 12" } else { Bad "conversation_starters: $cs exceeds 12" }

    if ($da.behavior_overrides.special_instructions.discourage_model_knowledge -eq $true) {
        Ok "discourage_model_knowledge = true (blocks invented cmdlets from model knowledge)"
    } else { Bad "discourage_model_knowledge is not true - the agent may invent cmdlets" }

    $ea = @($da.editorial_answers.answers).Count
    if ($ea -le 300) { Ok "editorial_answers: $ea / 300" } else { Bad "editorial_answers: $ea exceeds 300" }
} else { Bad "declarativeAgent.json not found" }

Write-Host "`n=== 4. NO TABLES IN KNOWLEDGE ===" -ForegroundColor Cyan
$tbl = @(Select-String -Path (Join-Path $know '*.txt') -Pattern '^\s*\|' -ErrorAction SilentlyContinue)
if (-not $tbl) { Ok "0 table rows (Copilot cannot parse tables)" }
else { Bad "$($tbl.Count) table row(s) remain"; $tbl | Select-Object -First 5 | ForEach-Object { Note "$($_.Filename):$($_.LineNumber)" } }

Write-Host "`n=== 5. DIRECTIVE SCAN (XPIA sanitisation risk) ===" -ForegroundColor Cyan
$imp = @(Select-String -Path (Join-Path $know '*.txt') -Pattern '(?i)\b(never (run|pipe|mix|use|fire|loop|commit)|always (pass|set|check|revoke)|do not (copy|confuse|loop|build|backslash)|avoid `|prefer server|prefer `)' -ErrorAction SilentlyContinue)
if (-not $imp) { Ok "no second-person imperatives remain in knowledge files" }
else {
    Write-Host "  WARN  $($imp.Count) imperative phrase(s) remain - review each" -ForegroundColor Yellow
    $imp | Select-Object -First 10 | ForEach-Object { Note "$($_.Filename):$($_.LineNumber)  $($_.Line.Trim())" }
}

Write-Host "`n=== 6. PACKAGE INTEGRITY ===" -ForegroundColor Cyan
$mPath = Join-Path $app 'manifest.json'
if (Test-Path $mPath) {
    $m = Get-Content $mPath -Raw | ConvertFrom-Json
    foreach ($ref in @($m.copilotAgents.declarativeAgents.file) + @($m.icons.color, $m.icons.outline)) {
        if ($ref) {
            if (Test-Path (Join-Path $app $ref)) { Ok "manifest reference resolves: $ref" }
            else { Bad "manifest reference missing: $ref" }
        }
    }
} else { Bad "manifest.json not found" }

Write-Host ""
if ($fail -eq 0) { Write-Host "ALL CHECKS PASSED" -ForegroundColor Green; exit 0 }
Write-Host "$fail CHECK(S) FAILED" -ForegroundColor Red; exit 1
