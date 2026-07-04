<#
.SYNOPSIS
    Intune Lens — resultant settings (RSOP) for Intune-managed Windows devices.
    Answers: "What are ALL the settings that apply to this device / these devices?"
    Run with no parameters for a guided interactive menu.

.DESCRIPTION
    Aggregates every Windows configuration source in an Intune tenant:
      - Settings Catalog policies            (deviceManagement/configurationPolicies)
      - Endpoint Security policies (ASR, AV, Firewall, BitLocker, EDR, ...) - modern (configurationPolicies) and legacy (intents)
      - Security Baselines                   (modern: configurationPolicies, legacy: intents)
      - Device Configuration templates       (deviceManagement/deviceConfigurations, incl. custom OMA-URI)
      - Administrative Templates / ADMX      (deviceManagement/groupPolicyConfigurations)
      - Compliance policies                  (deviceManagement/deviceCompliancePolicies) [optional]
      - Windows Update profiles              (feature / expedited quality / driver) [optional]
      - Platform scripts                     (incl. decoded script content, searchable) [optional]
      - Application assignments              (deviceAppManagement/mobileApps - one entry per
                                              assignment intent, so an app targeted with intent
                                              'uninstall' shows up as the cause of app removal) [optional]

    For each target device it resolves:
      - Entra ID transitive group membership of the DEVICE object
      - Entra ID transitive group membership of the PRIMARY USER (user-targeted policies)
      - "All devices" / "All users" virtual assignments
      - Assignment filters (local rule evaluation against live inventory first; server-side
        /deviceManagement/evaluateAssignmentFilter for rules that are not locally decidable)
      - Group exclusions (kind-aware: user-group exclusions do not undo device-targeted
        includes and vice versa, per the Intune support matrix)

    ...then flattens every individual setting (name + value) from every applicable policy,
    detects conflicts (same setting defined with different values by multiple applicable
    policies), and optionally cross-checks against what the device actually reported
    (reports/getConfigurationPoliciesReportForDevice - the data behind the portal's
    per-device Configuration blade).

    Targets can be specified by serial number, device name, Entra ID group, or assignment filter.

    Output: console summary + self-contained interactive HTML report (searchable, with
    CSV download). Optional raw CSV / JSON exports.

    Requires module: Microsoft.Graph.Authentication (only; raw REST is used for everything else).
    Delegated scopes: DeviceManagementConfiguration.Read.All,
                      DeviceManagementManagedDevices.Read.All,
                      Directory.Read.All,
                      DeviceManagementApps.Read.All (unless -SkipApps),
                      DeviceManagementScripts.Read.All (unless -SkipScripts)

.PARAMETER SerialNumber
    One or more device serial numbers.

.PARAMETER DeviceName
    One or more Intune device names.

.PARAMETER Group
    Entra ID group display name or object id. All *device* members (transitive) are resolved.

.PARAMETER GroupAssignedOnly
    With -Group: instead of resolving member devices, list the policies/settings whose
    assignments directly reference this group (fast; no per-device evaluation).

.PARAMETER AssignmentFilter
    Assignment filter display name or id. The filter is evaluated server-side and all
    matching devices become targets.

.PARAMETER All
    Tenant-wide inventory: every policy (assigned or not) with all settings and a
    resolved assignment summary (group names, filters, exclusions). Great for cleanup.

.PARAMETER ScopeGroup
    With -All: narrow the inventory to policies whose assignments reach this Entra ID
    group (display name or object id) - directly, via a parent group (transitive), or
    via an All devices / All users assignment. Policies that only EXCLUDE the scope
    stay visible as Excluded (their settings land in the shadow set); everything else
    is dropped. Answers "what policies apply to this group?" without per-device math.

.PARAMETER ScopeFilter
    With -All: narrow the inventory to policies with at least one assignment carrying
    this assignment filter (display name or id). The include/exclude mode of the
    filter usage is spelled out per policy. Combinable with -ScopeGroup (both must match).

.PARAMETER SkipUpdates
    Skip Windows Update profiles (feature / expedite / driver).

.PARAMETER SkipScripts
    Skip platform scripts (their decoded content is otherwise pulled and made
    searchable - that is how you catch a script that silently uninstalls an app).
    The script endpoint sits behind the dedicated DeviceManagementScripts.Read.All scope
    (only requested when scripts are included; not covered by DeviceManagementConfiguration).

.PARAMETER SkipApps
    Skip application assignments. When apps are included (default), every app is split into
    one entry per assignment intent (Required / Available / Uninstall), so "what is
    uninstalling app X on this device" becomes a direct report lookup. Requires the
    DeviceManagementApps.Read.All scope (only requested when apps are included).

.PARAMETER ExportHtml
    Path for the interactive HTML report. Default: .\IntuneLens-<timestamp>.html
    (pass -NoHtml to suppress).

.PARAMETER ExportCsv
    Optional path for a flat CSV (one row per device x setting).

.PARAMETER ExportJson
    Optional path for the full structured JSON result.

.PARAMETER NoHtml
    Suppress the default HTML report.

.PARAMETER SkipCompliance
    Do not include compliance policies.

.PARAMETER SkipReportedStatus
    Skip the per-device "what did the device actually report" cross-check (faster).

.PARAMETER MaxDevices
    Safety cap for group/filter modes (default 25). 0 = unlimited.

.PARAMETER CacheMinutes
    The policy corpus (all policies + settings + assignments) is cached on disk to make
    repeat queries fast. Default TTL 60 minutes. Use -Refresh to force a re-pull.

.PARAMETER Refresh
    Ignore the on-disk policy cache and re-pull everything from Graph.

.PARAMETER PassThru
    Emit the per-device result objects to the pipeline.

.PARAMETER TenantId
    Optional tenant id/domain for Connect-MgGraph.

.PARAMETER ClientId
    Optional app registration client id for Connect-MgGraph (defaults to the Graph SDK app).

.PARAMETER Environment
    Graph environment: Global (default), USGov, USGovDoD, China.

.PARAMETER UseDeviceCode
    Use device-code sign-in (handy over SSH / in containers).

.EXAMPLE
    ./Get-IntuneResultantSettings.ps1 -SerialNumber 5CD1234XYZ

.EXAMPLE
    ./Get-IntuneResultantSettings.ps1 -SerialNumber 5CD1234XYZ,PF2ABCDE -ExportCsv rsop.csv

.EXAMPLE
    ./Get-IntuneResultantSettings.ps1 -Group "Sales Laptops"

.EXAMPLE
    ./Get-IntuneResultantSettings.ps1 -Group "Pilot Ring 1" -GroupAssignedOnly

.EXAMPLE
    ./Get-IntuneResultantSettings.ps1 -AssignmentFilter "Corp Windows 11" -MaxDevices 10

.EXAMPLE
    ./Get-IntuneResultantSettings.ps1 -All -ScopeGroup "Sales Laptops" -ExportCsv sales-scope.csv

.EXAMPLE
    ./Get-IntuneResultantSettings.ps1 -All -ScopeFilter "Corp Windows 11"

.NOTES
    Version 2.3.1 (2026-07-05)
    Run with NO parameters for a guided interactive menu.
    Read-only: performs GET/report POST calls only; never modifies tenant data.
    Keep report-template.html next to this script for the full-featured HTML report.
#>
[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(ParameterSetName = 'BySerial', Mandatory = $true, Position = 0)]
    [string[]]$SerialNumber,

    [Parameter(ParameterSetName = 'ByDeviceName', Mandatory = $true)]
    [string[]]$DeviceName,

    [Parameter(ParameterSetName = 'ByGroup', Mandatory = $true)]
    [string]$Group,

    [Parameter(ParameterSetName = 'ByGroup')]
    [switch]$GroupAssignedOnly,

    [Parameter(ParameterSetName = 'ByFilter', Mandatory = $true)]
    [string]$AssignmentFilter,

    # Tenant-wide inventory: every policy + every setting + assignment summary (no device math)
    [Parameter(ParameterSetName = 'All', Mandatory = $true)]
    [switch]$All,

    # -All scoping (additive): narrow the inventory to a group and/or an assignment filter
    [Parameter(ParameterSetName = 'All')]
    [string]$ScopeGroup,

    [Parameter(ParameterSetName = 'All')]
    [string]$ScopeFilter,

    [switch]$SkipUpdates,   # skip feature/quality/driver update profiles
    [switch]$SkipScripts,   # skip platform scripts
    [switch]$SkipApps,      # skip application assignments (install/uninstall intents)

    [string]$ExportHtml,
    [string]$ExportCsv,
    [string]$ExportJson,
    [switch]$NoHtml,

    [switch]$SkipCompliance,
    [switch]$SkipReportedStatus,

    [int]$MaxDevices = 25,
    [int]$CacheMinutes = 60,
    [switch]$Refresh,
    [switch]$PassThru,

    [string]$TenantId,
    [string]$ClientId,
    [ValidateSet('Global', 'USGov', 'USGovDoD', 'China')]
    [string]$Environment = 'Global',
    [switch]$UseDeviceCode
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'
$script:Version = '2.3.1'
$script:StartTime = Get-Date

#region ---------- console helpers ----------------------------------------------------------

function Write-Step  { param([string]$Text) Write-Host ("==> " + $Text) -ForegroundColor Cyan }
function Write-Info  { param([string]$Text) Write-Host ("    " + $Text) -ForegroundColor DarkGray }
function Write-Good  { param([string]$Text) Write-Host ("    " + $Text) -ForegroundColor Green }
function Write-Warn2 { param([string]$Text) Write-Host ("    ! " + $Text) -ForegroundColor Yellow }

# Run log: every notable event (esp. Graph call failures) is collected here and embedded
# in the HTML report's Warnings panel, so problems are visible without scrollback.
$script:RunLog = New-Object System.Collections.Generic.List[object]

function Add-RunLog {
    param([ValidateSet('info', 'warn', 'error')][string]$Level, [string]$Message)
    [void]$script:RunLog.Add([pscustomobject]@{
        Time    = (Get-Date).ToString('HH:mm:ss')
        Level   = $Level
        Message = $Message
    })
    if ($Level -ne 'info') { Write-Warn2 $Message }
}

#endregion

#region ---------- graph plumbing -----------------------------------------------------------

$script:RequiredScopes = @(
    'DeviceManagementConfiguration.Read.All',
    'DeviceManagementManagedDevices.Read.All',
    'Directory.Read.All'
)
if (-not $SkipApps) { $script:RequiredScopes += 'DeviceManagementApps.Read.All' }
# Platform scripts live behind their own permission; a token holding only
# DeviceManagementConfiguration.Read.All gets 403 from the script endpoint.
if (-not $SkipScripts) { $script:RequiredScopes += 'DeviceManagementScripts.Read.All' }

function Connect-RsopGraph {
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        throw "Module 'Microsoft.Graph.Authentication' is not installed. Run: Install-Module Microsoft.Graph.Authentication -Scope CurrentUser"
    }
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop | Out-Null

    $ctx = $null
    try { $ctx = Get-MgContext } catch { $ctx = $null }

    $needConnect = $true
    if ($ctx -and $ctx.Scopes) {
        $missing = @($script:RequiredScopes | Where-Object { $ctx.Scopes -notcontains $_ })
        if ($missing.Count -eq 0) {
            $needConnect = $false
            Write-Info ("Reusing existing Graph session: {0} ({1})" -f $ctx.Account, $ctx.TenantId)
        }
    }

    if ($needConnect) {
        Write-Step "Signing in to Microsoft Graph (read-only scopes)"
        $cp = @{ Scopes = $script:RequiredScopes; Environment = $Environment; NoWelcome = $true }
        if ($TenantId)      { $cp['TenantId'] = $TenantId }
        if ($ClientId)      { $cp['ClientId'] = $ClientId }
        if ($UseDeviceCode) { $cp['UseDeviceCode'] = $true }
        Connect-MgGraph @cp
        $ctx = Get-MgContext
    }
    return $ctx
}

function Invoke-Rsop {
    # Thin wrapper: one retry on transient failures (SDK already honors 429 Retry-After).
    param(
        [string]$Method = 'GET',
        [Parameter(Mandatory = $true)][string]$Uri,
        [object]$Body
    )
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            if ($null -ne $Body) {
                $json = $Body | ConvertTo-Json -Depth 12
                return Invoke-MgGraphRequest -Method $Method -Uri $Uri -Body $json -ContentType 'application/json' -OutputType HashTable
            }
            return Invoke-MgGraphRequest -Method $Method -Uri $Uri -OutputType HashTable
        }
        catch {
            if ($attempt -ge 2) { throw }
            Start-Sleep -Seconds 3
        }
    }
}

function Invoke-RsopStream {
    # POST for report-style endpoints that answer with a Stream (octet-stream +
    # Content-Disposition): the SDK refuses to hand those back inline regardless of
    # -OutputType and demands -OutputFilePath, so land the body in a temp file and
    # parse from there. Works just as well when the tenant answers with plain JSON.
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][object]$Body
    )
    $json = $Body | ConvertTo-Json -Depth 12
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('IntuneLens-' + [guid]::NewGuid().ToString('n') + '.json')
    try {
        Invoke-MgGraphRequest -Method POST -Uri $Uri -Body $json -ContentType 'application/json' -OutputFilePath $tmp | Out-Null
        if (-not (Test-Path -LiteralPath $tmp)) { return $null }
        $raw = [System.IO.File]::ReadAllText($tmp)
        if (-not $raw) { return $null }
        # ConvertFrom-ReportGrid also copes with raw strings (JSON-in-string / base64)
        try { return $raw | ConvertFrom-Json -AsHashtable } catch { return $raw }
    }
    finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Get-RsopPaged {
    # Follows @odata.nextLink; returns a flat array of items.
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [string]$Activity
    )
    $items = New-Object System.Collections.Generic.List[object]
    $next = $Uri
    $page = 0
    while ($next) {
        $page++
        if ($Activity) {
            Write-Progress -Id 7 -Activity $Activity -Status ("page {0} ({1} items so far)" -f $page, $items.Count)
        }
        $resp = Invoke-Rsop -Uri $next
        if ($resp -and $resp.ContainsKey('value')) {
            foreach ($i in @($resp['value'])) { [void]$items.Add($i) }
        }
        $next = $null
        if ($resp -and $resp.ContainsKey('@odata.nextLink')) { $next = $resp['@odata.nextLink'] }
    }
    if ($Activity) { Write-Progress -Id 7 -Activity $Activity -Completed }
    return $items.ToArray()
}

function Get-Prop {
    # Case-insensitive property/key lookup that works on hashtables and PSObjects.
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        foreach ($k in $Object.Keys) {
            # unary comma: stop the pipeline from unrolling single-element arrays
            # (a one-row report grid would otherwise lose its shape)
            if ([string]$k -ieq $Name) { return , $Object[$k] }
        }
        return $null
    }
    $p = $Object.PSObject.Properties | Where-Object { $_.Name -ieq $Name } | Select-Object -First 1
    if ($p) { return , $p.Value }
    return $null
}

function Get-PropList {
    # Array-safe variant for iteration. Never use @(Get-Prop ...) - @() around a command
    # collects the output stream and double-wraps arrays; this returns a true array.
    param($Object, [string]$Name)
    $v = Get-Prop $Object $Name
    if ($null -eq $v) { return , @() }
    return , @($v)
}

function ConvertFrom-ReportGrid {
    # Normalizes Intune report responses ({Schema:[{Column}],Values:[[...]]}) and the
    # evaluateAssignmentFilter stream (raw JSON, JSON-in-string, or base64-in-'value')
    # into an array of PSCustomObjects.
    param($Response)

    if ($null -eq $Response) { return @() }

    if ($Response -is [string]) {
        $s = $Response.Trim()
        if ($s.StartsWith('{') -or $s.StartsWith('[')) {
            try { return ConvertFrom-ReportGrid -Response ($s | ConvertFrom-Json -AsHashtable) } catch { }
            try { return ConvertFrom-ReportGrid -Response ($s | ConvertFrom-Json) } catch { return @() }
        }
        try {
            $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($s))
            if ($decoded.TrimStart().StartsWith('{') -or $decoded.TrimStart().StartsWith('[')) {
                return ConvertFrom-ReportGrid -Response $decoded
            }
        } catch { }
        return @()
    }

    $schema = Get-Prop $Response 'Schema'
    $values = Get-Prop $Response 'Values'
    if ($schema -and $null -ne $values) {
        $cols = @()
        foreach ($c in @($schema)) {
            $cn = Get-Prop $c 'Column'
            if (-not $cn) { $cn = [string]$c }
            $cols += $cn
        }
        $rows = New-Object System.Collections.Generic.List[object]
        foreach ($v in @($values)) {
            $row = [ordered]@{}
            $arr = @($v)
            for ($i = 0; $i -lt $cols.Count -and $i -lt $arr.Count; $i++) { $row[$cols[$i]] = $arr[$i] }
            [void]$rows.Add([pscustomobject]$row)
        }
        return $rows.ToArray()
    }

    $val = Get-Prop $Response 'value'
    if ($null -ne $val) {
        if ($val -is [string]) { return ConvertFrom-ReportGrid -Response $val }
        $out = @()
        foreach ($item in @($val)) {
            if ($item -is [System.Collections.IDictionary]) { $out += [pscustomobject]$item } else { $out += $item }
        }
        return $out
    }

    return @()
}

#endregion

#region ---------- value rendering helpers --------------------------------------------------

function Format-SettingValue {
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [bool]) { if ($Value) { return 'True' } else { return 'False' } }
    if ($Value -is [System.Collections.IDictionary] -or ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string])) {
        try {
            $clean = Remove-JsonNoise -Value $Value
            $j = $clean | ConvertTo-Json -Depth 8 -Compress
            if ($j.Length -gt 2000) { $j = $j.Substring(0, 2000) + ' ...(truncated)' }
            return $j
        } catch { return [string]$Value }
    }
    $s = [string]$Value
    if ($s.Length -gt 2000) { $s = $s.Substring(0, 2000) + ' ...(truncated)' }
    return $s
}

function Remove-JsonNoise {
    # Strips null-valued keys and @odata.type annotations from nested objects so JSON
    # values in the report show only what is actually configured.
    param($Value, [int]$Depth = 0)
    if ($Depth -gt 6) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $o = [ordered]@{}
        foreach ($k in $Value.Keys) {
            $ks = [string]$k
            if ($ks.StartsWith('@') -or $ks.Contains('@odata')) { continue }
            $v = $Value[$k]
            if ($null -eq $v) { continue }
            $o[$ks] = Remove-JsonNoise -Value $v -Depth ($Depth + 1)
        }
        return $o
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $arr = @()
        foreach ($e in $Value) { $arr += , (Remove-JsonNoise -Value $e -Depth ($Depth + 1)) }
        return , $arr
    }
    return $Value
}

function ConvertTo-FriendlyName {
    # 'defenderSecurityCenterDisableAppBrowserUI' -> 'Defender Security Center Disable App Browser UI'
    param([string]$Text)
    if (-not $Text) { return $Text }
    $t = $Text -creplace '([a-z0-9])([A-Z])', '$1 $2'
    $t = $t -replace '[_\.]+', ' '
    $t = $t.Trim()
    if ($t.Length -gt 0) { $t = $t.Substring(0, 1).ToUpper() + $t.Substring(1) }
    return $t
}

function Get-DefinitionTail {
    # Last meaningful chunk of a settings-catalog / intent definition id.
    param([string]$DefinitionId)
    if (-not $DefinitionId) { return $DefinitionId }
    $tail = ($DefinitionId -split '_')[-1]
    return ConvertTo-FriendlyName $tail
}

#endregion

#region ---------- settings catalog flattening ----------------------------------------------

$script:ReusableSettingNames = @{}

