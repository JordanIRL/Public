<#
.SYNOPSIS
    Diagnoses (1) which policy layers are blocking USB/removable storage and
    (2) why the Microsoft 365 Copilot app keeps being removed, on an
    Entra-joined, Intune-managed Windows 11 device.

.DESCRIPTION
    Checks every known blocking mechanism, reports which are ACTIVE, and maps
    each one back to the Intune profile type that configures it so you can find
    the offending profile in the admin center.

    USB layers checked:
      1. Device Installation Restrictions   (PnP-level block, strongest)
      2. Removable Storage Access ADMX      (Deny_Read/Write/Execute per class)
      3. Storage CSP RemovableDiskDenyWriteAccess
      4. Defender for Endpoint Device Control (default enforcement + policies)
      5. BitLocker removable-drive write protection (RDVDenyWriteAccess)
      6. USBSTOR service disabled / legacy WriteProtect
      7. ASR rule: block untrusted processes running from USB
      8. Evidence: setupapi.dev.log, Kernel-PnP events, devices in error state

    Copilot checks:
      A. RemoveDefaultMicrosoftStorePackages policy (in-box app removal)
      B. AppXDeployment-Server events 762/606/614 (removal policy in action)
      C. Deprovisioned-package list (evidence a debloat script ran)
      D. WindowsAI policies (consumer Copilot vs M365 Copilot disambiguation)
      E. AppLocker rules matching Copilot/OfficeHub
      F. Intune Management Extension log mentions (remediation scripts)

.PARAMETER CollectMdmDiag
    Also runs mdmdiagnosticstool.exe to produce MDMDiagReport.html — the full
    list of every MDM policy applied to the device, with values.

.NOTES
    Run in an elevated PowerShell (5.1 or 7) on the affected device.
    Report is written to %ProgramData%\UsbCopilotDiag\ and echoed to console.
#>
[CmdletBinding()]
param(
    [switch]$CollectMdmDiag
)

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Run this script elevated. Some checks (event logs, HKU, Defender) will be incomplete."
}

