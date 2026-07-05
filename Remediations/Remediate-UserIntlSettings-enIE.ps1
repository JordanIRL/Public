<#
.SYNOPSIS
    Remediation - per-user international settings (English (Ireland)).

.DESCRIPTION
    Sets the signed-in user's regional format, home location, preferred
    language list, keyboard layout and default input override to the en-IE
    standard. en-US is removed from the language list; any other languages
    the user has added are preserved. Format and display changes complete
    at the next sign-in.

    Intune remediation deployment settings:
        Run this script using the logged-on credentials : Yes
        Enforce script signature check                  : No
        Run script in 64-bit PowerShell                 : Yes
#>

$LanguageTag = 'en-IE'
$GeoId       = 68                 # Ireland
$InputTip    = '1809:00001809'    # English (Ireland) + Irish keyboard
$RemoveTags  = @('en-US')

try {
    # en-IE first, with the Irish keyboard as its only input method
    $desired = New-WinUserLanguageList -Language $LanguageTag
    $desired[0].InputMethodTips.Clear()
    $desired[0].InputMethodTips.Add($InputTip)

    # Preserve additional languages the user has added; drop en-US
    Get-WinUserLanguageList |
        Where-Object { $_.LanguageTag -ne $LanguageTag -and $_.LanguageTag -notin $RemoveTags } |
        ForEach-Object { [void]$desired.Add($_) }

    Set-WinUserLanguageList -LanguageList $desired -Force
    Set-WinDefaultInputMethodOverride -InputTip $InputTip
    Set-Culture -CultureInfo $LanguageTag
    Set-WinHomeLocation -GeoId $GeoId

    Write-Output 'Remediated: user international settings set to en-IE (fully applied at next sign-in)'
    exit 0
}
catch {
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
