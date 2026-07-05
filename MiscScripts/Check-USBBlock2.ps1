<#
.SYNOPSIS
    Read-only diagnostic for "USB Access Denied" on an Intune/Defender-managed Windows device.

.DESCRIPTION
    Inspects EVERY common enforcement layer that can block USB / removable storage and reports
    which one is responsible. Read-only by default. Run in an elevated PowerShell on the target PC.

    Layers covered:
      0.  Management context  : dsregcmd join state, Intune enrollment, GPO-vs-Intune precedence, last sync
      1.  Kernel/driver layer : USBSTOR, UASPStor, hub/composite (usbhub3/usbccgp), class Upper/LowerFilters
      2.  Write-deny layers    : BitLocker FVE (+CSP mirror, RDVConfigureBDE), StorageDevicePolicies\WriteProtect
      3.  Removable Storage Access (ADMX) : Deny_All / per-class / Custom, HKLM *and* per-user hives
      4.  Intune CSP           : Storage/RemovableDiskDenyWriteAccess, System/AllowStorageCard
      5.  Device Installation Restrictions : deny lists, allow-list gating, "Prevent removable devices"
      6.  Microsoft Defender Device Control : Get-MpComputerStatus default-deny (+ corrected reg path)
      7.  ASR USB rule / Controlled Folder Access / third-party DLP / WDAC+AppLocker
      8.  Physical drive state : present/letter/RAW/offline, disk + VOLUME read-only, NTFS ACL, write probe
      9.  BitLocker lock state + BitLocker management event log
      10. Corrected Defender event log (ASR/CFA real IDs) + Device Control hunting query
      11. Optional -Path checks : per-file read-only/EFS, redirected/SMB path

.PARAMETER TestWrite
    Performs a real write+delete probe on each mounted removable volume (otherwise everything is read-only).

.PARAMETER Path
    A specific file/path the user reports failing. Enables per-file (read-only/EFS) and SMB-path checks.

.NOTES
    Run as: powershell -ExecutionPolicy Bypass -File .\Check-USBBlock.ps1 [-TestWrite] [-Path 'E:\file']
#>

[CmdletBinding()]
param(
    [switch]$TestWrite,
    [string]$Path
)

$ErrorActionPreference = 'SilentlyContinue'
$findings = New-Object System.Collections.Generic.List[object]

function Add-Finding {
    param(
        [string]$Layer,
        [ValidateSet('OK','BLOCK','INFO','WARN')] [string]$Status,
        [string]$Detail
    )
    $findings.Add([pscustomobject]@{ Layer = $Layer; Status = $Status; Detail = $Detail })
}
function Get-RegValue {
    param([string]$RegPath, [string]$Name)
    try { (Get-ItemProperty -Path $RegPath -Name $Name -ErrorAction Stop).$Name } catch { $null }
}
function Write-Header($t) {
    Write-Host ""
    Write-Host ("=" * 74) -ForegroundColor DarkGray
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host ("=" * 74) -ForegroundColor DarkGray
}

# ============================================================================
Write-Header "0. Context - who manages this device, and will local edits revert?"
# ============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host ("Elevated (admin)      : {0}" -f $isAdmin)
Write-Host ("Computer / User       : {0} \ {1}" -f $env:COMPUTERNAME, $env:USERNAME)
if (-not $isAdmin) { Add-Finding 'Context' 'WARN' 'Not elevated - Defender/BitLocker/event/minifilter checks will be incomplete. Re-run as admin.' }

# Join state via dsregcmd (authoritative) - also drives GPO-vs-Intune precedence reasoning
$mdm = $false
$domJoined = $false
$dsreg = (dsregcmd /status 2>$null) -join "`n"
if ($dsreg) {
    $aadJoined = $dsreg -match 'AzureAdJoined\s*:\s*YES'
    $domJoined = $dsreg -match 'DomainJoined\s*:\s*YES'
    $mdmUrl    = ([regex]::Match($dsreg,'MdmUrl\s*:\s*(\S+)')).Groups[1].Value
    $joinType  = if ($aadJoined -and $domJoined) {'Hybrid Entra joined (domain + Entra)'}
                 elseif ($aadJoined) {'Entra joined'}
                 elseif ($domJoined) {'Domain joined'}
                 else {'Workgroup / Entra registered'}
    Write-Host ("Join state            : {0}   MdmUrl={1}" -f $joinType, $mdmUrl)
    if ($mdmUrl -match 'manage.microsoft.com') { $mdm = $true }
    if ($domJoined) {
        Add-Finding 'Management' 'INFO' 'Device receives on-prem Group Policy. For Defender DEVICE CONTROL specifically, if BOTH GPO and Intune apply, ONLY the Group Policy setting takes effect (MS Device Control FAQ) - so a fix pushed via Intune can be silently overridden by GPO. Check local GPO too.'
    }
}
# Corroborate with the Enrollments hive (tightened: require EnrollmentState=1 + Intune URL)
Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue | ForEach-Object {
    $url   = Get-RegValue $_.PSPath 'DiscoveryServiceFullURL'
    $state = Get-RegValue $_.PSPath 'EnrollmentState'
    if ($state -eq 1 -and $url -match 'manage.microsoft.com') { $mdm = $true }
}
if ($mdm) {
    Write-Host "MDM authority         : Intune (manage.microsoft.com)" -ForegroundColor Yellow
    Add-Finding 'Management' 'INFO' 'Device is actively Intune-managed. Any local registry edit you make WILL be reverted on the next MDM sync (maintenance check-in ~every 8h, and on reboot/logon). Scope the exception in Intune, not the local registry.'
    $imeLog = 'C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\IntuneManagementExtension.log'
    if (Test-Path $imeLog) {
        Add-Finding 'Management' 'INFO' ("Intune Mgmt Extension last check-in (log mtime): {0}. Export applied policy with: mdmdiagnosticstool.exe -area DeviceProvisioning -zip C:\Users\Public\Documents\MDMDiag.zip" -f (Get-Item $imeLog).LastWriteTime)
    }
} else {
    Write-Host "MDM authority         : Intune not confirmed."
}

