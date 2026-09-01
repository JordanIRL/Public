<#
.SYNOPSIS
    User-context companion probe. Answers one question: is the user's session slower
    than SYSTEM's, and if so, what is different about it?

.DESCRIPTION
    Deploy as a SEPARATE remediation package with "Run using logged-on credentials" = Yes.
    Still silent - it runs in the user's session, it does not interact with the user.

    Deploy this when the SYSTEM probe reports HEALTHY against a live user complaint.
    SYSTEM has no per-user WinINET/PAC proxy config, so a user-context-only fault
    (proxy, per-user AV/extension, browser policy) is invisible to the SYSTEM probe
    by construction.

    Compare THRU s1 here against THRU s1 from the SYSTEM run:
      user << system  -> CONTEXT_DELTA. The network stack is fine; look at the
                         user-scoped proxy / security product / browser.
      user ~= system  -> the fault is machine-wide. Trust the SYSTEM fingerprint.

.NOTES
    Host requirements : PowerShell 5.1, 64-bit host
    Context           : USER ("Run using logged-on credentials" = Yes)
    Exit code         : always 0 - this probe is diagnostic only, it never triggers a fix.
#>

[CmdletBinding()]
param(
    [string[]] $ProbeEndpoint = @(
        'https://speed.cloudflare.com/__down?bytes=524288000'
        'https://ash-speed.hetzner.com/100MB.bin'
    ),
    [int]  $ProbeSeconds  = 8,
    [long] $ProbeMaxBytes = 25MB
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

function Get-Safe { param([scriptblock] $Block, $Default = '?')
    try { $v = & $Block; if ($null -eq $v -or $v -eq '') { return $Default }; return $v }
    catch { return $Default }
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add(('NFU|v1|{0}|USER|{1}' -f (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mmZ'), $env:USERNAME))

# --- user-scoped proxy. This is the whole reason the script exists.
$ie = Get-Safe { Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' } $null
$proxyEnable = if ($ie) { $ie.ProxyEnable } else { '?' }
$proxyServer = if ($ie -and $ie.ProxyServer) { $ie.ProxyServer } else { 'none' }
$autoConfig  = if ($ie -and $ie.AutoConfigURL) { 'yes' } else { 'no' }
$lines.Add("PROXY|enable=$proxyEnable|server=$proxyServer|pac=$autoConfig")

$sysProxy = Get-Safe {
    $p = [System.Net.WebRequest]::GetSystemWebProxy()
    $u = $p.GetProxy('https://www.microsoft.com')
    if ($u.Host -eq 'www.microsoft.com') { 'direct' } else { $u.Host }
} '?'
$lines.Add("EFFPROXY|$sysProxy")

# --- same bounded read loop as the SYSTEM probe so the two numbers are comparable.
$readLoop = {
    param($Url, $Seconds, $MaxBytes)
    try {
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Timeout          = 10000
        $req.ReadWriteTimeout = ($Seconds + 4) * 1000
        $req.Proxy            = [System.Net.WebRequest]::GetSystemWebProxy()
        $req.UserAgent        = 'NetworkFix-Triage/1.0'
        $resp   = $req.GetResponse()
        $stream = $resp.GetResponseStream()
        $buf    = New-Object byte[] 81920
        $total  = 0L
        $sw     = [System.Diagnostics.Stopwatch]::StartNew()
        while ($sw.Elapsed.TotalSeconds -lt $Seconds -and $total -lt $MaxBytes) {
            $n = $stream.Read($buf, 0, $buf.Length)
            if ($n -le 0) { break }
            $total += $n
        }
        $sw.Stop(); $stream.Close(); $resp.Close()
        return [pscustomobject]@{ Bytes = $total; Seconds = $sw.Elapsed.TotalSeconds }
    } catch { return [pscustomobject]@{ Bytes = 0L; Seconds = 0 } }
}

$s1 = '?'; $usedEp = 'none'
foreach ($ep in $ProbeEndpoint) {
    $r = & $readLoop $ep $ProbeSeconds $ProbeMaxBytes
    if ($r.Seconds -gt 0 -and $r.Bytes -gt 0) {
        $s1 = [math]::Round(($r.Bytes * 8) / $r.Seconds / 1MB, 2)
        $usedEp = ($ep -replace '^https?://([^/]+).*$', '$1')
        break
    }
}
$lines.Add("THRU|s1=$s1|ep=$usedEp")

$out = ($lines -join "`n")
if ($out.Length -gt 2040) { $out = $out.Substring(0, 2040) + "`nTRUNC" }
Write-Output $out
exit 0
