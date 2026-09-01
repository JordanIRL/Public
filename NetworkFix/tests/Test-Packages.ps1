<#
.SYNOPSIS
    Guards the deployment invariants - the ones that fail silently on real hardware.
.DESCRIPTION
    Test-Fingerprint.ps1 covers the fingerprint's output format. This covers everything
    that decides whether a package behaves correctly once Intune runs it, and every check
    here exists because getting it wrong produces a plausible, wrong result rather than
    an error:

      1. MANIFEST RESOLVES.   A renamed script silently deploys the old content, because
                              Invoke-Deploy.ps1 only throws at push time.
      2. SYNTAX.              A script that does not parse reports 'failed' on every
                              device with no indication why.
      3. 64-BIT.              runAs32Bit must be false everywhere. A 32-bit host hits
                              WOW64 registry redirection and the fingerprint renders
                              correctly while being quietly incorrect. README calls this
                              the single easiest way to get a plausible wrong answer.
      4. RUN CONTEXT.         Only the USER probe runs as the user. Anything else in user
                              context loses the machine hive and half the net cmdlets.
      5. NO REBOOTS.          Microsoft forbids reboot commands in detection and
                              remediation scripts, and a surprise reboot is the exact
                              disruption this kit exists to avoid.
      6. FIRING PATH.         A package with a remediation whose detection can never
                              exit 1 is inert - it deploys, runs, reports healthy, and
                              never once remediates.
      7. BLAST RADIUS.        Every 'NEVER SCHEDULE' package must carry a cooldown guard,
                              which is what limits the damage of a mis-assignment.
      8. NO BOM.              A UTF-8 BOM breaks Intune's signature-check path.
      9. NO ORPHANS.          A script on disk that no package references is a script
                              nobody is running.
     10. UNIQUE TAGS.         Two packages emitting the same leading tag collide into one
                              another's columns in Get-RemediationResults.ps1.

    Runs anywhere pwsh runs - no Windows needed.
.EXAMPLE
    pwsh -NoProfile -File tests/Test-Packages.ps1
#>
$ErrorActionPreference = 'Stop'
$fail = 0
function Assert { param([string]$Name, [bool]$Cond, [string]$Detail = '')
    if ($Cond) { Write-Host "  PASS  $Name" -ForegroundColor Green }
    else { Write-Host "  FAIL  $Name $Detail" -ForegroundColor Red; $script:fail++ }
}

$root     = Split-Path $PSScriptRoot -Parent
$manifest = Get-Content (Join-Path $root 'deploy/packages.json') -Raw | ConvertFrom-Json
$packages = $manifest.packages

Write-Host "`n1. Manifest resolves ($($packages.Count) packages)" -ForegroundColor Cyan
foreach ($p in $packages) {
    foreach ($k in 'detection', 'remediation') {
        $rel = $p.$k
        if (-not $rel) { continue }
        Assert "$($p.name) -> $k" (Test-Path (Join-Path $root $rel)) "(missing $rel)"
    }
}

Write-Host "`n2. Every script parses" -ForegroundColor Cyan
$scripts = Get-ChildItem $root -Recurse -Filter *.ps1
foreach ($s in $scripts) {
    $errs = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($s.FullName, [ref]$null, [ref]$errs)
    Assert $s.Name ($errs.Count -eq 0) "($($errs | Select-Object -First 1 | ForEach-Object { $_.Message }))"
}

Write-Host "`n3. 64-bit on every package" -ForegroundColor Cyan
$b32 = @($packages | Where-Object { $_.runAs32Bit })
Assert 'runAs32Bit false everywhere' ($b32.Count -eq 0) "(32-bit: $($b32.name -join ', '))"

Write-Host "`n4. Run context" -ForegroundColor Cyan
$asUser = @($packages | Where-Object { $_.runAsAccount -eq 'user' })
Assert 'exactly one user-context package' ($asUser.Count -eq 1) "(got $($asUser.Count))"
Assert 'and it is the USER probe' ($asUser.name -like '*(USER)') "(got '$($asUser.name)')"

Write-Host "`n5. No reboot commands" -ForegroundColor Cyan
foreach ($s in $scripts) {
    if ($s.FullName -like "*$([IO.Path]::DirectorySeparatorChar)tests$([IO.Path]::DirectorySeparatorChar)*") { continue }
    $body = (Get-Content $s.FullName -Raw) -split "`n" |
        Where-Object { $_ -notmatch '^\s*#' } | Join-String -Separator "`n"
    Assert "no reboot in $($s.Name)" ($body -notmatch 'Restart-Computer|shutdown\.exe|shutdown\s+/r')
}

Write-Host "`n6. Detection can actually fire its remediation" -ForegroundColor Cyan
foreach ($p in ($packages | Where-Object { $_.remediation })) {
    $det = Get-Content (Join-Path $root $p.detection) -Raw
    # House style puts exit 1 inline - '{ Write-Output ...; exit 1 }' - so match the
    # statement anywhere, not just on a line of its own.
    Assert "$($p.name) detection can exit 1" ($det -match '(?m)(^|[;{])\s*exit 1\b')
}

Write-Host "`n7. On-demand-only packages carry a cooldown" -ForegroundColor Cyan
foreach ($p in ($packages | Where-Object { $_.schedule -eq 'NEVER SCHEDULE' })) {
    $det = Get-Content (Join-Path $root $p.detection) -Raw
    Assert "$($p.name) has a cooldown guard" ($det -match 'cooldown')
    Assert "$($p.name) name warns in the portal" ($p.name -match 'ON-DEMAND ONLY')
}

Write-Host "`n8. No UTF-8 BOM" -ForegroundColor Cyan
foreach ($s in $scripts) {
    $bytes = [IO.File]::ReadAllBytes($s.FullName) | Select-Object -First 3
    $hasBom = ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    Assert "no BOM in $($s.Name)" (-not $hasBom)
}

Write-Host "`n9. No orphaned scripts" -ForegroundColor Cyan
$referenced = @($packages | ForEach-Object { $_.detection; $_.remediation } | Where-Object { $_ } |
    ForEach-Object { (Join-Path $root $_ | Resolve-Path).Path })
foreach ($s in $scripts) {
    if ($s.FullName -match "\$([IO.Path]::DirectorySeparatorChar)(tests|deploy)\$([IO.Path]::DirectorySeparatorChar)") { continue }
    Assert "$($s.Name) is deployed by a package" ($referenced -contains $s.FullName)
}

Write-Host "`n10. Output tags are unique per package" -ForegroundColor Cyan
$tags = @{}
foreach ($p in $packages) {
    $det = Get-Content (Join-Path $root $p.detection) -Raw
    $m = [regex]::Matches($det, "Write-Output\s+\(?[""']([A-Z][A-Z_]{2,})\|")
    foreach ($t in ($m | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)) {
        if (-not $tags.ContainsKey($t)) { $tags[$t] = @() }
        $tags[$t] += $p.name
    }
}
foreach ($t in ($tags.Keys | Sort-Object)) {
    Assert "tag $t used by one package" ($tags[$t].Count -eq 1) "(also: $($tags[$t] -join ', '))"
}

Write-Host ''
if ($fail) { Write-Host "$fail test(s) FAILED" -ForegroundColor Red; exit 1 }
Write-Host 'all tests passed' -ForegroundColor Green
exit 0
