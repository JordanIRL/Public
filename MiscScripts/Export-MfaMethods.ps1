
[CmdletBinding()]
param(
    [string]$OutputPath
)

$RequiredScope = 'AuditLog.Read.All'
$ReportUri     = 'https://graph.microsoft.com/v1.0/reports/authenticationMethods/userRegistrationDetails'

$MethodColumns = [ordered]@{
    'Passkey (Authenticator)'      = @('passKeyDeviceBoundAuthenticator')
    'Authenticator (Push)'         = @('microsoftAuthenticatorPush')
    'Authenticator (Passwordless)' = @('microsoftAuthenticatorPasswordless')
    'FIDO2 (Yubi)'                 = @('fido2SecurityKey')
    'Passkey (Device-bound)'       = @('passKeyDeviceBound')
    'Phone'                        = @('mobilePhone', 'alternateMobilePhone', 'officePhone')
}

$ctx = Get-MgContext
if (-not $ctx) {
    Connect-MgGraph -Scopes $RequiredScope -NoWelcome -ErrorAction Stop
    $ctx = Get-MgContext
}
if (-not $ctx) { throw 'Not connected to Microsoft Graph.' }
# Delegated sessions expose granted scopes; app-only sessions don't, so only warn.
if ($ctx.Scopes -and ($ctx.Scopes -notcontains $RequiredScope)) {
    Write-Warning "Current Graph session does not list $RequiredScope; the report query may fail."
}
function Invoke-GraphRead {
    param([Parameter(Mandatory)][string]$Uri)

    $maxAttempts = 5
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        try {
            return Invoke-MgGraphRequest -Method GET -Uri $Uri -OutputType PSObject -ErrorAction Stop
        }
        catch {
            $status = $null
            try { $status = [int]$_.Exception.Response.StatusCode } catch { }
            $msg = "$($_.Exception.Message) $($_.ErrorDetails.Message)"
            $transient = if ($status) { $status -in 429, 500, 502, 503, 504 }
                         else { $msg -match 'throttl|timed? ?out|temporarily|429|500|502|503|504' }
            if (-not $transient -or $attempt -eq $maxAttempts) { throw }

            $delay = $null
            try { $delay = [int]$_.Exception.Response.Headers.RetryAfter.Delta.TotalSeconds } catch { }
            if (-not $delay -or $delay -le 0) { $delay = [int][math]::Min(60, [math]::Pow(2, $attempt)) }
            Write-Verbose "Transient Graph error (status=$status); retry $attempt/$maxAttempts in ${delay}s."
            Start-Sleep -Seconds $delay
        }
    }
}

$records = [System.Collections.Generic.List[object]]::new()
$uri     = $ReportUri
$page    = 0
while ($uri) {
    $resp = Invoke-GraphRead -Uri $uri
    foreach ($u in $resp.value) { $records.Add($u) }
    $page++
    Write-Progress -Activity 'Exporting MFA registration details' `
                   -Status "$($records.Count) users" -CurrentOperation "Page $page"
    $uri = $resp.'@odata.nextLink'
}
Write-Progress -Activity 'Exporting MFA registration details' -Completed

$rows = foreach ($u in $records) {
    $registered = @($u.methodsRegistered)
    $row = [ordered]@{
        'User Principal Name' = $u.userPrincipalName
        'Display Name'        = $u.userDisplayName
        'User Type'           = $u.userType
        'Admin'               = $u.isAdmin
        'Preferred Method'    = (@($u.systemPreferredAuthenticationMethods) -join '; ')
    }
    foreach ($col in $MethodColumns.GetEnumerator()) {
        $row[$col.Key] = if ($col.Value | Where-Object { $registered -contains $_ }) { 'Y' } else { '' }
    }
    $row['Last Updated'] = $u.lastUpdatedDateTime
    [pscustomobject]$row
}

if (-not $OutputPath) {
    $exportDir = Join-Path $PSScriptRoot 'Exports'
    if (-not (Test-Path $exportDir)) { New-Item -ItemType Directory -Path $exportDir -Force | Out-Null }
    $stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputPath = Join-Path $exportDir "MfaMethods-$stamp.csv"
}
$rows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

$mfaRegistered = @($records | Where-Object { $_.isMfaRegistered }).Count
Write-Host "Exported $($rows.Count) users to $OutputPath"
Write-Host "MFA registered: $mfaRegistered / $($rows.Count)"
