<#
.SYNOPSIS
    Pulls fingerprint output back from Intune and parses it into columns.

.DESCRIPTION
    Read-only. Reads deviceRunStates for a remediation package, takes
    preRemediationDetectionScriptOutput from each device, parses the pipe-delimited
    fingerprint into flat columns, and writes CSV.

    This is what turns one-off triage into fleet data: once a few dozen devices have
    reported, you can sort by THRU_s1 and find every laptop with the same fault before
    anyone opens a ticket.

    Devices reporting 'TRUNC' hit the 2048-character output cap and their VERDICT line
    was lost - those rows are flagged rather than silently misparsed.

.NOTES
    Graph permission : DeviceManagementConfiguration.Read.All
    Module           : Microsoft.Graph.Authentication
    API              : /beta/deviceManagement/deviceHealthScripts/{id}/deviceRunStates

.EXAMPLE
    ./Get-RemediationResults.ps1 -PackageName 'Network Triage - Fingerprint (SYSTEM)'
    ./Get-RemediationResults.ps1 -PackageName '...' -OutFile ./triage.csv
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $PackageName,
    [string] $OutFile
)

$ErrorActionPreference = 'Stop'
Import-Module Microsoft.Graph.Authentication

if (-not (Get-MgContext)) {
    Connect-MgGraph -Scopes 'DeviceManagementConfiguration.Read.All' -NoWelcome
}

$base = 'https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts'
$pkg  = (Invoke-MgGraphRequest -Method GET -Uri "$base`?`$select=id,displayName").value |
            Where-Object displayName -eq $PackageName
if (-not $pkg) { throw "Package not found: $PackageName" }

$states = @()
$uri = "$base/$($pkg.id)/deviceRunStates?`$expand=managedDevice(`$select=deviceName,userPrincipalName,model)"
while ($uri) {
    $page   = Invoke-MgGraphRequest -Method GET -Uri $uri
    $states += $page.value
    $uri     = $page.'@odata.nextLink'
}

$rows = foreach ($s in $states) {
    $row = [ordered]@{
        Device    = $s.managedDevice.deviceName
        User      = $s.managedDevice.userPrincipalName
        Model     = $s.managedDevice.model
        Detection = $s.detectionState
        Updated   = $s.lastStateUpdateDateTime
        Truncated = $false
    }

    # Fingerprint lines look like:  KEY|k=v|k=v   (and  VERDICT|NAME|conf=x)
    foreach ($line in ($s.preRemediationDetectionScriptOutput -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split '\|'
        $key   = $parts[0].Trim()
        if ($key -eq 'TRUNC') { $row.Truncated = $true; continue }
        if ($key -eq 'VERDICT') {
            $row.VERDICT = $parts[1]
            $row.Confidence = ($parts[2] -replace '^conf=', '')
            continue
        }
        foreach ($p in $parts[1..($parts.Count - 1)]) {
            if ($p -match '^([^=]+)=(.*)$') { $row["${key}_$($Matches[1])"] = $Matches[2] }
        }
    }
    [pscustomobject]$row
}

if ($OutFile) {
    $rows | Export-Csv -Path $OutFile -NoTypeInformation -Encoding UTF8
    Write-Host "wrote $($rows.Count) rows -> $OutFile" -ForegroundColor Green
} else {
    $rows | Select-Object Device, User, VERDICT, Confidence, THRU_s1, THRU_ratio, TCP_autotune, Truncated |
        Format-Table -AutoSize
}

$trunc = @($rows | Where-Object Truncated)
if ($trunc) {
    Write-Warning "$($trunc.Count) device(s) hit the 2048-char output cap; VERDICT lost: $($trunc.Device -join ', ')"
}
