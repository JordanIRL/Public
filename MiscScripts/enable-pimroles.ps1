Connect-MgGraph -Scopes 'RoleEligibilitySchedule.Read.Directory', 'RoleAssignmentSchedule.ReadWrite.Directory', 'User.Read' -NoWelcome

$myId = (Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me').id

$eligible = Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance -Filter "principalId eq '$myId'" -ExpandProperty 'roleDefinition' -All

foreach ($assignment in $eligible) {
    $role = $assignment.RoleDefinition.DisplayName

    $params = @{
        Action           = 'SelfActivate'
        PrincipalId      = $myId
        RoleDefinitionId = $assignment.RoleDefinitionId
        DirectoryScopeId = $assignment.DirectoryScopeId
        Justification    = 'Required for role'
        ScheduleInfo     = @{
            StartDateTime = Get-Date
            Expiration    = @{ Type = 'AfterDuration'; Duration = 'PT8H' }
        }
    }

    try {
        New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -BodyParameter $params -ErrorAction Stop | Out-Null
        Write-Host "Activated: $role" -ForegroundColor Green
    } catch {
        Write-Host "Failed: $role - $($_.Exception.Message)" -ForegroundColor Red
    }
}