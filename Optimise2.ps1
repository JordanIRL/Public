#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Windows 11 Enterprise Gaming Optimisation v1.1

.DESCRIPTION
    Aggressive but supportable optimisation for a dedicated gaming PC.

    Target system:
      - Windows 11 Enterprise 25H2
      - Ryzen 7 3800X
      - NVIDIA RTX 5080
      - 16 GB RAM
      - 4K gaming

    Main goals:
      - Windows Update is manual only.
      - Windows Update does not install drivers.
      - Defender scheduled/catch-up scans are disabled.
      - Defender real-time protection remains enabled.
      - Game Mode and HAGS are enabled.
      - Game DVR/background recording is disabled.
      - Telemetry/consumer features are reduced.
      - Search indexing is disabled.
      - Unnecessary startup applications are removed.
      - Unnecessary consumer AppX packages are removed.
      - Core Windows gaming, Store and servicing components are preserved.

.PARAMETER AuditOnly
    Makes no changes. Creates a current-state audit folder that can
    be uploaded for review.

.EXAMPLE
    .\Optimise-v1.1.ps1

.EXAMPLE
    .\Optimise-v1.1.ps1 -AuditOnly

.NOTES
    Reboot after applying.

    After reboot run:
        .\Optimise-v1.1.ps1 -AuditOnly

    Then upload the resulting audit folder for comparison.
#>

[CmdletBinding()]
param(
    [switch]$AuditOnly
)

$ErrorActionPreference = 'Continue'

# ===========================================================================
# CONFIGURATION
# ===========================================================================

# Core optimisations
$DisableSearchIndexing     = $true
$DisableDiagTrack          = $true
$RemoveConsumerApps        = $true
$CleanGamingStartup        = $true
$OptimiseLogitechUpdater   = $true

# These are safe to remove from a dedicated gaming PC and can be
# reinstalled from the Store later.
$RemoveTeams               = $true
$RemoveNewOutlook          = $true
$RemoveStickyNotes         = $true

# Leave Store auto-updates enabled.
# Gaming Services, Xbox components and Store-delivered dependencies
# benefit from remaining current.
$DisableStoreAutoUpdates   = $false

# IMPORTANT:
# Disabled by default for the 4K system.
#
# Benchmark VBS/HVCI on/off before deciding whether the security
# reduction provides a meaningful performance improvement.
$DisableVBSForGaming       = $false

# Leave false unless Windows Dynamic Lighting / Logitech RGB is unused.
$DisableLogitechLighting   = $false

# ===========================================================================
# INITIALISATION
# ===========================================================================

$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$BasePath  = "$env:SystemDrive\GamingOptimizationBackup"

