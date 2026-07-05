<#
.SYNOPSIS
    Exports your Microsoft Intune configuration to a JSON snapshot for the Intune Documentation
    Builder — with NO app registration and NO client secret.

.DESCRIPTION
    Uses the Microsoft Graph PowerShell SDK, which signs in through Microsoft's own well-known public
    client application ("Microsoft Graph Command Line Tools", appId 14d82eec-204b-4c2f-b7e8-296a70dab67e).
    You are NOT registering an app and NOT creating a secret — you simply sign in interactively, and an
    Intune/Global administrator consents once per tenant to read-only access.

    The access token never leaves this machine. The script writes a plain JSON file that you then drag
    into the web app (Import from tenant). The web app stays fully offline.

    It exports device configuration (Settings Catalog + template) and compliance policies, and also
    resolves each policy's assignment groups and scope tags to names so the generated document fills in
    "Assigned groups" and "Scope tags" for you.

    Built for enterprise scale: every list is fully paged, collections use O(1)-append lists, transient
    throttling (HTTP 429/5xx) is retried with Retry-After / exponential backoff, and assignment group
    names are resolved in bulk via directoryObjects/getByIds (up to 1000 ids per request) instead of one
    call per group — so it stays fast against tenants with thousands of groups and policies.

.PARAMETER OutFile
    Output path. Defaults to intune-tenant-export.json in the current directory.

.PARAMETER TenantId
    Optional tenant id/domain to sign in to (useful for guests/multi-tenant accounts).

.PARAMETER SkipAssignments
    Don't resolve assignment group names. Requests only DeviceManagementConfiguration.Read.All
    (skips the Group.Read.All consent).

.PARAMETER InstallModule
    Install the Microsoft.Graph.Authentication module for the current user if it's missing.

.NOTES
    Requires PowerShell 7+ recommended (for fast, lossless ConvertTo-Json of large tenants).

.EXAMPLE
    ./Export-IntuneTenant.ps1
    ./Export-IntuneTenant.ps1 -OutFile C:\temp\intune.json -TenantId contoso.onmicrosoft.com
    ./Export-IntuneTenant.ps1 -SkipAssignments
#>
[CmdletBinding()]
param(
    [string]$OutFile = "intune-tenant-export.json",
    [string]$TenantId,
    [switch]$SkipAssignments,
    [switch]$InstallModule
)

$ErrorActionPreference = "Stop"
$ScriptVersion = "1.2.0"

# --- module -------------------------------------------------------------------------------------
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    if ($InstallModule) {
        Write-Host "Installing Microsoft.Graph.Authentication for the current user..."
        Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force -AllowClobber
    } else {
        Write-Error "Microsoft.Graph.Authentication is not installed. Run: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser   (or re-run with -InstallModule)"
        return
    }
}
Import-Module Microsoft.Graph.Authentication

# --- sign in (no app registration) --------------------------------------------------------------
$scopes = @("DeviceManagementConfiguration.Read.All")
if (-not $SkipAssignments) { $scopes += "Group.Read.All" }

$connectArgs = @{ Scopes = $scopes; NoWelcome = $true }
if ($TenantId) { $connectArgs["TenantId"] = $TenantId }

try {
    Connect-MgGraph @connectArgs
} catch {
    Write-Error "Sign-in failed: $($_.Exception.Message)"
    return
}

$context = Get-MgContext
Write-Host "Signed in as $($context.Account) (tenant $($context.TenantId))." -ForegroundColor Green

$beta = "https://graph.microsoft.com/beta/deviceManagement"
$v1 = "https://graph.microsoft.com/v1.0"

# --- transient-error retry (throttling + 5xx) ---------------------------------------------------
function Get-GraphErrorStatus {
    param($ErrorRecord)
    try {
        if ($ErrorRecord.Exception.Response -and $null -ne $ErrorRecord.Exception.Response.StatusCode) {
            return [int]$ErrorRecord.Exception.Response.StatusCode
        }
    } catch { }
    $message = "$($ErrorRecord.Exception.Message)"
    $match = [regex]::Match($message, '\b(429|500|502|503|504)\b')
    if ($match.Success) { return [int]$match.Value }
    if ($message -match 'TooManyRequests|throttl|temporarily unavailable|timed out|timeout') { return 429 }
    return 0
}

function Invoke-GraphRequestWithRetry {
    param(
        [Parameter(Mandatory)] [string]$Uri,
        [string]$Method = "GET",
        [string]$Body,
        [int]$MaxRetries = 6
    )
    $attempt = 0
    while ($true) {
        try {
            if ($Body) {
                return Invoke-MgGraphRequest -Method $Method -Uri $Uri -Body $Body -ContentType "application/json"
            }
            return Invoke-MgGraphRequest -Method $Method -Uri $Uri
        } catch {
            $status = Get-GraphErrorStatus $_
            $retryable = $status -in 429, 500, 502, 503, 504
            $attempt++
            if (-not $retryable -or $attempt -gt $MaxRetries) { throw }

            $delay = [Math]::Min(60, [Math]::Pow(2, $attempt))
            try {
                $retryAfter = $_.Exception.Response.Headers.RetryAfter.Delta.TotalSeconds
                if ($retryAfter -and $retryAfter -gt 0) { $delay = [Math]::Min(120, $retryAfter) }
            } catch { }
            Write-Warning "Transient error (HTTP $status). Retry $attempt/$MaxRetries in $([int]$delay)s..."
            Start-Sleep -Seconds ([int]$delay)
        }
    }
}

