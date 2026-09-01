<#
.SYNOPSIS
    Network triage fingerprint collector + verdict engine for Intune Remediations.

.DESCRIPTION
    Runs as the DETECTION script of an Intune remediation package, as SYSTEM, with no
    user involvement. Collects a compact fingerprint of the Wi-Fi / TCP / driver / filter
    stack, runs a bounded single-stream vs parallel-stream throughput probe, and emits a
    VERDICT naming the most likely cause class.

    The single-vs-parallel ratio is the primary discriminator:
      ratio >> 1  -> loss-limited or receive-window-limited (recoverable by more streams)
      ratio ~= 1  -> a hard rate cap somewhere in the stack (more streams do not help)

.NOTES
    Host requirements  : PowerShell 5.1, 64-BIT host (see README - the Intune default is 32-bit)
    Context            : SYSTEM ("Run using logged-on credentials" = No)
    Output budget      : 2048 characters (preRemediationDetectionScriptOutput truncates past this)
    Runtime budget     : < 60 seconds
    Exit codes         : 0 = no auto-fixable condition   1 = auto-fixable condition found

    Contains no reboot command. Microsoft forbids reboots in detection/remediation scripts.
#>

[CmdletBinding()]
param(
    # Endpoints are tried in order. The first that serves bytes wins and is recorded.
    [string[]] $ProbeEndpoint = @(
        'https://speed.cloudflare.com/__down?bytes=524288000'
        'https://ash-speed.hetzner.com/100MB.bin'
    ),
    [int]    $ProbeSeconds     = 8,          # per-test time box
    [long]   $ProbeMaxBytes    = 25MB,       # per-test byte cap (bounds fast links)
    [int]    $ParallelStreams  = 8,
    [int]    $CooldownMinutes  = 240,        # suppress re-probing on a recurring schedule
    [int]    $MinBatteryPct    = 25,         # skip probe below this when on battery
    [switch] $SkipThroughput,
    [switch] $IgnoreCooldown,
    [string] $StateKey         = 'HKLM:\SOFTWARE\NetworkFix'
)

$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference    = 'SilentlyContinue'

# ---------------------------------------------------------------- helpers

# Every collector runs inside this. One failing subsystem must never cost us the
# whole fingerprint - it degrades to '?' so the gap is visible rather than silent.
function Get-Safe {
    param([scriptblock] $Block, $Default = '?')
    try {
        $v = & $Block
        if ($null -eq $v -or $v -eq '') { return $Default }
        return $v
    } catch { return $Default }
}

function ConvertTo-Num {
    param($Text, $Default = '?')
    if ($null -eq $Text) { return $Default }
    $m = [regex]::Match([string]$Text, '(-?\d+(?:\.\d+)?)')
    if ($m.Success) { return $m.Groups[1].Value }
    return $Default
}

$script:Lines = New-Object System.Collections.Generic.List[string]
function Add-Line { param([string] $Key, [string[]] $Pairs)
    $script:Lines.Add(('{0}|{1}' -f $Key, ($Pairs -join '|')))
}

$ctx = if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) { 'SYSTEM' } else { 'USER' }

# ---------------------------------------------------------------- header