$ReportDir  = Join-Path $env:ProgramData 'UsbCopilotDiag'
$null       = New-Item -ItemType Directory -Path $ReportDir -Force
$ReportFile = Join-Path $ReportDir ("UsbCopilotDiag_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$script:Findings = New-Object System.Collections.Generic.List[object]

function Out-Report {
    param([string]$Text, [ConsoleColor]$Color = 'Gray')
    Write-Host $Text -ForegroundColor $Color
    Add-Content -Path $ReportFile -Value $Text
}

function Add-Finding {
    param(
        [ValidateSet('BLOCKING','LIKELY-CAUSE','WARNING','INFO')] [string]$Severity,
        [string]$Area,
        [string]$Message,
        [string]$IntuneSource   # where to look in the Intune admin center
    )
    $script:Findings.Add([pscustomobject]@{
        Severity = $Severity; Area = $Area; Message = $Message; IntuneSource = $IntuneSource
    })
    $color = switch ($Severity) {
        'BLOCKING'     { 'Red' }
        'LIKELY-CAUSE' { 'Red' }
        'WARNING'      { 'Yellow' }
        default        { 'Cyan' }
    }
    Out-Report ("  [{0}] {1}" -f $Severity, $Message) $color
    if ($IntuneSource) { Out-Report ("           -> Intune: {0}" -f $IntuneSource) DarkGray }
}

function Get-RegValue {
    param([string]$Path, [string]$Name)
    try { (Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop).$Name } catch { $null }
}

function Dump-RegKey {
    # Recursively prints a registry key's values into the report (for evidence).
    param([string]$Path, [int]$Depth = 0)
    if (-not (Test-Path $Path)) { return }
    $indent = '    ' * ($Depth + 1)
    $item = Get-Item $Path -ErrorAction SilentlyContinue
    foreach ($v in $item.GetValueNames()) {
        Out-Report ("{0}{1} = {2}" -f $indent, ($(if ($v) {$v} else {'(default)'})), ($item.GetValue($v) -join ', ')) DarkGray
    }
    foreach ($sub in Get-ChildItem $Path -ErrorAction SilentlyContinue) {
        Out-Report ("{0}[{1}]" -f $indent, $sub.PSChildName) DarkGray
        Dump-RegKey -Path $sub.PSPath -Depth ($Depth + 1)
    }
}

function Section { param([string]$Title)
    Out-Report "" ; Out-Report ("=" * 78) White
    Out-Report $Title White
    Out-Report ("=" * 78) White
}

Out-Report ("USB / Copilot policy diagnostics  -  {0}  -  {1}" -f $env:COMPUTERNAME, (Get-Date)) White
Out-Report ("OS: " + (Get-CimInstance Win32_OperatingSystem).Caption + "  build " + [Environment]::OSVersion.Version) Gray

# ============================================================================
# PART 1 - USB / REMOVABLE STORAGE BLOCKING
# ============================================================================

Section "1. Device Installation Restrictions (PnP-level - blocks the device itself)"
$dir = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions'
if (Test-Path $dir) {
    Dump-RegKey $dir
    $src = 'Settings Catalog > "Device Installation", or Administrative Templates > System > Device Installation, or a custom OMA-URI (DeviceInstallation CSP)'
    if ((Get-RegValue $dir 'DenyRemovableDevices') -eq 1) {
        Add-Finding BLOCKING 'DeviceInstall' 'Installation of ALL removable devices is denied (DenyRemovableDevices=1). This blocks USB storage at the PnP layer regardless of any allow rules elsewhere.' $src
    }
    if ((Get-RegValue $dir 'DenyUnspecified') -eq 1) {
        Add-Finding BLOCKING 'DeviceInstall' 'Devices NOT matched by an allow list are denied (DenyUnspecified=1). Any USB device missing from AllowDeviceIDs/AllowInstanceIDs/AllowDeviceClasses is blocked.' $src
    }
    foreach ($listName in 'DenyDeviceIDs','DenyDeviceClasses','DenyInstanceIDs') {
        if ((Get-RegValue $dir $listName) -eq 1) {
            $entries = @()
            $sub = Join-Path $dir $listName
            if (Test-Path $sub) { $k = Get-Item $sub; $entries = $k.GetValueNames() | ForEach-Object { $k.GetValue($_) } }
            Add-Finding BLOCKING 'DeviceInstall' ("{0} is enforced: {1}" -f $listName, ($entries -join '; ')) $src
            # USB storage / disk class GUIDs worth calling out explicitly
            if ($entries -match '4d36e967-e325-11ce-bfc1-08002be10318') {
                Add-Finding INFO 'DeviceInstall' 'Denied class {4d36e967...} = DiskDrive class: blocks ALL USB disks.' $null
            }
            if ($entries -match '36fc9e60-c465-11cf-8056-444553540000') {
                Add-Finding INFO 'DeviceInstall' 'Denied class {36fc9e60...} = USB Bus class: very broad, can break hubs/controllers too.' $null
            }
        }
    }
    foreach ($listName in 'AllowDeviceIDs','AllowDeviceClasses','AllowInstanceIDs') {
        if ((Get-RegValue $dir $listName) -eq 1) {
            Add-Finding INFO 'DeviceInstall' ("Allow list '{0}' is active - devices must match it if DenyUnspecified/deny-lists apply." -f $listName) $null
        }
    }
} else {
    Out-Report "  Not configured." Green
}

Section "2. Removable Storage Access ADMX (Deny_Read / Deny_Write / Deny_Execute)"
$classMap = @{
    '{53f56308-b6bf-11d0-94f2-00a0c91efb8b}' = 'CD and DVD'
    '{53f5630b-b6bf-11d0-94f2-00a0c91efb8b}' = 'Tape drives'
    '{53f5630d-b6bf-11d0-94f2-00a0c91efb8b}' = 'Removable disks (USB sticks/HDDs)'
    '{53f56311-b6bf-11d0-94f2-00a0c91efb8b}' = 'Floppy drives'
    '{6AC27878-A6FA-4155-BA85-F98F491D4F33}' = 'Windows Portable Devices (phones/tablets)'
    '{F33FDC04-D1AC-4E8E-9A30-19BBD4B108AE}' = 'Windows Portable Devices (phones/tablets)'
}
$rsSrc = 'Settings Catalog > Administrative Templates > System > Removable Storage Access; also set by Endpoint Security > Attack Surface Reduction > Device Control profiles'
$rsPaths = @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices')
# Include every loaded user hive - this policy also exists per-user
$null = New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS -ErrorAction SilentlyContinue
Get-ChildItem HKU:\ -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^S-1-5-21' } | ForEach-Object {
    $rsPaths += "$($_.PSPath)\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices"
}
$foundRs = $false
foreach ($p in $rsPaths) {
    if (-not (Test-Path $p)) { continue }
    $foundRs = $true
    $scope = if ($p -like 'HKLM*') { 'Device' } else { "User hive $((Split-Path (Split-Path (Split-Path (Split-Path $p)))) -replace '.*\\')" }
    Out-Report "  Scope: $scope  ($p)" Gray
    if ((Get-RegValue $p 'Deny_All') -eq 1) {
        Add-Finding BLOCKING 'RemovableStorage' "ALL removable storage classes: Deny all access ($scope scope)." $rsSrc
    }
    foreach ($sub in Get-ChildItem $p -ErrorAction SilentlyContinue) {
        $guid  = $sub.PSChildName
        $label = if ($classMap[$guid]) { $classMap[$guid] } else { "Custom class $guid" }
        foreach ($deny in 'Deny_Read','Deny_Write','Deny_Execute') {
            if ((Get-RegValue $sub.PSPath $deny) -eq 1) {
                Add-Finding BLOCKING 'RemovableStorage' ("{0}: {1} = 1 ({2} scope)" -f $label, $deny, $scope) $rsSrc
            }
        }
    }
}
if (-not $foundRs) { Out-Report "  Not configured." Green }

