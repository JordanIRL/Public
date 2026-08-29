#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Windows Gaming Network Optimiser v1.0

.DESCRIPTION
    Low-latency Ethernet configuration for a dedicated Windows 11
    gaming system, with particular emphasis on latency-sensitive
    multiplayer games such as Call of Duty: Modern Warfare 4.

    Target:
      - Windows 11 Enterprise
      - Wired Ethernet
      - Ryzen 7 3800X
      - RTX 5080
      - 4K gaming

    Changes:
      - Disables NIC power management.
      - Disables Energy Efficient / Green Ethernet when supported.
      - Disables Interrupt Moderation when supported.
      - Enables RSS.
      - Disables RSC for low-latency bias.
      - Disables Jumbo Frames when supported.
      - Keeps Speed/Duplex on Auto Negotiation.
      - Sets Cloudflare DNS.
      - Restores TCP Receive Window Auto-Tuning to Normal.
      - Flushes DNS cache.
      - Audits all relevant settings.

    Deliberately DOES NOT:
      - Disable IPv6.
      - Disable TCP/UDP checksum offloads.
      - Disable Large Send Offload.
      - Disable Windows Firewall.
      - Apply Nagle/TcpAckFrequency hacks.
      - Apply NetworkThrottlingIndex hacks.
      - Change MTU blindly.
      - Open Call of Duty firewall/router ports blindly.

.EXAMPLE
    .\Gaming-Network-v1.0.ps1

.EXAMPLE
    .\Gaming-Network-v1.0.ps1 -AuditOnly
#>

[CmdletBinding()]
param(
    [switch]$AuditOnly
)

$ErrorActionPreference = 'Continue'

# ===========================================================================
# CONFIGURATION
# ===========================================================================

$SetCloudflareDNS          = $true
$DisableInterruptModeration = $true
$DisableEnergySaving       = $true
$DisableNicPowerManagement = $true
$EnableRSS                 = $true

# Low-latency bias.
# RSC improves efficiency/throughput but can add coalescing latency.
$DisableRSC                = $true

$DisableJumboFrames        = $true
$ForceAutoNegotiation      = $true

# Do NOT change these to false for "gaming optimisation".
$KeepIPv6                  = $true
$KeepChecksumOffloads      = $true
$KeepLargeSendOffload      = $true

# ===========================================================================
# INITIALISATION
# ===========================================================================

$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$BasePath  = "$env:SystemDrive\GamingOptimizationBackup"

if ($AuditOnly) {
    $Root = "$BasePath\$Timestamp-Network-AUDIT"
}
else {
    $Root = "$BasePath\$Timestamp-Network-v1.0"
}

New-Item -Path $Root -ItemType Directory -Force | Out-Null

$Results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param(
        [string]$Category,
        [string]$Item,
        [string]$Status,
        [string]$Details = ''
    )

    $Results.Add(
        [PSCustomObject]@{
            Category = $Category
            Item     = $Item
            Status   = $Status
            Details  = $Details
        }
    )
}

# ===========================================================================
# IDENTIFY ACTIVE INTERNET NIC
# ===========================================================================

$DefaultRoute = Get-NetRoute `
    -DestinationPrefix '0.0.0.0/0' `
    -ErrorAction SilentlyContinue |
    Where-Object {
        $_.NextHop -ne '0.0.0.0'
    } |
    Sort-Object RouteMetric, InterfaceMetric |
    Select-Object -First 1

if (!$DefaultRoute) {
    throw "No active IPv4 Internet default route was found."
}

$Nic = Get-NetAdapter `
    -InterfaceIndex $DefaultRoute.InterfaceIndex `
    -ErrorAction Stop

Write-Host ""
Write-Host "============================================================"
Write-Host "Gaming Network Optimiser"
Write-Host "============================================================"
Write-Host ""
Write-Host "Adapter:     $($Nic.Name)"
Write-Host "Description: $($Nic.InterfaceDescription)"
Write-Host "Link speed:  $($Nic.LinkSpeed)"
Write-Host "Interface:   $($Nic.ifIndex)"
Write-Host ""