# ============================================================================
Write-Header "1. Kernel/driver layer  (USBSTOR is the value you set to 3)"
# ============================================================================
$usbstor = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR' 'Start'
switch ($usbstor) {
    3       { Write-Host "USBSTOR Start = 3  (enabled / manual) - correct/normal."; Add-Finding 'USBSTOR' 'OK' 'USBSTOR enabled (Start=3) - set correctly, and this is the normal default. NOTE: Defender Device Control enforces ABOVE this driver, so on a managed box this edit is unlikely to be the effective lever.' }
    4       { Write-Host "USBSTOR Start = 4  (DISABLED)" -ForegroundColor Red; Add-Finding 'USBSTOR' 'BLOCK' 'USBSTOR driver disabled (Start=4). Mass-storage class driver will not load.' }
    $null   { Write-Host "USBSTOR Start = <not found>"; Add-Finding 'USBSTOR' 'INFO' 'USBSTOR Start value not present.' }
    default { Write-Host "USBSTOR Start = $usbstor"; Add-Finding 'USBSTOR' 'INFO' "USBSTOR Start=$usbstor (0=boot,1=system,2=auto,3=manual,4=disabled)." }
}
# UASP (USB3 bulk-stream) drives bind to Uaspstor.sys, which registers under the SCSIAdapter class, NOT USBSTOR.
$uaspstor = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\UASPStor' 'Start'
if ($uaspstor -eq 4) { Write-Host "UASPStor Start = 4 (DISABLED)" -ForegroundColor Red; Add-Finding 'UASPStor' 'BLOCK' 'UASPStor (USB3 mass storage) disabled. A USB3 drive can be blocked even with USBSTOR enabled.' }
# Hub / composite stack: a USB3/composite storage device is enumerated BELOW USBSTOR by these.
foreach ($s in 'usbhub3','usbccgp','USBXHCI') {
    if ((Get-RegValue "HKLM:\SYSTEM\CurrentControlSet\Services\$s" 'Start') -eq 4) {
        Add-Finding 'USB-Stack' 'INFO' "$s Start=4 (disabled). USB3/composite storage is enumerated/split below USBSTOR by this driver - if disabled, such a drive is blocked even though USBSTOR=3. Rare as a deliberate block."
    }
}

# ----------------------------------------------------------------------------
Write-Header "1b. Class filter drivers (Upper/LowerFilters) - common DLP/encryption hook"
# ----------------------------------------------------------------------------
$classDefaults = @{
    '{4d36e967-e325-11ce-bfc1-08002be10318}' = @{ Name='DiskDrive';   Lower=@('partmgr') }
    '{71a27cdd-812a-11d0-bec7-08002be2092f}' = @{ Name='Volume';      Upper=@('volsnap') }
    '{4d36e97b-e325-11ce-bfc1-08002be10318}' = @{ Name='SCSIAdapter'; }   # UASPStor lives here
}
foreach ($g in $classDefaults.Keys) {
    $p  = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$g"
    $cn = $classDefaults[$g].Name
    foreach ($f in 'UpperFilters','LowerFilters') {
        $vals = @(Get-RegValue $p $f)
        if (-not $vals) { continue }
        $expected   = @($classDefaults[$g].($f -replace 'Filters',''))
        $unexpected = $vals | Where-Object { $_ -and ($expected -notcontains $_) }
        if ($unexpected) {
            Write-Host ("{0} class {1}: {2}  (NON-DEFAULT)" -f $cn, $f, ($vals -join ',')) -ForegroundColor Yellow
            Add-Finding 'ClassFilter' 'WARN' "$cn setup class has non-default $f service(s): $($unexpected -join ', '). A DLP/encryption class-filter driver here can fail or convert-to-read-only every write IRP (Access Denied) while the drive still mounts. Investigate that service under HKLM\...\Services."
        }
    }
}