function Resolve-ReusableSettingName {
    param([string]$Id)
    if (-not $Id) { return $Id }
    if ($script:ReusableSettingNames.ContainsKey($Id)) { return $script:ReusableSettingNames[$Id] }
    $name = $Id
    try {
        $r = Invoke-Rsop -Uri ("beta/deviceManagement/reusablePolicySettings/{0}?`$select=id,displayName" -f $Id)
        if ($r -and $r['displayName']) { $name = ("{0} (reusable setting)" -f $r['displayName']) }
    } catch { }
    $script:ReusableSettingNames[$Id] = $name
    return $name
}

function Expand-CatalogInstance {
    # Recursively flattens a deviceManagementConfigurationSettingInstance tree into rows.
    param(
        $Instance,
        [hashtable]$Defs,
        [string]$Prefix,
        [System.Collections.Generic.List[object]]$Rows
    )
    if ($null -eq $Instance) { return }

    $odata = [string](Get-Prop $Instance '@odata.type')
    $defId = [string](Get-Prop $Instance 'settingDefinitionId')
    $def = $null
    if ($defId -and $Defs.ContainsKey($defId)) { $def = $Defs[$defId] }

    $name = $null
    if ($def) { $name = [string](Get-Prop $def 'displayName') }
    if (-not $name) { $name = Get-DefinitionTail $defId }
    $display = if ($Prefix) { "$Prefix > $name" } else { $name }

    switch -Wildcard ($odata) {

        '*choiceSettingInstance' {
            $cv = Get-Prop $Instance 'choiceSettingValue'
            $optId = [string](Get-Prop $cv 'value')
            $optName = $null
            if ($def) {
                $opts = Get-Prop $def 'options'
                foreach ($o in @($opts)) {
                    if ([string](Get-Prop $o 'itemId') -eq $optId) { $optName = [string](Get-Prop $o 'displayName'); break }
                }
            }
            if (-not $optName) { $optName = Get-DefinitionTail $optId }
            [void]$Rows.Add([pscustomobject]@{ Key = $defId; Setting = $display; Value = $optName })
            foreach ($child in (Get-PropList $cv 'children')) {
                Expand-CatalogInstance -Instance $child -Defs $Defs -Prefix $display -Rows $Rows
            }
        }

        '*choiceSettingCollectionInstance' {
            $vals = Get-PropList $Instance 'choiceSettingCollectionValue'
            $labels = @()
            foreach ($cv in $vals) {
                $optId = [string](Get-Prop $cv 'value')
                $optName = $null
                if ($def) {
                    $opts = Get-Prop $def 'options'
                    foreach ($o in @($opts)) {
                        if ([string](Get-Prop $o 'itemId') -eq $optId) { $optName = [string](Get-Prop $o 'displayName'); break }
                    }
                }
                if (-not $optName) { $optName = Get-DefinitionTail $optId }
                $labels += $optName
            }
            [void]$Rows.Add([pscustomobject]@{ Key = $defId; Setting = $display; Value = ($labels -join '; ') })
            $idx = 0
            foreach ($cv in $vals) {
                foreach ($child in (Get-PropList $cv 'children')) {
                    Expand-CatalogInstance -Instance $child -Defs $Defs -Prefix ("{0} [{1}]" -f $display, $idx) -Rows $Rows
                }
                $idx++
            }
        }

        '*simpleSettingInstance' {
            $sv = Get-Prop $Instance 'simpleSettingValue'
            $svType = [string](Get-Prop $sv '@odata.type')
            $val = Get-Prop $sv 'value'
            if ($svType -like '*Secret*') { $val = '(secret - not shown)' }
            elseif ($svType -like '*Reference*') { $val = Resolve-ReusableSettingName ([string]$val) }
            [void]$Rows.Add([pscustomobject]@{ Key = $defId; Setting = $display; Value = (Format-SettingValue $val) })
        }

        '*simpleSettingCollectionInstance' {
            $vals = @()
            foreach ($sv in (Get-PropList $Instance 'simpleSettingCollectionValue')) {
                $svType = [string](Get-Prop $sv '@odata.type')
                if ($svType -like '*Secret*') { $vals += '(secret)' } else { $vals += (Format-SettingValue (Get-Prop $sv 'value')) }
            }
            [void]$Rows.Add([pscustomobject]@{ Key = $defId; Setting = $display; Value = ($vals -join '; ') })
        }

        '*groupSettingCollectionInstance' {
            $groups = Get-PropList $Instance 'groupSettingCollectionValue'
            $idx = 0
            foreach ($g in $groups) {
                $p = if ($groups.Count -gt 1) { "{0} [{1}]" -f $display, $idx } else { $display }
                foreach ($child in (Get-PropList $g 'children')) {
                    Expand-CatalogInstance -Instance $child -Defs $Defs -Prefix $p -Rows $Rows
                }
                $idx++
            }
            if ($groups.Count -eq 0) {
                [void]$Rows.Add([pscustomobject]@{ Key = $defId; Setting = $display; Value = '(configured, empty)' })
            }
        }

        '*groupSettingInstance' {
            $g = Get-Prop $Instance 'groupSettingValue'
            foreach ($child in (Get-PropList $g 'children')) {
                Expand-CatalogInstance -Instance $child -Defs $Defs -Prefix $display -Rows $Rows
            }
        }

        default {
            # Unknown instance type: record what we can.
            $val = Get-Prop $Instance 'value'
            [void]$Rows.Add([pscustomobject]@{ Key = $defId; Setting = $display; Value = (Format-SettingValue $val) })
        }
    }
}

function Convert-CatalogSettings {
    # $SettingItems = items from configurationPolicies/{id}/settings?$expand=settingDefinitions
    param($SettingItems, [hashtable]$CategoryMap = @{})
    $defs = @{}
    foreach ($item in @($SettingItems)) {
        foreach ($d in (Get-PropList $item 'settingDefinitions')) {
            $did = [string](Get-Prop $d 'id')
            if ($did -and -not $defs.ContainsKey($did)) { $defs[$did] = $d }
        }
    }
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($SettingItems)) {
        $inst = Get-Prop $item 'settingInstance'
        $before = $rows.Count
        Expand-CatalogInstance -Instance $inst -Defs $defs -Prefix '' -Rows $rows
        # stamp the root setting's category (matches how the portal groups settings)
        $cat = ''
        $rootDefId = [string](Get-Prop $inst 'settingDefinitionId')
        if ($rootDefId -and $defs.ContainsKey($rootDefId)) {
            $catId = [string](Get-Prop $defs[$rootDefId] 'categoryId')
            if ($catId -and $CategoryMap.ContainsKey($catId)) { $cat = $CategoryMap[$catId] }
        }
        for ($ri = $before; $ri -lt $rows.Count; $ri++) {
            $rows[$ri] | Add-Member -NotePropertyName Category -NotePropertyValue $cat -Force
        }
    }
    return $rows.ToArray()
}

#endregion

#region ---------- legacy / admx / intent flattening ----------------------------------------

function Convert-LegacyProperties {
    # Flattens a deviceConfiguration / deviceCompliancePolicy object's non-null typed properties.
    # Rows get a Category derived from the item's @odata.type so legacy settings group and
    # match like everything else; $FallbackCategory covers collections whose items carry no
    # @odata.type (e.g. windows update profiles).
    param($Policy, [string]$FallbackCategory = '')
    $metaProps = @(
        'id', 'displayname', 'description', 'createddatetime', 'lastmodifieddatetime', 'version',
        'supportsscopetags', 'rolescopetagids', 'assignments',
        'devicemanagementapplicabilityruleosedition', 'devicemanagementapplicabilityruleosversion',
        'devicemanagementapplicabilityruledevicemode', 'scheduledactionsforrule',
        'devicestatuses', 'userstatuses', 'devicestatusoverview', 'userstatusoverview',
        'devicesettingstatesummaries',
        'scriptcontent', 'filename'
    )
    $rows = New-Object System.Collections.Generic.List[object]
    $odataShort = ([string](Get-Prop $Policy '@odata.type')) -replace '#microsoft.graph.', ''
    $rowCategory = $FallbackCategory
    if ($odataShort) {
        $trimmed = $odataShort -replace '(Configuration|Policy|Profile)$', ''
        if ($trimmed) { $rowCategory = ConvertTo-FriendlyName $trimmed }
    }

    foreach ($key in @($Policy.Keys)) {
        $k = [string]$key
        if ($k.StartsWith('@') -or $k.Contains('@odata')) { continue }
        if ($metaProps -contains $k.ToLower()) { continue }
        $v = $Policy[$key]
        if ($null -eq $v) { continue }
        if ($v -is [string] -and $v -eq '') { continue }
        if (($v -is [System.Collections.IEnumerable]) -and ($v -isnot [string]) -and (@($v).Count -eq 0)) { continue }

        if ($k -ieq 'omaSettings') {
            foreach ($oma in @($v)) {
                $omaName = [string](Get-Prop $oma 'displayName')
                $omaUri = [string](Get-Prop $oma 'omaUri')
                $omaVal = Get-Prop $oma 'value'
                $omaType = [string](Get-Prop $oma '@odata.type')
                if ($omaType -like '*StringXml*' -or ($omaVal -is [string] -and $omaVal.Length -gt 400)) {
                    $omaVal = (Format-SettingValue $omaVal)
                }
                $enc = Get-Prop $oma 'isEncrypted'
                if ($enc) { $omaVal = '(encrypted value - view in portal)' }
                [void]$rows.Add([pscustomobject]@{
                    Key      = "oma:$omaUri"
                    Setting  = "Custom OMA-URI: $omaName ($omaUri)"
                    Value    = (Format-SettingValue $omaVal)
                    Category = 'Custom OMA-URI'
                })
            }
            continue
        }

        [void]$rows.Add([pscustomobject]@{
            Key      = "legacy:$odataShort/$k"
            Setting  = (ConvertTo-FriendlyName $k)
            Value    = (Format-SettingValue $v)
            Category = $rowCategory
        })
    }
    return $rows.ToArray()
}

function Convert-AdmxValues {
    # $DefinitionValues = items from groupPolicyConfigurations/{id}/definitionValues?$expand=...
    param($DefinitionValues)
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($dv in @($DefinitionValues)) {
        $def = Get-Prop $dv 'definition'
        $defId = [string](Get-Prop $def 'id')
        $defName = [string](Get-Prop $def 'displayName')
        if (-not $defName) { $defName = '(unknown ADMX setting)' }
        $classType = [string](Get-Prop $def 'classType')
        $scope = if ($classType -ieq 'user') { ' (User)' } else { ' (Computer)' }
        $enabled = Get-Prop $dv 'enabled'
        $state = if ($enabled) { 'Enabled' } else { 'Disabled' }
        $cat = ''
        $catPath = [string](Get-Prop $def 'categoryPath')
        if ($catPath) { $cat = @($catPath -split '\\' | Where-Object { $_ })[-1] }

        [void]$rows.Add([pscustomobject]@{
            Key      = "admx:$defId"
            Setting  = "$defName$scope"
            Value    = $state
            Category = $cat
        })

        if ($enabled) {
            foreach ($pv in (Get-PropList $dv 'presentationValues')) {
                $pres = Get-Prop $pv 'presentation'
                $label = [string](Get-Prop $pres 'label')
                if (-not $label) { $label = 'Value' }
                $pvId = [string](Get-Prop $pv 'id')
                $val = $null
                $vv = Get-Prop $pv 'value'
                $vvs = Get-Prop $pv 'values'
                if ($null -ne $vv) { $val = Format-SettingValue $vv }
                elseif ($null -ne $vvs) {
                    $parts = @()
                    foreach ($e in @($vvs)) {
                        $en = Get-Prop $e 'name'; $ev = Get-Prop $e 'value'
                        if ($null -ne $en -and "$en" -ne '') { $parts += ("{0}={1}" -f $en, $ev) } else { $parts += [string]$ev }
                    }
                    $val = $parts -join '; '
                }
                if ($null -ne $val -and "$val" -ne '') {
                    [void]$rows.Add([pscustomobject]@{
                        Key      = "admx:$defId#$pvId"
                        Setting  = "$defName$scope :: $label"
                        Value    = $val
                        Category = $cat
                    })
                }
            }
        }
    }
    return $rows.ToArray()
}

function Convert-IntentSettings {
    # $Settings = items from intents/{id}/settings; $DefMap: definitionId -> @{Name;Category}
    # (built from templates/{id}/categories?$expand=settingDefinitions)
    param($Settings, [hashtable]$DefMap = @{})
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($s in @($Settings)) {
        $defId = [string](Get-Prop $s 'definitionId')
        $val = Get-Prop $s 'value'
        if ($null -eq $val) { $val = Get-Prop $s 'valueJson' }
        if ($null -eq $val) { continue }
        if ($val -is [string]) {
            $trim = $val.Trim('"')
            if ($trim -eq 'null' -or $trim -eq '') { continue }
            $val = $trim
        }
        $name = Get-DefinitionTail $defId
        $cat = ''
        if ($defId -and $DefMap.ContainsKey($defId)) {
            $m = $DefMap[$defId]
            if ($m.Name) { $name = $m.Name }
            if ($m.Category) { $cat = $m.Category }
        }
        [void]$rows.Add([pscustomobject]@{
            Key      = "intent:$defId"
            Setting  = $name
            Value    = (Format-SettingValue $val)
            Category = $cat
        })
    }
    return $rows.ToArray()
}

#endregion

#region ---------- policy corpus (all families) + cache -------------------------------------

function Get-PolicyPlatformTag {
    # Coarse platform tag so we don't show iOS profiles against Windows devices.
    param([string]$Family, $Raw)
    switch ($Family) {
        'admx'   { return 'windows' }
        'intent' { return 'windows' }
        'catalog' {
            $p = [string](Get-Prop $Raw 'platforms')
            if ($p -match 'windows') { return 'windows' }
            if ($p -match 'macOS') { return 'macos' }
            if ($p -match 'iOS') { return 'ios' }
            if ($p -match 'android') { return 'android' }
            if ($p -match 'linux') { return 'linux' }
            return 'other'
        }
        default {
            $t = ([string](Get-Prop $Raw '@odata.type')).ToLower()
            if ($t -match 'ios|iphone|ipad') { return 'ios' }
            if ($t -match 'macos') { return 'macos' }
            if ($t -match 'android|aosp') { return 'android' }
            if ($t -match 'windows|editionupgrade|sharedpc|domainjoin') { return 'windows' }
            return 'other'
        }
    }
}

function ConvertTo-CompactAssignments {
    param($Assignments)
    $out = @()
    foreach ($a in @($Assignments)) {
        $t = Get-Prop $a 'target'
        if ($null -eq $t) { continue }
        $out += [pscustomobject]@{
            Type       = ([string](Get-Prop $t '@odata.type')) -replace '#microsoft.graph.', ''
            GroupId    = [string](Get-Prop $t 'groupId')
            FilterId   = [string](Get-Prop $t 'deviceAndAppManagementAssignmentFilterId')
            FilterType = [string](Get-Prop $t 'deviceAndAppManagementAssignmentFilterType')
        }
    }
    return $out
}

function Get-FamilyLabel {
    param([string]$Family, $Raw, [hashtable]$TemplateMap)
    switch ($Family) {
        'catalog' {
            $tr = Get-Prop $Raw 'templateReference'
            $tf = [string](Get-Prop $tr 'templateFamily')
            $tn = [string](Get-Prop $tr 'templateDisplayName')
            if ($tf -and $tf -ne 'none') {
                $nice = switch -Wildcard ($tf) {
                    'baseline'                          { 'Security Baseline' }
                    'endpointSecurityAntivirus'         { 'Endpoint Security - Antivirus' }
                    'endpointSecurityAttackSurfaceReduction*' { 'Endpoint Security - ASR' }
                    'endpointSecurityDiskEncryption'    { 'Endpoint Security - Disk Encryption' }
                    'endpointSecurityFirewall'          { 'Endpoint Security - Firewall' }
                    'endpointSecurityEndpointDetectionAndResponse' { 'Endpoint Security - EDR' }
                    'endpointSecurityAccountProtection' { 'Endpoint Security - Account Protection' }
                    'endpointSecurityApplicationControl' { 'Endpoint Security - App Control' }
                    default { "Endpoint Security ($tf)" }
                }
                if ($tn) { return "$nice" } else { return $nice }
            }
            return 'Settings Catalog'
        }
        'legacy' {
            $t = ([string](Get-Prop $Raw '@odata.type')) -replace '#microsoft.graph.', ''
            if ($t -ieq 'windows10CustomConfiguration') { return 'Template - Custom OMA-URI' }
            return "Template - $(ConvertTo-FriendlyName $t)"
        }
        'admx' { return 'Administrative Templates (ADMX)' }
        'intent' {
            $tid = [string](Get-Prop $Raw 'templateId')
            if ($tid -and $TemplateMap.ContainsKey($tid)) { return "$($TemplateMap[$tid]) (legacy intent)" }
            return 'Endpoint Security / Baseline (legacy intent)'
        }
        'compliance' { return 'Compliance Policy' }
    }
    return $Family
}