if ($Nic.MediaType -notmatch '802.3|Ethernet') {
    Write-Warning "The active Internet interface does not appear to be Ethernet."
    Write-Warning "This profile is designed primarily for wired gaming."
}

# ===========================================================================
# AUDIT FUNCTION
# ===========================================================================

function Save-NetworkAudit {

    param(
        [string]$Path
    )

    New-Item -Path $Path -ItemType Directory -Force | Out-Null

    # Adapter summary
    Get-NetAdapter |
        Select-Object `
            Name,
            InterfaceDescription,
            Status,
            LinkSpeed,
            MediaType,
            PhysicalMediaType,
            MacAddress,
            ifIndex |
        Format-Table -AutoSize |
        Out-File "$Path\Adapters.txt"

    # Active NIC
    $Nic |
        Format-List * |
        Out-File "$Path\ActiveNIC.txt"

    # Advanced properties
    try {
        Get-NetAdapterAdvancedProperty `
            -Name $Nic.Name `
            -AllProperties |
            Select-Object `
                DisplayName,
                DisplayValue,
                RegistryKeyword,
                RegistryValue |
            Sort-Object DisplayName |
            Export-Csv `
                "$Path\AdvancedProperties.csv" `
                -NoTypeInformation
    }
    catch {}

    # Power management
    try {
        Get-NetAdapterPowerManagement `
            -Name $Nic.Name |
            Format-List * |
            Out-File "$Path\PowerManagement.txt"
    }
    catch {}

    # RSS
    try {
        Get-NetAdapterRss `
            -Name $Nic.Name |
            Format-List * |
            Out-File "$Path\RSS.txt"
    }
    catch {}

    # RSC
    try {
        Get-NetAdapterRsc `
            -Name $Nic.Name |
            Format-List * |
            Out-File "$Path\RSC.txt"
    }
    catch {}

    # IP configuration
    Get-NetIPConfiguration `
        -InterfaceIndex $Nic.ifIndex |
        Format-List * |
        Out-File "$Path\IPConfiguration.txt"

    # IP interfaces / MTU
    Get-NetIPInterface `
        -InterfaceIndex $Nic.ifIndex |
        Select-Object `
            InterfaceAlias,
            AddressFamily,
            ConnectionState,
            NlMtu,
            InterfaceMetric,
            Dhcp,
            RouterDiscovery |
        Format-Table -AutoSize |
        Out-File "$Path\IPInterface.txt"

    # DNS
    Get-DnsClientServerAddress `
        -InterfaceIndex $Nic.ifIndex |
        Format-List * |
        Out-File "$Path\DNS.txt"

    try {
        Get-DnsClientDohServerAddress |
            Format-Table -AutoSize |
            Out-File "$Path\DoH.txt"
    }
    catch {}

    # TCP global state
    netsh interface tcp show global |
        Out-File "$Path\TCPGlobal.txt"

    # Full IP config
    ipconfig /all |
        Out-File "$Path\IPConfig-All.txt"

    # Routes
    Get-NetRoute |
        Sort-Object DestinationPrefix, RouteMetric |
        Format-Table -AutoSize |
        Out-File "$Path\Routes.txt"

    # Firewall profiles - audit only
    Get-NetFirewallProfile |
        Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction |
        Format-Table -AutoSize |
        Out-File "$Path\Firewall.txt"

    # Basic latency baseline
    cmd /c "ping -n 30 1.1.1.1" |
        Out-File "$Path\Ping-Cloudflare.txt"

    cmd /c "ping -n 30 8.8.8.8" |
        Out-File "$Path\Ping-Google.txt"

    if ($DefaultRoute.NextHop) {
        cmd /c "ping -n 30 $($DefaultRoute.NextHop)" |
            Out-File "$Path\Ping-Gateway.txt"
    }
}

# ===========================================================================
# HELPER - SET ADVANCED PROPERTY BY DISPLAY NAME
# ===========================================================================

function Set-AdvancedPropertyDisabled {

    param(
        [string]$Pattern,
        [string]$Category
    )

    try {

        $Properties = @(
            Get-NetAdapterAdvancedProperty `
                -Name $Nic.Name `
                -AllProperties `
                -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -match $Pattern
            }
        )

        if ($Properties.Count -eq 0) {
            Add-Result $Category $Pattern 'NOT SUPPORTED'
            return
        }

        foreach ($Property in $Properties) {

            $DisabledValue = $null

            if ($Property.ValidDisplayValues) {
                $DisabledValue = $Property.ValidDisplayValues |
                    Where-Object {
                        $_ -match '^(Disabled|Disable|Off)$'
                    } |
                    Select-Object -First 1
            }

            if (!$DisabledValue) {

                # Many drivers still accept the normal English value
                # despite not exposing ValidDisplayValues via CIM.

                foreach ($Candidate in @('Disabled','Off')) {

                    try {
                        Set-NetAdapterAdvancedProperty `
                            -Name $Nic.Name `
                            -DisplayName $Property.DisplayName `
                            -DisplayValue $Candidate `
                            -NoRestart `
                            -ErrorAction Stop

                        $DisabledValue = $Candidate
                        break
                    }
                    catch {}
                }
            }

            if ($DisabledValue) {

                $Current = Get-NetAdapterAdvancedProperty `
                    -Name $Nic.Name `
                    -DisplayName $Property.DisplayName `
                    -ErrorAction SilentlyContinue

                Add-Result `
                    $Category `
                    $Property.DisplayName `
                    'APPLIED' `
                    $Current.DisplayValue
            }
            else {
                Add-Result `
                    $Category `
                    $Property.DisplayName `
                    'SKIPPED' `
                    "Driver does not expose a recognised Disabled value"
            }
        }
    }
    catch {
        Add-Result `
            $Category `
            $Pattern `
            'FAILED' `
            $_.Exception.Message
    }
}

