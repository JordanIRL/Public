#Requires -Version 7.0
#Requires -Modules @{ ModuleName="Microsoft.Graph.Beta"; ModuleVersion="2.0.0" }
<#
.SYNOPSIS
    Report Overlapping Commercial Licenses
.DESCRIPTION
    Retrieves users with multiple assigned commercial licenses and cross-references their underlying service plans to detect overlaps or redundancies. 
.REQUIREMENTS
    - PowerShell 7+
    - Module: Microsoft.Graph.Beta
.PERMISSIONS
    Delegated: User.Read.All, Organization.Read.All
#>

# Connect to Microsoft Graph Beta with minimum required scopes
Connect-MgGraph -Scopes "User.Read.All", "Organization.Read.All"

# Retrieve all subscribed SKUs
$allSkus = Get-MgBetaSubscribedSku -Property "id,skuId,skuPartNumber,servicePlans" -All

# Filter for commercial paid SKUs, excluding A-series (Education), Faculty, Student, and common free/trial identifiers
$commercialSkus = $allSkus | Where-Object {
    $_.SkuPartNumber -notmatch '(?i)_A\d+_' -and
    $_.SkuPartNumber -notmatch '(?i)FACULTY|STUDENT|ALUMNI|TRIAL|FREE'
}

# Build a lookup dictionary for fast reference and cross-referencing
$skuDict = @{}
foreach ($sku in $commercialSkus) {
    $skuDict[$sku.SkuId] = $sku
}

# Retrieve all users who have at least one license assigned
# Advanced query requires ConsistencyLevel = eventual to filter by assignedLicenses
$users = Get-MgBetaUser -Filter "assignedLicenses/any(s:s/skuId ne null)" -ConsistencyLevel eventual -Property "id,displayName,userPrincipalName,assignedLicenses" -All

# Analyze users for overlapping service plans
$results = foreach ($user in $users) {
    # Only evaluate licenses that match our commercial SKU dictionary
    $validAssignedSkus = $user.AssignedLicenses | Where-Object { $skuDict.ContainsKey($_.SkuId) }

    # Redundancy requires at least 2 commercial SKUs
    if ($validAssignedSkus.Count -lt 2) {
        continue
    }

    $allServicePlans = [System.Collections.Generic.List[PSCustomObject]]::new()
    $assignedSkuNames = [System.Collections.Generic.List[string]]::new()

    foreach ($assignedSku in $validAssignedSkus) {
        $skuDetails = $skuDict[$assignedSku.SkuId]
        $assignedSkuNames.Add($skuDetails.SkuPartNumber)

        foreach ($plan in $skuDetails.ServicePlans) {
            $allServicePlans.Add([PSCustomObject]@{
                ServicePlanId   = $plan.ServicePlanId
                ServicePlanName = $plan.ServicePlanName
                SourceSku       = $skuDetails.SkuPartNumber
            })
        }
    }

    # Group by ServicePlanId to find overlaps
    $overlaps = $allServicePlans | Group-Object -Property ServicePlanId | Where-Object Count -gt 1

    if ($overlaps.Count -gt 0) {
        $overlappingServices = foreach ($overlap in $overlaps) {
            $sources = ($overlap.Group | Select-Object -ExpandProperty SourceSku) -join " & "
            "$($overlap.Group[0].ServicePlanName) ($sources)"
        }

        [PSCustomObject]@{
            UserPrincipalName   = $user.UserPrincipalName
            DisplayName         = $user.DisplayName
            AssignedPaidSKUs    = $assignedSkuNames -join ", "
            OverlappingServices = $overlappingServices -join " | "
        }
    }
}

# Output structured objects to the pipeline
$results