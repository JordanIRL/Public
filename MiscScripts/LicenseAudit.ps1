Connect-MgGraph -Scopes User.Read.All, Directory.Read.All, Organization.Read.All, AuditLog.Read.All

$skus = Get-MgSubscribedSku -All

$users = Get-MgUser -All `
  -Filter 'assignedLicenses/$count ne 0' -ConsistencyLevel eventual -CountVariable licensedCount `
  -Property Id,DisplayName,UserPrincipalName,Department,JobTitle,AccountEnabled,AssignedLicenses,AssignedPlans,SignInActivity

$report = foreach ($u in $users) {
    $licenseNames = foreach ($lic in $u.AssignedLicenses) {
        ($skus | Where-Object SkuId -eq $lic.SkuId).SkuPartNumber
    }

    [pscustomobject]@{
        DisplayName       = $u.DisplayName
        UserPrincipalName = $u.UserPrincipalName
        Department        = $u.Department
        JobTitle          = $u.JobTitle
        AccountEnabled    = $u.AccountEnabled
        LastSignIn        = $u.SignInActivity.LastSignInDateTime
        Licenses          = ($licenseNames -join ";")
        LicenseCount      = @($licenseNames).Count
    }
}

$report | Export-Csv ".\entra-license-audit.csv" -NoTypeInformation