# ===========================================================================
# AUDIT ONLY
# ===========================================================================

if ($AuditOnly) {

    Save-NetworkAudit $Root

    Write-Host ""
    Write-Host "Network audit complete:"
    Write-Host $Root
    Write-Host ""

    return
}

# ===========================================================================
# BEGIN APPLY
# ===========================================================================

Start-Transcript `
    -Path "$Root\Gaming-Network-v1.0.log" `
    -Force

Write-Host "[1/10] Capturing existing configuration..."

Save-NetworkAudit "$Root\Before"

# ===========================================================================
# DNS
# ===========================================================================

Write-Host "[2/10] Configuring DNS..."

if ($SetCloudflareDNS) {

    try {

        # Cloudflare IPv4
        $DnsServers = @(
            '1.1.1.1'
            '1.0.0.1'
        )

        # Add IPv6 resolvers only when IPv6 is actually bound to this NIC.
        $IPv6Enabled = Get-NetAdapterBinding `
            -Name $Nic.Name `
            -ComponentID ms_tcpip6 `
            -ErrorAction SilentlyContinue

        if ($IPv6Enabled.Enabled) {

            $DnsServers += @(
                '2606:4700:4700::1111'
                '2606:4700:4700::1001'
            )
        }

        Set-DnsClientServerAddress `
            -InterfaceIndex $Nic.ifIndex `
            -ServerAddresses $DnsServers `
            -Validate `
            -ErrorAction Stop

        Add-Result `
            'DNS' `
            'Cloudflare DNS' `
            'APPLIED' `
            ($DnsServers -join ', ')
    }
    catch {
        Add-Result `
            'DNS' `
            'Cloudflare DNS' `
            'FAILED' `
            $_.Exception.Message
    }
}

# ===========================================================================
# NIC POWER MANAGEMENT
# ===========================================================================

Write-Host "[3/10] Disabling NIC power-saving features..."

if ($DisableNicPowerManagement) {

    try {

        Disable-NetAdapterPowerManagement `
            -Name $Nic.Name `
            -NoRestart `
            -ErrorAction Stop

        Add-Result `
            'NIC Power' `
            'Adapter power management' `
            'DISABLED'
    }
    catch {
        Add-Result `
            'NIC Power' `
            'Adapter power management' `
            'FAILED/UNSUPPORTED' `
            $_.Exception.Message
    }
}

# ===========================================================================
# ENERGY EFFICIENT / GREEN ETHERNET
# ===========================================================================

Write-Host "[4/10] Disabling Ethernet energy-saving features..."

if ($DisableEnergySaving) {

    Set-AdvancedPropertyDisabled `
        -Pattern 'Energy.*Efficient.*Ethernet|EEE' `
        -Category 'Low Latency'

    Set-AdvancedPropertyDisabled `
        -Pattern '^Green Ethernet$' `
        -Category 'Low Latency'

    Set-AdvancedPropertyDisabled `
        -Pattern '^Gigabit Lite$' `
        -Category 'Low Latency'

    Set-AdvancedPropertyDisabled `
        -Pattern '^Power Saving Mode$' `
        -Category 'Low Latency'

    Set-AdvancedPropertyDisabled `
        -Pattern 'Auto Disable Gigabit' `
        -Category 'Low Latency'
}

# ===========================================================================
# INTERRUPT MODERATION
# ===========================================================================

Write-Host "[5/10] Disabling Interrupt Moderation..."

if ($DisableInterruptModeration) {

    Set-AdvancedPropertyDisabled `
        -Pattern '^Interrupt Moderation$' `
        -Category 'Low Latency'

    # Some drivers expose separate moderation controls.
    Set-AdvancedPropertyDisabled `
        -Pattern '^Interrupt Moderation Rate$' `
        -Category 'Low Latency'
}

# ===========================================================================
# RECEIVE SIDE SCALING
# ===========================================================================

Write-Host "[6/10] Configuring RSS/RSC..."

if ($EnableRSS) {

    try {

        Enable-NetAdapterRss `
            -Name $Nic.Name `
            -NoRestart `
            -ErrorAction Stop

        $RSS = Get-NetAdapterRss -Name $Nic.Name

        Add-Result `
            'RSS' `
            'Receive Side Scaling' `
            'ENABLED' `
            "Enabled=$($RSS.Enabled)"
    }
    catch {
        Add-Result `
            'RSS' `
            'Receive Side Scaling' `
            'FAILED/UNSUPPORTED' `
            $_.Exception.Message
    }
}