Section "3. Storage CSP / legacy write-protect / USBSTOR service"
$pmStorage = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Storage'
if (Test-Path $pmStorage) {
    Out-Report "  MDM-delivered Storage policy values:" Gray
    Dump-RegKey $pmStorage
    if ((Get-RegValue $pmStorage 'RemovableDiskDenyWriteAccess') -eq 1) {
        Add-Finding BLOCKING 'StorageCSP' 'RemovableDiskDenyWriteAccess=1 - write access denied to all removable disks (read still works).' 'Endpoint Security > Attack Surface Reduction > "Block write access to removable storage", or Device Restrictions template'
    }
}
if ((Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\StorageDevicePolicies' 'WriteProtect') -eq 1) {
    Add-Finding BLOCKING 'Legacy' 'StorageDevicePolicies\WriteProtect=1 (legacy write-protect, usually set by a script or old GPO).' 'Not an Intune UI setting - look for a PowerShell/remediation script or legacy GPO'
}
$usbstorStart = Get-RegValue 'HKLM:\SYSTEM\CurrentControlSet\Services\USBSTOR' 'Start'
if ($usbstorStart -eq 4) {
    Add-Finding BLOCKING 'Legacy' 'USBSTOR service is DISABLED (Start=4). No USB mass-storage driver will load at all.' 'Not an Intune UI setting - typically a remediation script or old GPO'
} else {
    Out-Report ("  USBSTOR Start = {0} (3 = normal/on-demand)" -f $usbstorStart) Green
}

Section "4. Defender for Endpoint Device Control"
$dcSrc = 'Endpoint Security > Attack Surface Reduction > Device Control profile (reusable settings groups), or custom OMA-URI (Defender CSP DeviceControl); can also come from MDE cloud "security settings management"'
try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    Out-Report ("  DeviceControlState              : {0}" -f $mp.DeviceControlState) Gray
    Out-Report ("  DeviceControlDefaultEnforcement : {0}" -f $mp.DeviceControlDefaultEnforcement) Gray
    Out-Report ("  DeviceControlPoliciesLastUpdated: {0}" -f $mp.DeviceControlPoliciesLastUpdated) Gray
    if ($mp.DeviceControlState -eq 'Enabled') {
        if ($mp.DeviceControlDefaultEnforcement -match 'Deny') {
            Add-Finding BLOCKING 'MDE-DeviceControl' 'Device Control is ENABLED with DefaultEnforcement=Deny - any device not matched by an Allow rule is blocked.' $dcSrc
        } else {
            Add-Finding WARNING 'MDE-DeviceControl' ('Device Control is ENABLED (default enforcement: {0}). Individual policy rules may still deny specific devices/users.' -f $mp.DeviceControlDefaultEnforcement) $dcSrc
        }
    } else {
        Out-Report "  Device Control not enabled." Green
    }
} catch { Out-Report "  Get-MpComputerStatus failed (Defender not primary AV, or run non-elevated): $_" Yellow }
foreach ($dcKey in 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Defender',
                   'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Device Control',
                   'HKLM:\SOFTWARE\Microsoft\Windows Defender\Device Control') {
    if (Test-Path $dcKey) {
        Out-Report "  $dcKey :" Gray
        Dump-RegKey $dcKey
        if ($dcKey -like '*Policies*') {
            Add-Finding WARNING 'MDE-DeviceControl' 'Device Control policy present under GROUP POLICY path. If GP and Intune both configure Device Control, GP wins and Intune settings are ignored.' 'Check for domain/local GPO or LGPO-based script'
        }
    }
}