# ============================================================================
Write-Header "2. Write-deny layers  (BitLocker FVE is the value you set to 0)"
# ============================================================================
$fve = 'HKLM:\SOFTWARE\Policies\Microsoft\FVE'
$rdvDeny = Get-RegValue $fve 'RDVDenyWriteAccess'
switch ($rdvDeny) {
    1       { Write-Host "FVE RDVDenyWriteAccess = 1 (write DENIED unless BitLocker-encrypted)" -ForegroundColor Red
              Add-Finding 'BitLocker-FVE' 'BLOCK' 'RDVDenyWriteAccess=1 -> writes blocked on non-BitLocker drives. Drive mounts read-only; writes return Access Denied. Classic symptom.' }
    0       { Write-Host "FVE RDVDenyWriteAccess = 0 (write allowed) - set correctly." ; Add-Finding 'BitLocker-FVE' 'OK' 'RDVDenyWriteAccess=0 set correctly (but if Intune owns it, the CSP mirror below may re-assert 1).' }
    $null   { Write-Host "FVE RDVDenyWriteAccess = <not found>"; Add-Finding 'BitLocker-FVE' 'INFO' 'No local RDVDenyWriteAccess value - this layer not blocking here (or enforced via CSP/Device Control).' }
    default { Write-Host "FVE RDVDenyWriteAccess = $rdvDeny" }
}
if ((Get-RegValue $fve 'RDVDenyCrossOrg') -eq 1) { Add-Finding 'BitLocker-FVE' 'WARN' 'RDVDenyCrossOrg=1: write denied to drives encrypted by a different org.' }
$rdvCfg = Get-RegValue $fve 'RDVConfigureBDE'
if ($null -ne $rdvCfg) { Add-Finding 'BitLocker-FVE' 'INFO' "RDVConfigureBDE=$rdvCfg ('Control use of BitLocker on removable drives'). If RDVDenyWriteAccess=1 forces read-only, the only user remedy is to encrypt the drive - and this/RDVAllowBDE can forbid that (error 0x80310078)." }
# CSP mirror is authoritative on Intune; FVE can be stale until the 'BitLocker MDM policy Refresh' task runs.
$pmBL = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\BitLocker'
if (Test-Path $pmBL) { Add-Finding 'BitLocker-FVE' 'INFO' 'BitLocker policy is Intune-owned (PolicyManager\...\BitLocker). FVE values are replicated from here - if FVE looks stale, this CSP node is the real source. Do not fix locally.' }
# Classic storage-stack write-protect (reverts on reboot if GPO-pushed)
$wp = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\StorageDevicePolicies' 'WriteProtect'
if ($wp -eq 1) { Write-Host "StorageDevicePolicies\WriteProtect = 1 (ALL removable storage write-protected)" -ForegroundColor Red
    Add-Finding 'WriteProtect' 'BLOCK' 'StorageDevicePolicies\WriteProtect=1 write-protects all removable storage at the storage-stack layer (Access Denied on write, reads still work). One of several write-protect mechanisms - also check Section 3 Deny_Write and a physical switch.' }

# ============================================================================
Write-Header "3. Removable Storage Access (ADMX)  - HKLM + per-user, Deny_All / per-class / Custom"
# ============================================================================
$rsdRel = 'SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices'
$rsd     = "HKLM:\$rsdRel"
# Build the full list of policy roots: machine + current user + every loaded user hive
$userRoots = @('HKCU:\' + $rsdRel)
Get-ChildItem 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -match '^S-1-5-21' -and $_.PSChildName -notmatch '_Classes$' } |
    ForEach-Object { $userRoots += "Registry::HKEY_USERS\$($_.PSChildName)\$rsdRel" }
$allRsdRoots = @($rsd) + $userRoots