function Get-PolicyCorpus {
    param([string]$TenantKey)

    $cacheFile = Join-Path $HOME (".intune-rsop-cache-{0}.json" -f ($TenantKey -replace '[^a-zA-Z0-9\-]', ''))
    if (-not $Refresh -and $CacheMinutes -gt 0 -and (Test-Path $cacheFile)) {
        try {
            $cached = Get-Content -Raw -Path $cacheFile | ConvertFrom-Json
            $age = (Get-Date) - [datetime]$cached.generated
            $ver = 0; try { $ver = [int]$cached.cacheVersion } catch { }
            if ($ver -eq 5 -and $age.TotalMinutes -lt $CacheMinutes) {
                Write-Step ("Using cached policy data from {0:HH:mm:ss} ({1:n0} min old; -Refresh to re-pull)" -f [datetime]$cached.generated, $age.TotalMinutes)
                return $cached
            }
        } catch { Write-Warn2 "Cache unreadable; re-pulling." }
    }

    $policies = New-Object System.Collections.Generic.List[object]
    $warnings = New-Object System.Collections.Generic.List[string]

    # -- templates map for legacy intents ------------------------------------------------
    $templateMap = @{}
    try {
        foreach ($t in (Get-RsopPaged -Uri 'beta/deviceManagement/templates?$select=id,displayName')) {
            $templateMap[[string]$t['id']] = [string]$t['displayName']
        }
    } catch { }

    # -- settings catalog category names (groups the report like the portal does) --------
    Write-Step "Pulling setting category names"
    $catMap = @{}
    try {
        foreach ($c in (Get-RsopPaged -Uri 'beta/deviceManagement/configurationCategories?$select=id,displayName' -Activity 'configurationCategories')) {
            $catMap[[string]$c['id']] = [string]$c['displayName']
        }
        Write-Info ("{0} categories" -f $catMap.Count)
    } catch { [void]$warnings.Add("Could not list setting categories: $($_.Exception.Message)") }

    function Get-PolicyMeta {
        param($Raw)
        $mod = [string](Get-Prop $Raw 'lastModifiedDateTime')
        if ($mod.Length -ge 10) { $mod = $mod.Substring(0, 10) }
        return @{
            Desc     = [string](Get-Prop $Raw 'description')
            Modified = $mod
        }
    }

    function Get-ScriptBodyRows {
        # Fetches one platform script individually (list responses omit the body),
        # decodes the base64 content and returns it as a searchable setting row. This is
        # how the report can answer "which script is removing app X".
        param([string]$BaseUri, $Item)
        $id = [string](Get-Prop $Item 'id')
        if (-not $id) { return , @() }
        $detail = $null
        try { $detail = Invoke-Rsop -Uri ("{0}/{1}" -f $BaseUri, $id) } catch {
            [void]$warnings.Add(("Could not fetch script body for '{0}': {1}" -f (Get-Prop $Item 'displayName'), $_.Exception.Message))
            return , @()
        }
        $b64 = [string](Get-Prop $detail 'scriptContent')
        if (-not $b64) { return , @() }
        $text = ''
        try { $text = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)).Trim() } catch { return , @() }
        if (-not $text) { return , @() }
        if ($text.Length -gt 6000) { $text = $text.Substring(0, 6000) + "`n...(truncated)" }
        $label = 'Script content'
        $fname = [string](Get-Prop $detail 'fileName')
        if ($fname) { $label = ("Script content ({0})" -f $fname) }
        return , @([pscustomobject]@{
            Key      = ("script:{0}:scriptContent" -f $id)
            Setting  = $label
            Value    = $text
            Category = 'Script body'
        })
    }

    # -- 1) Settings Catalog + modern Endpoint Security + modern Baselines ---------------
    Write-Step "Pulling Settings Catalog / Endpoint Security / Baseline policies (configurationPolicies)"
    $cfgPolicies = Get-RsopPaged -Uri 'beta/deviceManagement/configurationPolicies?$expand=assignments&$top=100' -Activity 'configurationPolicies'
    $n = 0
    foreach ($p in $cfgPolicies) {
        $n++
        $pname = [string]$p['name']
        Write-Progress -Id 3 -Activity 'Fetching settings (Settings Catalog & Endpoint Security)' -Status ("{0}/{1}  {2}" -f $n, @($cfgPolicies).Count, $pname) -PercentComplete ([int](100 * $n / [math]::Max(1, @($cfgPolicies).Count)))
        $rows = @()
        try {
            $settings = Get-RsopPaged -Uri ("beta/deviceManagement/configurationPolicies/{0}/settings?`$expand=settingDefinitions" -f $p['id'])
            $rows = Convert-CatalogSettings -SettingItems $settings -CategoryMap $catMap
        } catch {
            [void]$warnings.Add("Could not fetch settings for '$pname': $($_.Exception.Message)")
        }
        $meta = Get-PolicyMeta -Raw $p
        $tref = $p['templateReference']
        $detail = ''
        if ($tref) { $detail = [string](Get-Prop $tref 'templateDisplayName') }
        [void]$policies.Add([pscustomobject]@{
            Id          = [string]$p['id']
            Name        = $pname
            Family      = 'catalog'
            FamilyLabel = Get-FamilyLabel -Family 'catalog' -Raw $p -TemplateMap $templateMap
            Platform    = Get-PolicyPlatformTag -Family 'catalog' -Raw $p
            Desc        = $meta.Desc
            Modified    = $meta.Modified
            Detail      = $detail
            Assignments = @(ConvertTo-CompactAssignments -Assignments $p['assignments'])
            Settings    = @($rows)
        })
    }
    Write-Progress -Id 3 -Activity 'Fetching settings (Settings Catalog & Endpoint Security)' -Completed

    # -- 2) Legacy device configuration templates ----------------------------------------
    Write-Step "Pulling classic Device Configuration templates (deviceConfigurations)"
    $legacy = Get-RsopPaged -Uri 'beta/deviceManagement/deviceConfigurations?$expand=assignments&$top=100' -Activity 'deviceConfigurations'
    foreach ($p in $legacy) {
        $meta = Get-PolicyMeta -Raw $p
        [void]$policies.Add([pscustomobject]@{
            Id          = [string]$p['id']
            Name        = [string]$p['displayName']
            Family      = 'legacy'
            FamilyLabel = Get-FamilyLabel -Family 'legacy' -Raw $p -TemplateMap $templateMap
            Platform    = Get-PolicyPlatformTag -Family 'legacy' -Raw $p
            Desc        = $meta.Desc
            Modified    = $meta.Modified
            Detail      = ''
            Assignments = @(ConvertTo-CompactAssignments -Assignments $p['assignments'])
            Settings    = @(Convert-LegacyProperties -Policy $p)
        })
    }

    # -- 3) Administrative templates (ADMX) ----------------------------------------------
    Write-Step "Pulling Administrative Templates (groupPolicyConfigurations)"
    $admx = Get-RsopPaged -Uri 'beta/deviceManagement/groupPolicyConfigurations?$expand=assignments&$top=100' -Activity 'groupPolicyConfigurations'
    $n = 0
    foreach ($p in $admx) {
        $n++
        $pname = [string]$p['displayName']
        Write-Progress -Id 3 -Activity 'Fetching ADMX definition values' -Status ("{0}/{1}  {2}" -f $n, @($admx).Count, $pname) -PercentComplete ([int](100 * $n / [math]::Max(1, @($admx).Count)))
        $rows = @()
        try {
            $dv = Get-RsopPaged -Uri ("beta/deviceManagement/groupPolicyConfigurations/{0}/definitionValues?`$expand=definition(`$select=id,classType,displayName,categoryPath),presentationValues(`$expand=presentation)" -f $p['id'])
            $rows = Convert-AdmxValues -DefinitionValues $dv
        } catch {
            [void]$warnings.Add("Could not fetch ADMX values for '$pname': $($_.Exception.Message)")
        }
        $meta = Get-PolicyMeta -Raw $p
        [void]$policies.Add([pscustomobject]@{
            Id          = [string]$p['id']
            Name        = $pname
            Family      = 'admx'
            FamilyLabel = 'Administrative Templates (ADMX)'
            Platform    = 'windows'
            Desc        = $meta.Desc
            Modified    = $meta.Modified
            Detail      = ''
            Assignments = @(ConvertTo-CompactAssignments -Assignments $p['assignments'])
            Settings    = @($rows)
        })
    }
    Write-Progress -Id 3 -Activity 'Fetching ADMX definition values' -Completed

    # -- 4) Legacy endpoint security / baselines (intents) -------------------------------
    Write-Step "Pulling legacy Endpoint Security / Security Baselines (intents)"
    $intents = @()
    try { $intents = Get-RsopPaged -Uri 'beta/deviceManagement/intents' -Activity 'intents' } catch {
        [void]$warnings.Add("Could not list intents: $($_.Exception.Message)")
    }
    $intentDefMaps = @{}   # templateId -> (definitionId -> @{Name;Category})
    $n = 0
    foreach ($p in $intents) {
        $n++
        $pname = [string]$p['displayName']
        Write-Progress -Id 3 -Activity 'Fetching intent settings' -Status ("{0}/{1}  {2}" -f $n, @($intents).Count, $pname) -PercentComplete ([int](100 * $n / [math]::Max(1, @($intents).Count)))

        # real setting display names live on the intent's template categories
        $tid = [string]$p['templateId']
        if ($tid -and -not $intentDefMaps.ContainsKey($tid)) {
            $dm = @{}
            try {
                $cats = Get-RsopPaged -Uri ("beta/deviceManagement/templates/{0}/categories?`$expand=settingDefinitions" -f $tid)
                foreach ($c in @($cats)) {
                    $cname = [string](Get-Prop $c 'displayName')
                    foreach ($sd in (Get-PropList $c 'settingDefinitions')) {
                        $sdid = [string](Get-Prop $sd 'id')
                        if ($sdid -and -not $dm.ContainsKey($sdid)) {
                            $dm[$sdid] = @{ Name = [string](Get-Prop $sd 'displayName'); Category = $cname }
                        }
                    }
                }
            } catch { }
            $intentDefMaps[$tid] = $dm
        }
        $defMap = @{}
        if ($tid -and $intentDefMaps.ContainsKey($tid)) { $defMap = $intentDefMaps[$tid] }

        $rows = @(); $asg = @()
        try {
            $isettings = Get-RsopPaged -Uri ("beta/deviceManagement/intents/{0}/settings" -f $p['id'])
            $rows = Convert-IntentSettings -Settings $isettings -DefMap $defMap
        } catch { [void]$warnings.Add("Could not fetch settings for intent '$pname': $($_.Exception.Message)") }
        try {
            $ia = Get-RsopPaged -Uri ("beta/deviceManagement/intents/{0}/assignments" -f $p['id'])
            $asg = @(ConvertTo-CompactAssignments -Assignments $ia)
        } catch { [void]$warnings.Add("Could not fetch assignments for intent '$pname': $($_.Exception.Message)") }
        $meta = Get-PolicyMeta -Raw $p
        [void]$policies.Add([pscustomobject]@{
            Id          = [string]$p['id']
            Name        = $pname
            Family      = 'intent'
            FamilyLabel = Get-FamilyLabel -Family 'intent' -Raw $p -TemplateMap $templateMap
            Platform    = 'windows'
            Desc        = $meta.Desc
            Modified    = $meta.Modified
            Detail      = $(if ($tid -and $templateMap.ContainsKey($tid)) { $templateMap[$tid] } else { '' })
            Assignments = $asg
            Settings    = @($rows)
        })
    }
    Write-Progress -Id 3 -Activity 'Fetching intent settings' -Completed

    # -- 5) Compliance policies (optional) ------------------------------------------------
    if (-not $SkipCompliance) {
        Write-Step "Pulling Compliance policies"
        try {
            $comp = Get-RsopPaged -Uri 'beta/deviceManagement/deviceCompliancePolicies?$expand=assignments&$top=100' -Activity 'compliancePolicies'
            foreach ($p in $comp) {
                $meta = Get-PolicyMeta -Raw $p
                [void]$policies.Add([pscustomobject]@{
                    Id          = [string]$p['id']
                    Name        = [string]$p['displayName']
                    Family      = 'compliance'
                    FamilyLabel = 'Compliance Policy'
                    Platform    = Get-PolicyPlatformTag -Family 'compliance' -Raw $p
                    Desc        = $meta.Desc
                    Modified    = $meta.Modified
                    Detail      = ''
                    Assignments = @(ConvertTo-CompactAssignments -Assignments $p['assignments'])
                    Settings    = @(Convert-LegacyProperties -Policy $p)
                })
            }
        } catch { [void]$warnings.Add("Could not list compliance policies: $($_.Exception.Message)") }
    }

    # -- 6) Windows Update profiles + platform scripts (assignment-relevant extras) --------
    $extraSources = @(
        @{ Uri = 'beta/deviceManagement/windowsFeatureUpdateProfiles'; Label = 'Windows Update - Feature'; Gate = [bool]$SkipUpdates },
        @{ Uri = 'beta/deviceManagement/windowsQualityUpdateProfiles'; Label = 'Windows Update - Quality (expedite)'; Gate = [bool]$SkipUpdates },
        @{ Uri = 'beta/deviceManagement/windowsDriverUpdateProfiles'; Label = 'Windows Update - Drivers'; Gate = [bool]$SkipUpdates },
        @{ Uri = 'beta/deviceManagement/deviceManagementScripts'; Label = 'Platform Script (PowerShell)'; Gate = [bool]$SkipScripts; HasBody = $true }
    )
    foreach ($src in $extraSources) {
        if ($src.Gate) { continue }
        Write-Step ("Pulling {0}" -f $src.Label)
        $items = @(); $expandWorked = $true
        try {
            $items = Get-RsopPaged -Uri ($src.Uri + '?$expand=assignments')
        } catch {
            $expandWorked = $false
            try { $items = Get-RsopPaged -Uri $src.Uri } catch {
                $hint = ''
                if ($src.HasBody -and $_.Exception.Message -match 'Forbidden') {
                    $hint = ' (script endpoints need the DeviceManagementScripts.Read.All scope - re-run and consent, or -SkipScripts to silence)'
                }
                [void]$warnings.Add(("Could not list {0}: {1}{2}" -f $src.Label, $_.Exception.Message, $hint)); continue
            }
        }
        foreach ($p in $items) {
            $asg = $null
            if ($expandWorked) { $asg = $p['assignments'] }
            if ($null -eq $asg) {
                try { $asg = Get-RsopPaged -Uri ("{0}/{1}/assignments" -f $src.Uri, $p['id']) } catch { $asg = @() }
            }
            $meta = Get-PolicyMeta -Raw $p
            $rows = @(Convert-LegacyProperties -Policy $p -FallbackCategory $src.Label)
            if ($src.HasBody) { $rows += @(Get-ScriptBodyRows -BaseUri $src.Uri -Item $p) }
            [void]$policies.Add([pscustomobject]@{
                Id          = [string]$p['id']
                Name        = [string]$p['displayName']
                Family      = 'extra'
                FamilyLabel = $src.Label
                Platform    = 'windows'
                Desc        = $meta.Desc
                Modified    = $meta.Modified
                Detail      = ''
                Assignments = @(ConvertTo-CompactAssignments -Assignments $asg)
                Settings    = @($rows)
            })
        }
    }

    # -- 7) Applications, one entry per assignment intent ---------------------------------
    # An app assigned with intent 'uninstall' is the #1 cause of "app keeps disappearing";
    # splitting per intent lets the normal applicability engine answer that directly.
    if (-not $SkipApps) {
        Write-Step "Pulling application assignments (mobileApps)"
        $apps = @()
        try {
            $apps = Get-RsopPaged -Uri 'beta/deviceAppManagement/mobileApps?$filter=isAssigned eq true&$expand=assignments&$top=100' -Activity 'mobileApps'
        } catch {
            try {
                $apps = @(Get-RsopPaged -Uri 'beta/deviceAppManagement/mobileApps?$expand=assignments&$top=100' -Activity 'mobileApps') |
                    Where-Object { (Get-PropList $_ 'assignments').Count -gt 0 }
            } catch {
                [void]$warnings.Add("Could not list applications (missing DeviceManagementApps.Read.All? -SkipApps to silence): $($_.Exception.Message)")
                $apps = @()
            }
        }
        # Assignment intent is a secondary field (policy entry .Intent + the 'Assignment
        # intent' setting row); the policy type label is always just 'Apps'.
        $intentNames = @{
            required                   = 'Required install'
            uninstall                  = 'Uninstall'
            available                  = 'Available install'
            availableWithoutEnrollment = 'Available (no enrollment)'
        }
        $typeLabels = @{
            win32LobApp                  = 'Win32 app'
            win32CatalogApp              = 'Enterprise App Catalog (Win32)'
            winGetApp                    = 'Microsoft Store app (winget)'
            officeSuiteApp               = 'Microsoft 365 Apps suite'
            windowsMobileMSI             = 'MSI line-of-business'
            windowsUniversalAppX         = 'AppX / MSIX line-of-business'
            microsoftStoreForBusinessApp = 'Store for Business (legacy)'
            windowsMicrosoftEdgeApp      = 'Microsoft Edge'
            webApp                       = 'Web link'
            windowsWebApp                = 'Web link (Windows)'
        }
        $nApps = 0
        foreach ($app in @($apps)) {
            $nApps++
            $appId = [string](Get-Prop $app 'id')
            if (-not $appId) { continue }
            $appName = [string](Get-Prop $app 'displayName')
            Write-Progress -Id 3 -Activity 'Indexing application assignments' -Status ("{0}/{1}  {2}" -f $nApps, @($apps).Count, $appName) -PercentComplete ([int](100 * $nApps / [math]::Max(1, @($apps).Count)))
            $aType = ([string](Get-Prop $app '@odata.type')) -replace '#microsoft.graph.', ''
            $friendly = $typeLabels[$aType]
            if (-not $friendly) { $friendly = ConvertTo-FriendlyName $aType }
            $platform = 'other'
            if ($aType -match '^macO[Ss]') { $platform = 'macos' }
            elseif ($aType -match '^ios') { $platform = 'ios' }
            elseif ($aType -match '^(android|managedAndroid)') { $platform = 'android' }
            elseif ($aType -match '^(win32|windows|winGet|officeSuite|microsoftStore)') { $platform = 'windows' }

            # informational rows repeated under every intent of this app
            $infoRows = New-Object System.Collections.Generic.List[object]
            $pub = [string](Get-Prop $app 'publisher')
            $dver = [string](Get-Prop $app 'displayVersion')
            if ($pub)  { [void]$infoRows.Add(@{ K = 'publisher'; S = 'Publisher'; V = $pub }) }
            if ($dver) { [void]$infoRows.Add(@{ K = 'version'; S = 'App version'; V = $dver }) }
            foreach ($cmdProp in @('installCommandLine', 'uninstallCommandLine')) {
                $cmd = [string](Get-Prop $app $cmdProp)
                if ($cmd) { [void]$infoRows.Add(@{ K = $cmdProp; S = (ConvertTo-FriendlyName $cmdProp); V = $cmd }) }
            }
            $pkgId = [string](Get-Prop $app 'packageIdentifier')
            if ($pkgId) { [void]$infoRows.Add(@{ K = 'packageIdentifier'; S = 'Package identifier'; V = $pkgId }) }
            # officeSuiteApp: apps deselected from the suite are actively REMOVED from devices
            $excluded = Get-Prop $app 'excludedApps'
            if ($excluded) {
                $exNames = @()
                if ($excluded -is [System.Collections.IDictionary]) {
                    foreach ($k in $excluded.Keys) { if ($excluded[$k] -eq $true) { $exNames += [string]$k } }
                } else {
                    foreach ($pp in $excluded.PSObject.Properties) { if ($pp.Value -eq $true) { $exNames += $pp.Name } }
                }
                if ($exNames.Count -gt 0) {
                    [void]$infoRows.Add(@{ K = 'excludedApps'; S = 'Excluded Microsoft 365 apps (uninstalled if present)'; V = (($exNames | Sort-Object) -join ', ') })
                }
            }

            $byIntent = @{}
            foreach ($a in (Get-PropList $app 'assignments')) {
                $intent = [string](Get-Prop $a 'intent')
                if (-not $intent) { $intent = 'unknown' }
                if (-not $byIntent.ContainsKey($intent)) { $byIntent[$intent] = New-Object System.Collections.Generic.List[object] }
                [void]$byIntent[$intent].Add($a)
            }
            $meta = Get-PolicyMeta -Raw $app
            foreach ($intent in $byIntent.Keys) {
                $intentName = $intentNames[$intent]
                if (-not $intentName) { $intentName = ConvertTo-FriendlyName $intent }
                $rows = New-Object System.Collections.Generic.List[object]
                # Key shared across intents on purpose: if 'required' and 'uninstall' both
                # apply to one device, conflict detection surfaces the app tug-of-war.
                [void]$rows.Add([pscustomobject]@{ Key = ("app:{0}:intent" -f $appId); Setting = 'Assignment intent'; Value = $intent; Category = 'Application' })
                [void]$rows.Add([pscustomobject]@{ Key = ("app:{0}:{1}:type" -f $appId, $intent); Setting = 'App type'; Value = $friendly; Category = 'Application' })
                foreach ($ir in $infoRows) {
                    [void]$rows.Add([pscustomobject]@{ Key = ("app:{0}:{1}:{2}" -f $appId, $intent, $ir.K); Setting = [string]$ir.S; Value = [string]$ir.V; Category = 'Application' })
                }
                [void]$policies.Add([pscustomobject]@{
                    Id          = ("{0}:{1}" -f $appId, $intent)
                    Name        = $appName
                    Family      = 'app'
                    FamilyLabel = 'Apps'
                    Intent      = $intentName
                    Platform    = $platform
                    Desc        = $meta.Desc
                    Modified    = $meta.Modified
                    Detail      = $friendly
                    Assignments = @(ConvertTo-CompactAssignments -Assignments $byIntent[$intent].ToArray())
                    Settings    = @($rows.ToArray())
                })
            }
        }
        Write-Progress -Id 3 -Activity 'Indexing application assignments' -Completed
        Write-Info ("{0} assigned apps indexed" -f @($apps).Count)
    }

    # -- assignment filters ----------------------------------------------------------------
    Write-Step "Pulling assignment filters"
    $filters = @()
    try {
        foreach ($f in (Get-RsopPaged -Uri 'beta/deviceManagement/assignmentFilters?$select=id,displayName,platform,rule')) {
            $filters += [pscustomobject]@{
                Id       = [string]$f['id']
                Name     = [string]$f['displayName']
                Platform = [string]$f['platform']
                Rule     = [string]$f['rule']
            }
        }
    } catch { [void]$warnings.Add("Could not list assignment filters: $($_.Exception.Message)") }

    $corpus = [pscustomobject]@{
        cacheVersion = 5
        generated    = (Get-Date).ToString('o')
        tenant       = $TenantKey
        policies     = $policies.ToArray()
        filters      = $filters
        warnings     = $warnings.ToArray()
    }

    if ($CacheMinutes -gt 0) {
        try { $corpus | ConvertTo-Json -Depth 10 -Compress | Set-Content -Path $cacheFile -Encoding UTF8 } catch { }
    }

    $assignedCount = @($corpus.policies | Where-Object { @($_.Assignments).Count -gt 0 }).Count
    Write-Good ("Loaded {0} policies ({1} with assignments), {2} assignment filters" -f @($corpus.policies).Count, $assignedCount, @($corpus.filters).Count)
    foreach ($w in $corpus.warnings) { Write-Warn2 $w }
    return $corpus
}