Section "5. BitLocker removable-drive write protection"
$fveSrc = 'Endpoint Security > Disk Encryption (BitLocker) > Removable drive settings: "Deny write access to removable drives not protected by BitLocker"'
foreach ($fve in 'HKLM:\SOFTWARE\Policies\Microsoft\FVE','HKLM:\SYSTEM\CurrentControlSet\Policies\Microsoft\FVE') {
    if ((Get-RegValue $fve 'RDVDenyWriteAccess') -eq 1) {
        Add-Finding BLOCKING 'BitLocker' ("RDVDenyWriteAccess=1 at {0} - unencrypted USB drives are READ-ONLY until BitLocker-encrypted. Users see 'access denied' on write." -f $fve) $fveSrc
        if ((Get-RegValue $fve 'RDVDenyCrossOrg') -eq 1) {
            Add-Finding BLOCKING 'BitLocker' 'RDVDenyCrossOrg=1 - drives encrypted by OTHER organizations are also write-blocked.' $fveSrc
        }
    }
}
if (-not $script:Findings.Where({$_.Area -eq 'BitLocker'})) { Out-Report "  Not configured." Green }

Section "6. ASR rule - block untrusted/unsigned processes running from USB"
try {
    $pref = Get-MpPreference -ErrorAction Stop
    $ids  = @($pref.AttackSurfaceReductionRules_Ids)
    $acts = @($pref.AttackSurfaceReductionRules_Actions)
    $usbRule = 'b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4'
    $ix = [array]::FindIndex($ids, [Predicate[object]]{ param($x) $x -ieq $usbRule })
    if ($ix -ge 0 -and $acts[$ix] -eq 1) {
        Add-Finding WARNING 'ASR' 'ASR rule "Block untrusted and unsigned processes that run from USB" is in BLOCK mode. Drive mounts fine but .exe/.scr/.dll on it will not run - often mistaken for USB blocking.' 'Endpoint Security > Attack Surface Reduction > ASR rules profile'
    } else {
        Out-Report "  USB ASR rule not in block mode." Green
    }
} catch { Out-Report "  Get-MpPreference failed: $_" Yellow }

