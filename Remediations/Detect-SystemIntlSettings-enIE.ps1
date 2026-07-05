<#
.SYNOPSIS
    Detection - machine-wide international settings (English (Ireland)).

.DESCRIPTION
    Verifies the system locale and the welcome screen / system account
    defaults against the en-IE standard. Pairs with
    Remediate-SystemIntlSettings-enIE.ps1.

    Intune remediation deployment settings:
        Run this script using the logged-on credentials : No (SYSTEM)
        Enforce script signature check                  : No
        Run script in 64-bit PowerShell                 : Yes

    Exit 0 = compliant. Exit 1 = remediation required.
#>

$LanguageTag = 'en-IE'
$GeoNation   = '68'    # Ireland

try {
    $issues = [System.Collections.Generic.List[string]]::new()

    $sysLocale = (Get-WinSystemLocale).Name
    if ($sysLocale -ne $LanguageTag) { $issues.Add("SystemLocale=$sysLocale") }

    $intlKey = 'Registry::HKEY_USERS\.DEFAULT\Control Panel\International'

    $welcomeLocale = (Get-ItemProperty -Path $intlKey -Name LocaleName -ErrorAction Stop).LocaleName
    if ($welcomeLocale -ne $LanguageTag) { $issues.Add("WelcomeScreenLocale=$welcomeLocale") }

    $welcomeNation = (Get-ItemProperty -Path "$intlKey\Geo" -Name Nation -ErrorAction SilentlyContinue).Nation
    if ($welcomeNation -ne $GeoNation) { $issues.Add("WelcomeScreenGeoId=$welcomeNation") }

    if ($issues.Count -gt 0) {
        Write-Output ('Non-compliant: ' + ($issues -join '; '))
        exit 1
    }

    Write-Output 'Compliant: system locale and welcome screen defaults are en-IE'
    exit 0
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}