$model = Get-Safe { (Get-CimInstance Win32_ComputerSystem).Model.Trim() }
Add-Line 'NF' @('v1', (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mmZ'), $ctx, $model)

# ---------------------------------------------------------------- WLAN link

# netsh wlan output is LOCALISED. We match on English labels and fall back to '?'
# rather than emitting a wrong number - see README "Locale" note.
$wlanRaw = Get-Safe { (netsh wlan show interfaces) -join "`n" } ''
function Get-WlanField { param([string] $Pattern)
    $m = [regex]::Match($wlanRaw, $Pattern, 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return '?'
}

$band    = Get-WlanField '^\s*Band\s*:\s*(.+)$'
$chan    = Get-WlanField '^\s*Channel\s*:\s*(.+)$'
$sig     = ConvertTo-Num (Get-WlanField '^\s*Signal\s*:\s*(.+)$')
$rxRate  = ConvertTo-Num (Get-WlanField '^\s*Receive rate \(Mbps\)\s*:\s*(.+)$')
$txRate  = ConvertTo-Num (Get-WlanField '^\s*Transmit rate \(Mbps\)\s*:\s*(.+)$')
$radio   = Get-WlanField '^\s*Radio type\s*:\s*(.+)$'
$bssid   = Get-WlanField '^\s*BSSID\s*:\s*(.+)$'
if ($bssid -ne '?' -and $bssid.Length -ge 5) { $bssid = '..' + $bssid.Substring($bssid.Length - 5) }

Add-Line 'WLAN' @("band=$($band -replace '\s','')", "ch=$chan", "sig=$sig",
                  "rxrate=$rxRate", "txrate=$txRate", "radio=$($radio -replace '\s','')", "bssid=$bssid")

# ---------------------------------------------------------------- adapter counters

$wifiAdapter = Get-Safe {
    Get-NetAdapter -Physical |
        Where-Object { $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Virtual|Bluetooth|Loopback' } |
        Where-Object { $_.MediaType -eq 'Native 802.11' -or $_.PhysicalMediaType -match '802.11' } |
        Select-Object -First 1
} $null

if ($wifiAdapter) {
    $st = Get-Safe { Get-NetAdapterStatistics -Name $wifiAdapter.Name } $null
    Add-Line 'PHY' @("rxerr=$(if($st){$st.ReceivedPacketErrors}else{'?'})",
                     "rxdisc=$(if($st){$st.ReceivedDiscardedPackets}else{'?'})",
                     "txerr=$(if($st){$st.OutboundPacketErrors}else{'?'})",
                     "link=$($wifiAdapter.LinkSpeed -replace '\s','')")
} else {
    Add-Line 'PHY' @('adapter=none')
}

# ---------------------------------------------------------------- TCP stack

$tcpRaw    = Get-Safe { (netsh int tcp show global) -join "`n" } ''
$autotune  = Get-Safe { ([regex]::Match($tcpRaw,'Receive Window Auto-Tuning Level\s*:\s*(\w+)','IgnoreCase')).Groups[1].Value }
$rsc       = Get-Safe { ([regex]::Match($tcpRaw,'Receive Segment Coalescing State\s*:\s*(\w+)','IgnoreCase')).Groups[1].Value }

# Retransmit ratio is the loss proxy. netstat -s is cheap and locale-stable enough
# on the two counters we need.
$tcpStat   = Get-Safe { (netstat -s -p tcp) -join "`n" } ''
$segSent   = ConvertTo-Num (Get-Safe { ([regex]::Match($tcpStat,'Segments Sent\s*=\s*(\d+)','IgnoreCase')).Groups[1].Value })
$segRetx   = ConvertTo-Num (Get-Safe { ([regex]::Match($tcpStat,'Segments Retransmitted\s*=\s*(\d+)','IgnoreCase')).Groups[1].Value })
$retxPct   = '?'
if ($segSent -ne '?' -and $segRetx -ne '?' -and [double]$segSent -gt 0) {
    $retxPct = [math]::Round(([double]$segRetx / [double]$segSent) * 100, 2)
}
Add-Line 'TCP' @("autotune=$autotune", "rsc=$rsc", "retx=$retxPct%")

# ---------------------------------------------------------------- path RTT / loss

$gw = Get-Safe {
    (Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1).NextHop
} $null
$rttAvg = '?'; $lossPct = '?'
if ($gw) {
    $png = Get-Safe { (ping.exe -n 10 -w 1000 $gw) -join "`n" } ''
    $lossPct = ConvertTo-Num (Get-Safe { ([regex]::Match($png,'\((\d+)% loss','IgnoreCase')).Groups[1].Value })
    $rttAvg  = ConvertTo-Num (Get-Safe { ([regex]::Match($png,'Average = (\d+)ms','IgnoreCase')).Groups[1].Value })
}
Add-Line 'NET' @("gwrtt=$rttAvg", "gwloss=$lossPct%")

# ---------------------------------------------------------------- throughput probe

# Reads into a discard buffer, time-boxed AND byte-capped, so a fast link stops on
# bytes and a slow link stops on time. Bounds bandwidth in both directions.
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
        $sw.Stop()
        $stream.Close(); $resp.Close()
        return [pscustomobject]@{ Bytes = $total; Seconds = $sw.Elapsed.TotalSeconds }
    } catch {
        return [pscustomobject]@{ Bytes = 0L; Seconds = 0 }
    }
}

function Measure-Throughput {
    param([string] $Url, [int] $Streams, [int] $Seconds, [long] $MaxBytes)
    $per = [long]($MaxBytes / $Streams)
    if ($Streams -eq 1) {
        $r = & $readLoop $Url $Seconds $MaxBytes
        if ($r.Seconds -le 0) { return 0 }
        return [math]::Round(($r.Bytes * 8) / $r.Seconds / 1MB, 2)
    }
    $pool = [runspacefactory]::CreateRunspacePool(1, $Streams)
    $pool.Open()
    $jobs = @()
    foreach ($i in 1..$Streams) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        [void]$ps.AddScript($readLoop).AddArgument($Url).AddArgument($Seconds).AddArgument($per)
        $jobs += [pscustomobject]@{ PS = $ps; Handle = $ps.BeginInvoke() }
    }
    $bytes = 0L; $span = 0.0
    foreach ($j in $jobs) {
        try {
            $res = $j.PS.EndInvoke($j.Handle)
            if ($res -and $res[0]) {
                $bytes += $res[0].Bytes
                if ($res[0].Seconds -gt $span) { $span = $res[0].Seconds }
            }
        } catch {
            # A failed stream must not void the whole measurement - the remaining
            # streams still yield a usable aggregate. Recorded as fewer bytes.
            $null = $_
        }
        $j.PS.Dispose()
    }
    $pool.Close(); $pool.Dispose()
    if ($span -le 0) { return 0 }
    return [math]::Round(($bytes * 8) / $span / 1MB, 2)
}

$s1 = '?'; $sN = '?'; $ratio = '?'; $usedEp = 'none'; $probeNote = ''

# Guards. Each one is a reason to skip, recorded so a skipped probe is never
# mistaken for a healthy one.
$metered = Get-Safe {
    $cp = [Windows.Networking.Connectivity.NetworkInformation, Windows, ContentType=WindowsRuntime]::GetInternetConnectionProfile()
    if ($cp) { $cp.GetConnectionCost().NetworkCostType -ne 'Unrestricted' } else { $false }
} $false

$batt = Get-Safe { (Get-CimInstance Win32_Battery | Select-Object -First 1) } $null
$onBatteryLow = ($batt -and $batt.BatteryStatus -eq 1 -and $batt.EstimatedChargeRemaining -lt $MinBatteryPct)

$lastProbe = Get-Safe { [datetime](Get-ItemProperty -Path $StateKey -Name 'LastProbeUtc').LastProbeUtc } $null
$inCooldown = ($lastProbe -and -not $IgnoreCooldown -and
               ((Get-Date).ToUniversalTime() - $lastProbe).TotalMinutes -lt $CooldownMinutes)

if     ($SkipThroughput) { $probeNote = 'skip=flag' }
elseif ($metered)        { $probeNote = 'skip=metered' }
elseif ($onBatteryLow)   { $probeNote = 'skip=battery' }
elseif ($inCooldown)     { $probeNote = 'skip=cooldown' }
else {
    foreach ($ep in $ProbeEndpoint) {
        $t1 = Measure-Throughput -Url $ep -Streams 1 -Seconds $ProbeSeconds -MaxBytes $ProbeMaxBytes
        if ($t1 -le 0) { continue }
        $tN = Measure-Throughput -Url $ep -Streams $ParallelStreams -Seconds $ProbeSeconds -MaxBytes $ProbeMaxBytes
        $s1 = $t1; $sN = $tN
        if ($t1 -gt 0) { $ratio = [math]::Round($tN / $t1, 1) }
        $usedEp = ($ep -replace '^https?://([^/]+).*$', '$1')
        break
    }
    if ($usedEp -eq 'none') { $probeNote = 'skip=noendpoint' }
    else {
        Get-Safe { if (-not (Test-Path $StateKey)) { New-Item -Path $StateKey -Force | Out-Null }
                   Set-ItemProperty -Path $StateKey -Name 'LastProbeUtc' `
                     -Value ((Get-Date).ToUniversalTime().ToString('o')) -Force } | Out-Null
    }
}
Add-Line 'THRU' @("s1=$s1", "s$ParallelStreams=$sN", "ratio=$ratio", "ep=$usedEp", $probeNote)

# ---------------------------------------------------------------- driver

$drv = Get-Safe {
    Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='NET'" |
        Where-Object { $_.DeviceName -match 'Wi-?Fi|Wireless|802\.11|AX2\d\d|Killer' } |
        Select-Object -First 1
} $null
if ($drv) {
    $dd = Get-Safe { ([datetime]$drv.DriverDate).ToString('yyyy-MM-dd') }
    Add-Line 'DRV' @(($drv.DeviceName -replace '\|',''), $drv.DriverVersion, $dd)
} else { Add-Line 'DRV' @('none') }

# ---------------------------------------------------------------- software

# Both hives - a 32-bit host would silently miss the native one, which is exactly
# the trap the README warns about.
$uninstall = Get-Safe {
    @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') |
        ForEach-Object { Get-ItemProperty $_ } | Select-Object -ExpandProperty DisplayName
} @()

function Test-Installed { param([string] $Pattern)
    if ($uninstall -and ($uninstall -match $Pattern)) { 1 } else { 0 }
}
$vpn = Get-Safe {
    $v = $uninstall | Where-Object { $_ -match 'GlobalProtect|AnyConnect|Netskope|Zscaler|Umbrella|FortiClient|Pulse|OpenVPN' }
    if ($v) { (($v | Select-Object -First 1) -split ' ')[0] } else { 'none' }
} 'none'
$av = Get-Safe {
    $p = Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName AntiVirusProduct |
            Select-Object -First 1 -ExpandProperty displayName
    ($p -replace '\s','')
} '?'

Add-Line 'SW' @("SmartByte=$(Test-Installed 'SmartByte')",
                "Killer=$(Test-Installed 'Killer')",
                "DellOpt=$(Test-Installed 'Dell Optimizer')",
                "VPN=$vpn", "AV=$av")

# ---------------------------------------------------------------- filter drivers

if ($wifiAdapter) {
    $binds = Get-Safe {
        (Get-NetAdapterBinding -Name $wifiAdapter.Name |
            Where-Object { $_.Enabled -and $_.ComponentID -notmatch '^ms_(tcpip6?|msclient|server|pacer|lldp|rspndr|lltdio|implat|ndisuio)$' } |
            Select-Object -ExpandProperty ComponentID) -join ','
    } ''
    Add-Line 'FILT' @("extra=$(if($binds){$binds}else{'none'})")

    $pnpCap = Get-Safe {
        (Get-NetAdapterAdvancedProperty -Name $wifiAdapter.Name -RegistryKeyword '*PnPCapabilities' -ErrorAction Stop).RegistryValue[0]
    }
    $psMode = Get-Safe {
        (Get-NetAdapterPowerManagement -Name $wifiAdapter.Name).AllowComputerToTurnOffDevice
    }
    Add-Line 'PWR' @("pnpcap=$pnpCap", "sleepok=$psMode")
}

# ---------------------------------------------------------------- verdict engine

# Thresholds are deliberately conservative: we would rather return LOW confidence
# than send someone down a wrong path. That is the whole point of the kit.
$verdict = 'INCONCLUSIVE'; $conf = 'low'

$nRatio = if ($ratio -ne '?') { [double]$ratio } else { -1 }
$nS1    = if ($s1    -ne '?') { [double]$s1 }    else { -1 }
$nRetx  = if ($retxPct -ne '?') { [double]$retxPct } else { -1 }
$nRx    = if ($rxRate -ne '?') { [double]$rxRate } else { -1 }
$nSig   = if ($sig    -ne '?') { [double]$sig }   else { -1 }
$hasCap = ((Test-Installed 'SmartByte') -eq 1) -or ((Test-Installed 'Killer') -eq 1)

if ($probeNote -like 'skip=*') {
    $verdict = 'NO_PROBE'; $conf = 'none'
}
elseif ($nS1 -ge 25 -and $nRatio -ge 0) {
    $verdict = 'HEALTHY'; $conf = 'high'
}
elseif ($nS1 -ge 0 -and $nS1 -lt 15) {
    if ($nRatio -ge 3) {
        # More streams recovered the throughput -> per-connection limit, not a pipe cap.
        if ($autotune -and $autotune -notmatch '^normal$') { $verdict = 'TCP_WINDOW'; $conf = 'high' }
        elseif ($nRetx -ge 1.0 -or $nRx -ge 200)           { $verdict = 'RX_LOSS_RADIO'; $conf = 'high' }
        else                                                { $verdict = 'RX_LOSS_RADIO'; $conf = 'medium' }
    }
    elseif ($nRatio -ge 0 -and $nRatio -lt 1.6) {
        # More streams changed nothing -> something is capping the aggregate.
        if ($hasCap) { $verdict = 'HARD_CAP'; $conf = 'high' }
        else         { $verdict = 'HARD_CAP'; $conf = 'medium' }
    }
    if ($nRx -ge 0 -and $nRx -lt 100 -and $nSig -ge 0 -and $nSig -lt 60) {
        $verdict = 'RADIO_LINK'; $conf = 'medium'
    }
}

Add-Line 'VERDICT' @($verdict, "conf=$conf")

# ---------------------------------------------------------------- emit

$out = ($script:Lines -join "`n")
if ($out.Length -gt 2040) { $out = $out.Substring(0, 2040) + "`nTRUNC" }
Write-Output $out

# exit 1 only for conditions a paired remediation can actually fix unattended.
if ($verdict -in @('TCP_WINDOW', 'HARD_CAP', 'RADIO_LINK')) { exit 1 }
exit 0