if ($DisableRSC) {

    try {

        Disable-NetAdapterRsc `
            -Name $Nic.Name `
            -NoRestart `
            -ErrorAction Stop

        Add-Result `
            'RSC' `
            'Receive Segment Coalescing' `
            'DISABLED' `
            'Low-latency profile'
    }
    catch {
        Add-Result `
            'RSC' `
            'Receive Segment Coalescing' `
            'FAILED/UNSUPPORTED' `
            $_.Exception.Message
    }
}

# ===========================================================================
# JUMBO FRAMES
# ===========================================================================

Write-Host "[7/10] Checking Jumbo Frames..."

if ($DisableJumboFrames) {

    Set-AdvancedPropertyDisabled `
        -Pattern '^Jumbo (Packet|Frame|Frames)$' `
        -Category 'Ethernet'
}

# ===========================================================================
# SPEED & DUPLEX
# ===========================================================================

Write-Host "[8/10] Checking Speed & Duplex..."

if ($ForceAutoNegotiation) {

    try {

        $SpeedProperty = Get-NetAdapterAdvancedProperty `
            -Name $Nic.Name `
            -AllProperties `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -match '^Speed.*Duplex$'
            } |
            Select-Object -First 1

        if ($SpeedProperty) {

            $AutoValue = $null

            if ($SpeedProperty.ValidDisplayValues) {

                $AutoValue = $SpeedProperty.ValidDisplayValues |
                    Where-Object {
                        $_ -match 'Auto'
                    } |
                    Select-Object -First 1
            }

            if (!$AutoValue) {
                $AutoValue = 'Auto Negotiation'
            }

            try {

                Set-NetAdapterAdvancedProperty `
                    -Name $Nic.Name `
                    -DisplayName $SpeedProperty.DisplayName `
                    -DisplayValue $AutoValue `
                    -NoRestart `
                    -ErrorAction Stop

                Add-Result `
                    'Ethernet' `
                    'Speed & Duplex' `
                    'AUTO' `
                    $AutoValue
            }
            catch {
                Add-Result `
                    'Ethernet' `
                    'Speed & Duplex' `
                    'UNCHANGED' `
                    $SpeedProperty.DisplayValue
            }
        }
        else {
            Add-Result `
                'Ethernet' `
                'Speed & Duplex' `
                'NOT EXPOSED'
        }
    }
    catch {}
}

