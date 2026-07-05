<#
.SYNOPSIS
    Detection - per-user international settings (English (Ireland)).

.DESCRIPTION
    Verifies the signed-in user's regional format, home location, preferred
    language list, keyboard layout and default input override against the
    en-IE standard. Pairs with Remediate-UserIntlSettings-enIE.ps1.

    Intune remediation deployment settings:
        Run this script using the logged-on credentials : Yes
        Enforce script signature check                  : No
        Run script in 64-bit PowerShell                 : Yes

    Exit 0 = compliant. Exit 1 = remediation required.
#>

$LanguageTag = 'en-IE'
$GeoId       = 68                 # Ireland
$InputTip    = '1809:00001809'    # English (Ireland) + Irish keyboard
$BlockedTag  = 'en-US'

try {
    $issues = [System.Collections.Generic.List[string]]::new()

    $culture = (Get-Culture).Name
    if ($culture -ne $LanguageTag) { $issues.Add("RegionalFormat=$culture") }

    $geo = (Get-WinHomeLocation).GeoId
    if ($geo -ne $GeoId) { $issues.Add("HomeLocation=$geo") }

    $langList = Get-WinUserLanguageList

    if ($langList[0].LanguageTag -ne $LanguageTag) {
        $issues.Add("PrimaryLanguage=$($langList[0].LanguageTag)")
    }

    if ($langList.LanguageTag -contains $BlockedTag) {
        $issues.Add("LanguageListContains=$BlockedTag")
    }

    $enIE = $langList | Where-Object { $_.LanguageTag -eq $LanguageTag }
    if (-not $enIE -or $enIE.InputMethodTips -notcontains $InputTip) {
        $issues.Add('IrishKeyboardMissing')
    }

    $override = Get-WinDefaultInputMethodOverride
    if ($override -and $override.InputMethodTip -ne $InputTip) {
        $issues.Add("InputOverride=$($override.InputMethodTip)")
    }

    if ($issues.Count -gt 0) {
        Write-Output ('Non-compliant: ' + ($issues -join '; '))
        exit 1
    }

    Write-Output 'Compliant: user international settings are en-IE'
    exit 0
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}