#endregion

#region ---------- device + directory resolution --------------------------------------------

$script:DeviceIndex = $null

function Get-DeviceIndex {
    # Bulk index of Windows managed devices (used as a fallback and for group/filter modes).
    if ($null -ne $script:DeviceIndex) { return $script:DeviceIndex }
    Write-Info "Building managed-device index (one-time per run)..."
    $sel = 'id,deviceName,serialNumber,azureADDeviceId,userId,userPrincipalName,operatingSystem,osVersion,model,manufacturer,lastSyncDateTime,ownerType,enrollmentProfileName,deviceCategoryDisplayName,joinType,skuFamily,skuNumber,jailBroken'
    $all = Get-RsopPaged -Uri ("beta/deviceManagement/managedDevices?`$select={0}&`$top=1000" -f $sel) -Activity 'managedDevices index'
    $script:DeviceIndex = @($all)
    Write-Info ("Indexed {0} managed devices" -f @($all).Count)
    return $script:DeviceIndex
}

function Find-ManagedDevices {
    param(
        [ValidateSet('serialNumber', 'deviceName', 'azureADDeviceId')]
        [string]$By,
        [string]$Value
    )
    $sel = 'id,deviceName,serialNumber,azureADDeviceId,userId,userPrincipalName,operatingSystem,osVersion,model,manufacturer,lastSyncDateTime,ownerType,enrollmentProfileName,deviceCategoryDisplayName,joinType,skuFamily,skuNumber,jailBroken'
    $esc = $Value -replace "'", "''"
    try {
        $uri = "beta/deviceManagement/managedDevices?`$filter={0} eq '{1}'&`$select={2}" -f $By, $esc, $sel
        $hits = Get-RsopPaged -Uri $uri
        if (@($hits).Count -gt 0) { return @($hits) }
    } catch {
        Write-Info ("Server-side filter on {0} not accepted; falling back to full index scan." -f $By)
    }
    $idx = Get-DeviceIndex
    return @($idx | Where-Object { [string](Get-Prop $_ $By) -ieq $Value })
}

function Select-BestEnrollment {
    # Serial/name can match several enrollment records; prefer the most recently synced.
    param($Candidates, [string]$Label)
    $list = @($Candidates | Sort-Object { [string](Get-Prop $_ 'lastSyncDateTime') } -Descending)
    if ($list.Count -gt 1) {
        Write-Warn2 ("'{0}' matched {1} enrollment records; using most recently synced ({2}). Others are likely stale." -f $Label, $list.Count, (Get-Prop $list[0] 'deviceName'))
    }
    return $list[0]
}

function Get-EntraGroupIds {
    # Transitive group membership for a directory object (device or user).
    param([string]$DirectoryObjectId, [string]$Kind)
    if (-not $DirectoryObjectId) { return @() }
    try {
        $resp = Invoke-Rsop -Method POST -Uri ("v1.0/{0}/{1}/getMemberGroups" -f $Kind, $DirectoryObjectId) -Body @{ securityEnabledOnly = $false }
        return @($resp['value'] | ForEach-Object { [string]$_ })
    } catch {
        Write-Warn2 ("Could not read group membership for {0} {1}: {2}" -f $Kind, $DirectoryObjectId, $_.Exception.Message)
        return @()
    }
}

$script:GroupNameCache = @{}

function Resolve-GroupNames {
    param([string[]]$Ids)
    $todo = @($Ids | Where-Object { $_ -and -not $script:GroupNameCache.ContainsKey($_) } | Select-Object -Unique)
    for ($i = 0; $i -lt $todo.Count; $i += 900) {
        $chunk = @($todo[$i..([math]::Min($i + 899, $todo.Count - 1))])
        try {
            $resp = Invoke-Rsop -Method POST -Uri 'v1.0/directoryObjects/getByIds' -Body @{ ids = $chunk; types = @('group') }
            foreach ($o in @($resp['value'])) {
                $script:GroupNameCache[[string]$o['id']] = [string]$o['displayName']
            }
        } catch { }
    }
    foreach ($id in @($Ids)) {
        if ($id -and -not $script:GroupNameCache.ContainsKey($id)) { $script:GroupNameCache[$id] = $id }
    }
}

function Get-GroupName { param([string]$Id) if ($Id -and $script:GroupNameCache.ContainsKey($Id)) { return $script:GroupNameCache[$Id] } return $Id }

function Get-DeviceContext {
    # Everything needed to evaluate assignments for one managed device.
    param($ManagedDevice)

    $md = $ManagedDevice
    $azId = [string](Get-Prop $md 'azureADDeviceId')
    $dirId = $null
    if ($azId -and $azId -ne '00000000-0000-0000-0000-000000000000') {
        try {
            $resp = Invoke-Rsop -Uri ("v1.0/devices?`$filter=deviceId eq '{0}'&`$select=id" -f $azId)
            $vals = @($resp['value'])
            if ($vals.Count -gt 0) { $dirId = [string]$vals[0]['id'] }
        } catch { }
    }
    $deviceGroups = @()
    if ($dirId) { $deviceGroups = Get-EntraGroupIds -DirectoryObjectId $dirId -Kind 'devices' }
    else { Write-Warn2 ("No Entra device object found for '{0}' - device-group targeting cannot be evaluated." -f (Get-Prop $md 'deviceName')) }

    $userId = [string](Get-Prop $md 'userId')
    $userGroups = @()
    if ($userId -and $userId -ne '00000000-0000-0000-0000-000000000000') {
        $userGroups = Get-EntraGroupIds -DirectoryObjectId $userId -Kind 'users'
    }

    $dg = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($g in $deviceGroups) { [void]$dg.Add($g) }
    $ug = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($g in $userGroups) { [void]$ug.Add($g) }

    return [pscustomobject]@{
        ManagedDevice   = $md
        DirectoryId     = $dirId
        DeviceGroupIds  = $dg
        UserGroupIds    = $ug
        HasPrimaryUser  = [bool]($userId -and $userId -ne '00000000-0000-0000-0000-000000000000')
    }
}

#endregion

#region ---------- assignment filter evaluation ----------------------------------------------

$script:FilterEvalCache = @{}
$script:FilterById = @{}
$script:FilterEvalVariant = 0   # remembers which request shape this tenant accepts

function Invoke-FilterEvaluate {
    # Calls /deviceManagement/evaluateAssignmentFilter trying several request shapes,
    # because the endpoint is picky and its response is a Stream with varying envelopes.
    # Returns normalized rows; throws only if every variant fails.
    param($FilterObj, [int]$Top = 100, [int]$Skip = 0, [string]$Search = '')

    $mk = {
        param([bool]$HashPrefix, [bool]$IncludeEmpty)
        $data = [ordered]@{}
        if ($HashPrefix) { $data['@odata.type'] = '#microsoft.graph.assignmentFilterEvaluateRequest' }
        else             { $data['@odata.type'] = 'microsoft.graph.assignmentFilterEvaluateRequest' }
        $data['platform'] = $FilterObj.Platform
        $data['rule']     = $FilterObj.Rule
        $data['top']      = $Top
        $data['skip']     = $Skip
        if ($IncludeEmpty -or $Search) { $data['search'] = $Search }
        if ($IncludeEmpty) { $data['orderBy'] = @() }
        return @{ data = $data }
    }
    # The endpoint answers with a Stream (octet-stream + Content-Disposition) on real
    # tenants, which the SDK refuses to return inline - so temp-file variants go first.
    # variant 1: '#'-prefixed type, omit empty fields, response via temp file
    # variant 2: portal-style body (no '#', always send search/orderBy), temp file
    # variant 3: '#'-prefixed type, parsed inline (works where the answer is plain JSON)
    $variants = @(
        @{ N = 1; Body = (& $mk $true $false);  Stream = $true  },
        @{ N = 2; Body = (& $mk $false $true);  Stream = $true  },
        @{ N = 3; Body = (& $mk $true $false);  Stream = $false }
    )
    if ($script:FilterEvalVariant -gt 0) {
        $variants = @($variants | Sort-Object { $_.N -ne $script:FilterEvalVariant })
    }

    $lastErr = $null
    foreach ($v in $variants) {
        try {
            if ($v.Stream) {
                $resp = Invoke-RsopStream -Uri 'beta/deviceManagement/evaluateAssignmentFilter' -Body $v.Body
            } else {
                $json = $v.Body | ConvertTo-Json -Depth 8
                $resp = Invoke-MgGraphRequest -Method POST -Uri 'beta/deviceManagement/evaluateAssignmentFilter' -Body $json -ContentType 'application/json' -OutputType HashTable
            }
            $rows = ConvertFrom-ReportGrid -Response $resp
            $script:FilterEvalVariant = $v.N
            return , @($rows)
        } catch {
            $lastErr = $_.Exception.Message
            Add-RunLog -Level info -Message ("evaluateAssignmentFilter variant {0} failed for '{1}': {2}" -f $v.N, $FilterObj.Name, $lastErr)
        }
    }
    throw ("all evaluateAssignmentFilter request variants failed; last error: {0}" -f $lastErr)
}

# ---- client-side rule evaluation (fallback when the service call fails) --------------------

