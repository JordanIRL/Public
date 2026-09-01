<#
.SYNOPSIS
    Audits NDIS bindings and the Winsock catalog for third-party traffic interceptors.
.DESCRIPTION
    DETECTION-ONLY package. There is no paired remediation, by design: automatically
    unbinding a filter driver can sever connectivity on a remote device, and the right
    fix depends entirely on which product it is. This reports; a human decides.

    Inbound-inspecting filter drivers (AV/EDR with HTTPS inspection, leftover VPN NDIS
    filters, orphaned LSPs) slow the receive path far more than the send path, which
    matches the "slow download, fast upload" signature.

    Baseline set below is stock Windows. Anything outside it is worth a look, and is
    NOT automatically a fault - Defender and most EDRs legitimately appear here.
.NOTES
    Context: SYSTEM. 64-bit host. Always exits 0 - informational only.
#>
$ErrorActionPreference = 'SilentlyContinue'

$baseline = @(
    'ms_tcpip', 'ms_tcpip6', 'ms_msclient', 'ms_server', 'ms_pacer', 'ms_lldp',
    'ms_rspndr', 'ms_lltdio', 'ms_implat', 'ms_ndisuio', 'ms_netbios', 'ms_wfplwfs',
    'ms_virtual_wifi', 'ms_vwifi', 'ms_bridge'
)

$adapter = Get-NetAdapter -Physical |
    Where-Object { $_.Status -eq 'Up' -and ($_.PhysicalMediaType -match '802.11' -or $_.MediaType -eq 'Native 802.11') } |
    Select-Object -First 1

$lines = @()

if ($adapter) {
    $extra = Get-NetAdapterBinding -Name $adapter.Name |
        Where-Object { $_.Enabled -and $baseline -notcontains $_.ComponentID } |
        Select-Object -ExpandProperty ComponentID
    $lines += 'bind=' + $(if ($extra) { ($extra -join ',') } else { 'clean' })
} else {
    $lines += 'bind=noadapter'
}

# Non-Microsoft Winsock LSPs. Rare on modern Windows; when present, they intercept
# every socket on the machine.
$lsp = (netsh winsock show catalog) -join "`n"
$providers = [regex]::Matches($lsp, 'Winsock Catalog Provider Entry.*?Description:\s*(.+?)[\r\n]', 'Singleline')
$thirdParty = @($providers | ForEach-Object { $_.Groups[1].Value.Trim() } |
    Where-Object { $_ -notmatch 'MSAFD|RSVP|Microsoft|Hyper-V' } | Select-Object -Unique)
$lines += 'lsp=' + $(if ($thirdParty) { (($thirdParty | Select-Object -First 4) -join ',') } else { 'clean' })

# Light-touch service check for known inline inspectors.
$svc = @(Get-Service | Where-Object {
    $_.Status -eq 'Running' -and
    $_.Name -match 'Netskope|Zscaler|Umbrella|Forcepoint|Symantec|McAfee|SentinelOne|CrowdStrike|Palo|FortiClient'
} | Select-Object -ExpandProperty Name -Unique)
$lines += 'inspect=' + $(if ($svc) { (($svc | Select-Object -First 4) -join ',') } else { 'none' })

Write-Output ('FILTER|' + ($lines -join '|'))
exit 0