foreach ($root in $allRsdRoots) {
    if (-not (Test-Path $root)) { continue }
    $scope = if ($root -eq $rsd) { 'machine' } else { 'per-user' }
    if ((Get-RegValue $root 'Deny_All') -eq 1) {
        Write-Host ("Deny_All = 1  ({0}: {1})" -f $scope, $root) -ForegroundColor Red
        Add-Finding 'RemovableStorageAccess' 'BLOCK' "Deny_All=1 ($scope hive) -> ALL removable storage denied (read+write+execute). Key: $root"
    }
    # Per-class GUID subkeys
    Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
        $cls = $_.PSChildName
        foreach ($v in 'Deny_Read','Deny_Write','Deny_Execute') {
            if ((Get-RegValue $_.PSPath $v) -eq 1) {
                Write-Host ("Class {0} : {1} = 1  ({2})" -f $cls, $v, $scope) -ForegroundColor Red
                Add-Finding 'RemovableStorageAccess' 'BLOCK' "Class $cls $v=1 ($scope) - Removable Storage Access policy denying that access. Key: $root"
            }
        }
    }
    # Custom Classes deny lives ONE LEVEL DEEPER: ...\Custom\Deny_Read (value name = leaf key name)
    foreach ($leaf in 'Deny_Read','Deny_Write') {
        $ck = Join-Path $root "Custom\$leaf"
        if ((Get-RegValue $ck $leaf) -eq 1) {
            Add-Finding 'RemovableStorageAccess' 'BLOCK' "Custom Classes $leaf=1 ($scope, key $ck) - read/write denied for custom-defined device classes."
        }
    }
}
if (-not (Test-Path $rsd) -and -not ($userRoots | Where-Object { Test-Path $_ })) {
    Write-Host "No RemovableStorageDevices policy key present (machine or user)."
    Add-Finding 'RemovableStorageAccess' 'INFO' 'ADMX Removable Storage Access policy not present.'
}

# ============================================================================
Write-Header "4. Intune CSP  - Storage/RemovableDiskDenyWriteAccess + System/AllowStorageCard"
# ============================================================================
$rddwa = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Storage' 'RemovableDiskDenyWriteAccess'
if ($rddwa -eq 1) {
    Write-Host "Storage/RemovableDiskDenyWriteAccess = 1 (MDM) -> write DENIED" -ForegroundColor Red
    Add-Finding 'Storage-CSP' 'BLOCK' 'RemovableDiskDenyWriteAccess=1 pushed by Intune. Drive mounts but writes return Access Denied. Intune-owned - change it in Intune, not locally.'
} elseif ($null -ne $rddwa) { Add-Finding 'Storage-CSP' 'OK' "RemovableDiskDenyWriteAccess=$rddwa via MDM." }

$allowSC = Get-RegValue 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\System' 'AllowStorageCard'
if ($allowSC -eq 0) {
    Write-Host "System/AllowStorageCard = 0 (USB drives & SD cards DISABLED via Intune)" -ForegroundColor Red
    Add-Finding 'Storage-CSP' 'BLOCK' 'System/AllowStorageCard=0 (Intune device-restriction "Removable storage: Block"). Value 0 = SD card not allowed AND USB drives disabled - blocks the drive entirely at mount time. Fix in the Intune device-restrictions profile.'
} elseif ($null -ne $allowSC) { Add-Finding 'Storage-CSP' 'OK' "System/AllowStorageCard=$allowSC (1/absent = allowed)." }

# ============================================================================
Write-Header "5. Device Installation Restrictions  - deny lists + allow-list gating"
# ============================================================================
foreach ($di in @(
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions',
    'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\DeviceInstallation'
)) {
    if (-not (Test-Path $di)) { continue }
    $props = Get-ItemProperty $di -ErrorAction SilentlyContinue
    $hit = $false
    foreach ($n in 'DenyDeviceClasses','DenyDeviceClassesRetroactive','DenyDeviceIDs','DenyDeviceIDsRetroactive',
                   'DenyDeviceInstanceIDs','DenyInstanceIDsRetroactive','DenyInstallation','DeviceInstall_Removable_Deny',
                   'AllowDeviceClasses','AllowDeviceIDs','AllowInstanceIDs','AllowDenyLayered','PreventDeviceMetadataFromNetwork') {
        $val = $props.$n
        if ($null -ne $val -and $val -ne 0) {
            Write-Host ("{0} : {1} = {2}" -f $di, $n, $val) -ForegroundColor Yellow; $hit = $true
            if ($n -eq 'DeviceInstall_Removable_Deny' -and $val -eq 1) {
                Add-Finding 'DeviceInstallRestrictions' 'BLOCK' "'Prevent installation of removable devices' ENABLED (DeviceInstall_Removable_Deny=1). Blocks USB mass storage at install time (Device Manager Code 48/54). By default this beats any Allow list UNLESS AllowDenyLayered=1."
            }
        }
    }
    Get-ChildItem $di -ErrorAction SilentlyContinue | ForEach-Object {
        $k = Get-Item $_.PSPath
        $vals = $k.GetValueNames() | ForEach-Object { $k.GetValue($_) }
        if ($vals) { Write-Host ("  {0}\{1} -> {2}" -f $di, $_.PSChildName, ($vals -join '; ')) -ForegroundColor Yellow; $hit = $true }
    }
    if ($props.AllowDeviceClasses -or $props.AllowDeviceIDs -or $props.AllowInstanceIDs) {
        Add-Finding 'DeviceInstallRestrictions' 'WARN' "Device installation is gated by an ALLOW list. If THIS USB's class/hardware/instance ID is not on the allow list while a deny/removable-deny is active, it is blocked precisely because it is not allow-listed. AllowDenyLayered=$($props.AllowDenyLayered)."
    }
    if ($hit -and -not ($findings | Where-Object { $_.Layer -eq 'DeviceInstallRestrictions' -and $_.Status -eq 'BLOCK' })) {
        Add-Finding 'DeviceInstallRestrictions' 'WARN' "Device installation restrictions present at $di. If a USB mass-storage class/ID is denied the device shows in Device Manager with Code 48/54."
    }
}

