<#
.SYNOPSIS
    Detects Wi-Fi adapter settings that have drifted from their driver defaults.
.DESCRIPTION
    This is the "reset networking components to original settings" half of what the
    Windows Settings > Network reset button does. The other half - remove and reinstall
    the adapter - is a separate, much heavier pair: Network Driver Reinstall.

    NOT the same thing as Stack Reset. Stack Reset works below the adapter (Winsock
    catalog, IP stack) and needs a reboot. This works ON the adapter, applies live, and
    is the only pair in the kit that looks at driver advanced properties as a whole.

    Why it belongs in a download-only investigation: a mangled receive-path property
    caps inbound throughput while leaving transmit untouched, which is the exact
    signature this kit chases. The usual suspects are *ReceiveBuffers, *RSS,
    *FlowControl, *InterruptModeration and the 802.11 band/width/roaming keywords.
    Nothing else in the kit inspects them, and the fingerprint does not carry them.

    Also REPORTS - never changes - static IP, static DNS, a machine WinHTTP proxy and
    persistent static routes on the Wi-Fi interface. None of those can produce a
    download-only cap on their own, so resetting them would be motion without progress,
    and clearing a proxy the org actually needs breaks Intune itself. They are printed
    because they belong on the ticket.

    A 24-hour cooldown marker is the safety net. The reset bounces the adapter, so if
    this package is ever assigned to a group by mistake the cooldown stops it bouncing
    Wi-Fi on every check-in.
.NOTES
    Context: SYSTEM. 64-bit host. Exit 1 = drift found and outside cooldown.
#>
$ErrorActionPreference = 'SilentlyContinue'

$key  = 'HKLM:\SOFTWARE\NetworkFix'
$last = (Get-ItemProperty -Path $key -Name 'LastSettingsResetUtc').LastSettingsResetUtc
if ($last) {
    $age = ((Get-Date).ToUniversalTime() - [datetime]$last).TotalHours
    if ($age -lt 24) {
        Write-Output ("NET_RESET|cooldown|hours={0:N1}" -f $age)
        exit 0
    }
}

$adapter = Get-NetAdapter -Physical |
    Where-Object { $_.Status -eq 'Up' -and ($_.PhysicalMediaType -match '802.11' -or $_.MediaType -eq 'Native 802.11') } |
    Select-Object -First 1

if (-not $adapter) { Write-Output 'NET_RESET|noadapter'; exit 0 }

# Receive-path keywords: the subset that can plausibly cap download alone.
$rxKeywords = @(
    '*ReceiveBuffers', '*RSS', '*ReceiveSideScaling', '*FlowControl', '*JumboPacket'
    '*InterruptModeration', '*SelectiveSuspend', '*PMARPOffload', '*PMNSOffload'
    'ChannelWidth', 'RoamingPreferredBandType', 'PowerSaveMode', 'ThroughputBoost'
    'MIMOPowerSaveMode', 'FatChannelIntolerant', 'HtMode', 'PreferredBand'
)

# Drift = current registry value differs from the value the INF declares as default.
# Properties with no declared default cannot drift by definition, so they are skipped.
$drift = @()
$rxDrift = @()
foreach ($p in (Get-NetAdapterAdvancedProperty -Name $adapter.Name)) {
    $def = $p.DefaultRegistryValue
    if ($null -eq $def -or $def -eq '') { continue }
    $cur = if ($p.RegistryValue) { $p.RegistryValue[0] } else { '' }
    if ($cur -ne $def) {
        $drift += "$($p.RegistryKeyword)=$cur/$def"
        if ($rxKeywords -contains $p.RegistryKeyword) { $rxDrift += $p.RegistryKeyword }
    }
}

# Report-only context. None of this is touched by the remediation.
$ctx = @()

$ip = Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4
if ($ip -and $ip.Dhcp -eq 'Disabled') { $ctx += 'staticip=yes' }

$ifPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($adapter.InterfaceGuid)"
$ns     = (Get-ItemProperty -Path $ifPath -Name 'NameServer').NameServer
if ($ns) { $ctx += 'staticdns=yes' }

$proxy = (netsh winhttp show proxy) -join ' '
if ($proxy -notmatch 'Direct access|DIRECT') { $ctx += 'winhttpproxy=set' }

$routes = @(Get-NetRoute -InterfaceIndex $adapter.ifIndex -PolicyStore PersistentStore)
if ($routes.Count -gt 0) { $ctx += "persistroutes=$($routes.Count)" }

# Keep the line well inside the 2048-char detection budget on a chatty driver.
$shown = if ($drift.Count -gt 8) { ($drift[0..7] -join '|') + "|+$($drift.Count - 8)more" }
         else                    { $drift -join '|' }

$out = "NET_RESET|drift=$($drift.Count)|rx=$(if ($rxDrift) { $rxDrift -join ',' } else { 'none' })"
if ($ctx)   { $out += '|' + ($ctx -join '|') }
if ($drift) { $out += '|' + $shown }

Write-Output $out
if ($drift.Count -gt 0) { exit 1 }
exit 0
