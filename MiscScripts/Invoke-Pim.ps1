# Bulk activate/deactivate your PIM-eligible Entra ID directory roles.

foreach ($m in 'Microsoft.Graph.Authentication','Microsoft.Graph.Identity.Governance') {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        Install-Module $m -Scope CurrentUser -Force -AllowClobber -EA Stop
    }
    Import-Module $m -EA Stop
}

$scopes = 'RoleManagement.ReadWrite.Directory','User.Read'
$ctx = Get-MgContext
if (-not $ctx -or ($scopes | ? { $_ -notin $ctx.Scopes })) {
    if ($ctx) { Disconnect-MgGraph -EA SilentlyContinue | Out-Null }
    Connect-MgGraph -Scopes $scopes -NoWelcome | Out-Null
}

$me  = Invoke-MgGraphRequest GET 'https://graph.microsoft.com/v1.0/me?$select=id,displayName,userPrincipalName'
$uri = 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleRequests'

function Roles($cmd, $activeOnly = $false) {
    $r = & $cmd -Filter "principalId eq '$($me.id)'" -ExpandProperty RoleDefinition -All -EA Stop
    if ($activeOnly) { $r = $r | ? { $_.AssignmentType -eq 'Activated' } }
    $r | Sort-Object { $_.RoleDefinition.DisplayName }
}

function Err($e) {
    $srcs = @($e.ErrorDetails.Message, $e.Exception.Message)
    for ($ex = $e.Exception; $ex; $ex = $ex.InnerException) {
        try { $srcs += $ex.Response.Content.ReadAsStringAsync().GetAwaiter().GetResult() } catch {}
    }
    foreach ($t in $srcs) {
        if (-not $t) { continue }
        $i = $t.IndexOf('{'); if ($i -lt 0) { continue }
        try {
            $p = $t.Substring($i) | ConvertFrom-Json -EA Stop
            if ($p.error) { return "[$($p.error.code)] $($p.error.message)" }
        } catch {}
    }
    $e.Exception.Message
}

function Send-Pim($action, $role, $hours = 0) {
    $body = @{
        action           = $action
        principalId      = $me.id
        roleDefinitionId = $role.RoleDefinition.Id
        directoryScopeId = $role.DirectoryScopeId
        justification    = 'Required for role.'
    }
    if ($hours) {
        $body.scheduleInfo = @{
            startDateTime = (Get-Date).ToUniversalTime().ToString('o')
            expiration    = @{ type = 'AfterDuration'; duration = "PT${hours}H" }
        }
    }
    Invoke-MgGraphRequest POST $uri -Body ($body | ConvertTo-Json -Depth 5) -ContentType 'application/json' -EA Stop
}

function Pick($list) {
    (Read-Host 'Numbers (comma/space)') -split '[,\s]+' |
        ? { $_ -match '^\d+$' } | % { [int]$_ - 1 } |
        ? { $_ -ge 0 -and $_ -lt $list.Count } | % { $list[$_] }
}

function Show($list, $label, $color, $activeIds = $null) {
    Write-Host "${label}:" -ForegroundColor $color
    if (-not $list.Count) { Write-Host '  (none)' -ForegroundColor DarkGray; return }
    $i = 0
    foreach ($r in $list) {
        $i++
        $tag = if ($activeIds -and $activeIds[$r.RoleDefinition.Id]) { ' [active]' } else { '' }
        Write-Host ('  {0,2}. {1}{2}' -f $i, $r.RoleDefinition.DisplayName, $tag)
    }
}

Write-Host "Signed in as $($me.userPrincipalName)" -ForegroundColor Cyan

while ($true) {
    $el = @(Roles Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance)
    $ac = @(Roles Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance $true)
    $acIds = @{}; $ac | % { $acIds[$_.RoleDefinitionId] = $true }

    Write-Host ''
    Show $el 'Eligible' Yellow $acIds
    if ($ac.Count) { Show $ac 'Active (PIM)' Green }

    $choice = (Read-Host "`n[a]ctivate [d]eactivate [r]efresh [q]uit").ToLower()
    if ($choice -eq 'q') { return }
    if ($choice -notin 'a','d') { continue }

    $isAct = $choice -eq 'a'
    $picks = @(Pick $(if ($isAct) { $el } else { $ac }))
    if (-not $picks.Count) { continue }

    $hours = 0
    if ($isAct) {
        $raw = Read-Host 'Hours (1-8, default 8)'
        $hours = if ($raw -match '^\d+$') { [Math]::Max(1, [Math]::Min(8, [int]$raw)) } else { 8 }
    }

    $act  = if ($isAct) { 'selfActivate' } else { 'selfDeactivate' }
    $verb = if ($isAct) { 'Activating' }   else { 'Deactivating' }
    foreach ($r in $picks) {
        Write-Host "  $verb $($r.RoleDefinition.DisplayName)..." -NoNewline
        try   { Send-Pim $act $r $hours | Out-Null; Write-Host ' OK' -ForegroundColor Green }
        catch { Write-Host " FAIL $(Err $_)" -ForegroundColor Red }
    }
}