# ============================================================================
Write-Header "6. Microsoft Defender Device Control  (most likely culprit on Intune)"
# ============================================================================
$mp = Get-MpComputerStatus -ErrorAction SilentlyContinue
if ($mp) {
    Write-Host ("DeviceControlState               : {0}" -f $mp.DeviceControlState)
    Write-Host ("DeviceControlDefaultEnforcement  : {0}" -f $mp.DeviceControlDefaultEnforcement)
    Write-Host ("DeviceControlPoliciesLastUpdated : {0}" -f $mp.DeviceControlPoliciesLastUpdated)
    if ($mp.DeviceControlState -match 'Enabled') {
        if ("$($mp.DeviceControlDefaultEnforcement)" -match 'Deny') {
            Write-Host ">> Device Control ENABLED with DEFAULT-DENY." -ForegroundColor Red
            Add-Finding 'Defender-DeviceControl' 'BLOCK' 'Defender Device Control ENABLED + DefaultDeny. Blocks the drive ABOVE the USBSTOR driver - your USBSTOR=3 edit has no effect against it. Fix: an additive per-device ALLOW entry (scoped by ComputerSid), NOT a local edit and NOT removing the fleet policy (default-deny can only be beaten by an explicit Allow).'
        } else {
            Add-Finding 'Defender-DeviceControl' 'WARN' 'Device Control enabled but not global default-deny; a specific Deny rule may still match removable media. Check the Intune ASR policy rules and Advanced Hunting (Section 10).'
        }
    } else { Add-Finding 'Defender-DeviceControl' 'OK' 'Defender Device Control not enabled.' }
} else {
    Add-Finding 'Defender-DeviceControl' 'WARN' 'Could not query Defender (need admin / Defender present). Re-run elevated - this is the most common Intune USB block.'
}
# Best-effort registry cross-check (CORRECT path; Get-MpComputerStatus remains authoritative).
foreach ($dp in @('HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Policy Manager',
                  'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender')) {
    if (-not (Test-Path $dp)) { continue }
    $dcD = Get-RegValue $dp 'DefaultEnforcement'
    if ($dcD -eq 2) { Add-Finding 'Defender-DeviceControl' 'BLOCK' "DefaultEnforcement=2 (Deny) found under $dp." }
}

# ============================================================================
Write-Header "7. ASR USB rule / Controlled Folder Access"
# ============================================================================
$pref = Get-MpPreference -ErrorAction SilentlyContinue
if ($pref) {
    $usbAsr = 'b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4'  # Block untrusted & unsigned processes from USB
    for ($i=0; $i -lt $pref.AttackSurfaceReductionRules_Ids.Count; $i++) {
        if ($pref.AttackSurfaceReductionRules_Ids[$i] -eq $usbAsr -and $pref.AttackSurfaceReductionRules_Actions[$i] -eq 1) {
            Add-Finding 'ASR-USB' 'INFO' 'ASR USB rule = Block. NOTE: blocks RUNNING programs from the USB only, NOT reading/copying files. Not your cause unless you launch an .exe from the drive.'
        }
    }
    $cfa = $pref.EnableControlledFolderAccess
    if ([int]$cfa -in 1,3) {
        $cfaName = switch ([int]$cfa) {1{'Enabled (Block)'}3{'Block disk-modification only'}}
        Add-Finding 'CFA' 'WARN' "Controlled Folder Access = $cfaName. Returns Access Denied when an untrusted process (e.g. one running FROM the USB) writes a protected folder, or when copying FROM USB INTO Documents/Desktop. Not a block on the USB volume itself, but a plausible 'USB access denied' report."
    }
}

# ----------------------------------------------------------------------------
Write-Header "7b. Third-party DLP / device-control agents (non-Microsoft enforcement)"
# ----------------------------------------------------------------------------
$dlpRegex = 'DLP|Device Control|Forcepoint|Websense|Symantec|Broadcom|McAfee|Trellix|CrowdStrike|Falcon|Zscaler|Digital Guardian|Sophos|Carbon Black|Cortex|Netskope'
Get-CimInstance Win32_Service -ErrorAction SilentlyContinue |
    Where-Object { $_.State -eq 'Running' -and ($_.DisplayName -match $dlpRegex -or $_.Name -match 'csagent|CSFalcon|mfehidk|EDPA|dgagent|ZSAService|wepsvc') } |
    ForEach-Object {
        Write-Host ("Possible DLP/agent service: {0} ({1})" -f $_.DisplayName, $_.Name) -ForegroundColor Yellow
        Add-Finding 'ThirdPartyDLP' 'WARN' "Running service '$($_.DisplayName)' ($($_.Name)) looks like a 3rd-party DLP/device-control agent. These enforce via their OWN kernel minifilter, invisible to every Microsoft registry check here. Verify whether IT's DLP is blocking USB."
    }