if ($AuditOnly) {
    $Root = "$BasePath\$Timestamp-v1.1-AUDIT"
}
else {
    $Root = "$BasePath\$Timestamp-v1.1"
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

function Set-DwordSafe {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [int]$Value,

        [string]$Category = 'Registry'
    )

    try {
        if (!(Test-Path $Path)) {
            New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
        }

        New-ItemProperty `
            -Path $Path `
            -Name $Name `
            -PropertyType DWord `
            -Value $Value `
            -Force `
            -ErrorAction Stop | Out-Null

        $Actual = (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name

        if ($Actual -eq $Value) {
            Add-Result $Category "$Path\$Name" 'APPLIED' "$Value"
        }
        else {
            Add-Result $Category "$Path\$Name" 'FAILED' "Expected $Value; found $Actual"
        }
    }
    catch {
        Add-Result $Category "$Path\$Name" 'FAILED' $_.Exception.Message
    }
}

function Remove-RegistryValueSafe {
    param(
        [string]$Path,
        [string]$Name,
        [string]$Category = 'Startup'
    )

    try {
        if (!(Test-Path $Path)) {
            Add-Result $Category "$Path\$Name" 'NOT FOUND'
            return
        }

        $Existing = Get-ItemProperty `
            -Path $Path `
            -Name $Name `
            -ErrorAction SilentlyContinue

        if (!$Existing) {
            Add-Result $Category "$Path\$Name" 'NOT FOUND'
            return
        }

        Remove-ItemProperty `
            -Path $Path `
            -Name $Name `
            -Force `
            -ErrorAction Stop

        $StillExists = Get-ItemProperty `
            -Path $Path `
            -Name $Name `
            -ErrorAction SilentlyContinue

        if ($StillExists) {
            Add-Result $Category "$Path\$Name" 'FAILED'
        }
        else {
            Add-Result $Category "$Path\$Name" 'REMOVED'
        }
    }
    catch {
        Add-Result $Category "$Path\$Name" 'FAILED' $_.Exception.Message
    }
}

function Set-ServiceSafe {
    param(
        [string]$Name,
        [ValidateSet('Automatic','Manual','Disabled')]
        [string]$StartupType,
        [switch]$Stop
    )

    try {
        $Service = Get-Service -Name $Name -ErrorAction SilentlyContinue

        if (!$Service) {
            Add-Result 'Service' $Name 'NOT FOUND'
            return
        }

        if ($Stop) {
            Stop-Service $Name -Force -ErrorAction SilentlyContinue
        }

        Set-Service `
            -Name $Name `
            -StartupType $StartupType `
            -ErrorAction Stop

        $Service = Get-Service -Name $Name

        Add-Result `
            'Service' `
            $Name `
            'APPLIED' `
            "Startup=$($Service.StartType); Status=$($Service.Status)"
    }
    catch {
        Add-Result 'Service' $Name 'FAILED' $_.Exception.Message
    }
}

function Remove-AppxSafe {
    param(
        [string]$Name
    )

    $Found = $false
    $Errors = New-Object System.Collections.Generic.List[string]

    try {
        $Packages = @(
            Get-AppxPackage `
                -AllUsers `
                -Name $Name `
                -ErrorAction SilentlyContinue
        )

        if ($Packages.Count -gt 0) {
            $Found = $true
        }

        foreach ($Package in $Packages) {
            try {
                Remove-AppxPackage `
                    -Package $Package.PackageFullName `
                    -AllUsers `
                    -ErrorAction Stop
            }
            catch {
                $Errors.Add($_.Exception.Message)
            }
        }

        $Provisioned = @(
            Get-AppxProvisionedPackage -Online |
                Where-Object DisplayName -eq $Name
        )

        if ($Provisioned.Count -gt 0) {
            $Found = $true
        }

        foreach ($Package in $Provisioned) {
            try {
                Remove-AppxProvisionedPackage `
                    -Online `
                    -PackageName $Package.PackageName `
                    -AllUsers `
                    -ErrorAction Stop | Out-Null
            }
            catch {
                $Errors.Add($_.Exception.Message)
            }
        }

        $RemainingInstalled = @(
            Get-AppxPackage `
                -AllUsers `
                -Name $Name `
                -ErrorAction SilentlyContinue
        )

        $RemainingProvisioned = @(
            Get-AppxProvisionedPackage -Online |
                Where-Object DisplayName -eq $Name
        )

        if (!$Found) {
            Add-Result 'AppX' $Name 'NOT FOUND'
        }
        elseif (
            $RemainingInstalled.Count -eq 0 -and
            $RemainingProvisioned.Count -eq 0
        ) {
            Add-Result 'AppX' $Name 'REMOVED'
        }
        else {
            Add-Result `
                'AppX' `
                $Name `
                'PARTIAL/FAILED' `
                ($Errors -join ' | ')
        }
    }
    catch {
        Add-Result 'AppX' $Name 'FAILED' $_.Exception.Message
    }
}

function Export-RegistryBackup {
    param(
        [string]$Key,
        [string]$Filename
    )

    try {
        & reg.exe export `
            $Key `
            "$Root\$Filename" `
            /y 2>$null | Out-Null
    }
    catch {}
}

function Save-SystemAudit {
    param(
        [string]$Path
    )

    New-Item -Path $Path -ItemType Directory -Force | Out-Null

    # -----------------------------------------------------------------------
    # OS
    # -----------------------------------------------------------------------

    try {
        Get-ItemProperty `
            'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' |
            Select-Object `
                ProductName,
                DisplayVersion,
                CurrentBuild,
                UBR,
                EditionID,
                InstallationType |
            Format-List |
            Out-File "$Path\Windows.txt"
    }
    catch {}

    # -----------------------------------------------------------------------
    # CPU / RAM
    # -----------------------------------------------------------------------

    try {
        Get-CimInstance Win32_Processor |
            Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed |
            Format-List |
            Out-File "$Path\CPU.txt"
    }
    catch {}

    try {
        Get-CimInstance Win32_PhysicalMemory |
            Select-Object `
                Manufacturer,
                PartNumber,
                Capacity,
                Speed,
                ConfiguredClockSpeed |
            Format-Table -AutoSize |
            Out-File "$Path\Memory.txt"
    }
    catch {}

    # -----------------------------------------------------------------------
    # PAGE FILE / MEMORY COMPRESSION
    # -----------------------------------------------------------------------

    try {
        Get-CimInstance Win32_ComputerSystem |
            Select-Object AutomaticManagedPagefile |
            Format-List |
            Out-File "$Path\MemoryManagement.txt"

        Get-MMAgent |
            Select-Object `
                MemoryCompression,
                PageCombining,
                ApplicationPreLaunch |
            Format-List |
            Out-File "$Path\MemoryManagement.txt" -Append

        Get-CimInstance Win32_PageFileUsage |
            Format-List * |
            Out-File "$Path\MemoryManagement.txt" -Append
    }
    catch {}

    # -----------------------------------------------------------------------
    # GPU / DRIVER
    # -----------------------------------------------------------------------

    try {
        Get-CimInstance Win32_PnPSignedDriver |
            Where-Object DeviceClass -eq 'DISPLAY' |
            Select-Object `
                DeviceName,
                DriverVersion,
                DriverDate,
                Manufacturer |
            Format-List |
            Out-File "$Path\DisplayDrivers.txt"
    }
    catch {}

    try {
        $NvidiaSmi = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue

        if ($NvidiaSmi) {
            & $NvidiaSmi.Source -q |
                Out-File "$Path\NVIDIA-SMI.txt"
        }
    }
    catch {}

    # -----------------------------------------------------------------------
    # HAGS
    # -----------------------------------------------------------------------

    try {
        Get-ItemProperty `
            'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' `
            -Name HwSchMode `
            -ErrorAction SilentlyContinue |
            Select-Object HwSchMode |
            Format-List |
            Out-File "$Path\HAGS.txt"
    }
    catch {}

    # -----------------------------------------------------------------------
    # WINDOWS UPDATE
    # -----------------------------------------------------------------------

    try {
        Get-ItemProperty `
            'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' `
            -ErrorAction SilentlyContinue |
            Select-Object `
                NoAutoUpdate,
                AUOptions,
                NoAutoRebootWithLoggedOnUsers |
            Format-List |
            Out-File "$Path\WindowsUpdate.txt"

        Get-ItemProperty `
            'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' `
            -ErrorAction SilentlyContinue |
            Select-Object ExcludeWUDriversInQualityUpdate |
            Format-List |
            Out-File "$Path\WindowsUpdate.txt" -Append
    }
    catch {}

    # -----------------------------------------------------------------------
    # DEFENDER
    # -----------------------------------------------------------------------

    try {
        Get-MpPreference |
            Select-Object `
                ScanScheduleDay,
                DisableCatchupQuickScan,
                DisableCatchupFullScan,
                EnableLowCpuPriority,
                ScanAvgCPULoadFactor,
                DisableRealtimeMonitoring,
                DisableBehaviorMonitoring,
                DisableScriptScanning,
                DisableIOAVProtection,
                MAPSReporting,
                PUAProtection |
            Format-List |
            Out-File "$Path\Defender.txt"

        Get-MpComputerStatus |
            Select-Object `
                AntivirusEnabled,
                AntispywareEnabled,
                BehaviorMonitorEnabled,
                IoavProtectionEnabled,
                RealTimeProtectionEnabled,
                AntivirusSignatureLastUpdated |
            Format-List |
            Out-File "$Path\DefenderStatus.txt"
    }
    catch {}

    # -----------------------------------------------------------------------
    # VBS / DEVICE GUARD
    # -----------------------------------------------------------------------

    try {
        Get-CimInstance `
            -Namespace root\Microsoft\Windows\DeviceGuard `
            -ClassName Win32_DeviceGuard |
            Select-Object `
                VirtualizationBasedSecurityStatus,
                SecurityServicesConfigured,
                SecurityServicesRunning,
                AvailableSecurityProperties,
                RequiredSecurityProperties |
            Format-List |
            Out-File "$Path\DeviceGuard.txt"
    }
    catch {
        $_.Exception.Message |
            Out-File "$Path\DeviceGuard.txt"
    }

    # -----------------------------------------------------------------------
    # SERVICES
    # -----------------------------------------------------------------------

    try {
        Get-Service |
            Select-Object Name, DisplayName, Status, StartType |
            Sort-Object Name |
            Export-Csv `
                "$Path\Services.csv" `
                -NoTypeInformation
    }
    catch {}

    # -----------------------------------------------------------------------
    # STARTUP
    # -----------------------------------------------------------------------

    try {
        Get-CimInstance Win32_StartupCommand |
            Select-Object Name, Command, Location, User |
            Sort-Object Name |
            Export-Csv `
                "$Path\StartupItems.csv" `
                -NoTypeInformation
    }
    catch {}

    # -----------------------------------------------------------------------
    # APPX
    # -----------------------------------------------------------------------

    try {
        Get-AppxPackage -AllUsers |
            Select-Object Name, PackageFullName |
            Sort-Object Name |
            Export-Csv `
                "$Path\AppxPackages.csv" `
                -NoTypeInformation
    }
    catch {}

    # -----------------------------------------------------------------------
    # POWER PLAN
    # -----------------------------------------------------------------------

    try {
        powercfg /GETACTIVESCHEME |
            Out-File "$Path\PowerPlan.txt"
    }
    catch {}
}

# ===========================================================================
# AUDIT-ONLY MODE
# ===========================================================================

if ($AuditOnly) {

    Write-Host ""
    Write-Host "Gaming optimisation audit"
    Write-Host "Output: $Root"
    Write-Host ""

    Save-SystemAudit $Root

    Write-Host "Audit complete."
    Write-Host $Root
    return
}

# ===========================================================================
# START APPLY MODE
# ===========================================================================

Start-Transcript `
    -Path "$Root\GamingOptimization-v1.1.log" `
    -Force

Write-Host ""
Write-Host "Windows Gaming Optimisation v1.1"
Write-Host "Backup: $Root"
Write-Host ""

# ===========================================================================
# PRE-CHANGE BACKUP
# ===========================================================================

Write-Host "[1/12] Capturing pre-change state..."

Save-SystemAudit "$Root\Before"

Export-RegistryBackup `
    'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' `
    'WindowsUpdate.reg'

Export-RegistryBackup `
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Run' `
    'HKCU-Run.reg'

Export-RegistryBackup `
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' `
    'HKLM-Run.reg'

Export-RegistryBackup `
    'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard' `
    'DeviceGuard.reg'

try {
    Get-MpPreference |
        Format-List * |
        Out-File "$Root\DefenderPreferences-Before.txt"
}
catch {}

try {
    Checkpoint-Computer `
        -Description "Before Gaming Optimisation v1.1 $Timestamp" `
        -RestorePointType MODIFY_SETTINGS `
        -ErrorAction Stop

    Add-Result 'Backup' 'System Restore Point' 'CREATED'
}
catch {
    Add-Result `
        'Backup' `
        'System Restore Point' `
        'SKIPPED' `
        $_.Exception.Message
}

# ===========================================================================
# WINDOWS UPDATE
# ===========================================================================

Write-Host "[2/12] Configuring Windows Update..."

$WU   = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$WUAU = "$WU\AU"

# Disable Automatic Updates.
# Manual Settings > Windows Update > Check for updates remains available.
Set-DwordSafe `
    $WUAU `
    'NoAutoUpdate' `
    1 `
    'Windows Update'

# Remove AUOptions so it cannot conflict with NoAutoUpdate.
Remove-ItemProperty `
    -Path $WUAU `
    -Name AUOptions `
    -ErrorAction SilentlyContinue

# Prevent Windows Update delivering NVIDIA / AMD driver replacements.
Set-DwordSafe `
    $WU `
    'ExcludeWUDriversInQualityUpdate' `
    1 `
    'Windows Update'

Set-DwordSafe `
    $WUAU `
    'NoAutoRebootWithLoggedOnUsers' `
    1 `
    'Windows Update'

# ===========================================================================
# DELIVERY OPTIMIZATION
# ===========================================================================

Write-Host "[3/12] Configuring Delivery Optimization..."

$DO = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'

# HTTP only - no LAN/Internet peer-to-peer update distribution.
Set-DwordSafe `
    $DO `
    'DODownloadMode' `
    0 `
    'Delivery Optimization'

# Keep DoSvc itself intact for Store / Gaming Services / WinGet.

# ===========================================================================
# STORE SERVICING
# ===========================================================================

$StorePolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore'

if ($DisableStoreAutoUpdates) {

    Set-DwordSafe `
        $StorePolicy `
        'AutoDownload' `
        2 `
        'Microsoft Store'
}
else {
    Remove-ItemProperty `
        -Path $StorePolicy `
        -Name AutoDownload `
        -ErrorAction SilentlyContinue

    Add-Result `
        'Microsoft Store' `
        'Automatic Store updates' `
        'RETAINED' `
        'Required/recommended for Gaming Services and Store dependencies'
}

# ===========================================================================
# DEFENDER
# ===========================================================================

Write-Host "[4/12] Optimising Defender..."

try {

    # 8 = Never.
    Set-MpPreference -ScanScheduleDay 8

    # Never run a scan later because a scheduled scan was missed.
    Set-MpPreference -DisableCatchupQuickScan $true
    Set-MpPreference -DisableCatchupFullScan  $true

    # Keep any manually initiated scanning relatively unobtrusive.
    Set-MpPreference -EnableLowCpuPriority $true
    Set-MpPreference -ScanAvgCPULoadFactor 20

    # If Defender ever performs an idle scan, respect CPU throttling.
    Set-MpPreference -DisableCpuThrottleOnIdleScans $false

    $Defender = Get-MpPreference

    if (
        $Defender.ScanScheduleDay -eq 8 -and
        $Defender.DisableCatchupQuickScan -eq $true -and
        $Defender.DisableCatchupFullScan -eq $true
    ) {
        Add-Result `
            'Defender' `
            'Scheduled scans' `
            'DISABLED'
    }
    else {
        Add-Result `
            'Defender' `
            'Scheduled scans' `
            'VERIFY'
    }

    if ($Defender.DisableRealtimeMonitoring -eq $false) {
        Add-Result `
            'Defender' `
            'Real-time protection' `
            'RETAINED'
    }
}
catch {
    Add-Result `
        'Defender' `
        'Configuration' `
        'FAILED' `
        $_.Exception.Message
}

# Deliberately retain:
#   Real-time scanning
#   Behaviour monitoring
#   Script scanning
#   IOAV protection
#   Cloud protection
#   Signature updates
#
# No Steam/game-folder exclusions are created.

# ===========================================================================
# GAMING FEATURES
# ===========================================================================

Write-Host "[5/12] Configuring gaming features..."

$GameBar         = 'HKCU:\Software\Microsoft\GameBar'
$GameConfigStore = 'HKCU:\System\GameConfigStore'
$GameDVR         = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'
$GameDVRPolicy   = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'
$Graphics        = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'

# Game Mode ON
Set-DwordSafe `
    $GameBar `
    'AutoGameModeEnabled' `
    1 `
    'Gaming'

# Background recording / capture OFF
Set-DwordSafe `
    $GameConfigStore `
    'GameDVR_Enabled' `
    0 `
    'Gaming'

Set-DwordSafe `
    $GameDVR `
    'AppCaptureEnabled' `
    0 `
    'Gaming'

Set-DwordSafe `
    $GameDVRPolicy `
    'AllowGameDVR' `
    0 `
    'Gaming'

# HAGS ON
Set-DwordSafe `
    $Graphics `
    'HwSchMode' `
    2 `
    'Gaming'

# ===========================================================================
# WIDGETS / CONSUMER FEATURES
# ===========================================================================

Write-Host "[6/12] Removing consumer/background features..."

# Do NOT touch HKLM:\SOFTWARE\Policies\Microsoft\Dsh.
# That protected key caused the v1 failure.

# Hide Widgets using the current-user Windows taskbar setting.
$ExplorerAdvanced = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

Set-DwordSafe `
    $ExplorerAdvanced `
    'TaskbarDa' `
    0 `
    'Widgets'

# Enterprise consumer-experience controls.
$CloudContent = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'

Set-DwordSafe `
    $CloudContent `
    'DisableWindowsConsumerFeatures' `
    1 `
    'Consumer Features'

Set-DwordSafe `
    $CloudContent `
    'DisableConsumerAccountStateContent' `
    1 `
    'Consumer Features'

Set-DwordSafe `
    $CloudContent `
    'DisableTailoredExperiencesWithDiagnosticData' `
    1 `
    'Consumer Features'

# ===========================================================================
# TELEMETRY / ACTIVITY
# ===========================================================================

$DataCollection = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'

# Enterprise supports diagnostic data = 0.
Set-DwordSafe `
    $DataCollection `
    'AllowTelemetry' `
    0 `
    'Telemetry'

Set-DwordSafe `
    $DataCollection `
    'DoNotShowFeedbackNotifications' `
    1 `
    'Telemetry'

$SystemPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'

Set-DwordSafe `
    $SystemPolicy `
    'EnableActivityFeed' `
    0 `
    'Activity History'

Set-DwordSafe `
    $SystemPolicy `
    'PublishUserActivities' `
    0 `
    'Activity History'

Set-DwordSafe `
    $SystemPolicy `
    'UploadUserActivities' `
    0 `
    'Activity History'

# Advertising ID
$Advertising = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo'

Set-DwordSafe `
    $Advertising `
    'DisabledByGroupPolicy' `
    1 `
    'Privacy'

# ===========================================================================
# EDGE BACKGROUND EXECUTION
# ===========================================================================

$EdgePolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'

Set-DwordSafe `
    $EdgePolicy `
    'StartupBoostEnabled' `
    0 `
    'Edge'

Set-DwordSafe `
    $EdgePolicy `
    'BackgroundModeEnabled' `
    0 `
    'Edge'

# ===========================================================================
# TELEMETRY SERVICE
# ===========================================================================

Write-Host "[7/12] Configuring background services..."

if ($DisableDiagTrack) {
    Set-ServiceSafe `
        -Name 'DiagTrack' `
        -StartupType Disabled `
        -Stop
}

# ===========================================================================
# WINDOWS SEARCH INDEXING
# ===========================================================================

if ($DisableSearchIndexing) {
    Set-ServiceSafe `
        -Name 'WSearch' `
        -StartupType Disabled `
        -Stop
}

# ===========================================================================
# STARTUP CLEANUP
# ===========================================================================

Write-Host "[8/12] Cleaning startup applications..."

if ($CleanGamingStartup) {

    # Steam intentionally remains enabled.

    Remove-RegistryValueSafe `
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' `
        'EpicGamesLauncher'

    Remove-RegistryValueSafe `
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' `
        'EADM'

    Remove-RegistryValueSafe `
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' `
        'Logitech Download Assistant'

    Remove-RegistryValueSafe `
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run' `
        'Logitech Download Assistant'
}

# ===========================================================================
# LOGITECH
# ===========================================================================

Write-Host "[9/12] Optimising Logitech background components..."

if ($OptimiseLogitechUpdater) {

    # Options+ itself remains functional.
    # Its dedicated updater no longer runs continuously.
    Set-ServiceSafe `
        -Name 'OptionsPlusUpdaterService' `
        -StartupType Manual `
        -Stop
}

if ($DisableLogitechLighting) {

    Set-ServiceSafe `
        -Name 'logi_lamparray_service' `
        -StartupType Disabled `
        -Stop
}

# ===========================================================================
# CONSUMER APP REMOVAL
# ===========================================================================

Write-Host "[10/12] Removing unnecessary AppX packages..."

if ($RemoveConsumerApps) {

    $RemoveApps = @(
        'Clipchamp.Clipchamp'
        'Microsoft.BingNews'
        'Microsoft.BingWeather'
        'Microsoft.GetHelp'
        'Microsoft.Getstarted'
        'Microsoft.MicrosoftOfficeHub'
        'Microsoft.MicrosoftSolitaireCollection'
        'Microsoft.People'
        'Microsoft.PowerAutomateDesktop'
        'Microsoft.WindowsFeedbackHub'
        'Microsoft.WindowsMaps'
        'Microsoft.YourPhone'
        'MicrosoftCorporationII.QuickAssist'
        'Microsoft.Windows.DevHome'
    )

    if ($RemoveTeams) {
        $RemoveApps += 'MSTeams'
    }

    if ($RemoveNewOutlook) {
        $RemoveApps += 'Microsoft.OutlookForWindows'
    }

    if ($RemoveStickyNotes) {
        $RemoveApps += 'Microsoft.MicrosoftStickyNotes'
    }

    foreach ($App in ($RemoveApps | Sort-Object -Unique)) {
        Write-Host "    $App"
        Remove-AppxSafe $App
    }
}

# ===========================================================================
# VBS / HVCI / CREDENTIAL GUARD - OPTIONAL
# ===========================================================================

Write-Host "[11/12] Evaluating virtualization-based security..."

if ($DisableVBSForGaming) {

    $VirtualizationFeatures = @(
        'Microsoft-Hyper-V-All'
        'VirtualMachinePlatform'
        'HypervisorPlatform'
        'Microsoft-Windows-Subsystem-Linux'
        'Containers-DisposableClientVM'
    )

    $VirtualizationInUse = $false

    foreach ($Feature in $VirtualizationFeatures) {

        try {
            $State = Get-WindowsOptionalFeature `
                -Online `
                -FeatureName $Feature `
                -ErrorAction Stop

            if ($State.State -eq 'Enabled') {
                Add-Result `
                    'VBS' `
                    $Feature `
                    'ENABLED'

                $VirtualizationInUse = $true
            }
        }
        catch {}
    }

    if ($VirtualizationInUse) {

        Add-Result `
            'VBS' `
            'VBS/HVCI disable' `
            'SKIPPED' `
            'Hyper-V/WSL/virtualization functionality detected'
    }
    else {

        $DGPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'
        $DG       = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
        $HVCI     = "$DG\Scenarios\HypervisorEnforcedCodeIntegrity"
        $LSA      = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'

        Set-DwordSafe `
            $DGPolicy `
            'EnableVirtualizationBasedSecurity' `
            0 `
            'VBS'

        Set-DwordSafe `
            $DG `
            'EnableVirtualizationBasedSecurity' `
            0 `
            'VBS'

        Set-DwordSafe `
            $HVCI `
            'Enabled' `
            0 `
            'VBS'

        Set-DwordSafe `
            $LSA `
            'LsaCfgFlags' `
            0 `
            'Credential Guard'

        try {
            bcdedit /set hypervisorlaunchtype off | Out-Null

            Add-Result `
                'VBS' `
                'Hypervisor launch' `
                'DISABLED'
        }
        catch {
            Add-Result `
                'VBS' `
                'Hypervisor launch' `
                'FAILED' `
                $_.Exception.Message
        }
    }
}
else {
    Add-Result `
        'VBS' `
        'VBS/HVCI' `
        'UNCHANGED' `
        'Benchmark first; default for 4K gaming profile'
}

# ===========================================================================
# INTENTIONALLY RETAINED
# ===========================================================================

$Retained = @(
    'SysMain'
    'Memory compression'
    'System-managed page file'
    'Defender real-time protection'
    'Defender behaviour monitoring'
    'Defender cloud protection'
    'Defender intelligence updates'
    'Windows Update service'
    'BITS'
    'Delivery Optimization service'
    'Microsoft Store'
    'Gaming Services'
    'Xbox identity infrastructure'
    'Windows Installer'
    'Windows servicing stack'
    'Secure Boot'
    'TPM'
    'Audio services'
    'Realtek audio services'
    'NVIDIA services'
    'Steam Client Service'
)

foreach ($Item in $Retained) {
    Add-Result `
        'Retained' `
        $Item `
        'UNCHANGED'
}

# ===========================================================================
# IMMEDIATE POST-CHANGE AUDIT
# ===========================================================================

Write-Host "[12/12] Verifying applied configuration..."

Save-SystemAudit "$Root\After-Immediate"

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
Write-Host "Gaming optimisation v1.1 complete"
Write-Host "============================================================"
Write-Host ""
Write-Host "Backup and results:"
Write-Host "  $Root"
Write-Host ""
Write-Host "REBOOT WINDOWS."
Write-Host ""
Write-Host "After reboot run:"
Write-Host ""
Write-Host "  .\Optimise-v1.1.ps1 -AuditOnly"
Write-Host ""
Write-Host "Upload that AUDIT folder for final verification."
Write-Host ""

Write-Host "Important:"
Write-Host "  Windows Update: manual"
Write-Host "  Windows Update drivers: disabled"
Write-Host "  Defender scheduled scans: disabled"
Write-Host "  Defender real-time protection: retained"
Write-Host "  Store updates: retained"
Write-Host "  VBS/HVCI: unchanged by default"
Write-Host ""

Stop-Transcript
