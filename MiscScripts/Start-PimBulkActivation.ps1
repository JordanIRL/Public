<#
.SYNOPSIS
    Bulk activate/deactivate your PIM-eligible Entra ID directory roles.
#>

#region Bootstrap
foreach ($m in @('Microsoft.Graph.Authentication','Microsoft.Graph.Identity.Governance')) {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        Write-Host "Installing $m..." -ForegroundColor Yellow
        Install-Module -Name $m -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    }
    Import-Module $m -ErrorAction Stop
}
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

$Scopes = @('RoleManagement.ReadWrite.Directory', 'User.Read')
try {
    $ctx = Get-MgContext
    if (-not $ctx -or ($Scopes | Where-Object { $_ -notin $ctx.Scopes })) {
        if ($ctx) { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null }
        Connect-MgGraph -Scopes $Scopes -NoWelcome -ErrorAction Stop
    }
} catch {
    [Windows.MessageBox]::Show("Failed to connect to Microsoft Graph:`n$($_.Exception.Message)",
        'Connection error', 'OK', 'Error') | Out-Null
    return
}
#endregion

#region Graph
$ScheduleUri = 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleRequests'

function Get-Me {
    Invoke-MgGraphRequest GET 'https://graph.microsoft.com/v1.0/me?$select=id,displayName,userPrincipalName'
}

function Get-Eligible($principalId) {
    Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance `
        -Filter "principalId eq '$principalId'" -ExpandProperty RoleDefinition -All -ErrorAction Stop |
        ForEach-Object {
            [PSCustomObject]@{
                RoleId      = $_.RoleDefinition.Id
                Name        = $_.RoleDefinition.DisplayName
                Description = $_.RoleDefinition.Description
                ScopeId     = $_.DirectoryScopeId
                Scope       = if ($_.DirectoryScopeId -eq '/') { 'Tenant-wide' } else { "Scoped: $($_.DirectoryScopeId)" }
            }
        } | Sort-Object Name
}

function Get-Active($principalId) {
    try {
        Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance `
            -Filter "principalId eq '$principalId'" -ExpandProperty RoleDefinition -All -ErrorAction Stop |
            ForEach-Object {
                [PSCustomObject]@{
                    RoleId  = $_.RoleDefinitionId
                    Name    = $_.RoleDefinition.DisplayName
                    Type    = if ($_.AssignmentType -eq 'Activated') { 'PIM' } else { 'Permanent' }
                    EndTime = $_.EndDateTime
                    ScopeId = $_.DirectoryScopeId
                }
            } | Sort-Object Name
    } catch {}
}

