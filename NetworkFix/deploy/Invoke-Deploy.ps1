<#
.SYNOPSIS
    Creates or updates Intune Remediation script packages from deploy/packages.json.

.DESCRIPTION
    Idempotent: matches existing packages on displayName, PATCHes if present, POSTs if not.
    Re-running after editing a .ps1 pushes the new content to the same package.

    ASSUMPTION STATED UP FRONT: this script does NOT assign packages to any group.
    Creating a package is inert; assigning one is what makes it execute on real devices.
    Assignment shape is left to the portal deliberately, so that a scripting mistake here
    can never run 'Network Fix - Stack Reset' against the fleet. Assign in:
      Devices > Scripts and remediations > <package> > Assignments

    Uses Invoke-MgGraphRequest against /beta so only Microsoft.Graph.Authentication is
    needed - not the multi-gigabyte Microsoft.Graph.Beta module.

.PARAMETER WhatIf
    Supported. Run it first - it prints the create/update plan and touches nothing.

.NOTES
    Graph permission : DeviceManagementConfiguration.ReadWrite.All
    Module           : Microsoft.Graph.Authentication
    API              : /beta/deviceManagement/deviceHealthScripts

.EXAMPLE
    ./Invoke-Deploy.ps1 -WhatIf
    ./Invoke-Deploy.ps1
    ./Invoke-Deploy.ps1 -Name 'Network Fix - TCP Autotuning'
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]   $ManifestPath = (Join-Path $PSScriptRoot 'packages.json'),
    [string]   $RootPath     = (Split-Path $PSScriptRoot -Parent),
    [string[]] $Name,
    [string[]] $RoleScopeTagIds = @('0')
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable Microsoft.Graph.Authentication)) {
    throw 'Microsoft.Graph.Authentication is not installed. Install-Module Microsoft.Graph.Authentication -Scope CurrentUser'
}
Import-Module Microsoft.Graph.Authentication

if (-not (Get-MgContext)) {
    Connect-MgGraph -Scopes 'DeviceManagementConfiguration.ReadWrite.All' -NoWelcome
}

$manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
$base     = 'https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts'

function Get-ScriptB64 {
    param([string] $RelativePath)
    $full = Join-Path $RootPath $RelativePath
    if (-not (Test-Path $full)) { throw "Script not found: $full" }
    # UTF-8 WITHOUT BOM. A BOM breaks Intune's signature check path.
    $text = [IO.File]::ReadAllText($full)
    [Convert]::ToBase64String([Text.UTF8Encoding]::new($false).GetBytes($text))
}

$existing = @{}
(Invoke-MgGraphRequest -Method GET -Uri "$base`?`$select=id,displayName").value |
    ForEach-Object { $existing[$_.displayName] = $_.id }

$targets = $manifest.packages | Where-Object { -not $Name -or $Name -contains $_.name }
if (-not $targets) { throw "No packages matched: $($Name -join ', ')" }

foreach ($pkg in $targets) {
    $body = @{
        '@odata.type'          = '#microsoft.graph.deviceHealthScript'
        displayName            = $pkg.name
        description            = $pkg.description
        publisher              = $manifest.publisher
        detectionScriptContent = Get-ScriptB64 $pkg.detection
        runAsAccount           = $pkg.runAsAccount
        runAs32Bit             = [bool]$pkg.runAs32Bit
        enforceSignatureCheck  = $false
        roleScopeTagIds        = $RoleScopeTagIds
    }
    if ($pkg.remediation) {
        $body.remediationScriptContent = Get-ScriptB64 $pkg.remediation
    }

    $id = $existing[$pkg.name]
    if ($id) {
        if ($PSCmdlet.ShouldProcess($pkg.name, 'UPDATE')) {
            Invoke-MgGraphRequest -Method PATCH -Uri "$base/$id" -Body ($body | ConvertTo-Json -Depth 5)
            Write-Host "updated  $($pkg.name)" -ForegroundColor Yellow
        }
    }
    else {
        if ($PSCmdlet.ShouldProcess($pkg.name, 'CREATE')) {
            $new = Invoke-MgGraphRequest -Method POST -Uri $base -Body ($body | ConvertTo-Json -Depth 5)
            Write-Host "created  $($pkg.name)  [$($new.id)]" -ForegroundColor Green
        }
    }
}

Write-Host "`nPackages are created but NOT assigned. Assign in the portal:" -ForegroundColor Cyan
Write-Host '  Devices > Scripts and remediations > <package> > Assignments'
Write-Host "Never assign 'Network Fix - Stack Reset' to a group - run it on-demand only."
