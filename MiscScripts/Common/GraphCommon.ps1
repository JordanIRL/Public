<#
    GraphCommon.ps1 - shared helpers for the TeamsRoomCheck scripts.

    Dot-source this from a script:
        . "$PSScriptRoot/../Common/GraphCommon.ps1"

    Auth model: interactive delegated sign-in only (Connect-MgGraph -Scopes ...). The signed-in admin
    needs the appropriate rights over the target mailbox/drive.

    Requires: Microsoft.Graph PowerShell SDK  (Install-Module Microsoft.Graph -Scope CurrentUser)

    Note: strict mode is intentionally NOT enabled - Graph omits optional properties (e.g. an event's
    onlineMeeting) and lenient property access keeps the scripts robust against those gaps.
#>

function Connect-GraphSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Scopes
    )

    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        throw "Microsoft.Graph SDK not found. Install with: Install-Module Microsoft.Graph -Scope CurrentUser"
    }
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    # Reuse an existing delegated session if it already covers the scopes we need.
    $ctx = Get-MgContext
    if ($ctx -and $ctx.AuthType -eq 'Delegated') {
        $have = @($ctx.Scopes)
        if (-not ($Scopes | Where-Object { $_ -notin $have })) { return }
    }

    Write-Verbose "Connecting interactively with scopes: $($Scopes -join ', ')"
    Connect-MgGraph -Scopes $Scopes -NoWelcome
}

function Invoke-GraphPaged {
    <# Follows @odata.nextLink and returns the flattened collection. Use for raw REST calls. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [hashtable]$Headers
    )
    $results = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    while ($next) {
        $resp = if ($Headers) {
            Invoke-MgGraphRequest -Method GET -Uri $next -Headers $Headers -OutputType PSObject
        } else {
            Invoke-MgGraphRequest -Method GET -Uri $next -OutputType PSObject
        }
        if ($null -ne $resp.value) {
            foreach ($v in $resp.value) { $results.Add($v) }
            $next = $resp.'@odata.nextLink'
        } else {
            $results.Add($resp)   # single-object response
            $next = $null
        }
    }
    return $results
}

function ConvertTo-GraphShareToken {
    <# Encodes a sharing URL into the 'u!'-prefixed token the /shares endpoint expects. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Url)
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Url))
    return 'u!' + $b64.TrimEnd('=').Replace('/', '_').Replace('+', '-')
}

function Resolve-GraphUserId {
    <# Accepts a UPN/email/object id and returns id, upn and displayName. Requires User.Read.All (or Directory.Read.All). #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$User)
    $enc = [uri]::EscapeDataString($User)
    $u = Invoke-MgGraphRequest -Method GET -Uri "/v1.0/users/$enc`?`$select=id,userPrincipalName,displayName,mail" -OutputType PSObject
    [pscustomobject]@{
        Id                = $u.id
        UserPrincipalName = $u.userPrincipalName
        DisplayName       = $u.displayName
        Mail              = $u.mail
    }
}

function Format-Bytes {
    param([AllowNull()][Nullable[double]]$Bytes)   # nullable: absent quota/size fields render as ''
    if ($null -eq $Bytes) { return '' }
    $units = 'B', 'KB', 'MB', 'GB', 'TB', 'PB'
    $i = 0; $n = [double]$Bytes
    while ($n -ge 1024 -and $i -lt $units.Count - 1) { $n /= 1024; $i++ }
    return ('{0:N2} {1}' -f $n, $units[$i])
}

function Write-Section {
    param([Parameter(Mandatory)][string]$Title)
    Write-Host ''
    Write-Host ("=" * 78) -ForegroundColor DarkCyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ("=" * 78) -ForegroundColor DarkCyan
}