Section "7. Evidence of actual blocks (logs and device state)"
# 7a. setupapi.dev.log - device installs rejected by policy
$setupLog = "$env:windir\INF\setupapi.dev.log"
if (Test-Path $setupLog) {
    $hits = Select-String -Path $setupLog -Pattern 'restricted by (system )?policy|forbidden by (system )?policy|prohibited by' -SimpleMatch:$false |
            Select-Object -Last 10
    if ($hits) {
        Add-Finding INFO 'Evidence' 'setupapi.dev.log shows device installs rejected by policy (= Device Installation Restrictions fired). Last hits below.' $null
        $hits | ForEach-Object { Out-Report ("    " + $_.Line.Trim()) DarkGray }
    } else { Out-Report "  setupapi.dev.log: no policy-rejection entries found." Green }
}
# 7b. Present devices sitting in an error state
$errDevs = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
           Where-Object { $_.Status -ne 'OK' -and ($_.Class -in 'USB','DiskDrive','WPD','USBDevice' -or $_.InstanceId -like 'USB*') }
if ($errDevs) {
    Add-Finding INFO 'Evidence' 'USB-related devices currently in a non-OK state (a banned icon in Device Manager = install restriction; check properties for the problem text):' $null
    $errDevs | ForEach-Object { Out-Report ("    {0}  [{1}]  Status={2}" -f $_.FriendlyName, $_.InstanceId, $_.Status) DarkGray }
}
# 7c. Defender operational log - device control config changes / actions
try {
    Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-Windows Defender/Operational'; Id=5007 } -MaxEvents 200 -ErrorAction Stop |
        Where-Object { $_.Message -match 'Device\s*Control|DefaultEnforcement' } | Select-Object -First 5 | ForEach-Object {
            Out-Report ("    {0}  {1}" -f $_.TimeCreated, ($_.Message -split "`n")[0]) DarkGray
        }
} catch {}

# ============================================================================
# PART 2 - MICROSOFT 365 COPILOT APP KEEPS UNINSTALLING
# ============================================================================
# The Microsoft 365 Copilot app is the renamed "Microsoft 365 (Office)" app:
# package family Microsoft.MicrosoftOfficeHub_8wekyb3d8bbwe. Anything that
# removed "the Office hub app" now removes Copilot.

$pfnPattern = 'MicrosoftOfficeHub|M365Copilot'

Section "A. Current state of the Microsoft 365 Copilot app package"
$pkgs = Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $pfnPattern }
if ($pkgs) { $pkgs | ForEach-Object { Out-Report ("  Installed: {0}  v{1}  (users: {2})" -f $_.PackageFullName, $_.Version, (@($_.PackageUserInformation).Count)) Gray } }
else       { Out-Report "  Package NOT currently installed for any user." Yellow }
$prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match $pfnPattern }
if ($prov) { Out-Report ("  Provisioned (installs for new users): " + ($prov.DisplayName -join ', ')) Gray }
else       { Out-Report "  NOT provisioned - new users will not get it from the image." Yellow }

