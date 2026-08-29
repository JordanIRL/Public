#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Aggressive Windows 11 Enterprise gaming optimisation.

.DESCRIPTION
    Optimises a dedicated gaming PC while retaining Windows servicing,
    Microsoft Store, Xbox/Gaming Services, Defender real-time protection,
    anti-cheat compatibility, memory compression and the page file.

    Designed for:
    - Windows 11 Enterprise
    - Ryzen 7 3800X
    - NVIDIA RTX 5080
    - Dedicated gaming use

.NOTES
    Reboot required.

    Important:
    - Windows Update becomes manual.
    - Defender scheduled scans are disabled.
    - Defender real-time protection remains enabled.
    - VBS/HVCI is disabled only when no obvious Hyper-V/WSL/Sandbox
      dependencies are detected.
#>

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# OPTIONS
# ---------------------------------------------------------------------------

$RemoveBuiltInApps       = $true
$DisableSearchIndexing   = $true
$DisableVBSForGaming     = $true
$DisableDiagTrackService = $true

# Leave Store apps auto-updating by default because Gaming Services,
# Xbox components and some game dependencies use Store servicing.
$DisableStoreAutoUpdates = $false

# ---------------------------------------------------------------------------
# INITIALISATION
# ---------------------------------------------------------------------------

$TimeStamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupRoot = "$env:SystemDrive\GamingOptimizationBackup\$TimeStamp"

New-Item -Path $BackupRoot -ItemType Directory -Force | Out-Null

Start-Transcript -Path "$BackupRoot\GamingOptimization.log" -Force

Write-Host ""
Write-Host "Windows Gaming Optimisation"
Write-Host "Backup: $BackupRoot"
Write-Host ""

# Save useful pre-change information
Get-ComputerInfo |
    Select-Object WindowsProductName, WindowsVersion, OsBuildNumber, CsTotalPhysicalMemory |
    Out-File "$BackupRoot\System.txt"

Get-Service |
    Select-Object Name, DisplayName, Status, StartType |
    Export-Csv "$BackupRoot\Services.csv" -NoTypeInformation

Get-AppxPackage -AllUsers |
    Select-Object Name, PackageFullName |
    Export-Csv "$BackupRoot\AppxPackages.csv" -NoTypeInformation

Get-CimInstance Win32_StartupCommand |
    Select-Object Name, Command, Location, User |
    Export-Csv "$BackupRoot\StartupItems.csv" -NoTypeInformation

try {
    Get-MpPreference |
        Format-List * |
        Out-File "$BackupRoot\DefenderPreferences.txt"
}
catch {}

# Attempt restore point
try {
    Checkpoint-Computer `
        -Description "Before Gaming Optimisation $TimeStamp" `
        -RestorePointType MODIFY_SETTINGS
}
catch {
    Write-Warning "System Restore point could not be created. Registry/state backups continue."
}