# ===========================================================================
# WINDOWS TCP STACK
# ===========================================================================

Write-Host "[9/10] Normalising Windows networking stack..."

# Restore the supported modern TCP auto-tuning configuration.
# Some old gaming scripts disable this, which can hurt throughput.

try {

    netsh interface tcp set global autotuninglevel=normal |
        Out-Null

    Add-Result `
        'TCP' `
        'Receive Window Auto-Tuning' `
        'NORMAL'
}
catch {
    Add-Result `
        'TCP' `
        'Receive Window Auto-Tuning' `
        'FAILED' `
        $_.Exception.Message
}

# Ensure IPv6 hasn't been disabled by previous "gaming" tweak scripts.
if ($KeepIPv6) {

    try {

        Enable-NetAdapterBinding `
            -Name $Nic.Name `
            -ComponentID ms_tcpip6 `
            -ErrorAction Stop

        Add-Result `
            'IP' `
            'IPv6' `
            'ENABLED'
    }
    catch {
        Add-Result `
            'IP' `
            'IPv6' `
            'UNCHANGED/VERIFY' `
            $_.Exception.Message
    }
}

# ===========================================================================
# IMPORTANT OFFLOADS - AUDIT, DO NOT DISABLE
# ===========================================================================

$OffloadProperties = Get-NetAdapterAdvancedProperty `
    -Name $Nic.Name `
    -AllProperties `
    -ErrorAction SilentlyContinue |
    Where-Object {
        $_.DisplayName -match `
        'Checksum|Large Send Offload|LSO'
    }

foreach ($Property in $OffloadProperties) {

    Add-Result `
        'Offload - retained' `
        $Property.DisplayName `
        'UNCHANGED' `
        $Property.DisplayValue
}

# ===========================================================================
# APPLY / RESTART NIC
# ===========================================================================

Write-Host "[10/10] Applying NIC configuration..."

# Flush stale DNS cache.
Clear-DnsClientCache

# Restart adapter once to commit driver-level settings.
try {

    Restart-NetAdapter `
        -Name $Nic.Name `
        -Confirm:$false `
        -ErrorAction Stop

    Add-Result `
        'NIC' `
        'Adapter restart' `
        'SUCCESS'
}
catch {
    Add-Result `
        'NIC' `
        'Adapter restart' `
        'FAILED' `
        $_.Exception.Message
}

Start-Sleep -Seconds 3

# ===========================================================================
# AFTER AUDIT
# ===========================================================================

Save-NetworkAudit "$Root\After"

$Results |
    Export-Csv `
        "$Root\Results.csv" `
        -NoTypeInformation

$Results |
    Format-Table `
        Category,
        Item,
        Status,
        Details `
        -AutoSize |
    Out-File "$Root\Results.txt"

Write-Host ""
Write-Host "============================================================"
Write-Host "Gaming network optimisation complete"
Write-Host "============================================================"
Write-Host ""
Write-Host "Adapter:"
Write-Host "  $($Nic.InterfaceDescription)"
Write-Host ""
Write-Host "Results:"
Write-Host "  $Root"
Write-Host ""
Write-Host "Configured:"
Write-Host "  Interrupt Moderation     : Disabled where supported"
Write-Host "  EEE / Green Ethernet     : Disabled where supported"
Write-Host "  NIC power management     : Disabled"
Write-Host "  RSS                      : Enabled"
Write-Host "  RSC                      : Disabled"
Write-Host "  Jumbo Frames             : Disabled where supported"
Write-Host "  Speed / Duplex           : Auto Negotiation"
Write-Host "  DNS                      : Cloudflare"
Write-Host "  TCP auto-tuning          : Normal"
Write-Host "  IPv6                     : Retained"
Write-Host "  Checksum offloads        : Retained"
Write-Host "  Large Send Offload       : Retained"
Write-Host "  Windows Firewall         : Retained"
Write-Host ""
Write-Host "Upload this folder to GitHub and send me the link."
Write-Host ""

Stop-Transcript
