<#
.SYNOPSIS
    Deactivate all active (PIM-activated) Microsoft Entra roles.

.EXAMPLE
    .\Disable-PIMRoles.ps1
#>

Connect-MgGraph -Scopes 'RoleAssignmentSchedule.ReadWrite.Directory', 'User.Read' -NoWelcome

$myId = (Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me').id

$active = Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance -Filter "principalId eq '$myId'" -ExpandProperty 'roleDefinition' -All

foreach ($assignment in $active) {
    if ($assignment.AssignmentType -ne 'Activated') { continue }

    $role = $assignment.RoleDefinition.DisplayName

    $params = @{
        Action           = 'SelfDeactivate'
        PrincipalId      = $myId
        RoleDefinitionId = $assignment.RoleDefinitionId
        DirectoryScopeId = $assignment.DirectoryScopeId
    }

    try {
        New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -BodyParameter $params -ErrorAction Stop | Out-Null
        Write-Host "Deactivated: $role" -ForegroundColor Green
    } catch {
        Write-Host "Failed: $role - $($_.Exception.Message)" -ForegroundColor Red
    }
}