try {
    $flt = fltmc filters 2>$null
    if ($flt) {
        Write-Host 'Loaded minifilters (fltmc):' -ForegroundColor DarkGray
        $flt | Select-Object -Skip 1 | ForEach-Object { Write-Host "  $_" }
        Add-Finding 'ThirdPartyDLP' 'INFO' 'Review the fltmc list above: a NON-Microsoft storage/volume minifilter attached to the removable volume is the strongest signal of third-party USB blocking.'
    }
} catch {}

# ----------------------------------------------------------------------------
Write-Header "7c. WDAC (App Control) / AppLocker - EXECUTE-from-USB only (NOT data copy)"
# ----------------------------------------------------------------------------
Add-Finding 'AppControl' 'INFO' 'WDAC and AppLocker govern CODE EXECUTION (exe/dll/script/msi), NOT reading/copying data files. They cause "cannot RUN a program from the USB", never "copy a file off the USB = Access Denied".'
foreach ($probe in @(
    @{ Log='Microsoft-Windows-CodeIntegrity/Operational'; Ids=@(3077,3076); Name='WDAC' },
    @{ Log='Microsoft-Windows-AppLocker/EXE and DLL';      Ids=@(8004,8003); Name='AppLocker EXE/DLL' },
    @{ Log='Microsoft-Windows-AppLocker/MSI and Script';   Ids=@(8007,8006); Name='AppLocker MSI/Script' }
)) {
    try {
        Get-WinEvent -FilterHashtable @{ LogName=$probe.Log; Id=$probe.Ids } -MaxEvents 5 -ErrorAction Stop |
            ForEach-Object { Add-Finding 'AppControl' 'WARN' "$($probe.Name) event $($_.Id) - if the blocked path is on the removable drive, launching binaries from USB is blocked here (3077/8004/8007 = enforced block)." }
    } catch {}
}

