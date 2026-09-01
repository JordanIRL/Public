<#
.SYNOPSIS
    Local tests for the two things most likely to break silently.
.DESCRIPTION
    1. OUTPUT BUDGET. Intune truncates detection output at 2048 characters. The VERDICT
       line is emitted LAST, so an overlong fingerprint loses precisely the field the
       whole kit exists to produce. Tested against a deliberately worst-case device.
    2. PARSER ROUND-TRIP. Get-RemediationResults.ps1 turns the pipe format back into
       columns. If the two formats drift apart, the CSV silently loses columns.

    Runs anywhere pwsh runs - no Windows needed.
.EXAMPLE
    pwsh -NoProfile -File tests/Test-Fingerprint.ps1
#>
$ErrorActionPreference = 'Stop'
$fail = 0
function Assert { param([string]$Name, [bool]$Cond, [string]$Detail = '')
    if ($Cond) { Write-Host "  PASS  $Name" -ForegroundColor Green }
    else { Write-Host "  FAIL  $Name $Detail" -ForegroundColor Red; $script:fail++ }
}

Write-Host "`n1. Output budget (2048 char cap)" -ForegroundColor Cyan

# Worst case: longest plausible value in every field. Long Dell model, long driver name,
# a maximal filter-driver list, and a long AV product name.
$worst = @(
    'NF|v1|2026-09-01T14:22Z|SYSTEM|Latitude 7450 Ultralight Business Notebook'
    'WLAN|band=5GHz|ch=149|sig=100|rxrate=2402|txrate=2402|radio=802.11ax|bssid=..:1a'
    'PHY|rxerr=4294967295|rxdisc=4294967295|txerr=4294967295|link=2.4Gbps'
    'TCP|autotune=highlyrestricted|rsc=enabled|retx=99.99%'
    'NET|gwrtt=9999|gwloss=100%'
    'THRU|s1=9999.99|s8=9999.99|ratio=9999.9|ep=speed.cloudflare.com|skip=cooldown'
    'DRV|Intel(R) Wi-Fi 6E AX211 160MHz Wireless Network Adapter|23.60.1.2|2024-11-02'
    'SW|SmartByte=1|Killer=1|DellOpt=1|VPN=GlobalProtect|AV=MicrosoftDefenderAntivirus'
    ('FILT|extra=' + (( 1..12 | ForEach-Object { "vendor_ndis_filter_$_" }) -join ','))
    'PWR|pnpcap=24|sleepok=Enabled'
    'VERDICT|RX_LOSS_RADIO|conf=high'
) -join "`n"

Assert 'worst-case fingerprint under cap' ($worst.Length -lt 2048) "(actual $($worst.Length))"
Assert 'VERDICT survives truncation guard' (
    $(if ($worst.Length -gt 2040) { $worst.Substring(0,2040) } else { $worst }) -match 'VERDICT\|'
)

Write-Host "`n2. Parser round-trip" -ForegroundColor Cyan

# Same parsing logic as Get-RemediationResults.ps1.
function ConvertFrom-Fingerprint {
    param([string] $Text)
    $row = [ordered]@{ Truncated = $false }
    foreach ($line in ($Text -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split '\|'
        $key = $parts[0].Trim()
        if ($key -eq 'TRUNC') { $row.Truncated = $true; continue }
        if ($key -eq 'VERDICT') {
            $row.VERDICT = $parts[1]; $row.Confidence = ($parts[2] -replace '^conf=', ''); continue
        }
        foreach ($p in $parts[1..($parts.Count - 1)]) {
            if ($p -match '^([^=]+)=(.*)$') { $row["${key}_$($Matches[1])"] = $Matches[2] }
        }
    }
    [pscustomobject]$row
}

$p = ConvertFrom-Fingerprint $worst
Assert 'VERDICT parsed'       ($p.VERDICT -eq 'RX_LOSS_RADIO') "(got '$($p.VERDICT)')"
Assert 'confidence parsed'    ($p.Confidence -eq 'high')       "(got '$($p.Confidence)')"
Assert 'THRU_s1 parsed'       ($p.THRU_s1 -eq '9999.99')       "(got '$($p.THRU_s1)')"
Assert 'THRU_ratio parsed'    ($p.THRU_ratio -eq '9999.9')     "(got '$($p.THRU_ratio)')"
Assert 'TCP_autotune parsed'  ($p.TCP_autotune -eq 'highlyrestricted') "(got '$($p.TCP_autotune)')"
Assert 'SW_SmartByte parsed'  ($p.SW_SmartByte -eq '1')        "(got '$($p.SW_SmartByte)')"
Assert 'not flagged truncated' ($p.Truncated -eq $false)

# A value containing '=' must keep everything after the first delimiter.
$eq = ConvertFrom-Fingerprint "THRU|ep=host.example.com/path?bytes=500|s1=3.1"
Assert 'value with = preserved' ($eq.THRU_ep -eq 'host.example.com/path?bytes=500') "(got '$($eq.THRU_ep)')"

$tr = ConvertFrom-Fingerprint "NF|v1|SYSTEM`nTHRU|s1=3.1`nTRUNC"
Assert 'TRUNC flagged'        ($tr.Truncated -eq $true)
Assert 'truncated row has no VERDICT' ($null -eq $tr.VERDICT)

Write-Host ''
if ($fail) { Write-Host "$fail test(s) FAILED" -ForegroundColor Red; exit 1 }
Write-Host 'all tests passed' -ForegroundColor Green
exit 0
