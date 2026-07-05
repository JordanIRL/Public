<#
.SYNOPSIS
    Remediation - machine-wide international settings (English (Ireland)).

.DESCRIPTION
    Sets the system locale to en-IE, configures the SYSTEM account's
    international settings, then copies those settings to the welcome
    screen / system accounts and to the default profile inherited by new
    user accounts. The system locale takes effect after the next restart;
    no restart is forced. Requires Windows 11
    (Copy-UserInternationalSettingsToSystem).

    Intune remediation deployment settings:
        Run this script using the logged-on credentials : No (SYSTEM)
        Enforce script signature check                  : No
        Run script in 64-bit PowerShell                 : Yes
#>

$LanguageTag = 'en-IE'
$GeoId       = 68                 # Ireland
$InputTip    = '1809:00001809'    # English (Ireland) + Irish keyboard

try {
    # System locale (non-Unicode programs) - applied after next restart
    Set-WinSystemLocale -SystemLocale $LanguageTag

    # Configure the SYSTEM account's own international settings...
    $list = New-WinUserLanguageList -Language $LanguageTag
    $list[0].InputMethodTips.Clear()
    $list[0].InputMethodTips.Add($InputTip)
    Set-WinUserLanguageList -LanguageList $list -Force
    Set-WinDefaultInputMethodOverride -InputTip $InputTip
    Set-Culture -CultureInfo $LanguageTag
    Set-WinHomeLocation -GeoId $GeoId

    # ...then propagate them to the welcome screen / system accounts and
    # to the default profile used for new user accounts
    Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true

    Write-Output 'Remediated: system locale, welcome screen and new-user defaults set to en-IE (system locale applies after restart)'
    exit 0
}
catch {
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
