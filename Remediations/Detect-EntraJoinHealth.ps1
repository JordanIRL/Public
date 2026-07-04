# Runs as SYSTEM. Non-compliant when the device's Entra join state is broken.
# Defaults expect a pure Entra join. Flip $ExpectHybrid for hybrid-joined fleets.

$ExpectHybrid      = $false
$ExpectedTenantId  = $null   # optional — e.g. 'contoso.onmicrosoft.com' or a tenant GUID

try {
    $raw   = & dsregcmd /status 2>&1
    $state = @{}
    foreach ($line in $raw) {
        if ($line -match '^\s+([A-Za-z]+)\s+:\s+(.+)$') {
            $state[$Matches[1]] = $Matches[2].Trim()
        }
    }

    $issues = @()

    if ($state.AzureAdJoined -ne 'YES') {
        $issues += "AzureAdJoined=$($state.AzureAdJoined)"
    }
    if ($state.WorkplaceJoined -eq 'YES') {
        $issues += "WorkplaceJoined=YES (personal MSA registration present)"
    }
    $expectedDJ = if ($ExpectHybrid) { 'YES' } else { 'NO' }
    if ($state.DomainJoined -and $state.DomainJoined -ne $expectedDJ) {
        $issues += "DomainJoined=$($state.DomainJoined) (expected $expectedDJ)"
    }
    if ($state.DeviceAuthStatus -and $state.DeviceAuthStatus -ne 'SUCCESS') {
        $issues += "DeviceAuthStatus=$($state.DeviceAuthStatus)"
    }
    if ($state.KeySignTest -and $state.KeySignTest -ne 'PASSED') {
        $issues += "KeySignTest=$($state.KeySignTest)"
    }
    if ($ExpectedTenantId) {
        $tenant = "$($state.TenantId) $($state.TenantName)"
        if ($tenant -notmatch [regex]::Escape($ExpectedTenantId)) {
            $issues += "Tenant mismatch (got $tenant)"
        }
    }

    if ($issues) {
        Write-Output ("Entra join issues: " + ($issues -join '; '))
        exit 1
    }

    Write-Output "Entra join healthy (AzureAdJoined=YES, DeviceAuth=SUCCESS, KeySign=PASSED)."
    exit 0
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}