Section "B. In-box app removal policy (RemoveDefaultMicrosoftStorePackages)"
$rmKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Appx\RemoveDefaultMicrosoftStorePackages'
if (Test-Path $rmKey) {
    Out-Report "  Policy key present - contents:" Gray
    Dump-RegKey $rmKey
    # Match on subkey names, value names, AND value data (dynamic removal list stores PFNs as data)
    $flat = @(Get-Item $rmKey; Get-ChildItem $rmKey -Recurse -ErrorAction SilentlyContinue) | ForEach-Object {
        $k = $_
        $k.PSChildName
        $k.GetValueNames() | ForEach-Object { $_; [string]($k.GetValue($_)) }
    }
    if (($flat -join ' ') -match $pfnPattern) {
        Add-Finding LIKELY-CAUSE 'Copilot' 'The in-box app removal policy explicitly targets Microsoft.MicrosoftOfficeHub (= the Microsoft 365 Copilot app). It removes the app at every sign-in AND blocks reinstallation - Intune keeps pushing it, this policy keeps removing/blocking it.' 'Settings Catalog > Administrative Templates > Windows Components > App Package Deployment > "Remove default Microsoft Store packages from the system"'
    } else {
        Add-Finding WARNING 'Copilot' 'In-box app removal policy is active on this device (targets listed above). Verify the Copilot/OfficeHub package is not in its list or dynamic removal list.' 'Settings Catalog > Administrative Templates > Windows Components > App Package Deployment'
    }
} else {
    Out-Report "  Not configured." Green
}

Section "C. AppXDeployment-Server events (removal policy caught in the act)"
# 762 = install BLOCKED because a removal policy targets the package (smoking gun)
# 606 = removal policy successfully removed the package at sign-in
# 614 = removal policy tried and failed to remove the package
try {
    $appxEvents = Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-AppXDeployment-Server/Operational'; Id=762,606,614 } -MaxEvents 400 -ErrorAction Stop |
                  Where-Object { $_.Message -match $pfnPattern }
    if ($appxEvents) {
        Add-Finding LIKELY-CAUSE 'Copilot' ("Found {0} AppXDeployment events (762=install blocked by removal policy, 606=removed by policy, 614=removal failed) referencing the Copilot/OfficeHub package. A removal policy IS acting on this app." -f @($appxEvents).Count) 'Same policy as section B - find the Intune profile that delivers it'
        $appxEvents | Select-Object -First 6 | ForEach-Object {
            Out-Report ("    {0}  Event {1}: {2}" -f $_.TimeCreated, $_.Id, (($_.Message -split "`n")[0])) DarkGray }
    } else { Out-Report "  No removal-policy events referencing Copilot/OfficeHub." Green }
} catch { Out-Report "  Could not read AppXDeployment-Server log: $_" Yellow }

Section "D. Deprovisioned list (evidence a debloat/cleanup script ran)"
$deprov = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned' -ErrorAction SilentlyContinue |
          Where-Object { $_.PSChildName -match $pfnPattern }
if ($deprov) {
    Add-Finding LIKELY-CAUSE 'Copilot' ("The package is on the DEPROVISIONED list ({0}). Something ran Remove-AppxProvisionedPackage against it - classic signature of a 'remove built-in apps' / debloat script (platform script, remediation, or Autopilot script). While deprovisioned, Windows servicing won't re-provision it and reinstalls can fail or vanish for new users." -f ($deprov.PSChildName -join ', ')) 'Intune > Devices > Scripts and remediations - look for debloat/appx-removal scripts; also check Autopilot/ESP-era platform scripts'
} else {
    Out-Report "  Copilot/OfficeHub is not on the deprovisioned list." Green
}

Section "E. Consumer-Copilot policies (disambiguation) and AppLocker"
$waiKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'
if (Test-Path $waiKey) {
    Dump-RegKey $waiKey
    if ((Get-RegValue $waiKey 'RemoveMicrosoftCopilotApp') -eq 1) {
        Add-Finding INFO 'Copilot' 'WindowsAI\RemoveMicrosoftCopilotApp=1 removes the CONSUMER "Microsoft Copilot" app (Microsoft.Copilot) - NOT Microsoft 365 Copilot. Only relevant if users report the wrong app disappearing.' 'Settings Catalog > Windows AI'
    }
    if (Get-RegValue $waiKey 'TurnOffWindowsCopilot') {
        Add-Finding INFO 'Copilot' 'Legacy TurnOffWindowsCopilot policy present (deprecated; affects old Windows Copilot sidebar, not the M365 Copilot app).' $null
    }
} else { Out-Report "  No WindowsAI policies." Green }
try {
    $alp = Get-AppLockerPolicy -Effective -Xml -ErrorAction Stop
    if ($alp -match 'COPILOT|OFFICEHUB') {
        Add-Finding WARNING 'Copilot' 'Effective AppLocker policy contains rules matching COPILOT/OFFICEHUB - could block install or launch of the packaged app.' 'Check AppLocker policy source (Intune custom OMA-URI / GPO)'
    } else { Out-Report "  No AppLocker rules matching Copilot/OfficeHub." Green }
} catch { Out-Report "  No effective AppLocker policy (or query failed)." Green }

