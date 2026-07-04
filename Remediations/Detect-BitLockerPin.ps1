try {
    $osDrive = $env:SystemDrive
    $v = Get-BitLockerVolume -MountPoint $osDrive -ErrorAction Stop

    if ($v.ProtectionStatus -ne 'On') {
        Write-Output "BitLocker protection off on $osDrive."
        exit 1
    }
    if ($v.VolumeStatus -ne 'FullyEncrypted') {
        Write-Output "Volume $osDrive not fully encrypted ($($v.VolumeStatus))."
        exit 1
    }
    if (-not ($v.KeyProtector | Where-Object KeyProtectorType -eq 'TpmPin')) {
        Write-Output "No TpmPin protector on $osDrive."
        exit 1
    }

    Write-Output "Compliant: BitLocker + TPM/PIN active on $osDrive."
    exit 0
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}
