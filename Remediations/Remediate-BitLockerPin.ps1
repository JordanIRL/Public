# Enables BitLocker on the OS drive with TPM+PIN.
# Runs as SYSTEM. Enforces FVE policy, escrows recovery key to Entra ID,
# and schedules a per-user logon task that prompts the signed-in user for a PIN.
# NOTE: adding a TpmPin protector needs admin rights. On devices where the end
# user is a standard user, set $UserIsAdmin=$false to run the prompt task as SYSTEM
# via a session-spawn helper (not included here — swap in your preferred method).

[CmdletBinding()]
param(
    [int]$MinPinLength = 6,
    [bool]$UserIsAdmin = $true
)

$ErrorActionPreference = 'Stop'
$osDrive  = $env:SystemDrive
$stateDir = Join-Path $env:ProgramData 'IntuneRemediation\BitLockerPin'
$log      = Join-Path $stateDir 'remediation.log'
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null

function Write-Log { param($m) "$((Get-Date).ToString('o')) $m" | Add-Content $log; Write-Output $m }

try {
    # 1) FVE policy: require TPM+PIN on OS drive, enable Entra ID escrow
    $fve = 'HKLM:\SOFTWARE\Policies\Microsoft\FVE'
    if (-not (Test-Path $fve)) { New-Item $fve -Force | Out-Null }
    $policy = @{
        UseAdvancedStartup       = 1
        EnableBDEWithNoTPM       = 0
        UseTPM                   = 0  # disallow TPM-only
        UseTPMPIN                = 1  # require TPM+PIN
        UseTPMKey                = 0
        UseTPMKeyPIN             = 0
        UseEnhancedPin           = 1
        MinimumPIN               = $MinPinLength
        OSRecovery               = 1
        OSManageDRA              = 1
        OSRecoveryPassword       = 2
        OSRecoveryKey            = 2
        OSHideRecoveryPage       = 0
        OSActiveDirectoryBackup  = 0
        OSRequireActiveDirectoryBackup = 0
        OSBackupToAAD            = 1
        OSEncryptionType         = 1  # 1 = full, 2 = used-space only
    }
    foreach ($n in $policy.Keys) {
        New-ItemProperty -Path $fve -Name $n -Value $policy[$n] -PropertyType DWord -Force | Out-Null
    }
    New-ItemProperty -Path $fve -Name 'BitLockerPinMinLength' -Value $MinPinLength -PropertyType DWord -Force | Out-Null
    Write-Log "FVE policy applied (MinimumPIN=$MinPinLength)."

    # 2) Ensure recovery password exists and is escrowed to Entra ID
    $v = Get-BitLockerVolume -MountPoint $osDrive
    $rec = $v.KeyProtector | Where-Object KeyProtectorType -eq 'RecoveryPassword' | Select-Object -First 1
    if (-not $rec) {
        $added = Add-BitLockerKeyProtector -MountPoint $osDrive -RecoveryPasswordProtector
        $rec   = $added.KeyProtector | Where-Object KeyProtectorType -eq 'RecoveryPassword' | Select-Object -Last 1
        Write-Log "Added RecoveryPassword protector."
    }
    try {
        BackupToAAD-BitLockerKeyProtector -MountPoint $osDrive -KeyProtectorId $rec.KeyProtectorId | Out-Null
        Write-Log "Recovery key escrowed to Entra ID."
    } catch {
        Write-Log "Entra ID escrow failed: $($_.Exception.Message)"
    }

    # 3) Ensure a TPM protector exists (required before adding a PIN)
    $v = Get-BitLockerVolume -MountPoint $osDrive
    $hasTpm    = $v.KeyProtector | Where-Object KeyProtectorType -eq 'Tpm'
    $hasTpmPin = $v.KeyProtector | Where-Object KeyProtectorType -eq 'TpmPin'
    if (-not $hasTpm -and -not $hasTpmPin) {
        Add-BitLockerKeyProtector -MountPoint $osDrive -TpmProtector | Out-Null
        Write-Log "Added Tpm protector."
    }

    # 4) Start encryption if needed
    if ($v.ProtectionStatus -eq 'Off' -and $v.VolumeStatus -notin 'EncryptionInProgress','FullyEncrypted') {
        Enable-BitLocker -MountPoint $osDrive -EncryptionMethod XtsAes256 -TpmProtector -SkipHardwareTest | Out-Null
        Write-Log "BitLocker encryption started on $osDrive."
    }

    # 5) Drop the user-prompt script
    $promptPath = Join-Path $stateDir 'Prompt-BitLockerPin.ps1'
    $prompt = @'
$ErrorActionPreference = 'Stop'
$osDrive = $env:SystemDrive
$minLen  = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\FVE' -Name BitLockerPinMinLength -ErrorAction SilentlyContinue).BitLockerPinMinLength
if (-not $minLen) { $minLen = 6 }

$logDir = Join-Path $env:LOCALAPPDATA 'IntuneRemediation\BitLockerPin'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$log = Join-Path $logDir 'prompt.log'
function Log($m) { "$((Get-Date).ToString('o')) $m" | Add-Content $log }

$vol = Get-BitLockerVolume -MountPoint $osDrive
if ($vol.KeyProtector | Where-Object KeyProtectorType -eq 'TpmPin') {
    Log "TpmPin already present; exiting."
    Unregister-ScheduledTask -TaskName 'IntuneRemediation_BitLockerPinPrompt' -Confirm:$false -ErrorAction SilentlyContinue
    return
}

Add-Type -AssemblyName PresentationFramework

while ($true) {
    $xaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
        Title='Set BitLocker Startup PIN' Height='270' Width='430'
        WindowStartupLocation='CenterScreen' ResizeMode='NoResize' Topmost='True'>
  <StackPanel Margin='16'>
    <TextBlock TextWrapping='Wrap' Margin='0,0,0,8'
      Text='Your device requires a BitLocker startup PIN. Choose a PIN of at least $minLen digits. You will enter this PIN every time the device boots.'/>
    <TextBlock Text='Enter PIN:' Margin='0,8,0,2'/>
    <PasswordBox Name='Pin1' Height='26'/>
    <TextBlock Text='Confirm PIN:' Margin='0,8,0,2'/>
    <PasswordBox Name='Pin2' Height='26'/>
    <TextBlock Name='Err' Foreground='Red' Margin='0,8,0,0' TextWrapping='Wrap'/>
    <StackPanel Orientation='Horizontal' HorizontalAlignment='Right' Margin='0,12,0,0'>
      <Button Name='Ok' Content='Set PIN' Width='90' Height='28' IsDefault='True'/>
    </StackPanel>
  </StackPanel>
</Window>
"@
    $win  = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xaml)))
    $p1   = $win.FindName('Pin1')
    $p2   = $win.FindName('Pin2')
    $err  = $win.FindName('Err')
    $ok   = $win.FindName('Ok')
    $script:pin = $null

    $ok.Add_Click({
        if ($p1.Password -ne $p2.Password)       { $err.Text = 'PINs do not match.'; return }
        if ($p1.Password.Length -lt $minLen)     { $err.Text = "PIN must be at least $minLen characters."; return }
        $script:pin = $p1.Password
        $win.DialogResult = $true; $win.Close()
    })
    [void]$win.ShowDialog()

    if (-not $script:pin) { Log "User closed dialog; reprompting."; continue }

    try {
        $secure = ConvertTo-SecureString $script:pin -AsPlainText -Force
        Add-BitLockerKeyProtector -MountPoint $osDrive -TpmAndPinProtector -Pin $secure -ErrorAction Stop | Out-Null
        Log "TpmPin protector added."
        foreach ($k in ((Get-BitLockerVolume -MountPoint $osDrive).KeyProtector | Where-Object KeyProtectorType -eq 'Tpm')) {
            Remove-BitLockerKeyProtector -MountPoint $osDrive -KeyProtectorId $k.KeyProtectorId | Out-Null
        }
        Unregister-ScheduledTask -TaskName 'IntuneRemediation_BitLockerPinPrompt' -Confirm:$false -ErrorAction SilentlyContinue
        [System.Windows.MessageBox]::Show('BitLocker PIN set successfully.', 'BitLocker', 'OK', 'Information') | Out-Null
        break
    } catch {
        Log "Add-BitLockerKeyProtector failed: $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show("Failed to set PIN: $($_.Exception.Message)", 'BitLocker', 'OK', 'Error') | Out-Null
    }
}
'@
    Set-Content -Path $promptPath -Value $prompt -Encoding UTF8 -Force
    Write-Log "Wrote prompt script: $promptPath"

    # 6) Scheduled task: prompt user for PIN at every logon until compliant
    $taskName = 'IntuneRemediation_BitLockerPinPrompt'
    $action   = New-ScheduledTaskAction -Execute 'powershell.exe' `
                 -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$promptPath`""
    $trigger  = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    if ($UserIsAdmin) {
        # Runs in the user's session with elevation so Add-BitLockerKeyProtector succeeds.
        $principal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Highest
    } else {
        # Standard users cannot add a TpmPin protector. Run as SYSTEM and have the
        # script spawn a UI in the active user session (requires a helper such as
        # ServiceUI.exe or a CreateProcessAsUser wrapper — wire that into the prompt script).
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest -LogonType ServiceAccount
    }

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force | Out-Null
    Write-Log "Registered scheduled task '$taskName'."

    try { Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue } catch {}

    exit 0
}
catch {
    Write-Log "Remediation error: $($_.Exception.Message)"
    exit 1
}