function Invoke-Pim($action, $principalId, $roleId, $scopeId, [int]$minutes = 0) {
    $body = @{
        action           = $action
        principalId      = $principalId
        roleDefinitionId = $roleId
        directoryScopeId = $scopeId
        justification    = 'Required for role.'
    }
    if ($action -eq 'selfActivate') {
        $h = [int][Math]::Floor($minutes / 60); $m = $minutes % 60
        $iso = 'PT' + $(if ($h) { "${h}H" }) + $(if ($m) { "${m}M" })
        if ($iso -eq 'PT') { $iso = 'PT0M' }
        $body.scheduleInfo = @{
            startDateTime = (Get-Date).ToUniversalTime().ToString('o')
            expiration    = @{ type = 'AfterDuration'; duration = $iso }
        }
    }
    Invoke-MgGraphRequest POST $ScheduleUri `
        -Body ($body | ConvertTo-Json -Depth 5) -ContentType 'application/json' -ErrorAction Stop
}

function Format-Remaining($end) {
    if (-not $end) { return '' }
    try {
        $utc = if ($end -is [datetimeoffset]) { $end.UtcDateTime }
               elseif ($end -is [datetime])   { ([datetime]$end).ToUniversalTime() }
               else                           { [datetime]::Parse("$end").ToUniversalTime() }
        $d = $utc - [datetime]::UtcNow
        if ($d.TotalSeconds -le 0) { return 'Expired' }
        $h = [int][Math]::Floor($d.TotalHours)
        if ($h) { '{0}h {1:00}m left' -f $h, $d.Minutes } else { '{0}m left' -f $d.Minutes }
    } catch {}
}

function Format-GraphError($err) {
    $texts = New-Object System.Collections.Generic.List[string]
    $texts.Add([string]$err.ErrorDetails.Message)
    $texts.Add([string]$err.Exception.Message)
    $ex = $err.Exception
    while ($ex) {
        try {
            if ($ex.Response -and $ex.Response.Content) {
                $texts.Add($ex.Response.Content.ReadAsStringAsync().GetAwaiter().GetResult())
            }
        } catch {}
        $ex = $ex.InnerException
    }
    foreach ($t in $texts) {
        if (-not $t) { continue }
        $i = $t.IndexOf('{'); if ($i -lt 0) { continue }
        try {
            $p = $t.Substring($i) | ConvertFrom-Json -ErrorAction Stop
            if ($p.error) {
                $msg = $p.error.message
                if ($p.error.innerError.message -and $p.error.innerError.message -ne $msg) {
                    $msg = "$msg — $($p.error.innerError.message)"
                }
                $hint = @{
                    RoleAssignmentRequestPolicyValidationFailed = ' (policy blocked — check MFA/justification/ticket/duration)'
                    RoleAssignmentExists       = ' (already active)'
                    RoleAssignmentDoesNotExist = ' (not currently active)'
                    MfaRule                    = ' (MFA step-up required; reconnect)'
                }[$p.error.code]
                return "[$($p.error.code)] $msg$hint"
            }
        } catch {}
    }
    $err.Exception.Message
}
#endregion

#region XAML
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PIM Bulk Activator" Width="1000" Height="780"
        Background="#F3F3F5" FontFamily="Segoe UI"
        WindowStartupLocation="CenterScreen">
  <Window.Resources>
    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="White"/>
      <Setter Property="CornerRadius" Value="6"/>
      <Setter Property="Padding" Value="18"/>
      <Setter Property="Margin" Value="0,0,0,12"/>
      <Setter Property="BorderBrush" Value="#E4E4E7"/>
      <Setter Property="BorderThickness" Value="1"/>
    </Style>
    <Style x:Key="Header" TargetType="TextBlock">
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Margin" Value="0,0,0,10"/>
      <Setter Property="Foreground" Value="#1F1F23"/>
    </Style>
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Padding" Value="18,7"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="B" Background="{TemplateBinding Background}" CornerRadius="4"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Opacity" Value="0.88"/></Trigger>
              <Trigger Property="IsEnabled"   Value="False"><Setter TargetName="B" Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#0F6CBD"/><Setter Property="Foreground" Value="White"/>
    </Style>
    <Style x:Key="Secondary" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Background" Value="#E4E4E7"/><Setter Property="Foreground" Value="#1F1F23"/>
    </Style>
  </Window.Resources>
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" Background="White" BorderBrush="#E4E4E7" BorderThickness="0,0,0,1" Padding="20,14">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock Text="PIM Bulk Activator" FontSize="15" FontWeight="SemiBold"
                   VerticalAlignment="Center" Foreground="#1F1F23"/>
        <Button x:Name="BtnRefresh"    Grid.Column="1" Content="Refresh"             Style="{StaticResource Secondary}" Margin="0,0,6,0"/>
        <Button x:Name="BtnDeactivate" Grid.Column="2" Content="Deactivate selected" Style="{StaticResource Secondary}" Margin="0,0,6,0"/>
        <Button x:Name="BtnActivate"   Grid.Column="3" Content="Activate selected"   Style="{StaticResource Primary}"/>
      </Grid>
    </Border>

    <Border Grid.Row="1" Style="{StaticResource Card}" Margin="16,16,16,0">
      <StackPanel>
        <TextBlock x:Name="LblName" Text="—" FontSize="24" FontWeight="SemiBold" Foreground="#1F1F23"/>
        <TextBlock x:Name="LblUpn"  Text=""  FontSize="13" Foreground="#6B6B72" Margin="0,2,0,12"/>
        <WrapPanel x:Name="Chips"/>
      </StackPanel>
    </Border>

    <Border Grid.Row="2" Style="{StaticResource Card}" Margin="16,12,16,0">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock Text="Duration" VerticalAlignment="Center" Foreground="#6B6B72" FontSize="12.5" Margin="0,0,10,0"/>
        <ComboBox x:Name="CmbDuration" Grid.Column="1" Padding="8,5" MinWidth="120" Margin="0,0,20,0"/>
        <TextBlock Grid.Column="2" VerticalAlignment="Center" Foreground="#6B6B72" FontSize="12.5">
          <Run Text="Justification:"/>
          <Run Text="&quot;Required for role.&quot;" FontStyle="Italic" Foreground="#1F1F23"/>
        </TextBlock>
        <Button x:Name="BtnSelectAll" Grid.Column="3" Content="Select all" Style="{StaticResource Secondary}" Margin="0,0,6,0"/>
        <Button x:Name="BtnClearAll"  Grid.Column="4" Content="Clear"      Style="{StaticResource Secondary}"/>
      </Grid>
    </Border>

    <Border x:Name="ActiveCard" Grid.Row="3" Style="{StaticResource Card}" Margin="16,12,16,0" Visibility="Collapsed">
      <StackPanel>
        <TextBlock x:Name="ActiveHeader" Text="Currently active" Style="{StaticResource Header}"/>
        <StackPanel x:Name="ActivePanel"/>
      </StackPanel>
    </Border>

    <Border Grid.Row="4" Style="{StaticResource Card}" Margin="16,12,16,0" Padding="0">
      <Grid>
        <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="18,12">
          <StackPanel>
            <TextBlock Text="Eligible roles" Style="{StaticResource Header}"/>
            <StackPanel x:Name="RolesPanel"/>
          </StackPanel>
        </ScrollViewer>
        <TextBlock x:Name="LblEmpty" Text="No eligible roles found." Foreground="#6B6B72" FontSize="13"
                   HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed"/>
      </Grid>
    </Border>

    <Border x:Name="LogCard" Grid.Row="5" Style="{StaticResource Card}" Margin="16,12,16,0" Visibility="Collapsed">
      <StackPanel>
        <TextBlock Text="Results" Style="{StaticResource Header}"/>
        <StackPanel x:Name="LogPanel"/>
      </StackPanel>
    </Border>

    <Border Grid.Row="6" Background="White" BorderBrush="#E4E4E7" BorderThickness="0,1,0,0" Padding="20,6">
      <TextBlock x:Name="LblStatus" Foreground="#6B6B72" FontSize="11"/>
    </Border>
  </Grid>
</Window>
'@
$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ctrls = @{}
foreach ($n in 'BtnRefresh','BtnActivate','BtnDeactivate','BtnSelectAll','BtnClearAll',
               'LblName','LblUpn','Chips','CmbDuration','RolesPanel','LblEmpty',
               'ActiveCard','ActiveHeader','ActivePanel','LogCard','LogPanel','LblStatus') {
    $ctrls[$n] = $window.FindName($n)
}
#endregion

#region UI helpers
$brushes = @{}
function Get-Brush($hex) {
    if (-not $brushes.ContainsKey($hex)) {
        $brushes[$hex] = [Windows.Media.BrushConverter]::new().ConvertFromString($hex)
    }
    $brushes[$hex]
}

function Flush-UI {
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::Background,
        [Action]{ $frame.Continue = $false }) | Out-Null
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

function New-Chip($text, $kind = 'info') {
    $p = @{
        success = '#E6F4EA','#9BC9A5','#137333'
        danger  = '#FCE8E6','#E8A79F','#A50E0E'
        warning = '#FEF7E0','#E7C969','#7F5900'
        info    = '#E8F0FE','#B6C9EF','#174EA6'
    }[$kind]
    $b = New-Object Windows.Controls.Border
    $b.CornerRadius = [Windows.CornerRadius]::new(10)
    $b.Padding = '10,3'; $b.Margin = '0,0,6,6'
    $b.BorderThickness = [Windows.Thickness]::new(1)
    $b.Background = Get-Brush $p[0]; $b.BorderBrush = Get-Brush $p[1]
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $text; $t.FontSize = 11.5; $t.FontWeight = 'SemiBold'; $t.Foreground = Get-Brush $p[2]
    $b.Child = $t; $b
}

function Add-RoleRow($panel, $role, $mode, [bool]$alreadyActive = $false) {
    # $mode: 'eligible' | 'active'
    $border = New-Object Windows.Controls.Border
    $border.BorderBrush = Get-Brush '#EFEFF2'; $border.BorderThickness = '0,0,0,1'
    $border.Padding = if ($mode -eq 'eligible') { '0,10' } else { '0,8' }

    $grid = New-Object Windows.Controls.Grid
    foreach ($w in 'Auto','*','Auto') {
        $c = New-Object Windows.Controls.ColumnDefinition; $c.Width = $w
        $grid.ColumnDefinitions.Add($c)
    }

    $chk = $null
    $needsCheckbox = ($mode -eq 'eligible') -or ($role.Type -eq 'PIM')
    if ($needsCheckbox) {
        $chk = New-Object Windows.Controls.CheckBox
        $chk.VerticalAlignment = 'Center'; $chk.Margin = '0,0,12,0'
        if ($mode -eq 'active')    { $chk.ToolTip = 'Select to deactivate' }
        if ($alreadyActive)        { $chk.IsEnabled = $false }
        [Windows.Controls.Grid]::SetColumn($chk, 0); $grid.Children.Add($chk) | Out-Null
    } else {
        $spacer = New-Object Windows.Controls.Border; $spacer.Width = 28
        [Windows.Controls.Grid]::SetColumn($spacer, 0); $grid.Children.Add($spacer) | Out-Null
    }

    $info = New-Object Windows.Controls.StackPanel
    [Windows.Controls.Grid]::SetColumn($info, 1)
    $nm = New-Object Windows.Controls.TextBlock
    $nm.Text = $role.Name; $nm.FontWeight = 'SemiBold'; $nm.FontSize = 13
    $nm.Foreground = Get-Brush '#1F1F23'; $nm.VerticalAlignment = 'Center'
    $info.Children.Add($nm) | Out-Null
    if ($mode -eq 'eligible') {
        if ($role.Description) {
            $d = New-Object Windows.Controls.TextBlock
            $d.Text = $role.Description; $d.FontSize = 12
            $d.Foreground = Get-Brush '#6B6B72'; $d.TextWrapping = 'Wrap'; $d.Margin = '0,2,0,0'
            $info.Children.Add($d) | Out-Null
        }
        if ($role.Scope) {
            $s = New-Object Windows.Controls.TextBlock
            $s.Text = $role.Scope; $s.FontSize = 11
            $s.Foreground = Get-Brush '#8A8A90'; $s.Margin = '0,2,0,0'
            $info.Children.Add($s) | Out-Null
        }
    }
    $grid.Children.Add($info) | Out-Null

    $status = New-Object Windows.Controls.StackPanel
    $status.Orientation = 'Horizontal'; $status.VerticalAlignment = 'Center'; $status.Margin = '12,0,0,0'
    [Windows.Controls.Grid]::SetColumn($status, 2)
    if ($mode -eq 'active') {
        if ($role.Type -eq 'PIM') {
            $status.Children.Add((New-Chip 'PIM' 'info')) | Out-Null
            $rem = Format-Remaining $role.EndTime
            if ($rem) { $status.Children.Add((New-Chip $rem 'success')) | Out-Null }
        } else {
            $status.Children.Add((New-Chip 'Permanent' 'warning')) | Out-Null
        }
    } elseif ($alreadyActive) {
        $status.Children.Add((New-Chip 'Already active' 'success')) | Out-Null
    }
    $grid.Children.Add($status) | Out-Null

    $border.Child = $grid
    $panel.Children.Add($border) | Out-Null
    [PSCustomObject]@{ Role = $role; Checkbox = $chk; StatusHost = $status }
}

function Add-LogLine($text, $kind = 'info') {
    $r = New-Object Windows.Controls.Border
    $r.BorderBrush = Get-Brush '#EFEFF2'; $r.BorderThickness = '0,0,0,1'; $r.Padding = '0,8'
    $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
    $sp.Children.Add((New-Chip $kind.ToUpper() $kind)) | Out-Null
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $text; $t.FontSize = 12.5; $t.VerticalAlignment = 'Center'
    $sp.Children.Add($t) | Out-Null
    $r.Child = $sp
    $ctrls.LogPanel.Children.Add($r) | Out-Null
}
#endregion

#region State + data
for ($min = 30; $min -le 480; $min += 30) {
    $h = [int][Math]::Floor($min / 60); $m = $min % 60
    $label = if (-not $h) { "${m}m" } elseif (-not $m) { "${h}h" } else { '{0}h {1:00}m' -f $h, $m }
    $item = New-Object Windows.Controls.ComboBoxItem; $item.Content = $label; $item.Tag = $min
    $null = $ctrls.CmbDuration.Items.Add($item)
}
$ctrls.CmbDuration.SelectedIndex = $ctrls.CmbDuration.Items.Count - 1

$script:Me = $null
$script:EligibleRows = @()
$script:ActiveRows   = @()

function Update-Roles {
    $ctrls.LblStatus.Text = 'Loading roles...'
    $window.Cursor = [Windows.Input.Cursors]::Wait
    try {
        if (-not $script:Me) { $script:Me = Get-Me }
        $ctrls.LblName.Text = $script:Me.displayName
        $ctrls.LblUpn.Text  = $script:Me.userPrincipalName

        $eligible = @(Get-Eligible $script:Me.id)
        $active   = @(Get-Active   $script:Me.id)
        $activeIds = @{}; foreach ($a in $active) { $activeIds[$a.RoleId] = $true }

        $ctrls.RolesPanel.Children.Clear(); $script:EligibleRows = @()
        foreach ($r in $eligible) {
            $script:EligibleRows += Add-RoleRow $ctrls.RolesPanel $r 'eligible' ([bool]$activeIds[$r.RoleId])
        }

        $ctrls.ActivePanel.Children.Clear(); $script:ActiveRows = @()
        foreach ($a in $active) { $script:ActiveRows += Add-RoleRow $ctrls.ActivePanel $a 'active' }
        $ctrls.ActiveCard.Visibility = if ($active.Count) { 'Visible' } else { 'Collapsed' }
        if ($active.Count) { $ctrls.ActiveHeader.Text = "Currently active ($($active.Count))" }

        $ctrls.Chips.Children.Clear()
        $null = $ctrls.Chips.Children.Add((New-Chip "$($eligible.Count) eligible" 'info'))
        $null = $ctrls.Chips.Children.Add((New-Chip "$($active.Count) active" 'success'))

        $ctrls.LblEmpty.Visibility   = if ($eligible.Count) { 'Collapsed' } else { 'Visible' }
        $ctrls.BtnActivate.IsEnabled = $eligible.Count -gt 0
        $ctrls.LblStatus.Text = "Ready. Connected as $($script:Me.userPrincipalName)."
    } catch {
        [Windows.MessageBox]::Show($_.Exception.Message, 'Failed to load roles', 'OK', 'Warning') | Out-Null
        $ctrls.LblStatus.Text = "Load failed: $($_.Exception.Message)"
    } finally { $window.Cursor = $null }
}
#endregion

#region Run action (activate + deactivate)
function Invoke-BulkAction($label, $rows, $action, [int]$minutes = 0) {
    if (-not $rows.Count) {
        [Windows.MessageBox]::Show('Select at least one role.', 'Nothing to do', 'OK', 'Information') | Out-Null
        return
    }
    if ($action -eq 'selfDeactivate') {
        $confirm = [Windows.MessageBox]::Show(
            "Deactivate $($rows.Count) role$(if($rows.Count -ne 1){'s'})?`n`nThis ends the PIM session immediately.",
            'Confirm deactivation', 'OKCancel', 'Warning')
        if ($confirm -ne 'OK') { return }
    }

    $ctrls.LogPanel.Children.Clear(); $ctrls.LogCard.Visibility = 'Visible'
    $ctrls.BtnActivate.IsEnabled   = $false
    $ctrls.BtnDeactivate.IsEnabled = $false
    $ctrls.BtnRefresh.IsEnabled    = $false
    $window.Cursor = [Windows.Input.Cursors]::Wait

    $ok = 0; $fail = 0
    foreach ($row in $rows) {
        $ctrls.LblStatus.Text = "$label $($row.Role.Name)..."
        Flush-UI
        try {
            Invoke-Pim $action $script:Me.id $row.Role.RoleId $row.Role.ScopeId $minutes | Out-Null
            $msg = if ($minutes) { "$($row.Role.Name) — activated for $([int][Math]::Floor($minutes/60))h $($minutes%60)m" }
                   else          { "$($row.Role.Name) — deactivated" }
            Add-LogLine $msg 'success'
            $row.StatusHost.Children.Clear()
            $chipText = if ($minutes) { 'Activated' } else { 'Deactivated' }
            $null = $row.StatusHost.Children.Add((New-Chip $chipText 'success'))
            if ($row.Checkbox) { $row.Checkbox.IsEnabled = $false; $row.Checkbox.IsChecked = $false }
            $ok++
        } catch {
            Add-LogLine "$($row.Role.Name) — $(Format-GraphError $_)" 'danger'
            $null = $row.StatusHost.Children.Add((New-Chip 'Failed' 'danger'))
            $fail++
        }
    }

    try { Update-Roles } catch {}

    $ctrls.LblStatus.Text = "Done. $ok succeeded, $fail failed."
    $ctrls.BtnActivate.IsEnabled   = $true
    $ctrls.BtnDeactivate.IsEnabled = $true
    $ctrls.BtnRefresh.IsEnabled    = $true
    $window.Cursor = $null
}
#endregion

#region Events
$ctrls.BtnRefresh.Add_Click({ Update-Roles })
$ctrls.BtnActivate.Add_Click({
    $sel = @($script:EligibleRows | Where-Object { $_.Checkbox.IsChecked })
    Invoke-BulkAction 'Activating' $sel 'selfActivate' ([int]$ctrls.CmbDuration.SelectedItem.Tag)
})
$ctrls.BtnDeactivate.Add_Click({
    $sel = @($script:ActiveRows | Where-Object { $_.Checkbox -and $_.Checkbox.IsChecked })
    Invoke-BulkAction 'Deactivating' $sel 'selfDeactivate'
})
$ctrls.BtnSelectAll.Add_Click({
    foreach ($r in $script:EligibleRows) { if ($r.Checkbox.IsEnabled) { $r.Checkbox.IsChecked = $true } }
})
$ctrls.BtnClearAll.Add_Click({
    foreach ($r in $script:EligibleRows) { $r.Checkbox.IsChecked = $false }
})

$window.Add_Loaded({ Update-Roles })
$null = $window.ShowDialog()
#endregion