function ConvertTo-FilterTokens {
    param([string]$Rule)
    $tokens = New-Object System.Collections.Generic.List[object]
    $i = 0; $n = $Rule.Length
    while ($i -lt $n) {
        $c = $Rule[$i]
        if ([char]::IsWhiteSpace($c)) { $i++; continue }
        if ($c -eq '"') {
            $sb = New-Object System.Text.StringBuilder
            $i++
            while ($i -lt $n -and $Rule[$i] -ne '"') {
                if ($Rule[$i] -eq '\' -and $i + 1 -lt $n) { [void]$sb.Append($Rule[$i + 1]); $i += 2 }
                else { [void]$sb.Append($Rule[$i]); $i++ }
            }
            if ($i -ge $n) { throw 'unterminated string' }
            $i++
            [void]$tokens.Add(@{ T = 'str'; V = $sb.ToString() })
            continue
        }
        if ('()[],'.Contains($c)) { [void]$tokens.Add(@{ T = [string]$c; V = [string]$c }); $i++; continue }
        $j = $i
        while ($j -lt $n -and -not [char]::IsWhiteSpace($Rule[$j]) -and -not '()[],"'.Contains($Rule[$j])) { $j++ }
        $w = $Rule.Substring($i, $j - $i); $i = $j
        $wl = $w.ToLowerInvariant()
        # Rule syntax allows every operator with or without the dash ('-eq' | 'eq'),
        # including the boolean ones ('-and' | 'and').
        $opNames = @('eq', 'ne', 'in', 'notin', 'startswith', 'notstartswith',
                     'endswith', 'notendswith', 'contains', 'notcontains', 'gt', 'ge', 'lt', 'le')
        $bare = $wl.TrimStart('-')
        if ($bare -in @('and', 'or', 'not')) { [void]$tokens.Add(@{ T = 'kw'; V = $bare }) }
        elseif ($bare -in $opNames) { [void]$tokens.Add(@{ T = 'op'; V = ('-' + $bare) }) }
        elseif ($wl.StartsWith('-')) { [void]$tokens.Add(@{ T = 'op'; V = $wl }) }
        else { [void]$tokens.Add(@{ T = 'id'; V = $w }) }
    }
    return , $tokens.ToArray()
}

# Windows SKU number -> Intune filter operatingSystemSKU value, per
# learn.microsoft.com/intune/fundamentals/filters/ref-device-properties
$script:WinSkuNames = @{
    4 = 'Enterprise'; 27 = 'EnterpriseN'; 48 = 'Professional'; 49 = 'BusinessN'
    72 = 'EnterpriseEval'; 84 = 'EnterpriseNEval'; 98 = 'CoreN'; 99 = 'CoreCountrySpecific'
    100 = 'CoreSingleLanguage'; 101 = 'Core'; 111 = 'Core'; 119 = 'PPIPro'
    121 = 'Education'; 122 = 'EducationN'; 123 = 'IoTUAP'; 125 = 'EnterpriseS'
    126 = 'EnterpriseSN'; 129 = 'EnterpriseSEval'; 131 = 'IoTUAPCommercial'; 136 = 'Holographic'
    138 = 'ProfessionalSingleLanguage'; 161 = 'ProfessionalWorkstation'; 162 = 'ProfessionalN'
    164 = 'ProfessionalEducation'; 165 = 'ProfessionalEducationN'; 171 = 'EnterpriseG'
    172 = 'EnterpriseGN'; 175 = 'ServerRdsh'; 188 = 'IoTEnterprise'
    202 = 'CloudEditionN'; 203 = 'CloudEdition'
}

function Get-FilterDeviceValue {
    # Maps a filter rule property (device.xxx) onto managedDevice fields.
    # Returns $null (not '') when the device data cannot answer the question.
    param([string]$PropRef, $Md)
    $p = ($PropRef -replace '^(?i)device\.', '').ToLowerInvariant()
    switch ($p) {
        'devicename'             { return [string](Get-Prop $Md 'deviceName') }
        'manufacturer'           { return [string](Get-Prop $Md 'manufacturer') }
        'model'                  { return [string](Get-Prop $Md 'model') }
        'osversion'              { return [string](Get-Prop $Md 'osVersion') }
        'operatingsystemversion' { return [string](Get-Prop $Md 'osVersion') }
        'operatingsystemsku'     {
            # The rule compares against SKU *names* (Enterprise, Professional, ...) which
            # correspond to the numeric skuNumber; skuFamily is only a fallback.
            $n = Get-Prop $Md 'skuNumber'
            $ni = 0
            if ($null -ne $n -and [int]::TryParse([string]$n, [ref]$ni) -and $script:WinSkuNames.ContainsKey($ni)) {
                return [string]$script:WinSkuNames[$ni]
            }
            $fam = [string](Get-Prop $Md 'skuFamily')
            if ($fam) { return $fam }
            return $null
        }
        'enrollmentprofilename'  { return [string](Get-Prop $Md 'enrollmentProfileName') }
        'devicecategory'         { return [string](Get-Prop $Md 'deviceCategoryDisplayName') }
        'deviceownership'        {
            $o = [string](Get-Prop $Md 'ownerType')
            if ($o -ieq 'company') { return 'Corporate' }
            if ($o -ieq 'personal') { return 'Personal' }
            return $o
        }
        'devicetrusttype'        {
            # joinType 'azureADJoined' vs rule literal 'Azure AD joined' - Compare-FilterValue
            # normalizes whitespace on both sides for this property.
            return [string](Get-Prop $Md 'joinType')
        }
        'isrooted'               {
            $j = [string](Get-Prop $Md 'jailBroken')
            if ($j) { return $j }
            return $null
        }
        default                  { return $null }
    }
}

function Compare-FilterValue {
    # Single comparison; returns $true/$false, or $null when it cannot be decided.
    # $Prop = normalized rule property name; $RightIsBare = value was an unquoted token
    # (needed to give -eq $null / -eq Null the documented "is empty" semantics).
    param($Left, [string]$Op, $Right, [string]$Prop = '', [bool]$RightIsBare = $false)
    # $null = property unknown to the local evaluator -> undecidable; '' = known-empty -> comparable
    if ($null -eq $Left) { return $null }
    $l = ([string]$Left).Trim().ToLowerInvariant()

    if ($RightIsBare -and ([string]$Right) -match '^\$?null$') {
        switch ($Op) {
            '-eq' { return ($l -eq '') }
            '-ne' { return ($l -ne '') }
            default { return $null }
        }
    }

    # deviceTrustType inventory values have no spaces ('azureADJoined') while rule
    # literals do ('Azure AD joined') - compare that property whitespace-insensitively.
    $norm = { param($x) (([string]$x) -replace '\s', '').ToLowerInvariant() }
    $wsInsensitive = ($Prop -eq 'devicetrusttype')

    switch ($Op) {
        '-eq'            {
            if ($wsInsensitive) { return ((& $norm $Left) -eq (& $norm $Right)) }
            return $l -eq ([string]$Right).Trim().ToLowerInvariant()
        }
        '-ne'            { return -not (Compare-FilterValue -Left $Left -Op '-eq' -Right $Right -Prop $Prop) }
        '-startswith'    { return $l.StartsWith(([string]$Right).ToLowerInvariant()) }
        '-notstartswith' { return -not $l.StartsWith(([string]$Right).ToLowerInvariant()) }
        '-endswith'      { return $l.EndsWith(([string]$Right).ToLowerInvariant()) }
        '-notendswith'   { return -not $l.EndsWith(([string]$Right).ToLowerInvariant()) }
        '-contains'      { return $l.Contains(([string]$Right).ToLowerInvariant()) }
        '-notcontains'   { return -not $l.Contains(([string]$Right).ToLowerInvariant()) }
        '-in'            {
            foreach ($r in @($Right)) {
                if ($wsInsensitive) { if ((& $norm $Left) -eq (& $norm $r)) { return $true } }
                elseif ($l -eq ([string]$r).Trim().ToLowerInvariant()) { return $true }
            }
            return $false
        }
        '-notin'         { return -not (Compare-FilterValue -Left $Left -Op '-in' -Right $Right -Prop $Prop) }
        { $_ -in @('-gt', '-ge', '-lt', '-le') } {
            $lv = $null; $rv = $null
            if ([version]::TryParse([string]$Left, [ref]$lv) -and [version]::TryParse([string]$Right, [ref]$rv)) {
                switch ($Op) { '-gt' { return $lv -gt $rv } '-ge' { return $lv -ge $rv } '-lt' { return $lv -lt $rv } '-le' { return $lv -le $rv } }
            }
            return $null
        }
        default          { return $null }
    }
}

function Test-FilterRuleLocal {
    # Parses and evaluates an Intune filter rule against a managedDevice, entirely locally.
    # Returns $true / $false / $null (couldn't parse or property unavailable).
    param([string]$Rule, $Md)
    try {
        $toks = ConvertTo-FilterTokens -Rule $Rule
        $state = @{ i = 0; t = $toks }

        $peek = { if ($state.i -lt $state.t.Count) { $state.t[$state.i] } else { $null } }
        $take = { $tk = & $peek; $state.i++; $tk }

        # three-valued logic combinators ('fOr' would collide with the 'for' keyword)
        function Merge-TriAnd($a, $b) { if ($a -eq $false -or $b -eq $false) { return $false }; if ($null -eq $a -or $null -eq $b) { return $null }; return $true }
        function Merge-TriOr($a, $b)  { if ($a -eq $true -or $b -eq $true) { return $true };  if ($null -eq $a -or $null -eq $b) { return $null }; return $false }

        $parsePrimary = $null; $parseUnary = $null; $parseAnd = $null; $parseOr = $null

        $parsePrimary = {
            $tk = & $peek
            if ($null -eq $tk) { throw 'unexpected end' }
            if ($tk.T -eq '(') {
                [void](& $take)
                $v = & $parseOr
                $tk2 = & $take
                if ($null -eq $tk2 -or $tk2.T -ne ')') { throw 'expected )' }
                return $v
            }
            if ($tk.T -ne 'id') { throw "expected property, got '$($tk.V)'" }
            [void](& $take)
            $propRef = $tk.V
            $opTok = & $take
            if ($null -eq $opTok -or $opTok.T -ne 'op') { throw 'expected operator' }
            $valTok = & $peek
            $right = $null
            $rightIsBare = $false
            if ($null -ne $valTok -and $valTok.T -eq '[') {
                [void](& $take)
                $list = @()
                while ($true) {
                    $t2 = & $take
                    if ($null -eq $t2) { throw 'unterminated list' }
                    if ($t2.T -eq ']') { break }
                    if ($t2.T -eq ',') { continue }
                    $list += [string]$t2.V
                }
                $right = $list
            } else {
                $t2 = & $take
                if ($null -eq $t2) { throw 'expected value' }
                $right = [string]$t2.V
                $rightIsBare = ($t2.T -eq 'id')
            }
            $prop = ($propRef -replace '^(?i)(device|app)\.', '').ToLowerInvariant()
            $left = Get-FilterDeviceValue -PropRef $propRef -Md $Md
            return (Compare-FilterValue -Left $left -Op $opTok.V -Right $right -Prop $prop -RightIsBare $rightIsBare)
        }
        $parseUnary = {
            $tk = & $peek
            if ($null -ne $tk -and $tk.T -eq 'kw' -and $tk.V -eq 'not') {
                [void](& $take)
                $v = & $parseUnary
                if ($null -eq $v) { return $null }
                return (-not $v)
            }
            return (& $parsePrimary)
        }
        $parseAnd = {
            $v = & $parseUnary
            while ($true) {
                $tk = & $peek
                if ($null -ne $tk -and $tk.T -eq 'kw' -and $tk.V -eq 'and') { [void](& $take); $r = & $parseUnary; $v = Merge-TriAnd $v $r }
                else { break }
            }
            return $v
        }
        $parseOr = {
            $v = & $parseAnd
            while ($true) {
                $tk = & $peek
                if ($null -ne $tk -and $tk.T -eq 'kw' -and $tk.V -eq 'or') { [void](& $take); $r = & $parseAnd; $v = Merge-TriOr $v $r }
                else { break }
            }
            return $v
        }

        $result = & $parseOr
        if ($state.i -lt $state.t.Count) { throw 'trailing tokens' }
        return $result
    } catch {
        return $null
    }
}

$script:FilterMatchSetCache = @{}

function Get-FilterMatchSet {
    # Fully evaluates a filter server-side (paged) into id/name lookup sets, once per
    # filter per run. Complete=$false means the result was capped, so a device being
    # absent from the set proves nothing.
    param($FilterObj, [int]$Cap = 2000)
    $fid = [string]$FilterObj.Id
    if ($script:FilterMatchSetCache.ContainsKey($fid)) { return $script:FilterMatchSetCache[$fid] }

    $set = $null
    try {
        $ids = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $names = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $skip = 0; $count = 0; $complete = $false
        while ($true) {
            $batch = @(Invoke-FilterEvaluate -FilterObj $FilterObj -Top 100 -Skip $skip)
            foreach ($r in $batch) {
                $count++
                foreach ($p in @($r.PSObject.Properties)) {
                    $pn = $p.Name.ToLower()
                    if ($pn -match '^(deviceid|intunedeviceid)$' -and $p.Value) { [void]$ids.Add([string]$p.Value) }
                    elseif ($pn -match 'devicename' -and $p.Value) { [void]$names.Add([string]$p.Value) }
                }
            }
            if ($batch.Count -lt 100) { $complete = $true; break }
            if ($count -ge $Cap) { break }
            $skip += 100
        }
        $set = @{ Ids = $ids; Names = $names; Complete = $complete }
        if (-not $complete) {
            Add-RunLog -Level warn -Message ("Filter '{0}' matches more than {1} devices; absence from the evaluation set is treated as unknown, not as non-match." -f $FilterObj.Name, $Cap)
        }
    } catch {
        Add-RunLog -Level info -Message ("Full server-side evaluation of filter '{0}' failed: {1}" -f $FilterObj.Name, $_.Exception.Message)
        $set = $null
    }
    $script:FilterMatchSetCache[$fid] = $set
    return $set
}

function Test-DeviceMatchesFilter {
    # Layered: (1) local rule evaluation against live inventory (the server-side report
    # lags enrollment and pages at 100 rows, so a device missing from it proves nothing),
    # (2) server-side evaluateAssignmentFilter scoped by device-name search for positive
    # evidence, (3) full paged server evaluation - absence only counts as non-match when
    # that set is complete. Cached per (filter, device).
    param([string]$FilterId, $ManagedDevice)

    $mdId = [string](Get-Prop $ManagedDevice 'id')
    $mdName = [string](Get-Prop $ManagedDevice 'deviceName')
    $cacheKey = "$FilterId|$mdId"
    if ($script:FilterEvalCache.ContainsKey($cacheKey)) { return $script:FilterEvalCache[$cacheKey] }

    $flt = $null
    if ($script:FilterById.ContainsKey($FilterId)) { $flt = $script:FilterById[$FilterId] }
    if ($null -eq $flt) {
        Add-RunLog -Level warn -Message ("Assignment referenced unknown filter id {0}" -f $FilterId)
        $script:FilterEvalCache[$cacheKey] = 'error'; return 'error'
    }

    $result = 'error'

    $local = Test-FilterRuleLocal -Rule $flt.Rule -Md $ManagedDevice
    if ($local -is [bool]) {
        Add-RunLog -Level info -Message ("Filter '{0}' evaluated locally for '{1}': {2}" -f $flt.Name, $mdName, $local)
        $script:FilterEvalCache[$cacheKey] = $local
        return $local
    }
    Add-RunLog -Level info -Message ("Filter '{0}' rule not locally decidable for '{1}'; asking the service. Rule: {2}" -f $flt.Name, $mdName, $flt.Rule)

    if ($mdName) {
        try {
            $rows = Invoke-FilterEvaluate -FilterObj $flt -Search $mdName
            foreach ($r in @($rows)) {
                foreach ($p in @($r.PSObject.Properties)) {
                    $pn = $p.Name.ToLower()
                    if ($pn -match 'devicename' -and [string]$p.Value -ieq $mdName) { $result = $true; break }
                    if ($pn -match '^(deviceid|intunedeviceid)$' -and [string]$p.Value -ieq $mdId) { $result = $true; break }
                }
                if ($result -eq $true) { break }
            }
        } catch {
            Add-RunLog -Level info -Message ("Search-scoped evaluation of filter '{0}' failed ({1})." -f $flt.Name, $_.Exception.Message)
        }
    }

    if ($result -isnot [bool]) {
        $set = Get-FilterMatchSet -FilterObj $flt
        if ($null -ne $set) {
            if (($mdId -and $set.Ids.Contains($mdId)) -or ($mdName -and $set.Names.Contains($mdName))) { $result = $true }
            elseif ($set.Complete) { $result = $false }
            else { $result = 'error' }
        }
    }

    if ($result -isnot [bool]) {
        Add-RunLog -Level error -Message ("Filter '{0}' could not be conclusively evaluated for '{1}'. Rule: {2}" -f $flt.Name, $mdName, $flt.Rule)
    }
    $script:FilterEvalCache[$cacheKey] = $result
    return $result
}

function Get-FilterMatchedDevices {
    # Full evaluation of a filter -> managed devices (used for -AssignmentFilter mode).
    # Falls back to local rule evaluation across the device index when the service call fails.
    param($FilterObj, [int]$Cap = 2000)
    $rows = New-Object System.Collections.Generic.List[object]
    $skip = 0
    try {
        while ($true) {
            $batch = @(Invoke-FilterEvaluate -FilterObj $FilterObj -Top 100 -Skip $skip)
            foreach ($b in $batch) { [void]$rows.Add($b) }
            if ($batch.Count -lt 100 -or $rows.Count -ge $Cap) { break }
            $skip += 100
        }
    } catch {
        Write-Warn2 ("Server-side evaluation of filter '{0}' failed ({1}); evaluating the rule locally across the device index." -f $FilterObj.Name, $_.Exception.Message)
        $idx = Get-DeviceIndex
        $matched = New-Object System.Collections.Generic.List[object]
        $undecided = 0
        foreach ($d in $idx) {
            $v = Test-FilterRuleLocal -Rule $FilterObj.Rule -Md $d
            if ($v -is [bool]) { if ($v) { [void]$matched.Add($d) } }
            else { $undecided++ }
        }
        if ($undecided -gt 0) {
            Write-Warn2 ("Filter rule could not be evaluated locally for {0} devices; they are not included." -f $undecided)
        }
        return $matched.ToArray()
    }
    if ($rows.Count -ge $Cap) { Write-Warn2 ("Filter preview capped at {0} devices." -f $Cap) }

    # Map preview rows back to managed devices (by id column when present, else by name).
    $idx = Get-DeviceIndex
    $byId = @{}; $byName = @{}
    foreach ($d in $idx) {
        $byId[[string](Get-Prop $d 'id')] = $d
        $byName[([string](Get-Prop $d 'deviceName')).ToLower()] = $d
    }
    $out = New-Object System.Collections.Generic.List[object]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($r in $rows) {
        $md = $null
        foreach ($p in @($r.PSObject.Properties)) {
            $pn = $p.Name.ToLower()
            if ($pn -match '^(deviceid|intunedeviceid)$' -and $byId.ContainsKey([string]$p.Value)) { $md = $byId[[string]$p.Value]; break }
        }
        if ($null -eq $md) {
            foreach ($p in @($r.PSObject.Properties)) {
                if ($p.Name.ToLower() -match 'devicename') {
                    $k = ([string]$p.Value).ToLower()
                    if ($byName.ContainsKey($k)) { $md = $byName[$k] }
                    break
                }
            }
        }
        if ($null -ne $md) {
            $mid = [string](Get-Prop $md 'id')
            if ($seen.Add($mid)) { [void]$out.Add($md) }
        }
    }
    return $out.ToArray()
}

#endregion

#region ---------- applicability engine ------------------------------------------------------

function Get-PolicyApplicability {
    # Evaluates one policy's assignments against one device context.
    # Returns Status: Applies | Excluded | FilteredOut | Unknown | NotTargeted (+ Reasons).
    # Exclusions are kind-aware per the Intune support matrix: user-group exclusions do
    # not undo device-targeted includes (All devices / device groups) and vice versa,
    # because Intune doesn't evaluate user-to-device group relationships.
    param($Policy, $Ctx)

    $md = $Ctx.ManagedDevice
    $reasons = New-Object System.Collections.Generic.List[string]
    $excludeReasons = New-Object System.Collections.Generic.List[string]
    $filteredNotes = New-Object System.Collections.Generic.List[string]
    $unknownNotes = New-Object System.Collections.Generic.List[string]
    $applies = $false

    $deviceExcl = New-Object System.Collections.Generic.List[string]
    $userExcl = New-Object System.Collections.Generic.List[string]
    foreach ($a in @($Policy.Assignments)) {
        if ([string]$a.Type -notlike '*exclusionGroupAssignmentTarget*') { continue }
        if (-not $a.GroupId) { continue }
        if ($Ctx.DeviceGroupIds.Contains($a.GroupId)) { [void]$deviceExcl.Add((Get-GroupName $a.GroupId)) }
        if ($Ctx.UserGroupIds.Contains($a.GroupId)) { [void]$userExcl.Add((Get-GroupName $a.GroupId)) }
    }

    $hadDeviceInclude = $false; $hadUserInclude = $false
    $pathExcluded = $false

    foreach ($a in @($Policy.Assignments)) {
        $type = [string]$a.Type
        if ($type -like '*exclusionGroupAssignmentTarget*') { continue }

        $base = $null
        $kind = ''
        switch -Wildcard ($type) {
            '*allDevicesAssignmentTarget*'       { $base = 'All devices'; $kind = 'device' }
            '*allLicensedUsersAssignmentTarget*' {
                if ($Ctx.HasPrimaryUser) { $base = 'All users (via primary user)'; $kind = 'user' }
            }
            '*groupAssignmentTarget*' {
                if ($a.GroupId) {
                    if ($Ctx.DeviceGroupIds.Contains($a.GroupId)) { $base = ("Device group '{0}'" -f (Get-GroupName $a.GroupId)); $kind = 'device' }
                    elseif ($Ctx.UserGroupIds.Contains($a.GroupId)) { $base = ("User group '{0}' (via primary user)" -f (Get-GroupName $a.GroupId)); $kind = 'user' }
                }
            }
        }
        if ($null -eq $base) { continue }
        if ($kind -eq 'device') { $hadDeviceInclude = $true } elseif ($kind -eq 'user') { $hadUserInclude = $true }

        # same-kind exclusion beats the include (and its filter) for this path
        if ($kind -eq 'device' -and $deviceExcl.Count -gt 0) {
            $pathExcluded = $true
            [void]$excludeReasons.Add(("{0} - excluded via device group '{1}'" -f $base, (@($deviceExcl) -join "', '")))
            continue
        }
        if ($kind -eq 'user' -and $userExcl.Count -gt 0) {
            $pathExcluded = $true
            [void]$excludeReasons.Add(("{0} - excluded via user group '{1}' (via primary user)" -f $base, (@($userExcl) -join "', '")))
            continue
        }

        $filterOk = $true
        $filterNote = ''
        if ($a.FilterId -and $a.FilterType -and $a.FilterType -ne 'none') {
            $fname = $a.FilterId
            if ($script:FilterById.ContainsKey($a.FilterId)) { $fname = $script:FilterById[$a.FilterId].Name }
            $inFilter = Test-DeviceMatchesFilter -FilterId $a.FilterId -ManagedDevice $md
            # type check, not -eq: in PowerShell ($true -eq 'error') coerces and is $true
            if ($inFilter -isnot [bool]) {
                [void]$unknownNotes.Add(("{0} + filter '{1}' ({2}) - filter evaluation failed, applicability unknown" -f $base, $fname, $a.FilterType))
                continue
            }
            if ($a.FilterType -ieq 'include') {
                $filterOk = [bool]$inFilter
                $filterNote = (" + include filter '{0}' ({1})" -f $fname, $(if ($inFilter) { 'matched' } else { 'NOT matched' }))
            }
            elseif ($a.FilterType -ieq 'exclude') {
                $filterOk = -not [bool]$inFilter
                $filterNote = (" + exclude filter '{0}' ({1})" -f $fname, $(if ($inFilter) { 'matched - excluded' } else { 'not matched' }))
            }
        }

        if ($filterOk) {
            $applies = $true
            [void]$reasons.Add($base + $filterNote)
        } else {
            [void]$filteredNotes.Add($base + $filterNote)
        }
    }

    # Cross-kind exclusions that Intune ignores: surface them rather than applying them.
    $mixNotes = @()
    if ($userExcl.Count -gt 0 -and $hadDeviceInclude) {
        $mixNotes += ("note: user-group exclusion '{0}' does not affect device-targeted assignments (Intune doesn't evaluate user-to-device relationships)" -f (@($userExcl) -join "', '"))
    }
    if ($deviceExcl.Count -gt 0 -and $hadUserInclude) {
        $mixNotes += ("note: device-group exclusion '{0}' does not affect user-targeted assignments (Intune doesn't evaluate user-to-device relationships)" -f (@($deviceExcl) -join "', '"))
    }

    if ($applies) {
        $all = @($reasons)
        if ($excludeReasons.Count -gt 0) { $all += @($excludeReasons | ForEach-Object { "(other path excluded: $_)" }) }
        if ($filteredNotes.Count -gt 0) { $all += @($filteredNotes | ForEach-Object { "(other path filtered out: $_)" }) }
        $all += $mixNotes
        return [pscustomobject]@{ Status = 'Applies'; Reasons = $all }
    }
    if ($unknownNotes.Count -gt 0) {
        # an undecided filter path could still make the policy apply, so Unknown
        # outranks Excluded/FilteredOut
        return [pscustomobject]@{ Status = 'Unknown'; Reasons = (@($unknownNotes) + @($excludeReasons) + $mixNotes) }
    }
    if ($pathExcluded) {
        return [pscustomobject]@{ Status = 'Excluded'; Reasons = (@($excludeReasons) + @($filteredNotes | ForEach-Object { "(other path filtered out: $_)" }) + $mixNotes) }
    }
    if ($filteredNotes.Count -gt 0) {
        return [pscustomobject]@{ Status = 'FilteredOut'; Reasons = (@($filteredNotes) + $mixNotes) }
    }
    if ($deviceExcl.Count -gt 0 -or $userExcl.Count -gt 0) {
        # member of an excluded group but no include path targets the device anyway
        $names = @(@($deviceExcl) + @($userExcl) | Select-Object -Unique)
        return [pscustomobject]@{ Status = 'Excluded'; Reasons = @(("Member of excluded group '{0}' (no include path targets this device)" -f ($names -join "', '"))) }
    }
    return [pscustomobject]@{ Status = 'NotTargeted'; Reasons = @() }
}

#endregion

#region ---------- reported status (device truth) --------------------------------------------

function Get-ReportedPolicyStatus {
    # What the device actually reported, via the same endpoint the portal's per-device
    # Configuration blade uses. Returns @{ policyIdLower = @{Status=..; Name=..} }
    param([string]$IntuneDeviceId)
    $map = @{}
    # Best-effort mapping of the report's numeric PolicyStatus (raw value is kept alongside).
    $statusMap = @{
        0 = 'Unknown'; 1 = 'Not applicable'; 2 = 'Succeeded'; 3 = 'Remediated';
        4 = 'Not compliant'; 5 = 'Error'; 6 = 'Conflict'; 7 = 'Not assigned'
    }
    # The service rejects a bare IntuneDeviceId filter with 400 on some tenants; the
    # portal always scopes the report to the supported policy base types, so mirror
    # its request shape first and fall back to simpler bodies from there.
    $baseTypeClause = "((PolicyBaseTypeName eq 'Microsoft.Management.Services.Api.DeviceConfiguration') " +
        "or (PolicyBaseTypeName eq 'DeviceManagementConfigurationPolicy') " +
        "or (PolicyBaseTypeName eq 'DeviceConfigurationAdmxPolicy') " +
        "or (PolicyBaseTypeName eq 'Microsoft.Management.Services.Api.DeviceManagementIntent'))"
    try {
        $rows = @()
        $skip = 0
        while ($true) {
            $portalBody = @{
                select  = @('IntuneDeviceId', 'PolicyBaseTypeName', 'PolicyId', 'PolicyStatus', 'UPN', 'UserId', 'PolicyName', 'UnifiedPolicyType')
                filter  = ("{0} and (IntuneDeviceId eq '{1}')" -f $baseTypeClause, $IntuneDeviceId)
                skip    = $skip
                top     = 50
                orderBy = @('PolicyName')
            }
            $simpleBody = @{
                select = @('PolicyId', 'PolicyName', 'PolicyStatus', 'UPN', 'PolicyBaseTypeName')
                filter = "(IntuneDeviceId eq '$IntuneDeviceId')"
                skip   = $skip
                top    = 50
            }
            $reportUri = 'beta/deviceManagement/reports/getConfigurationPoliciesReportForDevice'
            try {
                # report responses are a Stream; read via temp file (see Invoke-RsopStream)
                $resp = Invoke-RsopStream -Uri $reportUri -Body $portalBody
            } catch {
                Add-RunLog -Level info -Message ("device report (portal-shaped) failed: {0}; retrying with simple filter" -f $_.Exception.Message)
                try {
                    $resp = Invoke-RsopStream -Uri $reportUri -Body $simpleBody
                } catch {
                    Add-RunLog -Level info -Message ("device report (simple filter) failed: {0}; retrying parsed inline" -f $_.Exception.Message)
                    $resp = Invoke-Rsop -Method POST -Uri $reportUri -Body $portalBody
                }
            }
            $batch = @(ConvertFrom-ReportGrid -Response $resp)
            $rows += $batch
            if ($batch.Count -lt 50 -or $skip -gt 1000) { break }
            $skip += 50
        }
        foreach ($r in @($rows)) {
            $polId = [string](Get-Prop $r 'PolicyId')
            if (-not $polId) { continue }
            $statusRaw = Get-Prop $r 'PolicyStatus'
            $statusTxt = "$statusRaw"
            $si = 0
            if ([int]::TryParse("$statusRaw", [ref]$si) -and $statusMap.ContainsKey($si)) {
                $statusTxt = ("{0} ({1})" -f $statusMap[$si], $si)
            }
            $key = $polId.ToLower()
            if (-not $map.ContainsKey($key)) {
                $map[$key] = [pscustomobject]@{
                    Status = $statusTxt
                    Name   = [string](Get-Prop $r 'PolicyName')
                    Upn    = [string](Get-Prop $r 'UPN')
                }
            }
        }
    } catch {
        Add-RunLog -Level warn -Message ("Reported-status lookup failed for device {0}: {1}" -f $IntuneDeviceId, $_.Exception.Message)
    }
    return $map
}

#endregion

#region ---------- per-device orchestration --------------------------------------------------

function Resolve-DeviceRsop {
    param($ManagedDevice, $Corpus)

    $md = $ManagedDevice
    $mdName = [string](Get-Prop $md 'deviceName')
    Write-Step ("Resolving device: {0}  (serial: {1})" -f $mdName, (Get-Prop $md 'serialNumber'))

    $ctx = Get-DeviceContext -ManagedDevice $md
    Write-Info ("Entra groups - device: {0}, primary user: {1}" -f $ctx.DeviceGroupIds.Count, $ctx.UserGroupIds.Count)

    # Resolve display names for every group referenced by any assignment - membership
    # reasons, exclusions AND the per-policy assignment breakdown all need names, not GUIDs.
    $mentioned = New-Object System.Collections.Generic.List[string]
    foreach ($p in @($Corpus.policies)) {
        foreach ($a in @($p.Assignments)) {
            if ($a.GroupId) { [void]$mentioned.Add([string]$a.GroupId) }
        }
    }
    Resolve-GroupNames -Ids $mentioned.ToArray()

    $os = [string](Get-Prop $md 'operatingSystem')
    $devPlatform = 'other'
    if ($os -match 'Windows') { $devPlatform = 'windows' }
    elseif ($os -match 'macOS|Mac OS') { $devPlatform = 'macos' }
    elseif ($os -match 'iOS|iPadOS') { $devPlatform = 'ios' }
    elseif ($os -match 'Android') { $devPlatform = 'android' }
    elseif ($os -match 'Linux') { $devPlatform = 'linux' }

    $policyResults = New-Object System.Collections.Generic.List[object]
    $settingRows = New-Object System.Collections.Generic.List[object]
    $shadowRows = New-Object System.Collections.Generic.List[object]   # settings of targeted-but-not-applying policies (report "near misses")

    $evalPolicies = @($Corpus.policies | Where-Object { @($_.Assignments).Count -gt 0 })
    $n = 0
    foreach ($p in $evalPolicies) {
        $n++
        Write-Progress -Id 5 -Activity ("Evaluating policies for {0}" -f $mdName) -Status ("{0}/{1}  {2}" -f $n, $evalPolicies.Count, $p.Name) -PercentComplete ([int](100 * $n / [math]::Max(1, $evalPolicies.Count)))

        if ($devPlatform -ne 'other' -and $p.Platform -ne 'other' -and $p.Platform -ne $devPlatform) { continue }

        $app = Get-PolicyApplicability -Policy $p -Ctx $ctx
        if ($app.Status -eq 'NotTargeted') { continue }

        $entry = [pscustomobject]@{
            PolicyId    = $p.Id
            Name        = $p.Name
            Family      = $p.Family
            FamilyLabel = $p.FamilyLabel
            Intent      = [string]$p.Intent
            Status      = $app.Status
            Via         = (@($app.Reasons) -join ' | ')
            Reported    = ''
            SettingCount = @($p.Settings).Count
            Modified    = [string]$p.Modified
            Detail      = [string]$p.Detail
            Desc        = [string]$p.Desc
            Assignment  = (ConvertTo-AssignmentSummary -Assignments $p.Assignments)
            AssignmentDetail = @(ConvertTo-AssignmentDetail -Assignments $p.Assignments)
        }
        [void]$policyResults.Add($entry)

        if ($app.Status -eq 'Applies' -or $app.Status -eq 'Unknown') {
            $tag = ''
            if ($app.Status -eq 'Unknown') { $tag = ' [applicability unknown]' }
            foreach ($s in @($p.Settings)) {
                [void]$settingRows.Add([pscustomobject]@{
                    Key         = $s.Key
                    Setting     = $s.Setting
                    Value       = $s.Value
                    Category    = [string]$s.Category
                    PolicyId    = $p.Id
                    PolicyName  = $p.Name + $tag
                    FamilyLabel = $p.FamilyLabel
                    Via         = $entry.Via
                    Conflict    = ''
                })
            }
        }
        elseif (($app.Status -eq 'Excluded' -or $app.Status -eq 'FilteredOut') -and $shadowRows.Count -lt 4000) {
            foreach ($s in @($p.Settings)) {
                [void]$shadowRows.Add([pscustomobject]@{
                    Key         = $s.Key
                    Setting     = $s.Setting
                    Value       = $s.Value
                    Category    = [string]$s.Category
                    PolicyId    = $p.Id
                    PolicyName  = $p.Name
                    FamilyLabel = $p.FamilyLabel
                    Via         = $entry.Via
                    Status      = $app.Status
                })
            }
        }
    }
    if ($shadowRows.Count -ge 4000) {
        Add-RunLog -Level info -Message ("{0}: settings of excluded/filtered policies capped at 4000 rows for report size" -f $mdName)
    }
    Write-Progress -Id 5 -Activity ("Evaluating policies for {0}" -f $mdName) -Completed

    # Cross-check with what the device actually reported.
    if (-not $SkipReportedStatus) {
        $reported = Get-ReportedPolicyStatus -IntuneDeviceId ([string](Get-Prop $md 'id'))
        $known = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($pr in $policyResults) {
            [void]$known.Add(([string]$pr.PolicyId).ToLower())
            $k = ([string]$pr.PolicyId).ToLower()
            if ($reported.ContainsKey($k)) { $pr.Reported = $reported[$k].Status }
            elseif ($pr.Status -eq 'Applies' -and $pr.Family -ne 'app') { $pr.Reported = 'not in device report' }
        }
        foreach ($k in $reported.Keys) {
            if (-not $known.Contains($k)) {
                $r = $reported[$k]
                [void]$policyResults.Add([pscustomobject]@{
                    PolicyId    = $k
                    Name        = $r.Name
                    Family      = 'reported'
                    FamilyLabel = 'Reported by device (not predicted - verify targeting)'
                    Intent      = ''
                    Status      = 'ReportedOnly'
                    Via         = 'Device check-in report'
                    Reported    = $r.Status
                    SettingCount = 0
                    Modified    = ''
                    Detail      = ''
                    Desc        = ''
                    Assignment  = ''
                    AssignmentDetail = @()
                })
            }
        }
    }

    # Conflict detection: same setting key from >1 applicable policy.
    $byKey = @{}
    foreach ($row in $settingRows) {
        $k = [string]$row.Key
        if (-not $k) { continue }
        if (-not $byKey.ContainsKey($k)) { $byKey[$k] = New-Object System.Collections.Generic.List[object] }
        [void]$byKey[$k].Add($row)
    }
    $conflicts = New-Object System.Collections.Generic.List[object]
    foreach ($k in $byKey.Keys) {
        $rows = $byKey[$k]
        $policies = @($rows | Select-Object -ExpandProperty PolicyId -Unique)
        if ($policies.Count -lt 2) { continue }
        $values = @($rows | Select-Object -ExpandProperty Value -Unique)
        $flag = if ($values.Count -gt 1) { 'CONFLICT' } else { 'Duplicate' }
        foreach ($r in $rows) { $r.Conflict = $flag }
        if ($flag -eq 'CONFLICT') {
            [void]$conflicts.Add([pscustomobject]@{
                Key     = $k
                Setting = $rows[0].Setting
                Sources = @($rows | ForEach-Object { [pscustomobject]@{ Policy = $_.PolicyName; PolicyId = $_.PolicyId; Value = $_.Value } })
            })
        }
    }

    $applied = @($policyResults | Where-Object { $_.Status -eq 'Applies' })
    Write-Good ("{0}: {1} policies apply, {2} settings, {3} conflicts, {4} excluded/filtered" -f `
        $mdName, $applied.Count, $settingRows.Count, $conflicts.Count, `
        @($policyResults | Where-Object { $_.Status -in @('Excluded', 'FilteredOut') }).Count)

    return [pscustomobject]@{
        Device = [pscustomobject]@{
            DeviceName      = $mdName
            SerialNumber    = [string](Get-Prop $md 'serialNumber')
            IntuneDeviceId  = [string](Get-Prop $md 'id')
            EntraDeviceId   = [string](Get-Prop $md 'azureADDeviceId')
            PrimaryUser     = [string](Get-Prop $md 'userPrincipalName')
            OS              = ("{0} {1}" -f (Get-Prop $md 'operatingSystem'), (Get-Prop $md 'osVersion')).Trim()
            Model           = ("{0} {1}" -f (Get-Prop $md 'manufacturer'), (Get-Prop $md 'model')).Trim()
            LastSync        = [string](Get-Prop $md 'lastSyncDateTime')
            DeviceGroups    = @($ctx.DeviceGroupIds | ForEach-Object { Get-GroupName $_ } | Sort-Object)
            UserGroups      = @($ctx.UserGroupIds | ForEach-Object { Get-GroupName $_ } | Sort-Object)
        }
        Policies  = @($policyResults | Sort-Object @{e = { $_.Status -ne 'Applies' } }, FamilyLabel, Name)
        Settings  = @($settingRows | Sort-Object FamilyLabel, PolicyName, Setting)
        Conflicts = @($conflicts | Sort-Object Setting)
        Shadow    = @($shadowRows | Sort-Object FamilyLabel, PolicyName, Setting)
    }
}

function Get-AssignmentFilterName {
    param($Assignment)
    if (-not ($Assignment.FilterId -and $Assignment.FilterType -and $Assignment.FilterType -ne 'none')) { return $null }
    $fn = $Assignment.FilterId
    if ($script:FilterById.ContainsKey($Assignment.FilterId)) { $fn = $script:FilterById[$Assignment.FilterId].Name }
    return $fn
}

function ConvertTo-AssignmentSummary {
    # Human-readable summary of a policy's assignments (group names + filters).
    param($Assignments)
    $inc = @(); $exc = @()
    foreach ($a in @($Assignments)) {
        $fnote = ''
        $fn = Get-AssignmentFilterName -Assignment $a
        if ($fn) { $fnote = (" [{0} filter: {1}]" -f $a.FilterType, $fn) }
        # break per case: '*groupAssignmentTarget*' also matches the (case-insensitive)
        # exclusion type, and a switch without break runs every matching case
        switch -Wildcard ([string]$a.Type) {
            '*exclusionGroupAssignmentTarget*'   { $exc += ((Get-GroupName $a.GroupId)); break }
            '*allDevicesAssignmentTarget*'       { $inc += ("All devices" + $fnote); break }
            '*allLicensedUsersAssignmentTarget*' { $inc += ("All users" + $fnote); break }
            '*groupAssignmentTarget*'            { $inc += ((Get-GroupName $a.GroupId) + $fnote); break }
        }
    }
    $parts = @()
    if ($inc.Count -gt 0) { $parts += ("Include: " + ($inc -join '; ')) }
    if ($exc.Count -gt 0) { $parts += ("Exclude: " + ($exc -join '; ')) }
    if ($parts.Count -eq 0) { return 'Not assigned' }
    return ($parts -join '  |  ')
}

function ConvertTo-AssignmentDetail {
    # Structured include/exclude breakdown of a policy's assignments - what the report's
    # detail pane renders (target, filter name, filter mode per assignment).
    param($Assignments)
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($a in @($Assignments)) {
        $mode = 'Include'; $target = $null
        switch -Wildcard ([string]$a.Type) {
            '*exclusionGroupAssignmentTarget*'   { $mode = 'Exclude'; $target = ("Group: " + (Get-GroupName $a.GroupId)); break }
            '*allDevicesAssignmentTarget*'       { $target = 'All devices'; break }
            '*allLicensedUsersAssignmentTarget*' { $target = 'All users'; break }
            '*groupAssignmentTarget*'            { $target = ("Group: " + (Get-GroupName $a.GroupId)); break }
            default                              { $target = [string]$a.Type }
        }
        if (-not $target) { continue }
        $fn = Get-AssignmentFilterName -Assignment $a
        [void]$out.Add([pscustomobject]@{
            Mode       = $mode
            Target     = $target
            GroupId    = [string]$a.GroupId
            Filter     = [string]$fn
            FilterMode = $(if ($fn) { [string]$a.FilterType } else { '' })
        })
    }
    # plain array (no unary comma): every call site wraps this in @(), which would
    # otherwise double-wrap the returned array into a single element
    return $out.ToArray()
}

function Get-GroupAssignedRsop {
    # -GroupAssignedOnly: which policies directly reference this group (no device math).
    param($GroupObj, $Corpus)

    $gid = [string]$GroupObj.id
    $gname = [string]$GroupObj.displayName
    $policyResults = New-Object System.Collections.Generic.List[object]
    $settingRows = New-Object System.Collections.Generic.List[object]

    foreach ($p in @($Corpus.policies)) {
        foreach ($a in @($p.Assignments)) {
            if ([string]$a.GroupId -ne $gid) { continue }
            $isExcl = ($a.Type -like '*exclusion*')
            $fnote = ''
            if ($a.FilterId -and $a.FilterType -and $a.FilterType -ne 'none') {
                $fn = $a.FilterId
                if ($script:FilterById.ContainsKey($a.FilterId)) { $fn = $script:FilterById[$a.FilterId].Name }
                $fnote = (" + {0} filter '{1}'" -f $a.FilterType, $fn)
            }
            $status = if ($isExcl) { 'Excluded' } else { 'Applies' }
            $via = $(if ($isExcl) { "Group '$gname' is EXCLUDED$fnote" } else { "Assigned to group '$gname'$fnote" })
            [void]$policyResults.Add([pscustomobject]@{
                PolicyId = $p.Id; Name = $p.Name; Family = $p.Family; FamilyLabel = $p.FamilyLabel
                Intent = [string]$p.Intent
                Status = $status; Via = $via; Reported = ''; SettingCount = @($p.Settings).Count
                Modified = [string]$p.Modified; Detail = [string]$p.Detail; Desc = [string]$p.Desc
                Assignment = (ConvertTo-AssignmentSummary -Assignments $p.Assignments)
                AssignmentDetail = @(ConvertTo-AssignmentDetail -Assignments $p.Assignments)
            })
            if (-not $isExcl) {
                foreach ($s in @($p.Settings)) {
                    [void]$settingRows.Add([pscustomobject]@{
                        Key = $s.Key; Setting = $s.Setting; Value = $s.Value; Category = [string]$s.Category
                        PolicyId = $p.Id; PolicyName = $p.Name; FamilyLabel = $p.FamilyLabel
                        Via = $via; Conflict = ''
                    })
                }
            }
            break
        }
    }

    return [pscustomobject]@{
        Device = [pscustomobject]@{
            DeviceName = "GROUP: $gname"; SerialNumber = ''; IntuneDeviceId = ''; EntraDeviceId = $gid
            PrimaryUser = ''; OS = '(policies directly assigned to this group)'; Model = ''; LastSync = ''
            DeviceGroups = @(); UserGroups = @()
        }
        Policies  = @($policyResults | Sort-Object Status, FamilyLabel, Name)
        Settings  = @($settingRows | Sort-Object FamilyLabel, PolicyName, Setting)
        Conflicts = @()
        Shadow    = @()
    }
}

function Get-TenantInventoryRsop {
    # -All: every policy in the tenant with its settings and an assignment summary.
    # No device math and no conflict detection (policies target different devices).
    # -ScopeGroup / -ScopeFilter narrow the inventory: only policies whose assignments
    # reach the scope group (directly, via a parent group, or via All devices/All users)
    # and/or carry the scope filter are kept, each with the reason spelled out. Policies
    # that only EXCLUDE the scope stay visible as Excluded; their settings go to Shadow.
    param($Corpus, $ScopeGroup, $ScopeFilter)

    # resolve every group name referenced anywhere, once
    $allGids = New-Object System.Collections.Generic.List[string]
    foreach ($p in @($Corpus.policies)) {
        foreach ($a in @($p.Assignments)) { if ($a.GroupId) { [void]$allGids.Add([string]$a.GroupId) } }
    }
    Resolve-GroupNames -Ids $allGids.ToArray()

    $scoped = ($null -ne $ScopeGroup -or $null -ne $ScopeFilter)
    $policyResults = New-Object System.Collections.Generic.List[object]
    $settingRows = New-Object System.Collections.Generic.List[object]
    $shadowRows = New-Object System.Collections.Generic.List[object]

    foreach ($p in @($Corpus.policies)) {
        $summary = ConvertTo-AssignmentSummary -Assignments $p.Assignments
        $assigned = ($summary -ne 'Not assigned')
        $status = $(if ($assigned) { 'Assigned' } else { 'NotAssigned' })
        $via = $summary

        if ($scoped) {
            $inc = New-Object System.Collections.Generic.List[string]
            $exc = New-Object System.Collections.Generic.List[string]
            $fhits = New-Object System.Collections.Generic.List[string]
            $filterOnInclude = $false
            foreach ($a in @($p.Assignments)) {
                $isExcl = ([string]$a.Type -like '*exclusionGroupAssignmentTarget*')
                $target = ''
                switch -Wildcard ([string]$a.Type) {
                    '*allDevicesAssignmentTarget*'       { $target = 'All devices'; break }
                    '*allLicensedUsersAssignmentTarget*' { $target = 'All users'; break }
                    '*GroupAssignmentTarget*'            { if ($a.GroupId) { $target = ("group '{0}'" -f (Get-GroupName $a.GroupId)) }; break }
                }
                $fnote = ''
                $fn = Get-AssignmentFilterName -Assignment $a
                if ($fn) { $fnote = (" [{0} filter: {1}]" -f $a.FilterType, $fn) }

                if ($null -ne $ScopeFilter -and [string]$a.FilterId -ieq [string]$ScopeFilter.Id) {
                    [void]$fhits.Add(("uses {0} filter '{1}' on {2}" -f $a.FilterType, $ScopeFilter.Name, $(if ($target) { $target } else { '(unknown target)' })))
                    if (-not $isExcl) { $filterOnInclude = $true }
                }
                if ($null -ne $ScopeGroup) {
                    if ($a.GroupId) {
                        $how = ''
                        if ([string]$a.GroupId -ieq [string]$ScopeGroup.Id) { $how = ("group '{0}'" -f $ScopeGroup.Name) }
                        elseif ($ScopeGroup.Parents.ContainsKey([string]$a.GroupId)) { $how = ("parent group '{0}'" -f $ScopeGroup.Parents[[string]$a.GroupId]) }
                        if ($how) {
                            if ($isExcl) { [void]$exc.Add(("EXCLUDED via {0}" -f $how)) }
                            else { [void]$inc.Add(("assigned to {0}{1}" -f $how, $fnote)) }
                        }
                    }
                    elseif (-not $isExcl -and ($target -eq 'All devices' -or $target -eq 'All users')) {
                        [void]$inc.Add(("{0} (tenant-wide){1}" -f $target, $fnote))
                    }
                }
            }
            $groupOk = ($null -eq $ScopeGroup) -or ($inc.Count -gt 0 -or $exc.Count -gt 0)
            $filterOk = ($null -eq $ScopeFilter) -or ($fhits.Count -gt 0)
            if (-not ($groupOk -and $filterOk)) { continue }   # out of scope -> dropped

            $inScope = $true
            if ($null -ne $ScopeGroup) { $inScope = ($inc.Count -gt 0) }
            elseif ($null -ne $ScopeFilter) { $inScope = $filterOnInclude }
            $status = $(if ($inScope) { 'Assigned' } else { 'Excluded' })
            $reason = ((@($inc) + @($exc) + @($fhits)) -join '; ')
            $via = ("Scope: {0}  |  {1}" -f $reason, $summary)
        }

        [void]$policyResults.Add([pscustomobject]@{
            PolicyId = $p.Id; Name = $p.Name; Family = $p.Family; FamilyLabel = $p.FamilyLabel
            Intent = [string]$p.Intent
            Status = $status
            Via = $via; Reported = ''; SettingCount = @($p.Settings).Count
            Modified = [string]$p.Modified; Detail = [string]$p.Detail; Desc = [string]$p.Desc
            Assignment = $summary
            AssignmentDetail = @(ConvertTo-AssignmentDetail -Assignments $p.Assignments)
        })

        if ($status -eq 'Excluded') {
            # scope-excluded: keep the settings inspectable via Investigate's rule-out list
            foreach ($s in @($p.Settings)) {
                [void]$shadowRows.Add([pscustomobject]@{
                    Key = $s.Key; Setting = $s.Setting; Value = $s.Value; Category = [string]$s.Category
                    PolicyId = $p.Id; PolicyName = $p.Name; FamilyLabel = $p.FamilyLabel
                    Via = $via; Status = 'Excluded'
                })
            }
            continue
        }
        $tag = $(if ($status -eq 'NotAssigned') { ' [not assigned]' } else { '' })
        foreach ($s in @($p.Settings)) {
            [void]$settingRows.Add([pscustomobject]@{
                Key = $s.Key; Setting = $s.Setting; Value = $s.Value; Category = [string]$s.Category
                PolicyId = $p.Id; PolicyName = ($p.Name + $tag); FamilyLabel = $p.FamilyLabel
                Via = $via; Conflict = ''
            })
        }
    }

    # Counts come straight off the List/array .Count (pwsh 7.6 throws on @($genericList).Count).
    $totalPolicies = @($Corpus.policies).Count
    $assignedCount = @($policyResults | Where-Object { $_.Status -eq 'Assigned' }).Count
    $name = 'TENANT-WIDE INVENTORY'
    $osLine = ("{0} policies ({1} assigned, {2} unassigned)" -f $totalPolicies, $assignedCount, ($totalPolicies - $assignedCount))
    if ($scoped) {
        $bits = @()
        if ($null -ne $ScopeGroup) { $bits += ("group '{0}'" -f $ScopeGroup.Name) }
        if ($null -ne $ScopeFilter) { $bits += ("filter '{0}'" -f $ScopeFilter.Name) }
        $inScopeCount = $policyResults.Count
        $excCount = @($policyResults | Where-Object { $_.Status -eq 'Excluded' }).Count
        $name = 'TENANT INVENTORY (scoped)'
        $osLine = ("scope {0}: {1} of {2} policies in scope ({3} apply, {4} exclude it)" -f `
            ($bits -join ' + '), $inScopeCount, $totalPolicies, $assignedCount, $excCount)
    }
    return [pscustomobject]@{
        Device = [pscustomobject]@{
            DeviceName = $name; SerialNumber = ''; IntuneDeviceId = ''; EntraDeviceId = ''
            PrimaryUser = ''
            OS = $osLine
            Model = ''; LastSync = ''; DeviceGroups = @(); UserGroups = @()
        }
        Policies  = @($policyResults | Sort-Object Status, FamilyLabel, Name)
        Settings  = @($settingRows | Sort-Object FamilyLabel, PolicyName, Setting)
        Conflicts = @()
        Shadow    = @($shadowRows | Sort-Object FamilyLabel, PolicyName, Setting)
    }
}

#endregion

#region ---------- output: console / csv / json / html ---------------------------------------

function Show-ConsoleSummary {
    param($Result)
    $d = $Result.Device
    Write-Host ""
    Write-Host ("DEVICE  {0}" -f $d.DeviceName) -ForegroundColor White
    Write-Host ("        serial {0} | {1} | {2} | user {3}" -f $d.SerialNumber, $d.OS, $d.Model, $d.PrimaryUser) -ForegroundColor DarkGray
    $applied  = @($Result.Policies | Where-Object { $_.Status -in @('Applies', 'Assigned') })
    $excluded = @($Result.Policies | Where-Object { $_.Status -in @('Excluded', 'FilteredOut', 'NotAssigned') })
    $unknown  = @($Result.Policies | Where-Object { $_.Status -in @('Unknown', 'ReportedOnly') })
    Write-Host ("        {0} policies apply | {1} settings | {2} conflicts | {3} excluded/filtered | {4} unknown/reported-only" -f `
        $applied.Count, @($Result.Settings).Count, @($Result.Conflicts).Count, $excluded.Count, $unknown.Count) -ForegroundColor White

    if ($applied.Count -gt 0) {
        $tbl = $applied | Select-Object @{n = 'Policy'; e = { $_.Name } },
            @{n = 'Type'; e = { $_.FamilyLabel } },
            @{n = 'Settings'; e = { $_.SettingCount } },
            @{n = 'Reported'; e = { $_.Reported } },
            @{n = 'Applies via'; e = { $_.Via } } |
            Format-Table -AutoSize -Wrap | Out-String -Width 300
        Write-Host $tbl
    }
    foreach ($x in $excluded) {
        Write-Host ("   EXCLUDED: {0}  <- {1}" -f $x.Name, $x.Via) -ForegroundColor Yellow
    }
    foreach ($x in $unknown) {
        Write-Host ("   {0}: {1}  <- {2}" -f $x.Status.ToUpper(), $x.Name, $x.Via) -ForegroundColor Magenta
    }
    if (@($Result.Conflicts).Count -gt 0) {
        Write-Host ("   CONFLICTS ({0}):" -f @($Result.Conflicts).Count) -ForegroundColor Red
        foreach ($c in $Result.Conflicts) {
            Write-Host ("     - {0}" -f $c.Setting) -ForegroundColor Red
            foreach ($s in $c.Sources) { Write-Host ("         {0}  =>  {1}" -f $s.Policy, $s.Value) -ForegroundColor DarkYellow }
        }
    }
}

function Get-CsvRows {
    param($Results)
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($r in @($Results)) {
        $reportedByPolicy = @{}
        $intentByPolicy = @{}
        foreach ($p in @($r.Policies)) {
            $reportedByPolicy[[string]$p.PolicyId] = [string]$p.Reported
            $intentByPolicy[[string]$p.PolicyId] = [string]$p.Intent
        }
        foreach ($s in @($r.Settings)) {
            $rep = ''
            if ($reportedByPolicy.ContainsKey([string]$s.PolicyId)) { $rep = $reportedByPolicy[[string]$s.PolicyId] }
            $int = ''
            if ($intentByPolicy.ContainsKey([string]$s.PolicyId)) { $int = $intentByPolicy[[string]$s.PolicyId] }
            [void]$rows.Add([pscustomobject]@{
                DeviceName     = $r.Device.DeviceName
                SerialNumber   = $r.Device.SerialNumber
                PolicyType     = $s.FamilyLabel
                AssignmentIntent = $int
                PolicyName     = $s.PolicyName
                Category       = [string]$s.Category
                Setting        = $s.Setting
                Value          = $s.Value
                Conflict       = $s.Conflict
                AppliesVia     = [string]$s.Via
                PolicyReported = $rep
                PolicyId       = $s.PolicyId
                SettingKey     = $s.Key
            })
        }
    }
    return $rows.ToArray()
}

$script:HtmlTemplate = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>__TITLE__</title>
<style>
:root{--bg:#f6f7f9;--card:#ffffff;--ink:#1a1f2b;--muted:#68707f;--line:#e3e6ea;--accent:#2458d6;
--chip:#eef1f5;--red:#c62f2f;--redbg:#fdecec;--amber:#9a6700;--amberbg:#fff3d6;--green:#1a7f37;--greenbg:#e9f7ee;}
@media (prefers-color-scheme: dark){:root{--bg:#12141a;--card:#1b1e27;--ink:#e8eaf0;--muted:#9aa2b1;--line:#2a2f3b;
--accent:#7aa2ff;--chip:#252a36;--red:#ff7b7b;--redbg:#3a2020;--amber:#e3b341;--amberbg:#3a3120;--green:#57d38c;--greenbg:#1d3327;}}
*{box-sizing:border-box}
body{margin:0;font:14px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;background:var(--bg);color:var(--ink);padding:24px}
h1{font-size:20px;margin:0 0 4px}
.sub{color:var(--muted);margin-bottom:18px;font-size:13px}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:16px;margin-bottom:16px}
.row{display:flex;gap:12px;flex-wrap:wrap;align-items:center}
select,input[type=text]{background:var(--card);color:var(--ink);border:1px solid var(--line);border-radius:8px;padding:8px 10px;font-size:14px;min-width:200px}
input[type=text]{flex:1;min-width:240px}
.stats{display:flex;gap:10px;flex-wrap:wrap;margin:12px 0 0}
.stat{background:var(--chip);border-radius:8px;padding:8px 14px;font-size:13px}
.stat b{font-size:16px;display:block}
.tabs{display:flex;gap:4px;margin:16px 0 0;border-bottom:1px solid var(--line)}
.tab{padding:8px 16px;cursor:pointer;border:none;background:none;color:var(--muted);font-size:14px;border-bottom:2px solid transparent}
.tab.active{color:var(--accent);border-bottom-color:var(--accent);font-weight:600}
.tblwrap{overflow-x:auto}
table{border-collapse:collapse;width:100%;font-size:13px}
th{position:sticky;top:0;background:var(--card);text-align:left;padding:8px 10px;border-bottom:2px solid var(--line);color:var(--muted);font-weight:600;white-space:nowrap}
td{padding:6px 10px;border-bottom:1px solid var(--line);vertical-align:top;word-break:break-word}
tr:hover td{background:var(--chip)}
.badge{display:inline-block;padding:1px 8px;border-radius:999px;font-size:11px;font-weight:600;white-space:nowrap}
.b-conflict{background:var(--redbg);color:var(--red)}
.b-dup{background:var(--chip);color:var(--muted)}
.b-applies{background:var(--greenbg);color:var(--green)}
.b-excluded{background:var(--redbg);color:var(--red)}
.b-other{background:var(--amberbg);color:var(--amber)}
.small{color:var(--muted);font-size:12px}
.btn{background:var(--accent);color:#fff;border:none;border-radius:8px;padding:8px 14px;font-size:13px;cursor:pointer}
label.chk{display:flex;align-items:center;gap:6px;color:var(--muted);font-size:13px;white-space:nowrap}
.conf-card{border:1px solid var(--line);border-left:4px solid var(--red);border-radius:8px;padding:10px 14px;margin-bottom:10px}
.conf-card h3{margin:0 0 6px;font-size:14px}
.conf-src{display:flex;justify-content:space-between;gap:16px;padding:3px 0;font-size:13px;border-top:1px dashed var(--line)}
.groups{font-size:12px;color:var(--muted);margin-top:6px}
mark{background:var(--amberbg);color:inherit;border-radius:3px}
</style>
</head>
<body>
<h1>🔍 Intune Lens</h1>
<div class="sub">Query: __QUERY__ &middot; Generated __GENERATED__ &middot; Tenant __TENANT__ &middot; v__VERSION__</div>

<div class="card">
  <div class="row">
    <select id="devSel"></select>
    <input type="text" id="q" placeholder="Search settings, values, policies...">
    <select id="famSel"><option value="">All policy types</option></select>
    <label class="chk"><input type="checkbox" id="confOnly"> conflicts only</label>
    <button class="btn" id="csvBtn">Download CSV</button>
  </div>
  <div class="stats" id="stats"></div>
  <div class="groups" id="groups"></div>
  <div class="tabs">
    <button class="tab active" data-tab="settings">Settings</button>
    <button class="tab" data-tab="policies">Policies</button>
    <button class="tab" data-tab="conflicts">Conflicts</button>
  </div>
</div>

<div class="card" id="pane-settings">
  <div class="tblwrap"><table id="tblSettings">
    <thead><tr><th>Setting</th><th>Value</th><th>Policy</th><th>Type</th><th></th></tr></thead>
    <tbody></tbody>
  </table></div>
  <div class="small" id="rowCount"></div>
</div>

<div class="card" id="pane-policies" style="display:none">
  <div class="tblwrap"><table id="tblPolicies">
    <thead><tr><th>Status</th><th>Policy</th><th>Type</th><th>#Settings</th><th>Device reported</th><th>Applies via</th></tr></thead>
    <tbody></tbody>
  </table></div>
</div>

<div class="card" id="pane-conflicts" style="display:none"><div id="confList"></div></div>

<script>
const DATA = __DATA__;
let cur = 0;

const esc = s => String(s == null ? "" : s).replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));

function init(){
  const sel = document.getElementById("devSel");
  DATA.devices.forEach((d,i)=>{
    const o=document.createElement("option");
    o.value=i; o.textContent=d.Device.DeviceName + (d.Device.SerialNumber? " ("+d.Device.SerialNumber+")":"");
    sel.appendChild(o);
  });
  sel.onchange = ()=>{cur=parseInt(sel.value); buildFamilies(); render();};
  document.getElementById("q").oninput = render;
  document.getElementById("famSel").onchange = render;
  document.getElementById("confOnly").onchange = render;
  document.getElementById("csvBtn").onclick = downloadCsv;
  document.querySelectorAll(".tab").forEach(t=>{
    t.onclick=()=>{
      document.querySelectorAll(".tab").forEach(x=>x.classList.remove("active"));
      t.classList.add("active");
      ["settings","policies","conflicts"].forEach(p=>{
        document.getElementById("pane-"+p).style.display = (t.dataset.tab===p) ? "" : "none";
      });
    };
  });
  buildFamilies(); render();
}

function buildFamilies(){
  const d = DATA.devices[cur];
  const fams = [...new Set(d.Settings.map(s=>s.FamilyLabel))].sort();
  const sel = document.getElementById("famSel");
  sel.innerHTML = '<option value="">All policy types</option>';
  fams.forEach(f=>{const o=document.createElement("option");o.value=f;o.textContent=f;sel.appendChild(o);});
}

function render(){
  const d = DATA.devices[cur];
  const q = document.getElementById("q").value.toLowerCase();
  const fam = document.getElementById("famSel").value;
  const confOnly = document.getElementById("confOnly").checked;

  const applied = d.Policies.filter(p=>p.Status==="Applies").length;
  const excl = d.Policies.filter(p=>p.Status==="Excluded"||p.Status==="FilteredOut").length;
  document.getElementById("stats").innerHTML =
    '<div class="stat"><b>'+applied+'</b>policies apply</div>'+
    '<div class="stat"><b>'+d.Settings.length+'</b>settings</div>'+
    '<div class="stat"><b>'+d.Conflicts.length+'</b>conflicts</div>'+
    '<div class="stat"><b>'+excl+'</b>excluded / filtered out</div>';

  const g = d.Device;
  document.getElementById("groups").innerHTML =
    (g.OS? esc(g.OS)+" &middot; " : "") + (g.PrimaryUser? "user "+esc(g.PrimaryUser)+" &middot; ":"") +
    (g.DeviceGroups && g.DeviceGroups.length ? "device groups: "+esc(g.DeviceGroups.join(", ")) : "") +
    (g.UserGroups && g.UserGroups.length ? " &middot; user groups: "+esc(g.UserGroups.join(", ")) : "");

  // settings table
  const tb = document.querySelector("#tblSettings tbody");
  const frag = document.createDocumentFragment();
  let shown = 0;
  d.Settings.forEach(s=>{
    if (fam && s.FamilyLabel!==fam) return;
    if (confOnly && s.Conflict!=="CONFLICT") return;
    if (q){
      const hay = (s.Setting+" "+s.Value+" "+s.PolicyName+" "+s.FamilyLabel).toLowerCase();
      if (!hay.includes(q)) return;
    }
    shown++;
    const tr = document.createElement("tr");
    let badge = "";
    if (s.Conflict==="CONFLICT") badge = '<span class="badge b-conflict">CONFLICT</span>';
    else if (s.Conflict==="Duplicate") badge = '<span class="badge b-dup">dup</span>';
    tr.innerHTML = "<td>"+esc(s.Setting)+"</td><td>"+esc(s.Value)+"</td><td>"+esc(s.PolicyName)+
      "</td><td class='small'>"+esc(s.FamilyLabel)+"</td><td>"+badge+"</td>";
    frag.appendChild(tr);
  });
  tb.innerHTML=""; tb.appendChild(frag);
  document.getElementById("rowCount").textContent = shown+" of "+d.Settings.length+" settings shown";

  // policies table (same search + type filter as the settings table)
  const pb = document.querySelector("#tblPolicies tbody");
  const pf = document.createDocumentFragment();
  d.Policies.forEach(p=>{
    if (fam && p.FamilyLabel!==fam) return;
    if (q){
      const hay = (p.Name+" "+p.FamilyLabel+" "+(p.Intent||"")+" "+p.Via).toLowerCase();
      if (!hay.includes(q)) return;
    }
    const tr=document.createElement("tr");
    let cls="b-other";
    if(p.Status==="Applies"||p.Status==="Assigned")cls="b-applies"; else if(p.Status==="Excluded"||p.Status==="FilteredOut")cls="b-excluded";
    tr.innerHTML="<td><span class='badge "+cls+"'>"+esc(p.Status)+"</span></td><td>"+esc(p.Name)+(p.Intent?" <span class='small'>("+esc(p.Intent)+")</span>":"")+"</td><td class='small'>"+
      esc(p.FamilyLabel)+"</td><td>"+esc(p.SettingCount)+"</td><td class='small'>"+esc(p.Reported||"")+"</td><td class='small'>"+esc(p.Via)+"</td>";
    pf.appendChild(tr);
  });
  pb.innerHTML=""; pb.appendChild(pf);

  // conflicts
  const cl = document.getElementById("confList");
  if(!d.Conflicts.length){ cl.innerHTML = '<div class="small">No conflicting values among applicable policies. Note: conflicts are matched per setting key; the same OS setting delivered via different policy families (e.g. ADMX vs Settings Catalog) cannot always be correlated.</div>'; }
  else {
    cl.innerHTML = d.Conflicts.map(c=>
      '<div class="conf-card"><h3>'+esc(c.Setting)+'</h3>'+
      c.Sources.map(s=>'<div class="conf-src"><span>'+esc(s.Policy)+'</span><b>'+esc(s.Value)+'</b></div>').join("")+
      '</div>').join("");
  }
}

function downloadCsv(){
  const d = DATA.devices[cur];
  const q = v => '"'+String(v==null?"":v).replace(/"/g,'""')+'"';
  let csv = "DeviceName,SerialNumber,PolicyName,PolicyType,Setting,Value,Conflict\r\n";
  d.Settings.forEach(s=>{
    csv += [q(d.Device.DeviceName),q(d.Device.SerialNumber),q(s.PolicyName),q(s.FamilyLabel),q(s.Setting),q(s.Value),q(s.Conflict)].join(",")+"\r\n";
  });
  const a=document.createElement("a");
  a.href=URL.createObjectURL(new Blob([csv],{type:"text/csv"}));
  a.download="IntuneLens-"+(d.Device.SerialNumber||d.Device.DeviceName).replace(/[^a-z0-9-]/gi,"_")+".csv";
  a.click();
}

init();
</script>
</body>
</html>
'@

function Export-HtmlReport {
    param($Results, [string]$Path, [string]$QueryLabel, [string]$Tenant)
    $payload = [pscustomobject]@{
        query     = $QueryLabel
        generated = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        tenant    = $Tenant
        version   = $script:Version
        warnings  = $script:RunLog.ToArray()
        devices   = @($Results)
    }
    $json = $payload | ConvertTo-Json -Depth 12 -Compress
    $json = $json.Replace('</', '<\/')

    # prefer the rich external template next to the script; fall back to the embedded one
    $templatePath = $script:HtmlTemplatePath
    if (-not $templatePath) { $templatePath = Join-Path $PSScriptRoot 'report-template.html' }
    if (Test-Path $templatePath) { $html = Get-Content -Raw -Path $templatePath }
    else {
        Write-Warn2 "report-template.html not found next to the script - using basic built-in layout."
        $html = $script:HtmlTemplate
    }
    $html = $html.Replace('__DATA__', $json)
    $html = $html.Replace('__TITLE__', ("Intune Lens - " + $QueryLabel))
    $html = $html.Replace('__QUERY__', [System.Net.WebUtility]::HtmlEncode($QueryLabel))
    $html = $html.Replace('__GENERATED__', (Get-Date).ToString('yyyy-MM-dd HH:mm'))
    $html = $html.Replace('__TENANT__', [System.Net.WebUtility]::HtmlEncode($Tenant))
    $html = $html.Replace('__VERSION__', $script:Version)
    Set-Content -Path $Path -Value $html -Encoding UTF8
    Write-Good ("HTML report: {0}" -f (Resolve-Path $Path))
}

#endregion

#region ---------- main -----------------------------------------------------------------------

function Resolve-GroupIdentity {
    # Group picker object / object id / display name -> @{ id; displayName } (or $null).
    param($Value)
    if ($Value -is [System.Collections.IDictionary] -or ($Value.PSObject -and (Get-Prop $Value 'id'))) {
        return [pscustomobject]@{ id = [string](Get-Prop $Value 'id'); displayName = [string](Get-Prop $Value 'displayName') }
    }
    $guid = [guid]::Empty
    if ([guid]::TryParse([string]$Value, [ref]$guid)) {
        $g = Invoke-Rsop -Uri ("v1.0/groups/{0}?`$select=id,displayName" -f $Value)
        return [pscustomobject]@{ id = [string](Get-Prop $g 'id'); displayName = [string](Get-Prop $g 'displayName') }
    }
    $esc = [string]$Value -replace "'", "''"
    $resp = Invoke-Rsop -Uri ("v1.0/groups?`$filter=displayName eq '{0}'&`$select=id,displayName" -f $esc)
    $vals = @($resp['value'])
    if ($vals.Count -gt 1) { Write-Warn2 ("Multiple groups named '{0}'; using the first." -f $Value) }
    if ($vals.Count -eq 0) { return $null }
    return [pscustomobject]@{ id = [string]$vals[0]['id']; displayName = [string]$vals[0]['displayName'] }
}

function Resolve-QueryResults {
    # Shared by CLI flags and the interactive menu. Returns @{ Label; Results }.
    param([string]$Mode, $Corpus, $Value, [bool]$AssignedOnly = $false)

    $results = New-Object System.Collections.Generic.List[object]
    $label = ''

    switch ($Mode) {
        'serial' {
            $label = "Serial: " + (@($Value) -join ', ')
            foreach ($sn in @($Value)) {
                $hits = Find-ManagedDevices -By serialNumber -Value $sn.Trim()
                if (@($hits).Count -eq 0) { Write-Warn2 ("No managed device found with serial '{0}'" -f $sn); continue }
                $md = Select-BestEnrollment -Candidates $hits -Label $sn
                [void]$results.Add((Resolve-DeviceRsop -ManagedDevice $md -Corpus $Corpus))
            }
        }
        'name' {
            $label = "Device: " + (@($Value) -join ', ')
            foreach ($dn in @($Value)) {
                $hits = Find-ManagedDevices -By deviceName -Value $dn.Trim()
                if (@($hits).Count -eq 0) { Write-Warn2 ("No managed device found named '{0}'" -f $dn); continue }
                $md = Select-BestEnrollment -Candidates $hits -Label $dn
                [void]$results.Add((Resolve-DeviceRsop -ManagedDevice $md -Corpus $Corpus))
            }
        }
        'group' {
            $gobj = Resolve-GroupIdentity -Value $Value
            if ($null -eq $gobj) { throw "Group '$Value' not found." }
            $label = "Group: " + $gobj.displayName

            if ($AssignedOnly) {
                Write-Step ("Listing policies directly assigned to group '{0}'" -f $gobj.displayName)
                Resolve-GroupNames -Ids @($gobj.id)
                [void]$results.Add((Get-GroupAssignedRsop -GroupObj $gobj -Corpus $Corpus))
            }
            else {
                Write-Step ("Resolving device members of '{0}' (transitive)" -f $gobj.displayName)
                $members = Get-RsopPaged -Uri ("v1.0/groups/{0}/transitiveMembers/microsoft.graph.device?`$select=id,deviceId,displayName&`$top=999" -f $gobj.id)
                Write-Info ("{0} device objects in group (user members are not expanded to their devices)" -f @($members).Count)
                $targets = New-Object System.Collections.Generic.List[object]
                $idx = Get-DeviceIndex
                $byAzId = @{}
                foreach ($d in $idx) { $byAzId[[string](Get-Prop $d 'azureADDeviceId')] = $d }
                foreach ($m in @($members)) {
                    $devId = [string](Get-Prop $m 'deviceId')
                    if ($devId -and $byAzId.ContainsKey($devId)) { [void]$targets.Add($byAzId[$devId]) }
                }
                Write-Info ("{0} of them are Intune-managed" -f $targets.Count)
                if ($MaxDevices -gt 0 -and $targets.Count -gt $MaxDevices) {
                    Write-Warn2 ("Group has {0} managed devices; evaluating the first {1} (use -MaxDevices 0 for all)." -f $targets.Count, $MaxDevices)
                }
                $take = if ($MaxDevices -gt 0) { [math]::Min($MaxDevices, $targets.Count) } else { $targets.Count }
                for ($i = 0; $i -lt $take; $i++) {
                    [void]$results.Add((Resolve-DeviceRsop -ManagedDevice $targets[$i] -Corpus $Corpus))
                }
            }
        }
        'filter' {
            $flt = $null
            foreach ($f in @($Corpus.filters)) {
                if ($f.Id -ieq [string]$Value -or $f.Name -ieq [string]$Value) { $flt = $f; break }
            }
            if ($null -eq $flt) {
                $names = @($Corpus.filters | ForEach-Object { $_.Name }) -join "', '"
                throw "Assignment filter '$Value' not found. Available: '$names'"
            }
            $label = "Filter: " + $flt.Name
            Write-Step ("Evaluating assignment filter '{0}' server-side" -f $flt.Name)
            $targets = @(Get-FilterMatchedDevices -FilterObj $flt)
            Write-Info ("{0} devices match the filter" -f $targets.Count)
            if ($MaxDevices -gt 0 -and $targets.Count -gt $MaxDevices) {
                Write-Warn2 ("Evaluating the first {0} (use -MaxDevices 0 for all)." -f $MaxDevices)
            }
            $take = if ($MaxDevices -gt 0) { [math]::Min($MaxDevices, $targets.Count) } else { $targets.Count }
            for ($i = 0; $i -lt $take; $i++) {
                [void]$results.Add((Resolve-DeviceRsop -ManagedDevice $targets[$i] -Corpus $Corpus))
            }
        }
        'all' {
            $label = 'Tenant-wide inventory'
            $sgObj = $null; $sfObj = $null
            $gRef = $null; $fRef = $null
            if ($null -ne $Value) { $gRef = Get-Prop $Value 'Group'; $fRef = Get-Prop $Value 'Filter' }
            if ($gRef) {
                $g = Resolve-GroupIdentity -Value $gRef
                if ($null -eq $g) { throw "Scope group '$gRef' not found." }
                # policies assigned to a group the scope group is nested in reach its members too
                $parents = @{}
                try {
                    foreach ($pg in (Get-RsopPaged -Uri ("v1.0/groups/{0}/transitiveMemberOf/microsoft.graph.group?`$select=id,displayName&`$top=999" -f $g.id))) {
                        $parents[[string](Get-Prop $pg 'id')] = [string](Get-Prop $pg 'displayName')
                    }
                    if ($parents.Count -gt 0) { Write-Info ("Scope group is nested in {0} parent group(s); assignments to those count as in scope." -f $parents.Count) }
                } catch {
                    Add-RunLog -Level warn -Message ("Could not resolve parent groups of '{0}' ({1}); scope matches direct assignments only." -f $g.displayName, $_.Exception.Message)
                }
                $sgObj = [pscustomobject]@{ Id = $g.id; Name = $g.displayName; Parents = $parents }
                $label += (" - group '{0}'" -f $g.displayName)
            }
            if ($fRef) {
                foreach ($f in @($Corpus.filters)) {
                    if ($f.Id -ieq [string]$fRef -or $f.Name -ieq [string]$fRef) { $sfObj = $f; break }
                }
                if ($null -eq $sfObj) {
                    $names = @($Corpus.filters | ForEach-Object { $_.Name }) -join "', '"
                    throw "Scope filter '$fRef' not found. Available: '$names'"
                }
                $label += (" - filter '{0}'" -f $sfObj.Name)
            }
            Write-Step $(if ($sgObj -or $sfObj) { "Building scoped tenant inventory" } else { "Building tenant-wide settings inventory" })
            [void]$results.Add((Get-TenantInventoryRsop -Corpus $Corpus -ScopeGroup $sgObj -ScopeFilter $sfObj))
        }
    }

    return [pscustomobject]@{ Label = $label; Results = $results.ToArray() }
}

function Export-RsopResults {
    param($Results, [string]$Label, [string]$Tenant, [string]$HtmlPath, [string]$CsvPath, [string]$JsonPath)
    foreach ($r in @($Results)) { Show-ConsoleSummary -Result $r }
    if ($HtmlPath) { Export-HtmlReport -Results @($Results) -Path $HtmlPath -QueryLabel $Label -Tenant $Tenant }
    if ($CsvPath) {
        Get-CsvRows -Results @($Results) | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
        Write-Good ("CSV export: {0}" -f (Resolve-Path $CsvPath))
    }
    if ($JsonPath) {
        [pscustomobject]@{ query = $Label; generated = (Get-Date).ToString('o'); devices = @($Results) } |
            ConvertTo-Json -Depth 12 | Set-Content -Path $JsonPath -Encoding UTF8
        Write-Good ("JSON export: {0}" -f (Resolve-Path $JsonPath))
    }
}

function Reset-RunLog {
    param($Corpus)
    $script:RunLog.Clear()
    foreach ($w in @($Corpus.warnings)) {
        [void]$script:RunLog.Add([pscustomobject]@{ Time = ''; Level = 'warn'; Message = [string]$w })
    }
}

function Open-File {
    param([string]$Path)
    try {
        if ($env:OS -eq 'Windows_NT') { Start-Process -FilePath $Path }
        elseif ($IsMacOS) { & open $Path }
        else { & xdg-open $Path 2>$null }
    } catch { Write-Warn2 "Could not auto-open $Path" }
}

#endregion

#region ---------- interactive menu -----------------------------------------------------------

function Select-EntraGroup {
    # Search-as-you-type group picker.
    while ($true) {
        $q = Read-Host "  Group name starts with (blank = cancel)"
        if (-not $q) { return $null }
        $guid = [guid]::Empty
        if ([guid]::TryParse($q, [ref]$guid)) {
            try { $g = Invoke-Rsop -Uri ("v1.0/groups/{0}?`$select=id,displayName" -f $q); return $g } catch { Write-Warn2 "Not found."; continue }
        }
        $esc = $q -replace "'", "''"
        $resp = Invoke-Rsop -Uri ("v1.0/groups?`$filter=startswith(displayName,'{0}')&`$select=id,displayName&`$top=20" -f $esc)
        $vals = @($resp['value'])
        if ($vals.Count -eq 0) { Write-Warn2 "No groups match."; continue }
        for ($i = 0; $i -lt $vals.Count; $i++) { Write-Host ("   [{0}] {1}" -f ($i + 1), $vals[$i]['displayName']) }
        $pick = Read-Host "  Pick number (blank = search again)"
        $pi = 0
        if ([int]::TryParse($pick, [ref]$pi) -and $pi -ge 1 -and $pi -le $vals.Count) { return $vals[$pi - 1] }
    }
}

function Select-CorpusFilter {
    param($Corpus)
    $flts = @($Corpus.filters)
    if ($flts.Count -eq 0) { Write-Warn2 "Tenant has no assignment filters."; return $null }
    for ($i = 0; $i -lt $flts.Count; $i++) {
        Write-Host ("   [{0}] {1}  ({2})" -f ($i + 1), $flts[$i].Name, $flts[$i].Platform)
    }
    $pick = Read-Host "  Pick number (blank = cancel)"
    $pi = 0
    if ([int]::TryParse($pick, [ref]$pi) -and $pi -ge 1 -and $pi -le $flts.Count) { return $flts[$pi - 1].Name }
    return $null
}

function Invoke-InteractiveMenu {
    param($Corpus, [string]$TenantKey, $GraphCtx)

    while ($true) {
        $assigned = @($Corpus.policies | Where-Object { @($_.Assignments).Count -gt 0 }).Count
        Write-Host ""
        Write-Host ("  🔍 Intune Lens v{0}" -f $script:Version) -ForegroundColor White
        Write-Host ("  Tenant {0}  |  signed in as {1}" -f $TenantKey, $GraphCtx.Account) -ForegroundColor DarkGray
        Write-Host ("  Policy corpus: {0} policies ({1} assigned), {2} filters, pulled {3}" -f `
            @($Corpus.policies).Count, $assigned, @($Corpus.filters).Count, ([datetime]$Corpus.generated).ToString('HH:mm')) -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  What do you want to look up?" -ForegroundColor Cyan
        Write-Host "   [1] Device(s) by serial number"
        Write-Host "   [2] Device(s) by name"
        Write-Host "   [3] All devices in an Entra group"
        Write-Host "   [4] Policies assigned directly to a group  (fast, no device math)"
        Write-Host "   [5] Devices matching an assignment filter"
        Write-Host "   [6] Tenant-wide settings inventory  (every policy + every setting; optional group/filter scope)"
        Write-Host "   [R] Refresh policy cache      [Q] Quit"
        $choice = (Read-Host "  Choice").Trim().ToUpper()

        if ($choice -eq 'Q') { break }
        if ($choice -eq 'R') {
            $script:Refresh = $true
            $Corpus = Get-PolicyCorpus -TenantKey $TenantKey
            $script:Refresh = $false
            $script:FilterById = @{}
            foreach ($f in @($Corpus.filters)) { $script:FilterById[[string]$f.Id] = $f }
            continue
        }

        $mode = $null; $value = $null; $assignedOnly = $false
        switch ($choice) {
            '1' {
                $s = Read-Host "  Serial number(s), comma-separated"
                if ($s) { $mode = 'serial'; $value = @($s -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
            }
            '2' {
                $s = Read-Host "  Device name(s), comma-separated"
                if ($s) { $mode = 'name'; $value = @($s -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
            }
            '3' { $g = Select-EntraGroup; if ($g) { $mode = 'group'; $value = $g } }
            '4' { $g = Select-EntraGroup; if ($g) { $mode = 'group'; $value = $g; $assignedOnly = $true } }
            '5' { $f = Select-CorpusFilter -Corpus $Corpus; if ($f) { $mode = 'filter'; $value = $f } }
            '6' {
                $mode = 'all'
                Write-Host "  Optional scope - answers 'what policies apply to this group / filter?'" -ForegroundColor DarkGray
                $sg = (Read-Host "  Scope by group name or id (blank = whole tenant)").Trim()
                $sf = (Read-Host "  Scope by assignment filter name or id (blank = none)").Trim()
                if ($sg -or $sf) { $value = [pscustomobject]@{ Group = $sg; Filter = $sf } }
            }
            default { continue }
        }
        if (-not $mode) { continue }

        Reset-RunLog -Corpus $Corpus
        $q = $null
        try { $q = Resolve-QueryResults -Mode $mode -Corpus $Corpus -Value $value -AssignedOnly $assignedOnly }
        catch { Write-Warn2 $_.Exception.Message; continue }
        if (-not $q -or @($q.Results).Count -eq 0) { Write-Warn2 "Nothing resolved."; continue }

        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $htmlPath = Join-Path (Get-Location) ("IntuneLens-{0}.html" -f $stamp)
        Export-RsopResults -Results $q.Results -Label $q.Label -Tenant $TenantKey -HtmlPath $htmlPath

        $open = (Read-Host "  Open the HTML report now? [Y/n]").Trim().ToUpper()
        if ($open -ne 'N') { Open-File -Path $htmlPath }
        $csvAns = (Read-Host "  Also write a CSV? Enter a path or leave blank to skip").Trim()
        if ($csvAns) {
            Get-CsvRows -Results $q.Results | Export-Csv -Path $csvAns -NoTypeInformation -Encoding UTF8
            Write-Good ("CSV export: {0}" -f (Resolve-Path $csvAns))
        }
    }
}

#endregion

#region ---------- main -----------------------------------------------------------------------

$ctx = Connect-RsopGraph
$tenantKey = [string]$ctx.TenantId

$corpus = Get-PolicyCorpus -TenantKey $tenantKey

# Index filters for quick lookup during evaluation.
$script:FilterById = @{}
foreach ($f in @($corpus.filters)) { $script:FilterById[[string]$f.Id] = $f }

if ($PSCmdlet.ParameterSetName -eq 'Interactive') {
    Invoke-InteractiveMenu -Corpus $corpus -TenantKey $tenantKey -GraphCtx $ctx
    Write-Host ""
    Write-Host "Bye." -ForegroundColor Cyan
    return
}

Reset-RunLog -Corpus $corpus

$mode = $null; $value = $null; $assignedOnly = $false
switch ($PSCmdlet.ParameterSetName) {
    'BySerial'     { $mode = 'serial'; $value = $SerialNumber }
    'ByDeviceName' { $mode = 'name'; $value = $DeviceName }
    'ByGroup'      { $mode = 'group'; $value = $Group; $assignedOnly = [bool]$GroupAssignedOnly }
    'ByFilter'     { $mode = 'filter'; $value = $AssignmentFilter }
    'All'          {
        $mode = 'all'
        if ($ScopeGroup -or $ScopeFilter) { $value = [pscustomobject]@{ Group = $ScopeGroup; Filter = $ScopeFilter } }
    }
}

$q = Resolve-QueryResults -Mode $mode -Corpus $corpus -Value $value -AssignedOnly $assignedOnly
if (-not $q -or @($q.Results).Count -eq 0) {
    Write-Warn2 "Nothing resolved - no report generated."
    return
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not $ExportHtml -and -not $NoHtml) { $ExportHtml = Join-Path (Get-Location) ("IntuneLens-{0}.html" -f $stamp) }

Export-RsopResults -Results $q.Results -Label $q.Label -Tenant $tenantKey -HtmlPath $ExportHtml -CsvPath $ExportCsv -JsonPath $ExportJson

$elapsed = (Get-Date) - $script:StartTime
Write-Host ""
Write-Host ("Done in {0:n0}s." -f $elapsed.TotalSeconds) -ForegroundColor Cyan

if ($PassThru) { @($q.Results) }

#endregion