Section "F. Intune Management Extension logs (remediation/platform scripts touching the app)"
$imeLogs = Get-ChildItem "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs" -Filter '*.log' -ErrorAction SilentlyContinue
$imeHits = @()
foreach ($lg in $imeLogs) {
    $imeHits += Select-String -Path $lg.FullName -Pattern 'OfficeHub|M365Copilot|Remove-AppxP' -ErrorAction SilentlyContinue | Select-Object -Last 5
}
if ($imeHits) {
    Add-Finding WARNING 'Copilot' 'Intune Management Extension logs mention OfficeHub/Copilot/Remove-AppxProvisionedPackage - a deployed script or remediation is touching the app. Excerpts below.' 'Intune > Devices > Scripts and remediations (check both Platform scripts and Remediations)'
    $imeHits | Select-Object -First 8 | ForEach-Object { Out-Report ("    {0}: {1}" -f (Split-Path $_.Path -Leaf), $_.Line.Trim().Substring(0, [Math]::Min(160, $_.Line.Trim().Length))) DarkGray }
} else {
    Out-Report "  No mentions in IME logs (note: logs rotate - absence is not proof)." Gray
}

# ============================================================================
# OPTIONAL - full MDM policy report
# ============================================================================
if ($CollectMdmDiag) {
    Section "MDM diagnostics report (every applied policy + value + source)"
    $mdmOut = Join-Path $ReportDir 'MDMDiag'
    $null = New-Item -ItemType Directory -Path $mdmOut -Force
    Start-Process -FilePath "$env:windir\system32\mdmdiagnosticstool.exe" -ArgumentList "-out `"$mdmOut`"" -Wait -NoNewWindow
    Out-Report "  Open $mdmOut\MDMDiagReport.html - it lists every MDM policy applied to this device with its value. Search it for: Storage, DeviceInstallation, RemovableStorage, Defender, Appx." Cyan
}

# ============================================================================
# SUMMARY
# ============================================================================
Section "SUMMARY OF FINDINGS"
if ($script:Findings.Count -eq 0) {
    Out-Report "  No blocking policies detected by these checks. Consider Purview Endpoint DLP (cloud-managed, not fully visible in registry) and re-run with -CollectMdmDiag." Yellow
} else {
    $script:Findings | Sort-Object @{e={switch ($_.Severity) {'BLOCKING'{0}'LIKELY-CAUSE'{0}'WARNING'{1}default{2}}}} | ForEach-Object {
        $c = if ($_.Severity -in 'BLOCKING','LIKELY-CAUSE') {'Red'} elseif ($_.Severity -eq 'WARNING') {'Yellow'} else {'Cyan'}
        Out-Report ("  [{0}] ({1}) {2}" -f $_.Severity, $_.Area, $_.Message) $c
        if ($_.IntuneSource) { Out-Report ("      Fix in: {0}" -f $_.IntuneSource) DarkGray }
    }
}
Out-Report "" ; Out-Report ("Full report saved to: {0}" -f $ReportFile) White
Out-Report "Not visible from the endpoint: Purview Endpoint DLP device restrictions and MDE cloud-side device control - check those portals if nothing above explains the block." Gray