# --- paged collection reader (O(1) append, fully paginated) -------------------------------------
function Get-GraphCollection {
    param([Parameter(Mandatory)] [string]$Uri)
    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    do {
        $response = Invoke-GraphRequestWithRetry -Uri $next
        if ($null -ne $response.value) { $items.AddRange([object[]]@($response.value)) }
        $next = $response.'@odata.nextLink'
    } while ($next)
    # Comma forces an array even for a single item, so the JSON shape stays consistent.
    return ,$items.ToArray()
}

# --- bulk group-name resolution (getByIds, up to 1000 ids/request) ------------------------------
function Resolve-GroupNames {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]]$Ids)
    $resolved = [System.Collections.Generic.List[object]]::new()
    $unique = @($Ids | Select-Object -Unique)
    for ($i = 0; $i -lt $unique.Count; $i += 1000) {
        $chunk = $unique[$i..([Math]::Min($i + 999, $unique.Count - 1))]
        $body = @{ ids = @($chunk); types = @("group") } | ConvertTo-Json -Depth 4
        try {
            $response = Invoke-GraphRequestWithRetry -Method POST -Uri "$v1/directoryObjects/getByIds" -Body $body
            foreach ($group in @($response.value)) {
                if ($group.id) { $resolved.Add([ordered]@{ id = $group.id; displayName = $group.displayName }) }
            }
        } catch {
            Write-Warning "Could not resolve a batch of group names ($($_.Exception.Message)); those groups will show as ids."
        }
    }
    return ,$resolved.ToArray()
}

# --- policies (with assignments expanded) -------------------------------------------------------
Write-Host "Reading Settings Catalog policies (device configuration)..."
$configurationPolicies = Get-GraphCollection "$beta/configurationPolicies?`$expand=settings,assignments&`$top=100"
Write-Host "  $($configurationPolicies.Count) found."

Write-Host "Reading template device configurations..."
$deviceConfigurations = Get-GraphCollection "$beta/deviceConfigurations?`$expand=assignments&`$top=100"
Write-Host "  $($deviceConfigurations.Count) found."

Write-Host "Reading compliance policies..."
$deviceCompliancePolicies = Get-GraphCollection "$beta/deviceCompliancePolicies?`$expand=assignments&`$top=100"
Write-Host "  $($deviceCompliancePolicies.Count) found."

$allPolicies = @($configurationPolicies) + @($deviceConfigurations) + @($deviceCompliancePolicies)

# --- scope tags (id -> name), best effort -------------------------------------------------------
$roleScopeTags = @()
try {
    $roleScopeTags = Get-GraphCollection "$beta/roleScopeTags?`$select=id,displayName"
} catch {
    Write-Warning "Could not read scope tags ($($_.Exception.Message)); scope-tag names will be omitted."
}

# --- assignment group names (id -> name) in bulk, best effort -----------------------------------
$groups = @()
if (-not $SkipAssignments) {
    $groupIds = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($policy in $allPolicies) {
        foreach ($assignment in @($policy.assignments)) {
            $gid = $assignment.target.groupId
            if ($gid) { [void]$groupIds.Add([string]$gid) }
        }
    }
    $ids = @($groupIds)
    if ($ids.Count -gt 0) {
        Write-Host "Resolving $($ids.Count) assignment group name(s) in bulk..."
        $groups = Resolve-GroupNames -Ids $ids
        Write-Host "Resolved $(@($groups).Count) of $($ids.Count) group name(s)."
    }
}

# --- write the snapshot -------------------------------------------------------------------------
$snapshot = [ordered]@{
    exportedAt               = (Get-Date).ToString("o")
    source                   = "powershell"
    scriptVersion            = $ScriptVersion
    tenantId                 = $context.TenantId
    configurationPolicies    = $configurationPolicies
    deviceConfigurations     = $deviceConfigurations
    deviceCompliancePolicies = $deviceCompliancePolicies
    roleScopeTags            = $roleScopeTags
    groups                   = $groups
}

# Depth 60 captures the nested Settings Catalog setting-instance trees.
$snapshot | ConvertTo-Json -Depth 60 | Out-File -FilePath $OutFile -Encoding utf8

Disconnect-MgGraph | Out-Null

$total = $allPolicies.Count
Write-Host ""
Write-Host "Wrote $OutFile ($total policies)." -ForegroundColor Green
Write-Host "Now open the Intune Documentation Builder -> Import from tenant, and drop in this file."