# ============================================================================
Write-Header "8. Physical drive state - present / letter / RAW / read-only / ACL"
# ============================================================================
Get-Disk -ErrorAction SilentlyContinue | Where-Object BusType -eq 'USB' | ForEach-Object {
    Write-Host ("USB Disk #{0}: '{1}'  Health={2}  Operational={3}  ReadOnly={4}  Partition={5}" -f `
        $_.Number, $_.FriendlyName, $_.HealthStatus, $_.OperationalStatus, $_.IsReadOnly, $_.PartitionStyle)
    if ($_.IsReadOnly) { Add-Finding 'Disk' 'BLOCK' ("USB disk #{0} READ-ONLY at DISK level (diskpart 'attributes disk'). Writes fail Access Denied." -f $_.Number) }
    if ($_.OperationalStatus -match 'Offline') { Add-Finding 'Disk' 'BLOCK' ("USB disk #{0} OFFLINE. Online it in Disk Management or 'attributes disk clear readonly' + online." -f $_.Number) }
    if ($_.PartitionStyle -eq 'RAW') { Add-Finding 'Disk' 'WARN' ("USB disk #{0} is RAW/unformatted - mounts but unusable until formatted." -f $_.Number) }
}
# VOLUME-level read-only (a volume can be read-only while Get-Disk.IsReadOnly is False)
Get-Partition -ErrorAction SilentlyContinue |
    Where-Object { $_.DriveLetter -and (Get-Disk -Number $_.DiskNumber -ErrorAction SilentlyContinue).BusType -eq 'USB' } |
    ForEach-Object {
        if ($_.IsReadOnly) {
            Write-Host ("Partition {0}: READ-ONLY at volume level" -f $_.DriveLetter) -ForegroundColor Red
            Add-Finding 'Partition' 'BLOCK' ("Partition {0}: READ-ONLY at the VOLUME level (diskpart 'attributes volume'). Clear: diskpart > select volume {0} > attributes volume clear readonly. Also catches a hardware write-protect switch." -f $_.DriveLetter)
        }
    }
$usbVols = Get-Volume -ErrorAction SilentlyContinue | Where-Object DriveType -eq 'Removable'
if ($usbVols) {
    $usbVols | ForEach-Object { Write-Host ("Volume {0}: FS={1}  Size={2:N1}GB  Health={3}" -f $_.DriveLetter, $_.FileSystem, ($_.Size/1GB), $_.HealthStatus) }
} else {
    Write-Host "No removable volume mounted (blocked before mount, or not inserted)."
    Add-Finding 'Disk' 'INFO' 'No removable volume mounted. If the drive IS inserted, the block is happening before mount (driver / Device Control / Device Install Restriction / AllowStorageCard).'
}
# NTFS ACL / owner on the volume root
if ($usbVols) {
    foreach ($v in $usbVols) {
        if (-not $v.DriveLetter) { continue }
        $root = "$($v.DriveLetter):\"
        $acl  = Get-Acl -Path $root -ErrorAction SilentlyContinue
        if ($acl) {
            $denies = $acl.Access | Where-Object { $_.AccessControlType -eq 'Deny' -and $_.FileSystemRights -match 'Write|FullControl|Modify' }
            if ($denies) {
                Add-Finding 'NTFS-ACL' 'BLOCK' ("Volume root $root has explicit DENY ACE(s) for: {0}. NTFS-level Access Denied independent of policy. Remediate: takeown /f $root /r ; icacls $root /grant Users:(M)" -f (($denies | ForEach-Object { $_.IdentityReference }) -join ', '))
            } else {
                Write-Host ("ACL {0}: Owner={1}; no explicit write-deny ACE at root." -f $root, $acl.Owner)
            }
        }
    }
}
# Behavioral write probe (only with -TestWrite) - confirms whether a write ACTUALLY fails and at which layer
if ($TestWrite -and $usbVols) {
    foreach ($v in $usbVols) {
        if (-not $v.DriveLetter) { continue }
        $rootp = "$($v.DriveLetter):\"
        $probe = Join-Path $rootp ('.usbwritetest_{0}.tmp' -f [guid]::NewGuid())
        try {
            [IO.File]::WriteAllText($probe,'x')
            Add-Finding 'WriteProbe' 'OK' "Wrote+deleted a temp file on $rootp - writes SUCCEED at the FS layer. The reported Access Denied is path/file-specific or intermittent."
        } catch [System.UnauthorizedAccessException] {
            Add-Finding 'WriteProbe' 'BLOCK' "WRITE DENIED on $rootp (UnauthorizedAccessException). Confirms an enforced read-only/ACL block at the volume root - correlate with a BLOCK layer above."
        } catch [System.IO.IOException] {
            Add-Finding 'WriteProbe' 'WARN' "$rootp write failed with IOException ($($_.Exception.Message)) - locked/dirty volume or no space, not a permissions block."
        } catch {
            Add-Finding 'WriteProbe' 'WARN' "$rootp write failed: $($_.Exception.GetType().Name) - $($_.Exception.Message)"
        } finally {
            if (Test-Path $probe) { Remove-Item $probe -Force -ErrorAction SilentlyContinue }
        }
    }
} elseif (-not $TestWrite) {
    Write-Host "(re-run with -TestWrite to confirm whether a write actually fails)" -ForegroundColor DarkGray
}
# PnP problem state (policy-blocked device = Code 48/54)
Get-PnpDevice -Class 'DiskDrive','USB' -ErrorAction SilentlyContinue |
    Where-Object { $_.Status -ne 'OK' -and $_.FriendlyName } |
    ForEach-Object { Add-Finding 'PnP' 'WARN' ("Device '{0}' status={1}. A policy-blocked device shows here (problem code 48/54)." -f $_.FriendlyName, $_.Status) }

# ============================================================================
Write-Header "9. BitLocker lock state on the removable drive itself"
# ============================================================================
Get-BitLockerVolume -ErrorAction SilentlyContinue | Where-Object { $_.VolumeType -eq 'Data' } | ForEach-Object {
    Write-Host ("BL Vol {0}: Protection={1}  LockStatus={2}" -f $_.MountPoint, $_.ProtectionStatus, $_.LockStatus)
    if ($_.LockStatus -eq 'Locked') { Add-Finding 'BitLocker-Drive' 'BLOCK' ("Drive {0} is BitLocker-LOCKED. Unlock with the password/recovery key before use." -f $_.MountPoint) }
}
try {
    Get-WinEvent -LogName 'Microsoft-Windows-BitLocker/BitLocker Management' -MaxEvents 20 -ErrorAction Stop |
        Where-Object { $_.LevelDisplayName -in 'Error','Warning' -or $_.Message -match 'Silent Encryption|conflicting Group Policy|write access to drives not protected' } |
        ForEach-Object { Add-Finding 'EventLog' 'WARN' "BitLocker Management event $($_.Id): $(($_.Message -split "`n")[0]). Links RDVDenyWriteAccess to a real force-encryption / GP-conflict failure." }
} catch {}