function Set-Dword {
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [int]$Value
    )

    if (!(Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }

    New-ItemProperty `
        -Path $Path `
        -Name $Name `
        -PropertyType DWord `
        -Value $Value `
        -Force | Out-Null
}

# ---------------------------------------------------------------------------
# 1. WINDOWS UPDATE - MANUAL ONLY
# ---------------------------------------------------------------------------

Write-Host "[1/10] Configuring Windows Update..."

$WU   = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$WUAU = "$WU\AU"

if (!(Test-Path $WUAU)) {
    New-Item -Path $WUAU -Force | Out-Null
}

# Configure Automatic Updates = Disabled
#
# Windows can still be manually updated through:
# Settings > Windows Update > Check for updates
Set-Dword $WUAU 'NoAutoUpdate' 1

# Prevent Windows Update replacing NVIDIA/AMD/etc drivers.
Set-Dword $WU 'ExcludeWUDriversInQualityUpdate' 1

# Extra safeguard against automatic reboot while logged in.
Set-Dword $WUAU 'NoAutoRebootWithLoggedOnUsers' 1

# Do not automatically install "minor" updates.
Set-Dword $WUAU 'AutoInstallMinorUpdates' 0

# ---------------------------------------------------------------------------
# 2. DELIVERY OPTIMIZATION
# ---------------------------------------------------------------------------

Write-Host "[2/10] Configuring Delivery Optimization..."

$DO = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'

# HTTP only. No LAN/Internet peer-to-peer update traffic.
Set-Dword $DO 'DODownloadMode' 0

# Do NOT disable the Delivery Optimization service.
# Windows Store, WinGet, Game Pass and other components can use it.

# ---------------------------------------------------------------------------
# 3. MICROSOFT STORE UPDATES
# ---------------------------------------------------------------------------

Write-Host "[3/10] Configuring Store servicing..."

$StorePolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore'

if ($DisableStoreAutoUpdates) {

    # 2 = Turn off automatic download/install of Store app updates.
    Set-Dword $StorePolicy 'AutoDownload' 2

    Write-Warning "Automatic Microsoft Store updates disabled."
    Write-Warning "Manually update Gaming Services/Xbox/Store apps periodically."
}
else {
    # Remove our policy if previously created.
    Remove-ItemProperty `
        -Path $StorePolicy `
        -Name 'AutoDownload' `
        -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# 4. MICROSOFT DEFENDER
# ---------------------------------------------------------------------------

Write-Host "[4/10] Optimising Defender..."

try {
    # Absolutely no scheduled quick/full scan.
    Set-MpPreference -ScanScheduleDay Never

    # Do not run scans later because a scheduled scan was missed.
    Set-MpPreference -DisableCatchupQuickScan $true
    Set-MpPreference -DisableCatchupFullScan $true

    # Manual scans should run at low priority.
    Set-MpPreference -EnableLowCpuPriority $true

    # If you manually initiate a scan, ask Defender to keep CPU load modest.
    Set-MpPreference -ScanAvgCPULoadFactor 20

    Write-Host "    Scheduled Defender scans: disabled"
    Write-Host "    Defender real-time protection: retained"
    Write-Host "    Defender cloud/behaviour protection: retained"
    Write-Host "    Defender signature updates: retained"
}
catch {
    Write-Warning "Some Defender settings were not changed. Tamper Protection or policy may control them."
}

# Deliberately NOT doing:
#
# Set-MpPreference -DisableRealtimeMonitoring $true
# Set-MpPreference -DisableBehaviorMonitoring $true
# Defender folder/game exclusions
#
# These create substantially larger security gaps than performance benefits.

# ---------------------------------------------------------------------------
# 5. GAME MODE
# ---------------------------------------------------------------------------

Write-Host "[5/10] Configuring Windows gaming features..."

$GameBar = 'HKCU:\Software\Microsoft\GameBar'

Set-Dword $GameBar 'AutoGameModeEnabled' 1

# ---------------------------------------------------------------------------
# 6. DISABLE BACKGROUND GAME CAPTURE / DVR
# ---------------------------------------------------------------------------

$GameConfigStore = 'HKCU:\System\GameConfigStore'
$GameDVR         = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'

Set-Dword $GameConfigStore 'GameDVR_Enabled' 0
Set-Dword $GameDVR 'AppCaptureEnabled' 0

# Keep Xbox Game Bar installed.
# This only stops automatic/background capture functionality.

# ---------------------------------------------------------------------------
# 7. HAGS - HARDWARE ACCELERATED GPU SCHEDULING
# ---------------------------------------------------------------------------

$Graphics = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'

# 2 = HAGS enabled
Set-Dword $Graphics 'HwSchMode' 2

# Especially appropriate for the RTX 5080 / modern NVIDIA feature stack.

# ---------------------------------------------------------------------------
# 8. ENTERPRISE CONSUMER / TELEMETRY CLEANUP
# ---------------------------------------------------------------------------

Write-Host "[6/10] Disabling Windows consumer background features..."

$CloudContent = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'

# Enterprise-only supported consumer-experience control.
Set-Dword $CloudContent 'DisableWindowsConsumerFeatures' 1
Set-Dword $CloudContent 'DisableConsumerAccountStateContent' 1

# Widgets
$Widgets = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'
Set-Dword $Widgets 'AllowNewsAndInterests' 0

# Diagnostic data off - available on Enterprise.
$DataCollection = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
Set-Dword $DataCollection 'AllowTelemetry' 0
Set-Dword $DataCollection 'DoNotShowFeedbackNotifications' 1

# Disable activity feed/cloud activity publishing.
$SystemPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
Set-Dword $SystemPolicy 'EnableActivityFeed' 0
Set-Dword $SystemPolicy 'PublishUserActivities' 0
Set-Dword $SystemPolicy 'UploadUserActivities' 0

# ---------------------------------------------------------------------------
# EDGE BACKGROUND ACTIVITY
# ---------------------------------------------------------------------------

$EdgePolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'

# Do not preload Edge at login.
Set-Dword $EdgePolicy 'StartupBoostEnabled' 0

# Do not keep Edge running after the browser closes.
Set-Dword $EdgePolicy 'BackgroundModeEnabled' 0

# ---------------------------------------------------------------------------
# DIAGNOSTIC SERVICE
# ---------------------------------------------------------------------------

if ($DisableDiagTrackService) {

    Write-Host "[7/10] Disabling Connected User Experiences telemetry service..."

    $DiagTrack = Get-Service -Name 'DiagTrack' -ErrorAction SilentlyContinue

    if ($DiagTrack) {
        Stop-Service 'DiagTrack' -Force -ErrorAction SilentlyContinue
        Set-Service 'DiagTrack' -StartupType Disabled
    }
}

# ---------------------------------------------------------------------------
# 9. SEARCH INDEXER
# ---------------------------------------------------------------------------

if ($DisableSearchIndexing) {

    Write-Host "[8/10] Disabling Windows Search indexing..."

    $Search = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue

    if ($Search) {
        Stop-Service 'WSearch' -Force -ErrorAction SilentlyContinue
        Set-Service 'WSearch' -StartupType Disabled
    }

    Write-Warning "File-content/indexed search will be reduced."
    Write-Warning "This does not affect Steam/game operation."
}

# ---------------------------------------------------------------------------
# 10. REMOVE NON-GAMING INBOX APPS
# ---------------------------------------------------------------------------

if ($RemoveBuiltInApps) {

    Write-Host "[9/10] Removing unnecessary inbox applications..."

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

    foreach ($App in $RemoveApps) {

        Write-Host "    $App"

        Get-AppxPackage -AllUsers -Name $App -ErrorAction SilentlyContinue |
            ForEach-Object {
                Remove-AppxPackage `
                    -Package $_.PackageFullName `
                    -AllUsers `
                    -ErrorAction SilentlyContinue
            }

        Get-AppxProvisionedPackage -Online |
            Where-Object DisplayName -eq $App |
            ForEach-Object {
                Remove-AppxProvisionedPackage `
                    -Online `
                    -PackageName $_.PackageName `
                    -AllUsers `
                    -ErrorAction SilentlyContinue | Out-Null
            }
    }
}

# ---------------------------------------------------------------------------
# VBS / HVCI
# ---------------------------------------------------------------------------

Write-Host "[10/10] Evaluating virtualization-based security..."

if ($DisableVBSForGaming) {

    $VirtualizationFeatures = @(
        'Microsoft-Hyper-V-All'
        'VirtualMachinePlatform'
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
                Write-Warning "$Feature is enabled."
                $VirtualizationInUse = $true
            }
        }
        catch {}
    }

    if ($VirtualizationInUse) {
        Write-Warning "VBS/HVCI NOT disabled because virtualization features are installed."
    }
    else {

        Write-Host "    Disabling VBS/HVCI/Credential Guard..."

        $DGPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard'
        $DG       = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'
        $HVCI     = "$DG\Scenarios\HypervisorEnforcedCodeIntegrity"
        $LSA      = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'

        Set-Dword $DGPolicy 'EnableVirtualizationBasedSecurity' 0
        Set-Dword $DG 'EnableVirtualizationBasedSecurity' 0
        Set-Dword $HVCI 'Enabled' 0
        Set-Dword $LSA 'LsaCfgFlags' 0

        Write-Warning "VBS/HVCI provides meaningful security protection."
        Write-Warning "It has been disabled because this profile is gaming-focused."
    }
}

# ---------------------------------------------------------------------------
# THINGS INTENTIONALLY LEFT ALONE
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "Intentionally retained:"
Write-Host "  SysMain"
Write-Host "  Memory compression"
Write-Host "  System-managed page file"
Write-Host "  Windows Defender real-time protection"
Write-Host "  Defender behaviour monitoring"
Write-Host "  Defender cloud protection"
Write-Host "  Microsoft Store"
Write-Host "  Gaming Services"
Write-Host "  Xbox infrastructure"
Write-Host "  Windows Update service"
Write-Host "  BITS"
Write-Host "  Delivery Optimization service"
Write-Host "  Windows TRIM / drive optimisation"
Write-Host "  Secure Boot"
Write-Host ""

# ---------------------------------------------------------------------------
# POST-CHANGE REPORT
# ---------------------------------------------------------------------------

Write-Host "Current Defender configuration:"
try {
    Get-MpPreference |
        Select-Object `
            ScanScheduleDay,
            DisableCatchupQuickScan,
            DisableCatchupFullScan,
            EnableLowCpuPriority,
            ScanAvgCPULoadFactor |
        Format-List
}
catch {}

Write-Host "Update policy:"
Get-ItemProperty $WUAU -ErrorAction SilentlyContinue |
    Select-Object NoAutoUpdate, NoAutoRebootWithLoggedOnUsers |
    Format-List

Write-Host "HAGS:"
Get-ItemProperty $Graphics -ErrorAction SilentlyContinue |
    Select-Object HwSchMode |
    Format-List

Write-Host ""
Write-Host "Optimisation complete."
Write-Host "REBOOT WINDOWS before testing."
Write-Host ""
Write-Host "Before/after data is stored in:"
Write-Host $BackupRoot

Stop-Transcript
