# 2>NUL & @TITLE Laptop Inspector & @ECHO OFF & PUSHD "%~dp0" & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$_=Get-Content -LiteralPath \"%~f0\" -Raw; iex $_" & POPD & EXIT /B

# ============================================================
#  LAPTOP INSPECTOR v2.5 - Portable Edition
#  Full refurbished-laptop authenticity checker
# ============================================================

$ErrorActionPreference = "SilentlyContinue"
$scriptRoot = $PWD.Path
$timestamp  = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportsDir = Join-Path $scriptRoot "Reports"
if (!(Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir | Out-Null }

$reportTxt  = Join-Path $reportsDir "report_$timestamp.txt"
$reportCsv  = Join-Path $reportsDir "history.csv"
$reportHtml = Join-Path $reportsDir "report_$timestamp.html"
$battReportDest = Join-Path $reportsDir "battery_report_$timestamp.html"

# ========================
# HELPERS
# ========================
function Safe-Query {
    param([scriptblock]$Block, [string]$Fallback = "N/A")
    try { $r = & $Block; if ($null -eq $r -or $r -eq "") { return $Fallback } else { return $r } }
    catch { return $Fallback }
}

$checks = @()

function Add-Check {
    param([string]$Name, [bool]$Passed, [string]$Detail, [int]$Weight = 1)
    $script:checks += [PSCustomObject]@{
        Name = $Name; Passed = $Passed; Detail = $Detail; Weight = $Weight
    }
}

# ========================
# RATING FUNCTIONS
# ========================
function Get-Rating {
    param([double]$Value, [double]$Excellent, [double]$Good, [double]$Poor, [bool]$LowerIsBetter = $true)
    if ($LowerIsBetter) {
        if ($Value -le $Excellent) { return @{ Rating="EXCELLENT"; Color="#2ecc71" } }
        elseif ($Value -le $Good)  { return @{ Rating="GOOD"; Color="#3498db" } }
        elseif ($Value -le $Poor)  { return @{ Rating="POOR"; Color="#f39c12" } }
        else                       { return @{ Rating="VERY POOR"; Color="#e74c3c" } }
    } else {
        if ($Value -ge $Excellent) { return @{ Rating="EXCELLENT"; Color="#2ecc71" } }
        elseif ($Value -ge $Good)  { return @{ Rating="GOOD"; Color="#3498db" } }
        elseif ($Value -ge $Poor)  { return @{ Rating="POOR"; Color="#f39c12" } }
        else                       { return @{ Rating="VERY POOR"; Color="#e74c3c" } }
    }
}

function Get-BatteryRating {
    param([object]$WearPct, [object]$Cycles)
    $w = 999; $c = 999
    if ($WearPct -ne "N/A" -and $null -ne $WearPct) { try { $w = [double]$WearPct } catch {} }
    if ($Cycles -ne "N/A" -and $null -ne $Cycles) { try { $c = [int]$Cycles } catch {} }
    if ($w -le 10 -and $c -lt 300) {
        return @{ Rating="EXCELLENT"; Color="#2ecc71"; Desc="Battery is in excellent condition. Minimal wear." }
    } elseif ($w -le 25 -and $c -lt 500) {
        return @{ Rating="GOOD"; Color="#3498db"; Desc="Battery is in good condition. Normal wear for its age." }
    } elseif ($w -le 40 -and $c -lt 800) {
        return @{ Rating="POOR"; Color="#f39c12"; Desc="Significant wear. May need replacement soon." }
    } else {
        return @{ Rating="VERY POOR"; Color="#e74c3c"; Desc="Battery is heavily degraded. Replacement recommended." }
    }
}

function Get-GpuCondition {
    param([string]$DriverDateStr, [int]$CrashCount, [string]$GpuName)
    $score = 0
    if ($DriverDateStr -ne "N/A" -and $DriverDateStr -ne "") {
        try {
            $driverAge = ((Get-Date) - [DateTime]::Parse($DriverDateStr)).Days
            if ($driverAge -gt 730) { $score++ }
            if ($driverAge -gt 1095) { $score++ }
        } catch {}
    }
    if ($CrashCount -gt 5) { $score += 2 } elseif ($CrashCount -gt 0) { $score++ }
    if ($GpuName -match "NVIDIA|AMD|Radeon|GeForce|RTX|GTX") {
        if ($CrashCount -gt 3) { $score++ }
    }
    if ($score -le 0) { return @{ Rating="GOOD"; Color="#2ecc71"; Desc="GPU appears in good condition." } }
    elseif ($score -le 2) { return @{ Rating="WARNING"; Color="#f39c12"; Desc="GPU shows some wear or outdated drivers." } }
    else { return @{ Rating="CONCERNING"; Color="#e74c3c"; Desc="GPU may have been heavily used (mining/rendering)." } }
}

# ========================
# WPF GUI
# ========================
Add-Type -AssemblyName PresentationFramework

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Laptop Inspector v2.5" Height="900" Width="1200"
        Background="#0f0f1a" FontFamily="Segoe UI" WindowStartupLocation="CenterScreen"
        ResizeMode="CanResizeWithGrip">
    <Window.Resources>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#e0e0e0"/>
            <Setter Property="FontSize" Value="12.5"/>
        </Style>
    </Window.Resources>
    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Margin="0,0,0,12">
            <TextBlock Text="LAPTOP INSPECTOR" FontSize="26" FontWeight="Bold" Foreground="#00d4ff" HorizontalAlignment="Center"/>
            <TextBlock Text="Refurbished Laptop Authenticity Checker  v2.5" FontSize="12" Foreground="#8892b0" HorizontalAlignment="Center"/>
        </StackPanel>
        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="410"/>
                <ColumnDefinition Width="12"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <ScrollViewer VerticalScrollBarVisibility="Auto">
                <StackPanel x:Name="leftPanel">
                    <Border Background="#1a1a2e" CornerRadius="10" BorderBrush="#22FFFFFF" BorderThickness="1" Padding="14" Margin="0,0,0,8">
                        <StackPanel>
                            <TextBlock Text="DETECTED SPECS" Foreground="#00d4ff" FontWeight="Bold" FontSize="14" Margin="0,0,0,8"/>
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="90"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>
                                <TextBlock Text="Model:" Grid.Row="0" Foreground="#8892b0" Margin="0,3"/>
                                <TextBlock x:Name="lblMfg" Grid.Row="0" Grid.Column="1" Text="-" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,3"/>
                                <TextBlock Text="Serial:" Grid.Row="1" Foreground="#8892b0" Margin="0,3"/>
                                <TextBlock x:Name="lblSerial" Grid.Row="1" Grid.Column="1" Text="-" FontWeight="SemiBold" Margin="0,3"/>
                                <TextBlock Text="CPU:" Grid.Row="2" Foreground="#8892b0" Margin="0,3"/>
                                <TextBlock x:Name="lblCpu" Grid.Row="2" Grid.Column="1" Text="-" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,3"/>
                                <TextBlock Text="RAM:" Grid.Row="3" Foreground="#8892b0" Margin="0,3"/>
                                <TextBlock x:Name="lblRam" Grid.Row="3" Grid.Column="1" Text="-" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,3"/>
                                <TextBlock Text="GPU:" Grid.Row="4" Foreground="#8892b0" Margin="0,3"/>
                                <TextBlock x:Name="lblGpu" Grid.Row="4" Grid.Column="1" Text="-" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,3"/>
                                <TextBlock Text="Storage:" Grid.Row="5" Foreground="#8892b0" Margin="0,3"/>
                                <TextBlock x:Name="lblStorage" Grid.Row="5" Grid.Column="1" Text="-" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,3"/>
                                <TextBlock Text="Display:" Grid.Row="6" Foreground="#8892b0" Margin="0,3"/>
                                <TextBlock x:Name="lblDisplay" Grid.Row="6" Grid.Column="1" Text="-" FontWeight="SemiBold" Margin="0,3"/>
                                <TextBlock Text="OS:" Grid.Row="7" Foreground="#8892b0" Margin="0,3"/>
                                <TextBlock x:Name="lblOs" Grid.Row="7" Grid.Column="1" Text="-" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,3"/>
                                <TextBlock Text="BIOS Age:" Grid.Row="8" Foreground="#8892b0" Margin="0,3"/>
                                <TextBlock x:Name="lblBiosAge" Grid.Row="8" Grid.Column="1" Text="-" FontWeight="SemiBold" Margin="0,3"/>
                            </Grid>
                        </StackPanel>
                    </Border>
                    <Border Background="#1a1a2e" CornerRadius="10" BorderBrush="#22FFFFFF" BorderThickness="1" Padding="14" Margin="0,0,0,8">
                        <StackPanel>
                            <TextBlock Text="BATTERY HEALTH" Foreground="#00d4ff" FontWeight="Bold" FontSize="14" Margin="0,0,0,6"/>
                            <TextBlock x:Name="lblBattRating" Text="-" FontSize="20" FontWeight="Bold" HorizontalAlignment="Center" Margin="0,0,0,2"/>
                            <Border Background="#0a0a14" CornerRadius="5" Height="16" Margin="0,2,0,4">
                                <Border x:Name="battGaugeBar" Background="#555" CornerRadius="5" Height="16" HorizontalAlignment="Left" Width="0"/>
                            </Border>
                            <TextBlock x:Name="lblBattDesc" Text="-" Foreground="#8892b0" FontSize="10.5" TextWrapping="Wrap" HorizontalAlignment="Center"/>
                            <Grid Margin="0,6,0,0">
                                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                                <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                                <TextBlock Text="Charge:" Foreground="#8892b0" Margin="0,2"/>
                                <TextBlock x:Name="lblBattCharge" Grid.Column="1" Text="-" Margin="0,2"/>
                                <TextBlock Text="Wear:" Grid.Row="1" Foreground="#8892b0" Margin="0,2"/>
                                <TextBlock x:Name="lblBattWear" Grid.Row="1" Grid.Column="1" Text="-" Margin="0,2"/>
                                <TextBlock Text="Cycles:" Grid.Row="2" Foreground="#8892b0" Margin="0,2"/>
                                <TextBlock x:Name="lblBattCycles" Grid.Row="2" Grid.Column="1" Text="-" Margin="0,2"/>
                                <TextBlock Text="Capacity:" Grid.Row="3" Foreground="#8892b0" Margin="0,2"/>
                                <TextBlock x:Name="lblBattCap" Grid.Row="3" Grid.Column="1" Text="-" Margin="0,2"/>
                            </Grid>
                        </StackPanel>
                    </Border>
                    <Border Background="#1a1a2e" CornerRadius="10" BorderBrush="#22FFFFFF" BorderThickness="1" Padding="14" Margin="0,0,0,8">
                        <StackPanel>
                            <TextBlock Text="GPU CONDITION" Foreground="#00d4ff" FontWeight="Bold" FontSize="14" Margin="0,0,0,6"/>
                            <TextBlock x:Name="lblGpuRating" Text="-" FontSize="18" FontWeight="Bold" HorizontalAlignment="Center"/>
                            <TextBlock x:Name="lblGpuDesc" Text="-" Foreground="#8892b0" FontSize="10.5" TextWrapping="Wrap" HorizontalAlignment="Center"/>
                            <TextBlock x:Name="lblGpuDetail" Text="" Foreground="#8892b0" FontSize="10.5" TextWrapping="Wrap" Margin="0,4,0,0"/>
                        </StackPanel>
                    </Border>
                    <Border Background="#1a1a2e" CornerRadius="10" BorderBrush="#22FFFFFF" BorderThickness="1" Padding="14" Margin="0,0,0,8">
                        <StackPanel>
                            <TextBlock Text="DISK HEALTH (SMART)" Foreground="#00d4ff" FontWeight="Bold" FontSize="14" Margin="0,0,0,6"/>
                            <TextBlock x:Name="lblDiskPowerOn" Text="Power-On Hours: -" Margin="0,2"/>
                            <TextBlock x:Name="lblDiskPowerOnRating" Text="-" FontWeight="Bold" FontSize="16" HorizontalAlignment="Center" Margin="0,2"/>
                            <TextBlock x:Name="lblDiskSectors" Text="Reallocated Sectors: -" Margin="0,2"/>
                            <TextBlock x:Name="lblDiskSectorsRating" Text="-" FontWeight="Bold" FontSize="16" HorizontalAlignment="Center" Margin="0,2"/>
                        </StackPanel>
                    </Border>
                    <Border Background="#1a1a2e" CornerRadius="10" BorderBrush="#22FFFFFF" BorderThickness="1" Padding="14" Margin="0,0,0,8">
                        <StackPanel>
                            <TextBlock Text="CPU THROTTLE TEST" Foreground="#00d4ff" FontWeight="Bold" FontSize="14" Margin="0,0,0,6"/>
                            <TextBlock x:Name="lblThrottleResult" Text="-" FontSize="16" FontWeight="Bold" HorizontalAlignment="Center"/>
                            <TextBlock x:Name="lblThrottleDetail" Text="" Foreground="#8892b0" FontSize="10.5" TextWrapping="Wrap" HorizontalAlignment="Center" Margin="0,4,0,0"/>
                        </StackPanel>
                    </Border>
                    <Border Background="#1a1a2e" CornerRadius="10" BorderBrush="#22FFFFFF" BorderThickness="1" Padding="14" Margin="0,0,0,8">
                        <StackPanel>
                            <TextBlock Text="RAM STABILITY" Foreground="#00d4ff" FontWeight="Bold" FontSize="14" Margin="0,0,0,6"/>
                            <TextBlock x:Name="lblRamTest" Text="-" FontSize="16" FontWeight="Bold" HorizontalAlignment="Center"/>
                            <TextBlock x:Name="lblRamTestDetail" Text="" Foreground="#8892b0" FontSize="10.5" TextWrapping="Wrap" HorizontalAlignment="Center" Margin="0,4,0,0"/>
                        </StackPanel>
                    </Border>
                    <Border Background="#1a1a2e" CornerRadius="10" BorderBrush="#22FFFFFF" BorderThickness="1" Padding="14" Margin="0,0,0,8">
                        <StackPanel>
                            <TextBlock Text="OEM LICENSE" Foreground="#00d4ff" FontWeight="Bold" FontSize="14" Margin="0,0,0,6"/>
                            <TextBlock x:Name="lblOemKey" Text="-" FontSize="14" FontWeight="Bold" HorizontalAlignment="Center"/>
                            <TextBlock x:Name="lblOemDetail" Text="" Foreground="#8892b0" FontSize="10.5" TextWrapping="Wrap" HorizontalAlignment="Center" Margin="0,4,0,0"/>
                        </StackPanel>
                    </Border>
                    <Border Background="#0f0f1a" CornerRadius="10" Padding="14" Margin="0,0,0,4" BorderBrush="#22FFFFFF" BorderThickness="1">
                        <StackPanel HorizontalAlignment="Center">
                            <TextBlock Text="OVERALL HEALTH" Foreground="#8892b0" FontSize="11" HorizontalAlignment="Center"/>
                            <TextBlock x:Name="lblScore" Text="NOT RUN" FontSize="28" FontWeight="Bold" Foreground="#555" HorizontalAlignment="Center" Margin="0,4,0,0"/>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </ScrollViewer>
            <Border Grid.Column="2" Background="#1a1a2e" CornerRadius="10" BorderBrush="#22FFFFFF" BorderThickness="1" Padding="12">
                <ScrollViewer x:Name="LogScroll" VerticalScrollBarVisibility="Auto">
                    <TextBlock x:Name="txtLog" FontFamily="Consolas" TextWrapping="Wrap" FontSize="12" Foreground="#e0e0e0"/>
                </ScrollViewer>
            </Border>
        </Grid>
        <ProgressBar x:Name="ProgBar" Grid.Row="2" Height="5" Margin="0,12" Background="#1a1a2e" Foreground="#00d4ff" Maximum="100" Value="0" BorderThickness="0"/>
        <Grid Grid.Row="3">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="8"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="8"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="8"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="txtStatus" Text="Ready to inspect." VerticalAlignment="Center" Foreground="#8892b0" FontSize="12"/>
            <Button x:Name="btnPixelTest" Grid.Column="1" Content="PIXEL TEST" Width="110" Height="36" Background="#1a1a2e" Foreground="#d63384" FontWeight="Bold" FontSize="11" BorderThickness="1" BorderBrush="#d63384" Cursor="Hand" Visibility="Collapsed"/>
            <Button x:Name="btnBattReport" Grid.Column="3" Content="BATTERY RPT" Width="120" Height="36" Background="#1a1a2e" Foreground="#f39c12" FontWeight="Bold" FontSize="11" BorderThickness="1" BorderBrush="#f39c12" Cursor="Hand" Visibility="Collapsed"/>
            <Button x:Name="btnReport" Grid.Column="5" Content="OPEN REPORT" Width="120" Height="36" Background="#1a1a2e" Foreground="#00d4ff" FontWeight="Bold" FontSize="11" BorderThickness="1" BorderBrush="#00d4ff" Cursor="Hand" Visibility="Collapsed"/>
            <Button x:Name="btnStart" Grid.Column="7" Content="START SCAN" Width="140" Height="36" Background="#00d4ff" Foreground="#0f0f1a" FontWeight="Bold" FontSize="12" BorderThickness="0" Cursor="Hand"/>
        </Grid>
    </Grid>
</Window>
'@

$reader = (New-Object System.Xml.XmlNodeReader ([xml]$xaml))
$Window = [Windows.Markup.XamlReader]::Load($reader)

$txtLog    = $Window.FindName("txtLog")
$LogScroll = $Window.FindName("LogScroll")
$ProgBar   = $Window.FindName("ProgBar")
$txtStatus = $Window.FindName("txtStatus")
$btnStart  = $Window.FindName("btnStart")
$btnReport = $Window.FindName("btnReport")
$btnBattReport = $Window.FindName("btnBattReport")
$btnPixelTest  = $Window.FindName("btnPixelTest")

$lblMfg     = $Window.FindName("lblMfg")
$lblSerial  = $Window.FindName("lblSerial")
$lblCpu     = $Window.FindName("lblCpu")
$lblRam     = $Window.FindName("lblRam")
$lblGpu     = $Window.FindName("lblGpu")
$lblStorage = $Window.FindName("lblStorage")
$lblDisplay = $Window.FindName("lblDisplay")
$lblOs      = $Window.FindName("lblOs")
$lblBiosAge = $Window.FindName("lblBiosAge")
$lblScore   = $Window.FindName("lblScore")

$lblBattRating = $Window.FindName("lblBattRating")
$battGaugeBar  = $Window.FindName("battGaugeBar")
$lblBattDesc   = $Window.FindName("lblBattDesc")
$lblBattCharge = $Window.FindName("lblBattCharge")
$lblBattWear   = $Window.FindName("lblBattWear")
$lblBattCycles = $Window.FindName("lblBattCycles")
$lblBattCap    = $Window.FindName("lblBattCap")

$lblGpuRating  = $Window.FindName("lblGpuRating")
$lblGpuDesc    = $Window.FindName("lblGpuDesc")
$lblGpuDetail  = $Window.FindName("lblGpuDetail")

$lblDiskPowerOn       = $Window.FindName("lblDiskPowerOn")
$lblDiskPowerOnRating = $Window.FindName("lblDiskPowerOnRating")
$lblDiskSectors       = $Window.FindName("lblDiskSectors")
$lblDiskSectorsRating = $Window.FindName("lblDiskSectorsRating")

$lblThrottleResult = $Window.FindName("lblThrottleResult")
$lblThrottleDetail = $Window.FindName("lblThrottleDetail")

$lblRamTest       = $Window.FindName("lblRamTest")
$lblRamTestDetail = $Window.FindName("lblRamTestDetail")

$lblOemKey    = $Window.FindName("lblOemKey")
$lblOemDetail = $Window.FindName("lblOemDetail")

function DoEvents {
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(
        [System.Action]{},
        [System.Windows.Threading.DispatcherPriority]::Background
    )
}

function Write-Gui {
    param([string]$Text, [string]$Color = "#e0e0e0")
    switch ($Color) {
        "Cyan"       { $Color = "#00d4ff" }
        "DarkCyan"   { $Color = "#008ba3" }
        "Magenta"    { $Color = "#d63384" }
        "Blue"       { $Color = "#3498db" }
        "DarkYellow" { $Color = "#f39c12" }
        "Yellow"     { $Color = "#f1c40f" }
        "Green"      { $Color = "#2ecc71" }
        "Red"        { $Color = "#e74c3c" }
        "Gray"       { $Color = "#95a5a6" }
        "White"      { $Color = "#ffffff" }
    }
    $run = New-Object System.Windows.Documents.Run
    $run.Text = $Text + "`n"
    try { $run.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($Color) }
    catch { $run.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#e0e0e0") }
    $txtLog.Inlines.Add($run)
    $LogScroll.ScrollToEnd()
    DoEvents
}

function Update-ProgressBar([int]$Value, [string]$Status) {
    if ($Value -ge 0 -and $Value -le 100) { $ProgBar.Value = $Value }
    $txtStatus.Text = $Status
    DoEvents
}

function Set-LabelColor($Label, [string]$HexColor) {
    try { $Label.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($HexColor) } catch {}
}

function Write-Rating {
    param([string]$Label, [hashtable]$Rating, [string]$Extra = "")
    $color = switch($Rating.Rating) { "EXCELLENT" {"Green"} "GOOD" {"Blue"} "WARNING" {"DarkYellow"} default {"Red"} }
    Write-Gui "    $Label : $($Rating.Rating) $Extra" $color
}

# ========================
# DEAD PIXEL TEST WINDOW
# ========================
function Show-PixelTest {
    $pxaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Dead Pixel Test - Press Escape or click to cycle" WindowState="Maximized" WindowStyle="None"
        Background="Red" Topmost="True" Cursor="None">
    <Grid x:Name="pxGrid"/>
</Window>
'@
    $pr = New-Object System.Xml.XmlNodeReader ([xml]$pxaml)
    $pw = [Windows.Markup.XamlReader]::Load($pr)
    $colors = @("Red","Green","Blue","White","Black")
    $script:pxIdx = 0
    $pw.Add_MouseDown({
        $script:pxIdx++
        if ($script:pxIdx -ge $colors.Count) { $pw.Close(); return }
        $pw.Background = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($colors[$script:pxIdx])
    })
    $pw.Add_KeyDown({
        if ($_.Key -eq "Escape") { $pw.Close(); return }
        $script:pxIdx++
        if ($script:pxIdx -ge $colors.Count) { $pw.Close(); return }
        $pw.Background = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($colors[$script:pxIdx])
    })
    $pw.ShowDialog() | Out-Null
}

# Button handlers
$btnReport.Add_Click({ try { Invoke-Item $reportHtml } catch {} })
$btnBattReport.Add_Click({ try { if (Test-Path $battReportDest) { Invoke-Item $battReportDest } } catch {} })
$btnPixelTest.Add_Click({ Show-PixelTest })

# ========================
# MAIN SCAN
# ========================
$btnStart.Add_Click({
    $btnStart.IsEnabled = $false
    $btnStart.Content = "SCANNING..."
    $txtLog.Inlines.Clear()
    $script:checks = @()

    Write-Gui ""
    Write-Gui "  +================================================+" "Cyan"
    Write-Gui "  |   LAPTOP INSPECTOR v2.5 - Authenticity Checker  |" "Cyan"
    Write-Gui "  +================================================+" "Cyan"
    Write-Gui ""

    # ============================================================
    #  1. SYSTEM INFO
    # ============================================================
    Update-ProgressBar 3 "[1/16] Collecting system info..."
    Write-Gui "  [1/16] Collecting system info..." "DarkCyan"

    $cpu = Safe-Query { (Get-CimInstance Win32_Processor).Name }
    $cpuCores = Safe-Query { (Get-CimInstance Win32_Processor).NumberOfCores }
    $cpuThreads = Safe-Query { (Get-CimInstance Win32_Processor).NumberOfLogicalProcessors }
    $cpuMaxMhz = Safe-Query { (Get-CimInstance Win32_Processor).MaxClockSpeed }
    $cpuSpeed = Safe-Query { "$([math]::Round((Get-CimInstance Win32_Processor).MaxClockSpeed/1000,2)) GHz" }
    $ram = Safe-Query { [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory/1GB,2) }
    $ramSlots = Safe-Query {
        $sticks = @(Get-CimInstance Win32_PhysicalMemory)
        $details = ($sticks | ForEach-Object { "$([math]::Round($_.Capacity/1GB))GB $($_.Speed)MHz" }) -join " + "
        "$($sticks.Count) slot(s): $details"
    }
    $gpu = Safe-Query { ((Get-CimInstance Win32_VideoController).Name) -join "; " }
    $serial = Safe-Query { (Get-CimInstance Win32_BIOS).SerialNumber }
    $model = Safe-Query { (Get-CimInstance Win32_ComputerSystem).Model }
    $manufacturer = Safe-Query { (Get-CimInstance Win32_ComputerSystem).Manufacturer }

    Write-Gui "    $manufacturer $model (SN: $serial)" "White"
    Write-Gui "    CPU: $cpu ($cpuCores C / $cpuThreads T) $cpuSpeed" "White"
    Write-Gui "    RAM: $ram GB ($ramSlots)" "White"
    Write-Gui "    GPU: $gpu" "White"
    Write-Gui ""

    # ============================================================
    #  2. BIOS AGE & SYSTEM AGE
    # ============================================================
    Update-ProgressBar 8 "[2/16] Checking BIOS age..."
    Write-Gui "  [2/16] Checking BIOS age & system age..." "DarkCyan"

    $biosDate = Safe-Query {
        $d = (Get-CimInstance Win32_BIOS).ReleaseDate
        if ($d) { $d.ToString("yyyy-MM-dd") } else { "N/A" }
    }
    $biosVersion = Safe-Query { (Get-CimInstance Win32_BIOS).SMBIOSBIOSVersion }
    $biosAgeDays = -1
    $biosAgeRating = @{ Rating="N/A"; Color="#95a5a6" }
    if ($biosDate -ne "N/A") {
        try {
            $biosAgeDays = ((Get-Date) - [DateTime]::Parse($biosDate)).Days
            $biosAgeYears = [math]::Round($biosAgeDays / 365.25, 1)
            # Rating: <1yr=EXCELLENT, <2yr=GOOD, <4yr=POOR, >4yr=VERY POOR
            $biosAgeRating = Get-Rating -Value $biosAgeYears -Excellent 1 -Good 2 -Poor 4 -LowerIsBetter $true
        } catch {}
    }

    $installDate = Safe-Query {
        $d = (Get-CimInstance Win32_OperatingSystem).InstallDate
        if ($d) { $d.ToString("yyyy-MM-dd") } else { "N/A" }
    }

    # Check oldest event log entry to estimate real usage
    $oldestBoot = Safe-Query {
        try {
            $ev = Get-WinEvent -LogName System -MaxEvents 1 -Oldest -ErrorAction Stop
            if ($ev) { $ev.TimeCreated.ToString("yyyy-MM-dd") } else { "N/A" }
        } catch { "N/A" }
    }

    Add-Check -Name "BIOS Age" -Passed ($biosAgeDays -lt 1460) -Detail "BIOS: $biosDate ($biosVersion) Age: $([math]::Round($biosAgeDays/365.25,1))yr" -Weight 1
    
    Write-Gui "    BIOS Date: $biosDate ($biosVersion)" "White"
    if ($biosAgeDays -gt 0) {
        Write-Rating "BIOS Age" $biosAgeRating "$([math]::Round($biosAgeDays/365.25,1)) years"
    }
    Write-Gui "    OS Install Date: $installDate" "White"
    Write-Gui "    Oldest Event Log: $oldestBoot" "White"
    if ($installDate -ne "N/A" -and $oldestBoot -ne "N/A") {
        try {
            $instD = [DateTime]::Parse($installDate)
            $oldD  = [DateTime]::Parse($oldestBoot)
            $diff  = [math]::Abs(($instD - $oldD).Days)
            if ($diff -gt 30) {
                Write-Gui "    WARNING: OS install is $diff days newer than oldest log - possible reinstall" "Yellow"
            }
        } catch {}
    }
    Write-Gui ""

    # ============================================================
    #  3. OEM LICENSE KEY CHECK
    # ============================================================
    Update-ProgressBar 12 "[3/16] Checking OEM license key..."
    Write-Gui "  [3/16] Checking OEM license key..." "DarkCyan"

    $oemKey = Safe-Query {
        try {
            $k = (Get-CimInstance -Query "SELECT OA3xOriginalProductKey FROM SoftwareLicensingService" -ErrorAction Stop).OA3xOriginalProductKey
            if ($k -and $k.Length -gt 5) { $k } else { "Not embedded" }
        } catch { "N/A" }
    }
    $installedKeyLast5 = Safe-Query {
        try {
            $lic = Get-CimInstance SoftwareLicensingProduct -ErrorAction Stop |
                Where-Object { $_.PartialProductKey -and $_.Name -like "*Windows*" } | Select-Object -First 1
            if ($lic) { $lic.PartialProductKey } else { "N/A" }
        } catch { "N/A" }
    }
    $oemMatch = "N/A"
    if ($oemKey -ne "Not embedded" -and $oemKey -ne "N/A" -and $installedKeyLast5 -ne "N/A") {
        if ($oemKey.EndsWith($installedKeyLast5)) { $oemMatch = "MATCH" } else { $oemMatch = "MISMATCH" }
    }

    $oemOk = ($oemMatch -eq "MATCH" -or $oemMatch -eq "N/A")
    Add-Check -Name "OEM Key Match" -Passed $oemOk -Detail "OEM: $oemKey | Installed last5: $installedKeyLast5 | $oemMatch" -Weight 2

    Write-Gui "    OEM Key: $(if($oemKey.Length -gt 10){"XXXXX-XXXXX-XXXXX-$($oemKey.Substring($oemKey.Length-10))"}else{$oemKey})" "White"
    Write-Gui "    Installed Key (last 5): $installedKeyLast5" "White"
    Write-Gui "    Match: $oemMatch" $(if($oemMatch -eq "MATCH"){"Green"}elseif($oemMatch -eq "MISMATCH"){"Red"}else{"Gray"})
    Write-Gui ""

    # ============================================================
    #  4. GPU ANALYSIS
    # ============================================================
    Update-ProgressBar 18 "[4/16] Analyzing GPU condition..."
    Write-Gui "  [4/16] Analyzing GPU condition..." "DarkCyan"

    $gpuDriverVersion = Safe-Query { ((Get-CimInstance Win32_VideoController).DriverVersion) -join "; " }
    $gpuDriverDateRaw = Safe-Query {
        $d = (Get-CimInstance Win32_VideoController | Select-Object -First 1).DriverDate
        if ($d) { $d.ToString("yyyy-MM-dd") } else { "N/A" }
    }
    $gpuVram = Safe-Query {
        $v = Get-CimInstance Win32_VideoController | Select-Object -First 1
        if ($v.AdapterRAM -and $v.AdapterRAM -gt 0) { "$([math]::Round($v.AdapterRAM/1GB,1)) GB" } else { "N/A" }
    }
    $gpuStatus = Safe-Query { (Get-CimInstance Win32_VideoController | Select-Object -First 1).Status }
    $resolution = Safe-Query {
        $v = Get-CimInstance Win32_VideoController | Select-Object -First 1
        "$($v.CurrentHorizontalResolution) x $($v.CurrentVerticalResolution)"
    }
    $refreshRate = Safe-Query { (Get-CimInstance Win32_VideoController | Select-Object -First 1).CurrentRefreshRate }

    $gpuCrashCount = 0
    try {
        $since30 = (Get-Date).AddDays(-30)
        $gev = @(Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2,3; StartTime=$since30} -MaxEvents 300 -ErrorAction Stop |
            Where-Object { $_.Message -match "display|nvlddmkm|atikmdag|igfx|gpu|dxgkrnl|video" })
        $gpuCrashCount = $gev.Count
    } catch {}

    $gpuCondition = Get-GpuCondition -DriverDateStr $gpuDriverDateRaw -CrashCount $gpuCrashCount -GpuName $gpu
    $isDedicatedGpu = $gpu -match "NVIDIA|AMD|Radeon|GeForce|RTX|GTX|Quadro"
    $gpuTypeLabel = if ($isDedicatedGpu) { "Dedicated GPU" } else { "Integrated Only" }

    Add-Check -Name "GPU Condition" -Passed ($gpuCondition.Rating -eq "GOOD") `
              -Detail "$($gpuCondition.Rating) | Crashes(30d): $gpuCrashCount | $gpuTypeLabel" -Weight 2

    Write-Gui "    $gpu | VRAM: $gpuVram | $gpuTypeLabel" "White"
    Write-Gui "    Driver: $gpuDriverVersion ($gpuDriverDateRaw)" "White"
    Write-Gui "    Display driver crashes (30d): $gpuCrashCount" $(if($gpuCrashCount -eq 0){"Green"}elseif($gpuCrashCount -le 3){"Yellow"}else{"Red"})
    Write-Rating "Condition" $gpuCondition
    Write-Gui ""

    # ============================================================
    #  5. BATTERY HEALTH
    # ============================================================
    Update-ProgressBar 24 "[5/16] Analyzing battery health..."
    Write-Gui "  [5/16] Analyzing battery health..." "DarkCyan"

    $batteryPresent = $false
    $batteryPercent = Safe-Query {
        $b = Get-CimInstance Win32_Battery
        if ($b) { $script:batteryPresent = $true; $b.EstimatedChargeRemaining } else { "N/A" }
    }
    $batteryStatus = Safe-Query { $b = Get-CimInstance Win32_Battery; if($b){$b.Status}else{"N/A"} }
    $batteryChemistry = Safe-Query {
        $b = Get-CimInstance Win32_Battery; if(-not $b){return "N/A"}
        switch($b.Chemistry){1{"Other"}2{"Unknown"}3{"Lead Acid"}4{"NiCd"}5{"NiMH"}6{"Li-ion"}7{"Zinc air"}8{"Li-Polymer"}default{"Unknown"}}
    }

    $batteryReportPath = Join-Path $env:TEMP "batt_insp_$timestamp.html"
    $batteryWear = "N/A"; $designCapacity = "N/A"; $fullChargeCapacity = "N/A"; $cycleCount = "N/A"

    try {
        & powercfg /batteryreport /output $batteryReportPath 2>&1 | Out-Null
        Start-Sleep -Milliseconds 600
        if (Test-Path $batteryReportPath) {
            $html = Get-Content $batteryReportPath -Raw -ErrorAction Stop
            if ($html -match "DESIGN CAPACITY[\s\S]*?(\d[\d,]+)\s*mWh") { $designCapacity = $matches[1] -replace "," }
            if ($html -match "FULL CHARGE CAPACITY[\s\S]*?(\d[\d,]+)\s*mWh") { $fullChargeCapacity = $matches[1] -replace "," }
            if ($designCapacity -ne "N/A" -and $fullChargeCapacity -ne "N/A") {
                $dc = [int]$designCapacity; $fc = [int]$fullChargeCapacity
                if ($dc -gt 0) { $batteryWear = [math]::Round((1 - $fc/$dc)*100,1); if($batteryWear -lt 0){$batteryWear=0} }
            }
            if ($html -match "CYCLE COUNT[\s\S]*?(\d+)") { $cycleCount = $matches[1] }
            Copy-Item $batteryReportPath $battReportDest -Force -ErrorAction SilentlyContinue
            Remove-Item $batteryReportPath -Force -ErrorAction SilentlyContinue
        }
    } catch {}

    $battRating = Get-BatteryRating -WearPct $batteryWear -Cycles $cycleCount
    $wearOk = ($batteryWear -eq "N/A") -or ([double]$batteryWear -lt 30)
    Add-Check -Name "Battery Wear" -Passed $wearOk -Detail "Wear: $batteryWear% | Design: $designCapacity | Full: $fullChargeCapacity mWh" -Weight 3
    Add-Check -Name "Battery Status" -Passed ($batteryStatus -eq "OK" -or -not $batteryPresent) -Detail "Status: $batteryStatus" -Weight 2

    Write-Gui "    Charge: $batteryPercent% | Wear: $batteryWear% | Cycles: $cycleCount" "White"
    Write-Gui "    Design: $designCapacity mWh | Full Charge: $fullChargeCapacity mWh" "White"
    Write-Rating "Battery" $battRating "- $($battRating.Desc)"
    Write-Gui ""

    # ============================================================
    #  6. DISK SMART DEEP DIVE
    # ============================================================
    Update-ProgressBar 30 "[6/16] Checking disk SMART data..."
    Write-Gui "  [6/16] Checking disk SMART data..." "DarkCyan"

    $disks = @()
    try {
        Get-CimInstance Win32_DiskDrive | ForEach-Object {
            $dk = $_; $szGB = [math]::Round($dk.Size/1GB,1); $mt = "Unknown"
            try { $pd = Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.DeviceId -eq $dk.Index }; if($pd){$mt=$pd.MediaType} } catch {}
            $disks += [PSCustomObject]@{Model=$dk.Model;SizeGB=$szGB;Status=$dk.Status;MediaType=$mt;Serial=$dk.SerialNumber}
        }
    } catch {}

    $logicalDisks = @()
    try {
        Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
            $tGB=[math]::Round($_.Size/1GB,1); $fGB=[math]::Round($_.FreeSpace/1GB,1)
            $uPct = if($_.Size -gt 0){[math]::Round((($_.Size-$_.FreeSpace)/$_.Size)*100,1)}else{0}
            $logicalDisks += [PSCustomObject]@{Drive=$_.DeviceID;TotalGB=$tGB;FreeGB=$fGB;UsedPct=$uPct}
        }
    } catch {}

    $smartOk = $true
    $disks | ForEach-Object { if ($_.Status -ne "OK" -and $_.Status -ne "N/A") { $smartOk = $false } }
    Add-Check -Name "Disk S.M.A.R.T." -Passed $smartOk -Detail "Status: $(($disks|ForEach-Object{$_.Status})-join', ')" -Weight 3

    # Power-On Hours & Reallocated Sectors via StorageReliabilityCounter
    $powerOnHours = "N/A"; $reallocSectors = "N/A"; $readErrors = "N/A"; $writeErrors = "N/A"
    $powerOnRating = @{Rating="N/A";Color="#95a5a6"}
    $sectorRating  = @{Rating="N/A";Color="#95a5a6"}
    try {
        $rel = Get-PhysicalDisk | Get-StorageReliabilityCounter -ErrorAction Stop | Select-Object -First 1
        if ($rel) {
            if ($null -ne $rel.PowerOnHours -and $rel.PowerOnHours -ge 0) {
                $powerOnHours = $rel.PowerOnHours
                # <1000h=EXCELLENT, <5000h=GOOD, <10000h=POOR, >10000h=VERY POOR
                $powerOnRating = Get-Rating -Value $powerOnHours -Excellent 1000 -Good 5000 -Poor 10000 -LowerIsBetter $true
            }
            if ($null -ne $rel.ReadErrorsTotal) { $readErrors = $rel.ReadErrorsTotal }
            if ($null -ne $rel.WriteErrorsTotal) { $writeErrors = $rel.WriteErrorsTotal }
            # Reallocated sectors - try Wear property for SSDs
            if ($null -ne $rel.Wear) {
                $reallocSectors = $rel.Wear
                # For SSD wear: 0=EXCELLENT (100% life left), <5=GOOD, <30=POOR, >30=VERY POOR 
                $sectorRating = Get-Rating -Value $reallocSectors -Excellent 0 -Good 5 -Poor 30 -LowerIsBetter $true
            }
        }
    } catch {}

    Add-Check -Name "Disk Power-On Hours" -Passed ($powerOnHours -eq "N/A" -or [int]$powerOnHours -lt 10000) `
              -Detail "Hours: $powerOnHours | $($powerOnRating.Rating)" -Weight 3
    Add-Check -Name "Disk Wear/Sectors" -Passed ($reallocSectors -eq "N/A" -or [int]$reallocSectors -lt 30) `
              -Detail "Wear: $reallocSectors | Read Errors: $readErrors | Write Errors: $writeErrors" -Weight 3

    $totalStorage = ($disks | Measure-Object -Property SizeGB -Sum).Sum

    foreach ($d in $disks) { Write-Gui "    [$($d.MediaType)] $($d.Model) - $($d.SizeGB)GB - SMART: $($d.Status)" "White" }
    foreach ($ld in $logicalDisks) { Write-Gui "    Drive $($ld.Drive) $($ld.FreeGB)GB free / $($ld.TotalGB)GB ($($ld.UsedPct)% used)" "White" }
    Write-Gui "    Power-On Hours: $powerOnHours" "White"
    if ($powerOnHours -ne "N/A") { Write-Rating "Power-On" $powerOnRating "$powerOnHours hours (<1000=Excellent, <5000=Good, <10000=Poor)" }
    Write-Gui "    Disk Wear / Reallocated: $reallocSectors | Read Errors: $readErrors | Write: $writeErrors" "White"
    if ($reallocSectors -ne "N/A") { Write-Rating "Disk Wear" $sectorRating }
    Write-Gui ""

    # ============================================================
    #  7. CPU THROTTLE TEST
    # ============================================================
    Update-ProgressBar 38 "[7/16] CPU throttle test (8 seconds)..."
    Write-Gui "  [7/16] CPU throttle test (~8 seconds)..." "DarkCyan"
    Write-Gui "    Running CPU stress burst..." "Gray"
    DoEvents

    $throttleRating = @{Rating="N/A";Color="#95a5a6"}
    $throttlePct = "N/A"
    $baseClock = 0; $stressClock = 0
    try {
        $baseClock = (Get-CimInstance Win32_Processor).CurrentClockSpeed
        if ($null -eq $baseClock -or $baseClock -eq 0) { $baseClock = (Get-CimInstance Win32_Processor).MaxClockSpeed }

        # Brief stress: spin CPU for ~8 seconds
        $stressEnd = (Get-Date).AddSeconds(8)
        while ((Get-Date) -lt $stressEnd) {
            for ($i = 0; $i -lt 50000; $i++) { $null = [math]::Sqrt(12345.6789 * $i) }
            DoEvents
        }

        $stressClock = (Get-CimInstance Win32_Processor).CurrentClockSpeed
        $maxClock = [int](Safe-Query { (Get-CimInstance Win32_Processor).MaxClockSpeed })
        if ($maxClock -gt 0 -and $stressClock -gt 0) {
            $throttlePct = [math]::Round(($stressClock / $maxClock) * 100, 1)
            # >=95%=EXCELLENT, >=85%=GOOD, >=70%=POOR, <70%=VERY POOR
            $throttleRating = Get-Rating -Value $throttlePct -Excellent 95 -Good 85 -Poor 70 -LowerIsBetter $false
        }
    } catch {}

    $throttleOk = ($throttlePct -eq "N/A") -or ([double]$throttlePct -ge 70)
    Add-Check -Name "CPU Throttle" -Passed $throttleOk `
              -Detail "Clock held: $throttlePct% of max | $($throttleRating.Rating)" -Weight 2

    Write-Gui "    Base Clock: $baseClock MHz | Under Stress: $stressClock MHz | Max: $cpuMaxMhz MHz" "White"
    if ($throttlePct -ne "N/A") {
        Write-Rating "Throttle" $throttleRating "- Maintained $throttlePct% of max clock"
        if ([double]$throttlePct -lt 85) {
            Write-Gui "    WARNING: CPU may have thermal issues (bad paste, worn cooling)" "Yellow"
        }
    }
    Write-Gui ""

    # ============================================================
    #  8. RAM STABILITY CHECK
    # ============================================================
    Update-ProgressBar 46 "[8/16] RAM stability test..."
    Write-Gui "  [8/16] RAM stability test (~5 seconds)..." "DarkCyan"
    DoEvents

    $ramTestResult = "N/A"
    $ramTestRating = @{Rating="N/A";Color="#95a5a6"}
    $ramBlocksMB = 256
    $ramBlocksCount = [math]::Min(4, [math]::Floor([double]$ram / 2))  # Test up to half of RAM, max 4 blocks
    $ramErrors = 0
    try {
        for ($b = 0; $b -lt $ramBlocksCount; $b++) {
            try {
                $arr = New-Object byte[] ($ramBlocksMB * 1MB)
                # Fill with pattern
                $rng = New-Object System.Random(42)
                $rng.NextBytes($arr)
                # Read back and verify a sample
                $rng2 = New-Object System.Random(42)
                $check = New-Object byte[] 4096
                $rng2.NextBytes($check)
                $mismatch = $false
                for ($j = 0; $j -lt 4096; $j++) {
                    if ($arr[$j] -ne $check[$j]) { $mismatch = $true; break }
                }
                if ($mismatch) { $ramErrors++ }
                $arr = $null
            } catch { $ramErrors++ }
            DoEvents
        }
        [GC]::Collect()
        if ($ramErrors -eq 0) {
            $ramTestResult = "PASS"
            $ramTestRating = @{Rating="EXCELLENT";Color="#2ecc71"}
        } else {
            $ramTestResult = "ERRORS ($ramErrors)"
            $ramTestRating = @{Rating="VERY POOR";Color="#e74c3c"}
        }
    } catch {
        $ramTestResult = "COULD NOT TEST"
        $ramTestRating = @{Rating="N/A";Color="#95a5a6"}
    }

    Add-Check -Name "RAM Stability" -Passed ($ramErrors -eq 0) `
              -Detail "Tested $ramBlocksCount x ${ramBlocksMB}MB blocks - Errors: $ramErrors" -Weight 2

    Write-Gui "    Tested $ramBlocksCount x ${ramBlocksMB}MB blocks | Errors: $ramErrors" "White"
    Write-Rating "RAM" $ramTestRating "- $ramTestResult"
    Write-Gui ""

    # ============================================================
    #  9. DISPLAY PANEL INFO
    # ============================================================
    Update-ProgressBar 52 "[9/16] Checking display panel..."
    Write-Gui "  [9/16] Checking display panel..." "DarkCyan"

    $panelMfg = "N/A"; $panelModel = "N/A"; $panelType = "N/A"
    try {
        $mon = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop | Select-Object -First 1
        if ($mon) {
            $panelMfg = if($mon.ManufacturerName){ -join ($mon.ManufacturerName | Where-Object {$_ -gt 0} | ForEach-Object {[char]$_}) } else { "N/A" }
            $panelModel = if($mon.UserFriendlyName){ -join ($mon.UserFriendlyName | Where-Object {$_ -gt 0} | ForEach-Object {[char]$_}) } else { "N/A" }
        }
    } catch {}
    try {
        $monConn = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams -ErrorAction Stop | Select-Object -First 1
        if ($monConn) {
            $panelType = switch($monConn.VideoOutputTechnology) {
                0 {"VGA"} 2 {"S-Video"} 3 {"Composite"} 4 {"Component"} 5 {"DVI"} 6 {"HDMI"} 
                8 {"D_Jpn"} 9 {"SDI"} 10 {"DisplayPort"} 11 {"eDP (internal)"} 12 {"UDI"}
                14 {"LVDS (internal)"} 0xFFFFFFFF {"Internal"} default {"Type $($monConn.VideoOutputTechnology)"}
            }
        }
    } catch {}

    Write-Gui "    Panel Manufacturer: $panelMfg" "White"
    Write-Gui "    Panel Model: $panelModel" "White"
    Write-Gui "    Connection: $panelType" "White"
    Write-Gui "    Resolution: $resolution @ ${refreshRate}Hz" "White"
    Write-Gui "    (Use PIXEL TEST button after scan to check for dead pixels)" "Magenta"
    Write-Gui ""

    # ============================================================
    #  10. TEMPERATURE
    # ============================================================
    Update-ProgressBar 58 "[10/16] Reading temperatures..."
    Write-Gui "  [10/16] Reading temperatures..." "DarkCyan"

    $temp = "N/A"
    try {
        $tz = Get-CimInstance -Namespace "root\WMI" -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop | Select-Object -First 1
        if ($tz -and $tz.CurrentTemperature) { $temp = [math]::Round(($tz.CurrentTemperature/10)-273.15,1) }
    } catch {}

    $tempOk = ($temp -eq "N/A") -or ([double]$temp -lt 85)
    $tempRating = if ($temp -ne "N/A") { Get-Rating -Value $temp -Excellent 45 -Good 65 -Poor 85 -LowerIsBetter $true } else { @{Rating="N/A";Color="#95a5a6"} }
    Add-Check -Name "Temperature" -Passed $tempOk -Detail "$(if($temp -ne 'N/A'){"${temp}C"}else{'N/A (needs admin)'}) | $($tempRating.Rating)" -Weight 1

    Write-Gui "    Temperature: $(if($temp -ne 'N/A'){"$temp C"}else{'N/A (may need admin)'})" "White"
    if ($temp -ne "N/A") { Write-Rating "Temp" $tempRating "(<45=Excellent, <65=Good, <85=Poor)" }
    Write-Gui ""

    # ============================================================
    #  11. NETWORK
    # ============================================================
    Update-ProgressBar 63 "[11/16] Checking network..."
    Write-Gui "  [11/16] Checking network..." "DarkCyan"

    $wifiAdapter = Safe-Query {
        (Get-CimInstance Win32_NetworkAdapter | Where-Object {
            $_.NetConnectionID -like "*Wi-Fi*" -or $_.NetConnectionID -like "*Wireless*" -or
            $_.Name -like "*Wireless*" -or $_.Name -like "*Wi-Fi*"
        } | Select-Object -First 1).Name
    }
    $ethernetAdapters = Safe-Query {
        ((Get-CimInstance Win32_NetworkAdapter | Where-Object {
            $_.NetConnectionID -like "*Ethernet*" -and $_.PhysicalAdapter -eq $true
        }).Name) -join "; "
    }
    $wifiSignal = Safe-Query {
        $p = netsh wlan show interfaces 2>$null | Select-String "Signal"
        if ($p) { ($p -split ":")[1].Trim() } else { "N/A" }
    }

    $internetOk = $false; $pingLatency = "N/A"
    try {
        $ping = Test-Connection -ComputerName "8.8.8.8" -Count 2 -ErrorAction Stop
        $internetOk = $true
        try { $pingLatency = "$([math]::Round(($ping|Measure-Object -Property Latency -Average).Average,1)) ms" }
        catch { $pingLatency = "Connected" }
    } catch {}

    Add-Check -Name "Wi-Fi Adapter" -Passed ($wifiAdapter -ne "N/A") -Detail "$wifiAdapter" -Weight 1
    Add-Check -Name "Internet" -Passed $internetOk -Detail "Ping: $pingLatency" -Weight 1

    Write-Gui "    Wi-Fi: $wifiAdapter (Signal: $wifiSignal)" "White"
    Write-Gui "    Ethernet: $ethernetAdapters" "White"
    Write-Gui "    Internet: $(if($internetOk){'Connected'}else{'No Connection'}) ($pingLatency)" $(if($internetOk){"Green"}else{"Red"})
    Write-Gui ""

    # ============================================================
    #  12. OS & SECURITY
    # ============================================================
    Update-ProgressBar 70 "[12/16] Checking OS & security..."
    Write-Gui "  [12/16] Checking OS & security..." "DarkCyan"

    $osName = Safe-Query { (Get-CimInstance Win32_OperatingSystem).Caption }
    $osBuild = Safe-Query { (Get-CimInstance Win32_OperatingSystem).BuildNumber }
    $osVersion = Safe-Query { (Get-CimInstance Win32_OperatingSystem).Version }
    $osArch = Safe-Query { (Get-CimInstance Win32_OperatingSystem).OSArchitecture }
    $lastBoot = Safe-Query {
        $d = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        if ($d) { $d.ToString("yyyy-MM-dd HH:mm") } else { "N/A" }
    }
    $uptime = "N/A"
    try { $boot=(Get-CimInstance Win32_OperatingSystem).LastBootUpTime; if($boot){$up=(Get-Date)-$boot;$uptime="$($up.Days)d $($up.Hours)h"} } catch {}

    $activated = Safe-Query {
        $lic = Get-CimInstance SoftwareLicensingProduct -ErrorAction Stop |
            Where-Object { $_.PartialProductKey -and $_.Name -like "*Windows*" } | Select-Object -First 1
        if ($lic -and $lic.LicenseStatus -eq 1) { "Activated" } else { "Not Activated" }
    }
    $bitlocker = Safe-Query { try { $bl=Get-BitLockerVolume -MountPoint "C:" -ErrorAction Stop; $bl.ProtectionStatus.ToString() } catch {"N/A"} }
    $avStatus = "N/A"
    try { $def=Get-MpComputerStatus -ErrorAction Stop; $avStatus=if($def.RealTimeProtectionEnabled){"Defender (Active)"}else{"Defender (Disabled)"} }
    catch { $avStatus = Safe-Query { $av=Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName AntiVirusProduct -ErrorAction Stop|Select-Object -First 1; if($av){$av.displayName}else{"N/A"} } }
    $firewallStatus = Safe-Query { try{$fw=Get-NetFirewallProfile -ErrorAction Stop|Where-Object{$_.Enabled};if($fw){"Enabled"}else{"Disabled"}}catch{"N/A"} }
    $tpmVersion = Safe-Query { try{$t=Get-CimInstance -Namespace "root\cimv2\security\microsofttpm" -ClassName Win32_Tpm -ErrorAction Stop; if($t-and$t.SpecVersion){$t.SpecVersion.Split(",")[0]}else{"Not Found"}}catch{"N/A"} }
    $secureBoot = Safe-Query { try{if(Confirm-SecureBootUEFI -ErrorAction Stop){"Enabled"}else{"Disabled"}}catch{"N/A"} }

    Add-Check -Name "Windows Activation" -Passed ($activated -eq "Activated") -Detail "$activated" -Weight 2
    Add-Check -Name "Antivirus" -Passed ($avStatus -ne "N/A" -and $avStatus -notlike "*Disabled*") -Detail "$avStatus" -Weight 1
    Add-Check -Name "Firewall" -Passed ($firewallStatus -like "*Enabled*") -Detail "$firewallStatus" -Weight 1
    Add-Check -Name "TPM" -Passed ($tpmVersion -ne "N/A" -and $tpmVersion -ne "Not Found" -and $tpmVersion -notlike "*requires*") -Detail "v$tpmVersion" -Weight 1

    Write-Gui "    OS: $osName ($osArch) Build $osBuild" "White"
    Write-Gui "    Installed: $installDate | Boot: $lastBoot | Up: $uptime" "White"
    Write-Gui "    Activation: $activated" $(if($activated -eq "Activated"){"Green"}else{"Red"})
    Write-Gui "    AV: $avStatus | FW: $firewallStatus | TPM: $tpmVersion | SecureBoot: $secureBoot" "White"
    Write-Gui ""

    # ============================================================
    #  13. PERIPHERALS & USB & FAN
    # ============================================================
    Update-ProgressBar 78 "[13/16] Detecting peripherals, USB, fan..."
    Write-Gui "  [13/16] Detecting peripherals, USB ports, fan..." "DarkCyan"

    $webcam = Safe-Query { $c=Get-CimInstance Win32_PnPEntity|Where-Object{$_.PNPClass -eq "Camera" -or $_.PNPClass -eq "Image" -or $_.Name -like "*webcam*" -or $_.Name -like "*camera*"}|Select-Object -First 1; if($c){$c.Name}else{"Not Found"} }
    $bluetooth = Safe-Query { $b=Get-CimInstance Win32_PnPEntity|Where-Object{$_.PNPClass -eq "Bluetooth" -or $_.Name -like "*Bluetooth*"}|Select-Object -First 1; if($b){$b.Name}else{"Not Found"} }
    $audioDevices = Safe-Query { $a=(Get-CimInstance Win32_SoundDevice).Name; if($a){$a -join "; "}else{"Not Found"} }
    $keyboard = Safe-Query { $k=Get-CimInstance Win32_Keyboard -ErrorAction Stop|Select-Object -First 1; if($k){$k.Description}else{"Not Found"} }
    $touchpad = Safe-Query { $t=Get-CimInstance Win32_PnPEntity|Where-Object{$_.Name -like "*touchpad*" -or $_.Name -like "*trackpad*" -or $_.Name -like "*pointing*"}|Select-Object -First 1; if($t){$t.Name}else{"Not Found"} }

    # USB port enumeration
    $usbControllers = @()
    try { $usbControllers = @(Get-CimInstance Win32_USBController -ErrorAction Stop) } catch {}
    $usbDevices = @()
    try {
        $usbDevices = @(Get-CimInstance Win32_USBControllerDevice -ErrorAction Stop | ForEach-Object {
            try { [wmi]($_.Dependent) } catch { $null }
        } | Where-Object { $_ -ne $null -and $_.Name -notlike "*Hub*" -and $_.Name -notlike "*Controller*" })
    } catch {}

    # Fan detection
    $fanDetected = Safe-Query {
        try {
            $f = Get-CimInstance -Namespace "root\WMI" -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop
            if ($f) { "Thermal zone active (fan likely present)" } else { "N/A" }
        } catch {
            $f2 = Get-CimInstance Win32_Fan -ErrorAction SilentlyContinue
            if ($f2) { "Detected: $($f2.Name)" } else { "Not detected via WMI" }
        }
    }

    Add-Check -Name "Webcam" -Passed ($webcam -ne "Not Found") -Detail "$webcam" -Weight 1
    Add-Check -Name "Bluetooth" -Passed ($bluetooth -ne "Not Found") -Detail "$bluetooth" -Weight 1
    Add-Check -Name "Audio" -Passed ($audioDevices -ne "Not Found") -Detail "$audioDevices" -Weight 1
    Add-Check -Name "Keyboard" -Passed ($keyboard -ne "Not Found") -Detail "$keyboard" -Weight 1
    Add-Check -Name "USB Ports" -Passed ($usbControllers.Count -gt 0) -Detail "$($usbControllers.Count) controllers, $($usbDevices.Count) devices" -Weight 1

    Write-Gui "    Webcam: $webcam" "White"
    Write-Gui "    Bluetooth: $bluetooth" "White"
    Write-Gui "    Audio: $audioDevices" "White"
    Write-Gui "    Keyboard: $keyboard | Touchpad: $touchpad" "White"
    Write-Gui "    USB: $($usbControllers.Count) controllers, $($usbDevices.Count) devices attached" "White"
    Write-Gui "    Fan: $fanDetected" "White"
    Write-Gui ""

    # ============================================================
    #  14. POWER PLAN & STARTUP
    # ============================================================
    Update-ProgressBar 84 "[14/16] Checking power plan & startup..."
    Write-Gui "  [14/16] Checking power plan & startup..." "DarkCyan"

    $powerPlan = Safe-Query { $p=powercfg /getactivescheme 2>$null; if($p){$p -replace ".*:\s*","" -replace "\(|\)",""}else{"N/A"} }
    $startupItems = @(); try { $startupItems = @(Get-CimInstance Win32_StartupCommand -ErrorAction Stop | Select-Object Name, Command, Location) } catch {}
    $processCount = Safe-Query { (Get-Process).Count }
    $topMemProcs = @(); try { $topMemProcs = @(Get-Process|Sort-Object WorkingSet64 -Descending|Select-Object -First 5 Name,@{N="MemMB";E={[math]::Round($_.WorkingSet64/1MB,1)}}) } catch {}

    # Startup bloat rating: <10=EXCELLENT, <25=GOOD, <50=POOR, >50=VERY POOR
    $startupRating = Get-Rating -Value $startupItems.Count -Excellent 10 -Good 25 -Poor 50 -LowerIsBetter $true

    Write-Gui "    Power Plan: $powerPlan" "White"
    Write-Gui "    Processes: $processCount | Startup Items: $($startupItems.Count)" "White"
    Write-Rating "Startup Bloat" $startupRating "$($startupItems.Count) items"
    if ($topMemProcs.Count -gt 0) {
        Write-Gui "    Top RAM:" "Gray"
        foreach ($p in $topMemProcs) { Write-Gui "      $($p.Name): $($p.MemMB) MB" "Gray" }
    }
    Write-Gui ""

    # ============================================================
    #  15. EVENT LOG
    # ============================================================
    Update-ProgressBar 90 "[15/16] Scanning event logs..."
    Write-Gui "  [15/16] Scanning event logs..." "DarkCyan"

    $criticalEvents = @()
    try {
        $since48 = (Get-Date).AddHours(-48)
        $criticalEvents = @(Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2;StartTime=$since48} -MaxEvents 20 -ErrorAction Stop |
            Select-Object TimeCreated, Id, Message)
    } catch {}
    $eventIssues = $criticalEvents.Count
    # <0=EXCELLENT, <3=GOOD, <10=POOR, >10=VERY POOR
    $eventRating = Get-Rating -Value $eventIssues -Excellent 0 -Good 3 -Poor 10 -LowerIsBetter $true
    Add-Check -Name "System Errors (48h)" -Passed ($eventIssues -eq 0) -Detail "$eventIssues critical/error events" -Weight 2

    Write-Gui "    Critical/Error Events (48h): $eventIssues" $(if($eventIssues -eq 0){"Green"}else{"Red"})
    Write-Rating "Event Log" $eventRating
    Write-Gui ""

    # ============================================================
    #  16. SPEAKER TEST
    # ============================================================
    Update-ProgressBar 95 "[16/16] Testing speaker..."
    Write-Gui "  [16/16] Testing speaker..." "DarkCyan"
    try { [console]::Beep(800,300); [console]::Beep(1000,300); [console]::Beep(1200,200) } catch {}
    Write-Gui "    Speaker test complete (3 beeps)" "White"
    Write-Gui ""

    # ============================================================
    #  SCORING
    # ============================================================
    $totalWeight = ($checks | Measure-Object -Property Weight -Sum).Sum
    if ($totalWeight -eq 0) { $totalWeight = 1 }
    $earnedWeight = ($checks | Where-Object { $_.Passed } | Measure-Object -Property Weight -Sum).Sum
    $scorePct = [math]::Round(($earnedWeight / $totalWeight) * 100, 0)

    if ($scorePct -ge 85) { $result = "EXCELLENT"; $resultColor = "Green" }
    elseif ($scorePct -ge 70) { $result = "GOOD"; $resultColor = "Blue" }
    elseif ($scorePct -ge 50) { $result = "POOR"; $resultColor = "Yellow" }
    else { $result = "VERY POOR"; $resultColor = "Red" }

    Write-Gui "  +------------------------------------------------+" "Yellow"
    Write-Gui "  |             CHECK RESULTS                       |" "Yellow"
    Write-Gui "  +------------------------------------------------+" "Yellow"
    foreach ($c in $checks) {
        $icon = if ($c.Passed) { "[PASS]" } else { "[FAIL]" }
        $clr = if ($c.Passed) { "Green" } else { "Red" }
        Write-Gui "  $icon $($c.Name.PadRight(22)) x$($c.Weight)  $($c.Detail)" $clr
    }
    Write-Gui ""
    Write-Gui "  +================================================+" $resultColor
    Write-Gui "  |  RESULT: $($result.PadRight(14)) SCORE: $earnedWeight/$totalWeight ($scorePct%)      |" $resultColor
    Write-Gui "  +================================================+" $resultColor
    Write-Gui ""

    # ============================================================
    #  UPDATE GUI PANELS
    # ============================================================
    $lblMfg.Text = "$manufacturer $model"
    $lblSerial.Text = $serial
    $lblCpu.Text = "$cpu ($cpuCores C/$cpuThreads T) $cpuSpeed"
    $lblRam.Text = "$ram GB - $ramSlots"
    $lblGpu.Text = "$gpu (VRAM: $gpuVram)"
    $lblStorage.Text = "$([math]::Round($totalStorage,1)) GB - $(($disks|ForEach-Object{$_.MediaType})-join', ')"
    $lblDisplay.Text = "$resolution @ ${refreshRate}Hz | $panelMfg $panelModel"
    $lblOs.Text = "$osName ($osArch) Build $osBuild"
    if ($biosAgeDays -gt 0) { $lblBiosAge.Text = "$biosDate ($([math]::Round($biosAgeDays/365.25,1)) yrs) - $($biosAgeRating.Rating)"; Set-LabelColor $lblBiosAge $biosAgeRating.Color }
    else { $lblBiosAge.Text = $biosDate }

    # Battery gauge
    $lblBattRating.Text = $battRating.Rating; Set-LabelColor $lblBattRating $battRating.Color
    $lblBattDesc.Text = $battRating.Desc
    $lblBattCharge.Text = "$batteryPercent%"
    $lblBattWear.Text = if($batteryWear -ne "N/A"){"$batteryWear%"}else{"N/A"}
    $lblBattCycles.Text = "$cycleCount"
    $lblBattCap.Text = if($designCapacity -ne "N/A"){"$fullChargeCapacity / $designCapacity mWh"}else{"N/A"}
    $gw = 370
    if ($batteryWear -ne "N/A") { $hp=[math]::Max(0,100-[double]$batteryWear); $battGaugeBar.Width=[math]::Round($gw*$hp/100) }
    else { $battGaugeBar.Width = $gw }
    try { $battGaugeBar.Background = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($battRating.Color) } catch {}

    # GPU
    $lblGpuRating.Text = $gpuCondition.Rating; Set-LabelColor $lblGpuRating $gpuCondition.Color
    $lblGpuDesc.Text = $gpuCondition.Desc
    $lblGpuDetail.Text = "$gpuTypeLabel | VRAM: $gpuVram | Driver: $gpuDriverDateRaw | Crashes: $gpuCrashCount"

    # Disk SMART
    $lblDiskPowerOn.Text = "Power-On Hours: $powerOnHours"
    $lblDiskPowerOnRating.Text = $powerOnRating.Rating; Set-LabelColor $lblDiskPowerOnRating $powerOnRating.Color
    $lblDiskSectors.Text = "Disk Wear / Realloc: $reallocSectors | Read Err: $readErrors"
    $lblDiskSectorsRating.Text = $sectorRating.Rating; Set-LabelColor $lblDiskSectorsRating $sectorRating.Color

    # Throttle
    $lblThrottleResult.Text = $throttleRating.Rating; Set-LabelColor $lblThrottleResult $throttleRating.Color
    $lblThrottleDetail.Text = "Clock held $throttlePct% of max ($stressClock/$cpuMaxMhz MHz)"

    # RAM
    $lblRamTest.Text = $ramTestRating.Rating; Set-LabelColor $lblRamTest $ramTestRating.Color
    $lblRamTestDetail.Text = "$ramTestResult - Tested $ramBlocksCount x ${ramBlocksMB}MB"

    # OEM Key
    $oemColor = if($oemMatch -eq "MATCH"){"#2ecc71"}elseif($oemMatch -eq "MISMATCH"){"#e74c3c"}else{"#95a5a6"}
    $lblOemKey.Text = $oemMatch; Set-LabelColor $lblOemKey $oemColor
    $lblOemDetail.Text = "OEM key $(if($oemKey -ne 'Not embedded' -and $oemKey -ne 'N/A'){'embedded'}else{'not embedded'}) in BIOS | Installed last5: $installedKeyLast5"

    # Score
    $lblScore.Text = "$result ($scorePct%)"
    $scoreColor = switch($result){"EXCELLENT"{"#2ecc71"}"GOOD"{"#3498db"}"POOR"{"#f39c12"}default{"#e74c3c"}}
    Set-LabelColor $lblScore $scoreColor

    # ============================================================
    #  REPORTS
    # ============================================================
    $textReport = @"
================================================================
  LAPTOP INSPECTION REPORT v2.5
  Generated: $timestamp
================================================================

--- SYSTEM ---
Manufacturer : $manufacturer
Model        : $model
Serial       : $serial
CPU          : $cpu ($cpuCores C/$cpuThreads T) $cpuSpeed
RAM          : $ram GB ($ramSlots)
GPU          : $gpu (VRAM: $gpuVram) | $gpuTypeLabel
GPU Driver   : $gpuDriverVersion ($gpuDriverDateRaw)
GPU Condition: $($gpuCondition.Rating) - $($gpuCondition.Desc)
GPU Crashes  : $gpuCrashCount (30 day)
Resolution   : $resolution @ $refreshRate Hz
Panel        : $panelMfg $panelModel ($panelType)

--- BIOS & AGE ---
BIOS Date    : $biosDate ($biosVersion)
BIOS Age     : $([math]::Round($biosAgeDays/365.25,1)) years - $($biosAgeRating.Rating)
OS Install   : $installDate
Oldest Log   : $oldestBoot

--- OEM LICENSE ---
OEM Key      : $oemKey
Installed    : ...$installedKeyLast5
Match        : $oemMatch

--- BATTERY ---
Charge       : $batteryPercent %
Chemistry    : $batteryChemistry
Design Cap.  : $designCapacity mWh
Full Charge  : $fullChargeCapacity mWh
Wear Level   : $batteryWear %
Cycle Count  : $cycleCount
Status       : $batteryStatus
Rating       : $($battRating.Rating) - $($battRating.Desc)

--- STORAGE (SMART) ---
$(($disks|ForEach-Object{"[$($_.MediaType)] $($_.Model) - $($_.SizeGB)GB - SMART: $($_.Status)"})-join"`n")
$(($logicalDisks|ForEach-Object{"Drive $($_.Drive) $($_.FreeGB)GB free / $($_.TotalGB)GB ($($_.UsedPct)% used)"})-join"`n")
Power-On Hours : $powerOnHours - $($powerOnRating.Rating)
Disk Wear      : $reallocSectors - $($sectorRating.Rating)
Read Errors    : $readErrors
Write Errors   : $writeErrors

--- CPU THROTTLE ---
Base Clock   : $baseClock MHz
Under Stress : $stressClock MHz
Max Clock    : $cpuMaxMhz MHz
Maintained   : $throttlePct% - $($throttleRating.Rating)

--- RAM STABILITY ---
Result       : $ramTestResult
Blocks       : $ramBlocksCount x ${ramBlocksMB}MB
Errors       : $ramErrors

--- OS & SECURITY ---
OS           : $osName ($osArch) Build $osBuild ($osVersion)
Installed    : $installDate
Last Boot    : $lastBoot | Uptime: $uptime
Activation   : $activated
Antivirus    : $avStatus
Firewall     : $firewallStatus
BitLocker    : $bitlocker
TPM          : $tpmVersion
Secure Boot  : $secureBoot

--- NETWORK ---
Wi-Fi        : $wifiAdapter (Signal: $wifiSignal)
Ethernet     : $ethernetAdapters
Internet     : $(if($internetOk){'Connected'}else{'No'}) ($pingLatency)

--- PERIPHERALS ---
Webcam       : $webcam
Bluetooth    : $bluetooth
Audio        : $audioDevices
Keyboard     : $keyboard
Touchpad     : $touchpad
USB          : $($usbControllers.Count) controllers, $($usbDevices.Count) devices
Fan          : $fanDetected

--- PERFORMANCE ---
Processes    : $processCount
Startup      : $($startupItems.Count) - $($startupRating.Rating)
Power Plan   : $powerPlan
Events (48h) : $eventIssues - $($eventRating.Rating)

--- CHECK RESULTS ---
$(($checks|ForEach-Object{"$(if($_.Passed){'[PASS]'}else{'[FAIL]'}) $($_.Name.PadRight(22)) x$($_.Weight)  $($_.Detail)"})-join"`n")

================================================================
  RESULT: $result   SCORE: $earnedWeight/$totalWeight ($scorePct%)
  BATTERY: $($battRating.Rating)  GPU: $($gpuCondition.Rating)
  DISK: $($powerOnRating.Rating)  CPU: $($throttleRating.Rating)  RAM: $($ramTestRating.Rating)
================================================================
"@
    $textReport | Out-File $reportTxt -Encoding UTF8

    # CSV
    if (!(Test-Path $reportCsv)) {
        "Date,Model,Serial,CPU,RAM_GB,GPU,GPU_Cond,Batt_Wear,Batt_Rating,DiskHours,Disk_Rating,CPU_Throttle,RAM_Test,Score,Result" | Out-File $reportCsv -Encoding UTF8
    }
    $csvLine = '"' + (@($timestamp,$model,$serial,$cpu,$ram,$gpu,$gpuCondition.Rating,$batteryWear,$battRating.Rating,$powerOnHours,$powerOnRating.Rating,$throttlePct,$ramTestResult,$scorePct,$result) -join '","') + '"'
    $csvLine | Out-File $reportCsv -Append -Encoding UTF8

    # HTML
    $passedChecks = ($checks|Where-Object{$_.Passed}).Count
    $failedChecks = ($checks|Where-Object{-not $_.Passed}).Count
    $checkRowsHtml = ""; foreach($c in $checks){$i=if($c.Passed){"&#10004;"}else{"&#10008;"};$rc=if($c.Passed){"pass"}else{"fail"};$checkRowsHtml+="<tr class='$rc'><td>$i</td><td>$($c.Name)</td><td>x$($c.Weight)</td><td>$($c.Detail)</td></tr>`n"}
    $diskRowsHtml = ""; foreach($d in $disks){$diskRowsHtml+="<tr><td>$($d.Model)</td><td>$($d.MediaType)</td><td>$($d.SizeGB)GB</td><td>$($d.Status)</td></tr>`n"}
    $driveRowsHtml = ""; foreach($ld in $logicalDisks){$pc=if($ld.UsedPct -gt 90){"fail"}elseif($ld.UsedPct -gt 75){"warn"}else{"pass"};$driveRowsHtml+="<tr class='$pc'><td>$($ld.Drive)</td><td>$($ld.TotalGB)GB</td><td>$($ld.FreeGB)GB</td><td>$($ld.UsedPct)%</td></tr>`n"}
    $resultBgColor = switch($result){"EXCELLENT"{"#27ae60"}"GOOD"{"#2980b9"}"POOR"{"#f39c12"}default{"#e74c3c"}}
    $battGaugeHtml = if($batteryWear -ne "N/A"){[math]::Max(0,100-[double]$batteryWear)}else{100}

    $htmlContent = @"
<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>Laptop Inspection v2.5 - $timestamp</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Segoe UI',sans-serif;background:#0f0f1a;color:#e0e0e0;padding:20px}
.container{max-width:1000px;margin:0 auto}
.header{background:linear-gradient(135deg,#1a1a2e,#16213e,#0f3460);border-radius:16px;padding:30px;margin-bottom:20px;text-align:center;border:1px solid rgba(255,255,255,.1)}
.header h1{font-size:28px;color:#00d4ff;letter-spacing:2px}.header p{color:#8892b0;margin-top:8px}
.result-banner{background:$resultBgColor;border-radius:12px;padding:20px;text-align:center;margin-bottom:20px}
.result-banner h2{font-size:32px;color:white}.result-banner p{color:rgba(255,255,255,.9);font-size:18px;margin-top:5px}
.card{background:#1a1a2e;border-radius:12px;padding:20px;margin-bottom:16px;border:1px solid rgba(255,255,255,.08)}
.card h3{color:#00d4ff;font-size:15px;text-transform:uppercase;letter-spacing:1.5px;margin-bottom:14px;padding-bottom:8px;border-bottom:1px solid rgba(0,212,255,.2)}
.info-grid{display:grid;grid-template-columns:1fr 1fr;gap:6px 24px}
.info-item{display:flex;justify-content:space-between;padding:5px 0;border-bottom:1px solid rgba(255,255,255,.04)}
.info-item .label{color:#8892b0}.info-item .value{color:#e0e0e0;font-weight:500;text-align:right}
table{width:100%;border-collapse:collapse;font-size:13px}
th{background:rgba(0,212,255,.1);color:#00d4ff;padding:8px;text-align:left;font-weight:600;text-transform:uppercase;font-size:11px;letter-spacing:1px}
td{padding:7px 8px;border-bottom:1px solid rgba(255,255,255,.05)}
tr.pass td:first-child{color:#27ae60;font-weight:bold} tr.fail td:first-child{color:#e74c3c;font-weight:bold} tr.warn td{background:rgba(243,156,18,.1)}
.gauge-container{background:rgba(255,255,255,.08);border-radius:10px;height:22px;overflow:hidden;margin:8px 0}
.gauge-bar{height:100%;border-radius:10px}
.rating-badge{display:inline-block;padding:5px 16px;border-radius:18px;font-weight:bold;font-size:15px;color:white}
.stats-row{display:flex;gap:10px;margin-bottom:16px}
.stat-box{flex:1;background:rgba(0,212,255,.08);border-radius:10px;padding:14px;text-align:center;border:1px solid rgba(0,212,255,.15)}
.stat-box .num{font-size:26px;font-weight:700}.stat-box .lbl{color:#8892b0;font-size:11px;text-transform:uppercase;letter-spacing:1px;margin-top:4px}
.pass-color{color:#27ae60}.fail-color{color:#e74c3c}.score-color{color:#00d4ff}
.footer{text-align:center;color:#555;font-size:12px;margin-top:30px;padding:15px}
.score-bar-container{background:rgba(255,255,255,.1);border-radius:10px;height:18px;overflow:hidden;margin-top:10px}
.score-bar{height:100%;background:$resultBgColor;border-radius:10px}
@media(max-width:700px){.info-grid{grid-template-columns:1fr}.stats-row{flex-direction:column}}
</style></head><body><div class="container">
<div class="header"><h1>LAPTOP INSPECTION REPORT v2.5</h1><p>$manufacturer $model &mdash; $timestamp</p></div>
<div class="result-banner"><h2>$result</h2><p>Score: $earnedWeight/$totalWeight ($scorePct%)</p><div class="score-bar-container"><div class="score-bar" style="width:$scorePct%"></div></div></div>
<div class="stats-row">
<div class="stat-box"><div class="num pass-color">$passedChecks</div><div class="lbl">Passed</div></div>
<div class="stat-box"><div class="num fail-color">$failedChecks</div><div class="lbl">Failed</div></div>
<div class="stat-box"><div class="num score-color">$scorePct%</div><div class="lbl">Score</div></div>
<div class="stat-box"><div class="num" style="color:#f39c12">$($checks.Count)</div><div class="lbl">Checks</div></div>
</div>
<div class="card"><h3>Rating Summary</h3>
<div class="stats-row">
<div class="stat-box"><div class="num" style="color:$($battRating.Color)">$($battRating.Rating)</div><div class="lbl">Battery</div></div>
<div class="stat-box"><div class="num" style="color:$($gpuCondition.Color)">$($gpuCondition.Rating)</div><div class="lbl">GPU</div></div>
<div class="stat-box"><div class="num" style="color:$($powerOnRating.Color)">$($powerOnRating.Rating)</div><div class="lbl">Disk Hours</div></div>
<div class="stat-box"><div class="num" style="color:$($throttleRating.Color)">$($throttleRating.Rating)</div><div class="lbl">CPU Throttle</div></div>
<div class="stat-box"><div class="num" style="color:$($ramTestRating.Color)">$($ramTestRating.Rating)</div><div class="lbl">RAM</div></div>
</div></div>
<div class="card"><h3>Battery Health</h3>
<div style="text-align:center;margin-bottom:10px"><span class="rating-badge" style="background:$($battRating.Color)">$($battRating.Rating)</span></div>
<p style="text-align:center;color:#8892b0;margin-bottom:10px">$($battRating.Desc)</p>
<div class="gauge-container"><div class="gauge-bar" style="width:$($battGaugeHtml)%;background:$($battRating.Color)"></div></div>
<div class="info-grid">
<div class="info-item"><span class="label">Charge</span><span class="value">$batteryPercent%</span></div>
<div class="info-item"><span class="label">Wear</span><span class="value">$batteryWear%</span></div>
<div class="info-item"><span class="label">Design Cap</span><span class="value">$designCapacity mWh</span></div>
<div class="info-item"><span class="label">Full Charge</span><span class="value">$fullChargeCapacity mWh</span></div>
<div class="info-item"><span class="label">Cycles</span><span class="value">$cycleCount</span></div>
<div class="info-item"><span class="label">Chemistry</span><span class="value">$batteryChemistry</span></div>
</div></div>
<div class="card"><h3>GPU Condition</h3>
<div style="text-align:center;margin-bottom:10px"><span class="rating-badge" style="background:$($gpuCondition.Color)">$($gpuCondition.Rating)</span></div>
<p style="text-align:center;color:#8892b0;margin-bottom:10px">$($gpuCondition.Desc)</p>
<div class="info-grid">
<div class="info-item"><span class="label">GPU</span><span class="value">$gpu</span></div>
<div class="info-item"><span class="label">Type</span><span class="value">$gpuTypeLabel</span></div>
<div class="info-item"><span class="label">VRAM</span><span class="value">$gpuVram</span></div>
<div class="info-item"><span class="label">Driver</span><span class="value">$gpuDriverVersion</span></div>
<div class="info-item"><span class="label">Driver Date</span><span class="value">$gpuDriverDateRaw</span></div>
<div class="info-item"><span class="label">Crashes (30d)</span><span class="value">$gpuCrashCount</span></div>
</div></div>
<div class="card"><h3>Disk SMART Health</h3>
<div class="info-grid">
<div class="info-item"><span class="label">Power-On Hours</span><span class="value" style="color:$($powerOnRating.Color)">$powerOnHours - $($powerOnRating.Rating)</span></div>
<div class="info-item"><span class="label">Wear/Realloc</span><span class="value" style="color:$($sectorRating.Color)">$reallocSectors - $($sectorRating.Rating)</span></div>
<div class="info-item"><span class="label">Read Errors</span><span class="value">$readErrors</span></div>
<div class="info-item"><span class="label">Write Errors</span><span class="value">$writeErrors</span></div>
</div><br>
<table><tr><th>Model</th><th>Type</th><th>Size</th><th>SMART</th></tr>$diskRowsHtml</table><br>
<table><tr><th>Drive</th><th>Total</th><th>Free</th><th>Used</th></tr>$driveRowsHtml</table>
<p style="color:#8892b0;font-size:11px;margin-top:8px">Limits: &lt;1000h=Excellent, &lt;5000h=Good, &lt;10000h=Poor, &gt;10000h=Very Poor</p>
</div>
<div class="card"><h3>CPU Throttle Test</h3>
<div style="text-align:center;margin-bottom:10px"><span class="rating-badge" style="background:$($throttleRating.Color)">$($throttleRating.Rating)</span></div>
<div class="info-grid">
<div class="info-item"><span class="label">Max Clock</span><span class="value">$cpuMaxMhz MHz</span></div>
<div class="info-item"><span class="label">Under Stress</span><span class="value">$stressClock MHz</span></div>
<div class="info-item"><span class="label">Maintained</span><span class="value">$throttlePct%</span></div>
</div>
<p style="color:#8892b0;font-size:11px;margin-top:8px">Limits: &gt;95%=Excellent, &gt;85%=Good, &gt;70%=Poor, &lt;70%=Very Poor</p>
</div>
<div class="card"><h3>RAM Stability</h3>
<div style="text-align:center;margin-bottom:10px"><span class="rating-badge" style="background:$($ramTestRating.Color)">$($ramTestRating.Rating)</span></div>
<div class="info-grid">
<div class="info-item"><span class="label">Result</span><span class="value">$ramTestResult</span></div>
<div class="info-item"><span class="label">Tested</span><span class="value">$ramBlocksCount x ${ramBlocksMB}MB</span></div>
<div class="info-item"><span class="label">Errors</span><span class="value">$ramErrors</span></div>
</div></div>
<div class="card"><h3>BIOS Age &amp; System Age</h3>
<div style="text-align:center;margin-bottom:10px"><span class="rating-badge" style="background:$($biosAgeRating.Color)">$($biosAgeRating.Rating)</span></div>
<div class="info-grid">
<div class="info-item"><span class="label">BIOS Date</span><span class="value">$biosDate</span></div>
<div class="info-item"><span class="label">BIOS Version</span><span class="value">$biosVersion</span></div>
<div class="info-item"><span class="label">BIOS Age</span><span class="value">$([math]::Round($biosAgeDays/365.25,1)) years</span></div>
<div class="info-item"><span class="label">OS Install</span><span class="value">$installDate</span></div>
<div class="info-item"><span class="label">Oldest Event</span><span class="value">$oldestBoot</span></div>
</div>
<p style="color:#8892b0;font-size:11px;margin-top:8px">Limits: &lt;1yr=Excellent, &lt;2yr=Good, &lt;4yr=Poor, &gt;4yr=Very Poor</p>
</div>
<div class="card"><h3>OEM License Key</h3>
<div class="info-grid">
<div class="info-item"><span class="label">OEM Key in BIOS</span><span class="value">$(if($oemKey -ne 'Not embedded' -and $oemKey -ne 'N/A'){'Embedded'}else{$oemKey})</span></div>
<div class="info-item"><span class="label">Installed Key (last 5)</span><span class="value">$installedKeyLast5</span></div>
<div class="info-item"><span class="label">Match</span><span class="value" style="color:$(if($oemMatch -eq 'MATCH'){'#2ecc71'}elseif($oemMatch -eq 'MISMATCH'){'#e74c3c'}else{'#95a5a6'})">$oemMatch</span></div>
</div></div>
<div class="card"><h3>System Info</h3><div class="info-grid">
<div class="info-item"><span class="label">Manufacturer</span><span class="value">$manufacturer</span></div>
<div class="info-item"><span class="label">Model</span><span class="value">$model</span></div>
<div class="info-item"><span class="label">Serial</span><span class="value">$serial</span></div>
<div class="info-item"><span class="label">CPU</span><span class="value">$cpu</span></div>
<div class="info-item"><span class="label">Cores/Threads</span><span class="value">$cpuCores/$cpuThreads</span></div>
<div class="info-item"><span class="label">Clock</span><span class="value">$cpuSpeed</span></div>
<div class="info-item"><span class="label">RAM</span><span class="value">$ram GB ($ramSlots)</span></div>
<div class="info-item"><span class="label">Resolution</span><span class="value">$resolution @ ${refreshRate}Hz</span></div>
<div class="info-item"><span class="label">Panel</span><span class="value">$panelMfg $panelModel ($panelType)</span></div>
</div></div>
<div class="card"><h3>OS &amp; Security</h3><div class="info-grid">
<div class="info-item"><span class="label">OS</span><span class="value">$osName ($osArch)</span></div>
<div class="info-item"><span class="label">Build</span><span class="value">$osBuild</span></div>
<div class="info-item"><span class="label">Activation</span><span class="value">$activated</span></div>
<div class="info-item"><span class="label">Antivirus</span><span class="value">$avStatus</span></div>
<div class="info-item"><span class="label">Firewall</span><span class="value">$firewallStatus</span></div>
<div class="info-item"><span class="label">BitLocker</span><span class="value">$bitlocker</span></div>
<div class="info-item"><span class="label">TPM</span><span class="value">$tpmVersion</span></div>
<div class="info-item"><span class="label">Secure Boot</span><span class="value">$secureBoot</span></div>
</div></div>
<div class="card"><h3>Network</h3><div class="info-grid">
<div class="info-item"><span class="label">Wi-Fi</span><span class="value">$wifiAdapter</span></div>
<div class="info-item"><span class="label">Signal</span><span class="value">$wifiSignal</span></div>
<div class="info-item"><span class="label">Ethernet</span><span class="value">$ethernetAdapters</span></div>
<div class="info-item"><span class="label">Internet</span><span class="value">$(if($internetOk){'Connected'}else{'Disconnected'}) ($pingLatency)</span></div>
</div></div>
<div class="card"><h3>Peripherals</h3><div class="info-grid">
<div class="info-item"><span class="label">Webcam</span><span class="value">$webcam</span></div>
<div class="info-item"><span class="label">Bluetooth</span><span class="value">$bluetooth</span></div>
<div class="info-item"><span class="label">Audio</span><span class="value">$audioDevices</span></div>
<div class="info-item"><span class="label">Keyboard</span><span class="value">$keyboard</span></div>
<div class="info-item"><span class="label">Touchpad</span><span class="value">$touchpad</span></div>
<div class="info-item"><span class="label">USB</span><span class="value">$($usbControllers.Count) controllers, $($usbDevices.Count) devices</span></div>
<div class="info-item"><span class="label">Fan</span><span class="value">$fanDetected</span></div>
</div></div>
<div class="card"><h3>Detailed Check Results</h3>
<table><tr><th>Status</th><th>Check</th><th>Weight</th><th>Detail</th></tr>$checkRowsHtml</table>
</div>
<div class="footer">Laptop Inspector v2.5 - Portable Edition &mdash; $timestamp</div>
</div></body></html>
"@
    $htmlContent | Out-File $reportHtml -Encoding UTF8

    # Open report
    try { Invoke-Item $reportHtml } catch {}

    Write-Gui "  Reports saved:" "Cyan"
    Write-Gui "    TXT  : $reportTxt" "White"
    Write-Gui "    CSV  : $reportCsv" "White"
    Write-Gui "    HTML : $reportHtml" "White"
    if (Test-Path $battReportDest) { Write-Gui "    BATT : $battReportDest" "White" }
    Write-Gui ""

    Update-ProgressBar 100 "Inspection Complete!"
    $btnStart.Content = "SCAN COMPLETE"
    $btnStart.Visibility = "Collapsed"
    $btnReport.Visibility = "Visible"
    $btnPixelTest.Visibility = "Visible"
    if (Test-Path $battReportDest) { $btnBattReport.Visibility = "Visible" }
})

$Window.ShowDialog() | Out-Null