# ============================================================================
Write-Header "10. Defender event log (CORRECT IDs) + Device Control hunting query"
# ============================================================================
# CFA: 1123 block / 1124 audit / 1127-1128 sector.  ASR: 1121 block / 1122 audit.
# Device Control has NO local Operational event ID - do NOT assert 1124/1125 as Device Control.
try {
    Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-Windows Defender/Operational'; Id=1121,1122,1123,1124,1127,1128 } -MaxEvents 20 -ErrorAction Stop |
        ForEach-Object {
            $kind = switch ($_.Id) {1121{'ASR block'}1122{'ASR audit'}1123{'CFA block'}1124{'CFA audit'}1127{'CFA sector block'}1128{'CFA sector audit'}default{"ID $($_.Id)"}}
            Write-Host ("[{0}] {1}" -f $_.TimeCreated, $kind) -ForegroundColor Yellow
            Add-Finding 'EventLog' 'INFO' "$kind event in Defender/Operational. CFA/ASR are file/execute blocks, NOT removable-storage Device Control."
        }
} catch { Write-Host "No recent ASR/CFA events (or log not present)." }
Add-Finding 'Defender-DeviceControl' 'INFO' "Device Control denials are NOT in a local event ID. Confirm in the Defender portal > Advanced Hunting: DeviceEvents | where ActionType == 'RemovableStoragePolicyTriggered' | extend p=parse_json(AdditionalFields) | project Timestamp,DeviceName,Verdict=tostring(p.RemovableStoragePolicyVerdict),Policy=tostring(p.RemovableStoragePolicy),Access=tostring(p.RemovableStorageAccess),VID=tostring(p.VendorId),PID=tostring(p.ProductId),Serial=tostring(p.SerialNumber). AccessMask bits: 1=disk read,2=disk write,4=disk exec,8=fs read,16=fs write,32=fs exec,64=print."

# ============================================================================
if ($Path) {
Write-Header "11. Specific path checks  (-Path '$Path')"
# ============================================================================
    if ($Path -match '^\\\\tsclient' -or $Path -match '^\\\\' ) {
        Add-Finding 'Redirected' 'WARN' "$Path is a NETWORK/redirected path (UNC or \\tsclient RDP redirection), not a local USB. Access Denied here is an SMB share-permission / SMB-encryption issue (server logs Event ID 1003 in Microsoft-Windows-SmbServer/Operational), not a device/NTFS-local block."
    } elseif (Test-Path $Path) {
        $attr = (Get-Item $Path -Force).Attributes
        if ($attr -band [IO.FileAttributes]::ReadOnly)  { Add-Finding 'File' 'WARN' "$Path has the READ-ONLY attribute. Clear: attrib -r '$Path'." }
        if ($attr -band [IO.FileAttributes]::Encrypted) { Add-Finding 'File' 'WARN' "$Path is EFS-encrypted - accessible only to the user who encrypted it, regardless of NTFS permissions. Use the owning user or a Data Recovery Agent." }
        $dl = ($Path -replace '^([A-Za-z]):.*','$1')
        if ((Get-Volume -DriveLetter $dl -ErrorAction SilentlyContinue).DriveType -eq 'Network') {
            Add-Finding 'Redirected' 'WARN' "$Path resolves to a NETWORK drive - treat as SMB permissions, not local USB."
        }
    }
}

# ============================================================================
Write-Header "VERDICT"
# ============================================================================
# Rank order: on a managed box, lead with the Intune-era enforcers; demote the manually-edited layers.
$priority = 'Defender-DeviceControl','Storage-CSP','RemovableStorageAccess','DeviceInstallRestrictions',
            'ThirdPartyDLP','ClassFilter','BitLocker-FVE','WriteProtect','BitLocker-Drive','NTFS-ACL',
            'Partition','Disk','WriteProbe','USBSTOR','UASPStor'
$blocks = $findings | Where-Object Status -eq 'BLOCK' |
          Sort-Object @{ Expression = { $i = $priority.IndexOf($_.Layer); if ($i -lt 0) { 99 } else { $i } } }
if ($blocks) {
    Write-Host "Most likely cause(s) of Access Denied (highest-probability first):" -ForegroundColor Red
    $n = 1
    foreach ($b in $blocks) { Write-Host ("  {0}. [{1}] {2}" -f $n++, $b.Layer, $b.Detail) -ForegroundColor Red }
} else {
    Write-Host "No hard registry/Defender block detected." -ForegroundColor Green
    Write-Host "If writes still fail: re-run with -TestWrite; check a third-party DLP minifilter (Section 7b), an NTFS DENY ACE, a volume read-only attribute, or a physical write-protect switch - none of these leave a registry footprint." -ForegroundColor Yellow
}
if ($mdm) {
    Write-Host ""
    Write-Host "NOTE: This device is Intune-managed. Your USBSTOR=3 and FVE=0 edits are almost certainly NOT the effective lever -" -ForegroundColor Yellow
    Write-Host "Defender Device Control enforces above USBSTOR and Intune reverts local edits on the next sync. Scope the fix in Intune." -ForegroundColor Yellow
    if ($domJoined) { Write-Host "Also: this box gets GPO. For Device Control, GPO WINS over Intune if both apply - check local GPO before blaming Intune." -ForegroundColor Yellow }
}
Write-Host ""
Write-Host "Full findings:" -ForegroundColor Cyan
$findings | Format-Table Layer, Status, Detail -AutoSize -Wrap
