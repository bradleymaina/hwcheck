# 2>NUL & @TITLE Laptop Inspector & @ECHO OFF & PUSHD "%~dp0" & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$_=Get-Content -LiteralPath \"%~f0\" -Raw; iex $_" & POPD & EXIT /B

# ============================================================
#  LAPTOP INSPECTOR - Portable Edition (All-In-One Script)
# ============================================================

param(
    [switch]$Quick,   # Skip stress / slow checks
    [switch]$Full     # Include everything (default)
)

# ========================
# TARGET SPECS (Edit these values as needed)
# ========================
$expected = @{
    CPU = "i7"
    RAM = 8
    GPU = "Intel"
    BATTERY = 40
    STORAGE_MIN_GB = 200
    RESOLUTION_MIN_WIDTH = 1920
}

# ========================
# INIT
# ========================
$scriptRoot = $PWD.Path
$timestamp  = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportsDir = Join-Path $scriptRoot "Reports"
if (!(Test-Path $reportsDir)) { New-Item -ItemType Directory -Path $reportsDir | Out-Null }

$reportTxt  = Join-Path $reportsDir "report_$timestamp.txt"
$reportCsv  = Join-Path $reportsDir "history.csv"
$reportHtml = Join-Path $reportsDir "report_$timestamp.html"

# ========================
# HELPERS
# ========================
function Safe-Query {
    param([scriptblock]$Block, [string]$Fallback = "N/A")
    try { $r = & $Block; if ($null -eq $r -or $r -eq "") { return $Fallback } else { return $r } }
    catch { return $Fallback }
}

$checks = @()  # Collect per-check results for report

function Add-Check {
    param([string]$Name, [bool]$Passed, [string]$Detail, [int]$Weight = 1)
    $script:checks += [PSCustomObject]@{
        Name    = $Name
        Passed  = $Passed
        Detail  = $Detail
        Weight  = $Weight
    }
}


Add-Type -AssemblyName PresentationFramework

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Laptop Inspector - GUI Edition" Height="750" Width="1050" 
        Background="#0f0f1a" FontFamily="Segoe UI" WindowStartupLocation="CenterScreen">
    <Window.Resources>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#e0e0e0" />
            <Setter Property="FontSize" Value="14" />
        </Style>
    </Window.Resources>
    
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <StackPanel Grid.Row="0" Margin="0,0,0,20">
            <TextBlock Text="LAPTOP INSPECTOR" FontSize="28" FontWeight="Bold" Foreground="#00d4ff" HorizontalAlignment="Center" />
            <TextBlock Text="Portable Diagnostic Tool" FontSize="14" Foreground="#8892b0" HorizontalAlignment="Center"/>
        </StackPanel>
        
        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="380"/>
                <ColumnDefinition Width="20"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            
            <Border Background="#1a1a2e" CornerRadius="12" BorderBrush="#22FFFFFF" BorderThickness="1" Padding="20">
                <StackPanel>
                    <TextBlock Text="SYSTEM DASHBOARD" Foreground="#00d4ff" FontWeight="Bold" Margin="0,0,0,15" FontSize="16"/>
                    
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="110"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        
                        <TextBlock Text="Model:" Grid.Row="0" Grid.Column="0" Foreground="#8892b0" Margin="0,6"/>
                        <TextBlock x:Name="lblMfg" Grid.Row="0" Grid.Column="1" Text="-" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,6"/>
                        
                        <TextBlock Text="Serial:" Grid.Row="1" Grid.Column="0" Foreground="#8892b0" Margin="0,6"/>
                        <TextBlock x:Name="lblSerial" Grid.Row="1" Grid.Column="1" Text="-" FontWeight="SemiBold" Margin="0,6"/>
                        
                        <TextBlock Text="CPU:" Grid.Row="2" Grid.Column="0" Foreground="#8892b0" Margin="0,6"/>
                        <TextBlock x:Name="lblCpu" Grid.Row="2" Grid.Column="1" Text="-" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,6"/>
                        
                        <TextBlock Text="RAM:" Grid.Row="3" Grid.Column="0" Foreground="#8892b0" Margin="0,6"/>
                        <TextBlock x:Name="lblRam" Grid.Row="3" Grid.Column="1" Text="-" FontWeight="SemiBold" Margin="0,6"/>
                        
                        <TextBlock Text="GPU:" Grid.Row="4" Grid.Column="0" Foreground="#8892b0" Margin="0,6"/>
                        <TextBlock x:Name="lblGpu" Grid.Row="4" Grid.Column="1" Text="-" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,6"/>
                        
                        <TextBlock Text="Battery:" Grid.Row="5" Grid.Column="0" Foreground="#8892b0" Margin="0,6"/>
                        <TextBlock x:Name="lblBatt" Grid.Row="5" Grid.Column="1" Text="-" FontWeight="SemiBold" Margin="0,6"/>
                        
                        <TextBlock Text="Storage:" Grid.Row="6" Grid.Column="0" Foreground="#8892b0" Margin="0,6"/>
                        <TextBlock x:Name="lblStorage" Grid.Row="6" Grid.Column="1" Text="-" FontWeight="SemiBold" Margin="0,6"/>
                        
                        <TextBlock Text="Sec &amp; TPM:" Grid.Row="7" Grid.Column="0" Foreground="#8892b0" Margin="0,6"/>
                        <TextBlock x:Name="lblSec" Grid.Row="7" Grid.Column="1" Text="-" FontWeight="SemiBold" Margin="0,6"/>
                    </Grid>
                    
                    <Border Background="#0f0f1a" CornerRadius="8" Padding="15" Margin="0,25,0,0">
                        <StackPanel HorizontalAlignment="Center">
                            <TextBlock Text="RESULT SCORE" Foreground="#8892b0" FontSize="12" HorizontalAlignment="Center"/>
                            <TextBlock x:Name="lblScore" Text="NOT RUN" FontSize="32" FontWeight="Bold" Foreground="#555" HorizontalAlignment="Center" Margin="0,5,0,0"/>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </Border>
            
            <Border Grid.Column="2" Background="#1a1a2e" CornerRadius="12" BorderBrush="#22FFFFFF" BorderThickness="1" Padding="15">
                <ScrollViewer x:Name="LogScroll" VerticalScrollBarVisibility="Auto">
                    <TextBlock x:Name="txtLog" FontFamily="Consolas" TextWrapping="Wrap" FontSize="13" Foreground="#e0e0e0" />
                </ScrollViewer>
            </Border>
        </Grid>
        
        <ProgressBar x:Name="ProgBar" Grid.Row="2" Height="6" Margin="0,20" Background="#1a1a2e" Foreground="#00d4ff" Maximum="100" Value="0" BorderThickness="0"/>
        
        <Grid Grid.Row="3">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="10"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="txtStatus" Text="Ready to inspect." VerticalAlignment="Center" Foreground="#8892b0" FontSize="14"/>
            <Button x:Name="btnReport" Grid.Column="1" Content="OPEN REPORTS" Width="140" Height="42" Background="#1a1a2e" Foreground="#00d4ff" FontWeight="Bold" BorderThickness="1" BorderBrush="#00d4ff" Cursor="Hand" Visibility="Collapsed"/>
            <Button x:Name="btnStart" Grid.Column="3" Content="START SCAN" Width="160" Height="42" Background="#00d4ff" Foreground="#0f0f1a" FontWeight="Bold" BorderThickness="0" Cursor="Hand"/>
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

$lblMfg    = $Window.FindName("lblMfg")
$lblSerial = $Window.FindName("lblSerial")
$lblCpu    = $Window.FindName("lblCpu")
$lblRam    = $Window.FindName("lblRam")
$lblGpu    = $Window.FindName("lblGpu")
$lblBatt   = $Window.FindName("lblBatt")
$lblStorage= $Window.FindName("lblStorage")
$lblSec    = $Window.FindName("lblSec")
$lblScore  = $Window.FindName("lblScore")

function DoEvents {
    $action = [System.Action] {}
    $Window.Dispatcher.Invoke($action, "Background")
}

function Write-Gui {
    param([string]$Text, [string]$Color = "#e0e0e0")
    
    switch ($Color) {
        "Cyan" { $Color = "#00d4ff" }
        "DarkCyan" { $Color = "#008ba3" }
        "Magenta" { $Color = "#d63384" }
        "Blue" { $Color = "#3498db" }
        "DarkYellow" { $Color = "#f39c12" }
        "Yellow" { $Color = "#f1c40f" }
        "Green" { $Color = "#2ecc71" }
        "Red" { $Color = "#e74c3c" }
        "Gray" { $Color = "#95a5a6" }
        "White" { $Color = "#ffffff" }
    }

    $run = New-Object System.Windows.Documents.Run
    $run.Text = $Text + "`n"
    try {
        $run.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($Color)
    } catch {
        $run.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#e0e0e0")
    }
    $txtLog.Inlines.Add($run)
    $LogScroll.ScrollToEnd()
    DoEvents
}

function Update-ProgressBar([int]$Value, [string]$Status) {
    if ($Value -ge 0 -and $Value -le 100) { $ProgBar.Value = $Value }
    $txtStatus.Text = $Status
    DoEvents
}

$btnReport.Add_Click({
    try { Invoke-Item $reportHtml } catch {}
})

$btnStart.Add_Click({
    $btnStart.IsEnabled = $false
    $btnStart.Content = "SCANNING..."
    $txtLog.Inlines.Clear()
    $script:checks = @()

    Write-Gui ""
    Write-Gui "  ╔══════════════════════════════════════════════╗" "Cyan"
    Write-Gui "  ║       LAPTOP INSPECTOR - Portable Edition    ║" "Cyan"
    Write-Gui "  ╚══════════════════════════════════════════════╝" "Cyan"
    Write-Gui ""
    
    # ============================================================
    #  SECTION 1 — SYSTEM INFO
    # ============================================================
    Update-ProgressBar 10 "[1/10] Collecting system info..."
    Write-Gui "  [1/10] Collecting system info..." "DarkCyan"
    
    $cpu       = Safe-Query { (Get-CimInstance Win32_Processor).Name }
    $cpuCores  = Safe-Query { (Get-CimInstance Win32_Processor).NumberOfCores }
    $cpuThreads= Safe-Query { (Get-CimInstance Win32_Processor).NumberOfLogicalProcessors }
    $ram       = Safe-Query { [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2) }
    $gpu       = Safe-Query { ((Get-CimInstance Win32_VideoController).Name) -join "; " }
    $serial    = Safe-Query { (Get-CimInstance Win32_BIOS).SerialNumber }
    $model     = Safe-Query { (Get-CimInstance Win32_ComputerSystem).Model }
    $manufacturer = Safe-Query { (Get-CimInstance Win32_ComputerSystem).Manufacturer }
    
    Add-Check -Name "CPU Match" -Passed ($cpu -like "*$($expected['CPU'])*") `
              -Detail "Found: $cpu | Expected contains: $($expected['CPU'])" -Weight 2
    Add-Check -Name "RAM" -Passed ($ram -ge [double]$expected["RAM"]) `
              -Detail "Found: $ram GB | Expected >= $($expected['RAM']) GB" -Weight 2
    
    # ============================================================
    #  SECTION 2 — GPU
    # ============================================================
    Update-ProgressBar 20 "[2/10] Checking GPU..."
    Write-Gui "  [2/10] Checking GPU..." "DarkCyan"
    
    $gpuDriverVersion = Safe-Query { (Get-CimInstance Win32_VideoController).DriverVersion }
    $gpuDriverDate    = Safe-Query { (Get-CimInstance Win32_VideoController).DriverDate }
    $resolution       = Safe-Query { 
        $v = Get-CimInstance Win32_VideoController | Select -First 1
        "$($v.CurrentHorizontalResolution) x $($v.CurrentVerticalResolution)"
    }
    $resWidth = Safe-Query { (Get-CimInstance Win32_VideoController | Select -First 1).CurrentHorizontalResolution } 
    $refreshRate = Safe-Query { (Get-CimInstance Win32_VideoController | Select -First 1).CurrentRefreshRate }
    
    Add-Check -Name "GPU Match" -Passed ($gpu -like "*$($expected['GPU'])*") `
              -Detail "Found: $gpu | Expected contains: $($expected['GPU'])" -Weight 1
    $minWidth = if ($expected.ContainsKey("RESOLUTION_MIN_WIDTH")) { [int]$expected["RESOLUTION_MIN_WIDTH"] } else { 1920 }
    $resCheck = try { [int]$resWidth -ge $minWidth } catch { $false }
    Add-Check -Name "Display Resolution" -Passed $resCheck `
              -Detail "Resolution: $resolution | Min width: $minWidth" -Weight 1
    
    # ============================================================
    #  SECTION 3 — BATTERY HEALTH (Deep)
    # ============================================================
    Update-ProgressBar 30 "[3/10] Analyzing battery health..."
    Write-Gui "  [3/10] Analyzing battery health..." "DarkCyan"
    
    $batteryPercent   = Safe-Query { (Get-CimInstance Win32_Battery).EstimatedChargeRemaining }
    $batteryStatus    = Safe-Query { (Get-CimInstance Win32_Battery).Status }
    $batteryChemistry = Safe-Query {
        $c = (Get-CimInstance Win32_Battery).Chemistry
        switch ($c) { 1 {"Other"} 2 {"Unknown"} 3 {"Lead Acid"} 4 {"Nickel Cadmium"} 
                      5 {"Nickel Metal Hydride"} 6 {"Lithium-ion"} 7 {"Zinc air"} 
                      8 {"Lithium Polymer"} default {"Unknown ($c)"} }
    }
    
    # Parse battery report for wear level
    $batteryReportPath = Join-Path $env:TEMP "battery_inspector.html"
    $batteryWear = "N/A"
    $designCapacity = "N/A"
    $fullChargeCapacity = "N/A"
    $cycleCount = "N/A"
    
    try {
        powercfg /batteryreport /output $batteryReportPath 2>$null | Out-Null
        if (Test-Path $batteryReportPath) {
            $html = Get-Content $batteryReportPath -Raw
            if ($html -match "DESIGN CAPACITY.*?(\d[\d,]+)\s*mWh") { $designCapacity = $matches[1] -replace "," }
            if ($html -match "FULL CHARGE CAPACITY.*?(\d[\d,]+)\s*mWh") { $fullChargeCapacity = $matches[1] -replace "," }
            if ($designCapacity -ne "N/A" -and $fullChargeCapacity -ne "N/A" -and [int]$designCapacity -gt 0) {
                $batteryWear = [math]::Round((1 - [int]$fullChargeCapacity / [int]$designCapacity) * 100, 1)
            }
            if ($html -match "CYCLE COUNT.*?(\d+)") { $cycleCount = $matches[1] }
            Remove-Item $batteryReportPath -Force -ErrorAction SilentlyContinue
        }
    } catch {}
    
    $battMinPct = if ($expected.ContainsKey("BATTERY")) { [int]$expected["BATTERY"] } else { 40 }
    Add-Check -Name "Battery Level" -Passed ($batteryPercent -ne "N/A" -and [int]$batteryPercent -ge $battMinPct) `
              -Detail "Charge: $batteryPercent% | Min: $battMinPct%" -Weight 2
    $wearOk = ($batteryWear -eq "N/A") -or ($batteryWear -lt 30)
    Add-Check -Name "Battery Wear" -Passed $wearOk `
              -Detail "Wear: $batteryWear% | Design: $designCapacity mWh | Full: $fullChargeCapacity mWh" -Weight 2
    
    # ============================================================
    #  SECTION 4 — STORAGE HEALTH
    # ============================================================
    Update-ProgressBar 40 "[4/10] Checking storage..."
    Write-Gui "  [4/10] Checking storage..." "DarkCyan"
    
    $disks = @()
    try {
        Get-CimInstance Win32_DiskDrive | ForEach-Object {
            $sizeGB = [math]::Round($_.Size / 1GB, 1)
            $status = $_.Status
            $mediaType = Safe-Query { (Get-PhysicalDisk | Where-Object DeviceId -eq $_.Index).MediaType } 
            $disks += [PSCustomObject]@{
                Model     = $_.Model
                SizeGB    = $sizeGB
                Status    = $status
                MediaType = $mediaType
                Serial    = $_.SerialNumber
            }
        }
    } catch {}
    
    $logicalDisks = @()
    try {
        Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
            $totalGB = [math]::Round($_.Size / 1GB, 1)
            $freeGB  = [math]::Round($_.FreeSpace / 1GB, 1)
            $usedPct = [math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1)
            $logicalDisks += [PSCustomObject]@{
                Drive   = $_.DeviceID
                TotalGB = $totalGB
                FreeGB  = $freeGB
                UsedPct = $usedPct
            }
        }
    } catch {}
    
    $smartOk = $true
    $disks | ForEach-Object { if ($_.Status -ne "OK" -and $_.Status -ne "N/A") { $smartOk = $false } }
    Add-Check -Name "Disk S.M.A.R.T." -Passed $smartOk -Detail "Status: $( ($disks | ForEach-Object { $_.Status }) -join ', ')" -Weight 3
    
    $minStorage = if ($expected.ContainsKey("STORAGE_MIN_GB")) { [int]$expected["STORAGE_MIN_GB"] } else { 200 }
    $totalStorage = ($disks | Measure-Object -Property SizeGB -Sum).Sum
    Add-Check -Name "Storage Capacity" -Passed ($totalStorage -ge $minStorage) `
              -Detail "Total: $totalStorage GB | Min: $minStorage GB" -Weight 1
    
    # ============================================================
    #  SECTION 5 — TEMPERATURE
    # ============================================================
    Update-ProgressBar 50 "[5/10] Reading temperatures..."
    Write-Gui "  [5/10] Reading temperatures..." "DarkCyan"
    
    $temp = "N/A"
    try {
        $thermalZone = Get-CimInstance -Namespace "root\WMI" -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop |
            Select-Object -First 1
        if ($thermalZone) {
            $temp = [math]::Round(($thermalZone.CurrentTemperature / 10) - 273.15, 1)
        }
    } catch {}
    
    $tempOk = ($temp -eq "N/A") -or ($temp -lt 85)
    Add-Check -Name "Temperature" -Passed $tempOk `
              -Detail "Current: $(if($temp -ne 'N/A'){"$temp °C"}else{'N/A'}) | Max: 85 °C" -Weight 1
    
    # ============================================================
    #  SECTION 6 — NETWORK
    # ============================================================
    Update-ProgressBar 60 "[6/10] Checking network..."
    Write-Gui "  [6/10] Checking network..." "DarkCyan"
    
    $wifiAdapter = Safe-Query { (Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.NetConnectionID -like "*Wi-Fi*" -or $_.NetConnectionID -like "*Wireless*" -or $_.Name -like "*Wireless*" -or $_.Name -like "*Wi-Fi*" } | Select -First 1).Name }
    $ethernetAdapters = Safe-Query { ((Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.NetConnectionID -like "*Ethernet*" -and $_.PhysicalAdapter -eq $true }).Name) -join "; " }
    $wifiSignal = Safe-Query {
        $profile = netsh wlan show interfaces 2>$null | Select-String "Signal"
        if ($profile) { ($profile -split ":")[1].Trim() } else { "N/A" }
    }
    
    $internetOk = $false
    $pingLatency = "N/A"
    try {
        $ping = Test-Connection -ComputerName "8.8.8.8" -Count 2 -ErrorAction Stop
        $internetOk = $true
        $pingLatency = "$([math]::Round(($ping | Measure-Object -Property Latency -Average).Average, 1)) ms"
    } catch {
        try {
            $ping = Test-Connection -ComputerName "8.8.8.8" -Count 2 -ErrorAction Stop
            $internetOk = $true
            $pingLatency = "Connected"
        } catch {}
    }
    
    Add-Check -Name "Wi-Fi Adapter" -Passed ($wifiAdapter -ne "N/A") -Detail "Adapter: $wifiAdapter" -Weight 1
    Add-Check -Name "Internet" -Passed $internetOk -Detail "Ping: $pingLatency" -Weight 1
    
    # ============================================================
    #  SECTION 7 — SECURITY & OS
    # ============================================================
    Update-ProgressBar 70 "[7/10] Checking OS & security..."
    Write-Gui "  [7/10] Checking OS & security..." "DarkCyan"
    
    $osName    = Safe-Query { (Get-CimInstance Win32_OperatingSystem).Caption }
    $osBuild   = Safe-Query { (Get-CimInstance Win32_OperatingSystem).BuildNumber }
    $osVersion = Safe-Query { (Get-CimInstance Win32_OperatingSystem).Version }
    $osArch    = Safe-Query { (Get-CimInstance Win32_OperatingSystem).OSArchitecture }
    $installDate = Safe-Query { (Get-CimInstance Win32_OperatingSystem).InstallDate.ToString("yyyy-MM-dd") }
    $lastBoot  = Safe-Query { (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString("yyyy-MM-dd HH:mm") }
    
    # Uptime
    $uptime = "N/A"
    try {
        $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        $up = (Get-Date) - $boot
        $uptime = "$($up.Days)d $($up.Hours)h $($up.Minutes)m"
    } catch {}
    
    # Windows Activation
    $activated = Safe-Query {
        $lic = Get-CimInstance SoftwareLicensingProduct | Where-Object { $_.PartialProductKey -ne $null -and $_.Name -like "*Windows*" } | Select -First 1
        if ($lic.LicenseStatus -eq 1) { "Activated" } else { "Not Activated" }
    }
    
    # BitLocker
    $bitlocker = Safe-Query {
        $bl = Get-BitLockerVolume -MountPoint "C:" -ErrorAction Stop
        $bl.ProtectionStatus.ToString()
    }
    
    # Antivirus (Windows Defender)
    $avStatus = "N/A"
    try {
        $defender = Get-MpComputerStatus -ErrorAction Stop
        $avStatus = if ($defender.RealTimeProtectionEnabled) { "Active" } else { "Disabled" }
    } catch {
        $avStatus = Safe-Query {
            $av = Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName AntiVirusProduct -ErrorAction Stop | Select -First 1
            $av.displayName
        }
    }
    
    # Firewall
    $firewallStatus = Safe-Query {
        $fw = Get-NetFirewallProfile -ErrorAction Stop | Where-Object { $_.Enabled -eq $true }
        if ($fw) { "Enabled ($( ($fw.Name) -join ', '))" } else { "Disabled" }
    }
    
    # TPM
    $tpmVersion = Safe-Query {
        $tpm = Get-WmiObject -Namespace "root\cimv2\security\microsofttpm" -Class Win32_Tpm -ErrorAction Stop
        $tpm.SpecVersion.Split(",")[0]
    }
    
    Add-Check -Name "Windows Activation" -Passed ($activated -eq "Activated") -Detail "$activated" -Weight 2
    Add-Check -Name "Antivirus" -Passed ($avStatus -ne "N/A" -and $avStatus -ne "Disabled") -Detail "$avStatus" -Weight 1
    Add-Check -Name "Firewall" -Passed ($firewallStatus -like "*Enabled*") -Detail "$firewallStatus" -Weight 1
    Add-Check -Name "TPM" -Passed ($tpmVersion -ne "N/A") -Detail "Version: $tpmVersion" -Weight 1
    
    # ============================================================
    #  SECTION 8 — PERIPHERALS
    # ============================================================
    Update-ProgressBar 80 "[8/10] Detecting peripherals..."
    Write-Gui "  [8/10] Detecting peripherals..." "DarkCyan"
    
    $webcam = Safe-Query {
        $cam = Get-CimInstance Win32_PnPEntity | Where-Object { $_.PNPClass -eq "Camera" -or $_.PNPClass -eq "Image" -or $_.Name -like "*webcam*" -or $_.Name -like "*camera*" } | Select -First 1
        $cam.Name
    }
    
    $bluetooth = Safe-Query {
        $bt = Get-CimInstance Win32_PnPEntity | Where-Object { $_.PNPClass -eq "Bluetooth" -or $_.Name -like "*Bluetooth*" } | Select -First 1
        $bt.Name
    }
    
    $audioDevices = Safe-Query {
        ((Get-CimInstance Win32_SoundDevice).Name) -join "; "
    }
    
    $usbDevices = @()
    try {
        $usbDevices = Get-CimInstance Win32_USBControllerDevice | ForEach-Object {
            [wmi]($_.Dependent) | Select-Object Name, DeviceID
        } | Where-Object { $_.Name -notlike "*Hub*" -and $_.Name -notlike "*Controller*" }
    } catch {}
    
    Add-Check -Name "Webcam" -Passed ($webcam -ne "N/A") -Detail "$webcam" -Weight 1
    Add-Check -Name "Bluetooth" -Passed ($bluetooth -ne "N/A") -Detail "$bluetooth" -Weight 1
    Add-Check -Name "Audio" -Passed ($audioDevices -ne "N/A") -Detail "$audioDevices" -Weight 1
    
    # ============================================================
    #  SECTION 9 — POWER PLAN & STARTUP BLOAT
    # ============================================================
    Update-ProgressBar 90 "[9/10] Checking power plan & startup..."
    Write-Gui "  [9/10] Checking power plan & startup..." "DarkCyan"
    
    $powerPlan = Safe-Query {
        (powercfg /getactivescheme) -replace ".*: ", "" -replace "\(", "" -replace "\)", ""
    }
    
    $startupItems = @()
    try {
        $startupItems = Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location
    } catch {}
    
    $processCount = Safe-Query { (Get-Process).Count }
    $topMemProcs = @()
    try {
        $topMemProcs = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 Name, @{N="MemMB";E={[math]::Round($_.WorkingSet64/1MB,1)}}
    } catch {}
    
    # ============================================================
    #  SECTION 10 — EVENT LOG (Errors in last 48h)
    # ============================================================
    Update-ProgressBar 100 "[10/10] Scanning event logs..."
    Write-Gui "  [10/10] Scanning event logs..." "DarkCyan"
    
    $criticalEvents = @()
    if (-not $Quick) {
        try {
            $since = (Get-Date).AddHours(-48)
            $criticalEvents = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=$since} -MaxEvents 20 -ErrorAction Stop |
                Select-Object TimeCreated, Id, Message
        } catch {}
    }
    $eventIssues = $criticalEvents.Count
    Add-Check -Name "System Errors (48h)" -Passed ($eventIssues -eq 0) `
              -Detail "$eventIssues critical/error events found" -Weight 2
    
    # ============================================================
    #  SCORING — WEIGHTED
    # ============================================================
    $totalWeight = ($checks | Measure-Object -Property Weight -Sum).Sum
    $earnedWeight = ($checks | Where-Object { $_.Passed } | Measure-Object -Property Weight -Sum).Sum
    $scorePct = [math]::Round(($earnedWeight / $totalWeight) * 100, 0)
    
    if ($scorePct -ge 80) {
        $result = "PASS"
        $resultColor = "Green"
        $resultEmoji = "PASS"
    } elseif ($scorePct -ge 60) {
        $result = "WARNING"
        $resultColor = "Yellow"
        $resultEmoji = "WARNING"
    } else {
        $result = "FAIL"
        $resultColor = "Red"
        $resultEmoji = "FAIL"
    }
    
    # ============================================================
    #  CONSOLE OUTPUT
    # ============================================================
    Write-Gui ""
    Write-Gui "  ┌──────────────────────────────────────────────┐" "Green"
    Write-Gui "  │             SYSTEM INFORMATION                │" "Green"
    Write-Gui "  └──────────────────────────────────────────────┘" "Green"
    Write-Gui "  Manufacturer : $manufacturer"
    Write-Gui "  Model        : $model"
    Write-Gui "  Serial       : $serial"
    Write-Gui "  CPU          : $cpu ($cpuCores cores / $cpuThreads threads)"
    Write-Gui "  RAM          : $ram GB"
    Write-Gui "  GPU          : $gpu"
    Write-Gui "  Resolution   : $resolution @ $refreshRate Hz"
    Write-Gui "  OS           : $osName ($osArch)"
    Write-Gui "  Build        : $osBuild ($osVersion)"
    Write-Gui "  Installed    : $installDate"
    Write-Gui "  Last Boot    : $lastBoot"
    Write-Gui "  Uptime       : $uptime"
    Write-Gui ""
    
    Write-Gui "  ┌──────────────────────────────────────────────┐" "Magenta"
    Write-Gui "  │             BATTERY & POWER                   │" "Magenta"
    Write-Gui "  └──────────────────────────────────────────────┘" "Magenta"
    Write-Gui "  Charge       : $batteryPercent %"
    Write-Gui "  Chemistry    : $batteryChemistry"
    Write-Gui "  Design Cap.  : $designCapacity mWh"
    Write-Gui "  Full Charge  : $fullChargeCapacity mWh"
    Write-Gui "  Wear Level   : $batteryWear %"
    Write-Gui "  Cycle Count  : $cycleCount"
    Write-Gui "  Status       : $batteryStatus"
    Write-Gui "  Power Plan   : $powerPlan"
    Write-Gui "  Temperature  : $(if($temp -ne 'N/A'){"$temp C"}else{'N/A'})"
    Write-Gui ""
    
    Write-Gui "  ┌──────────────────────────────────────────────┐" "Blue"
    Write-Gui "  │             STORAGE                           │" "Blue"
    Write-Gui "  └──────────────────────────────────────────────┘" "Blue"
    foreach ($d in $disks) {
        Write-Gui "  [$($d.MediaType)] $($d.Model) - $($d.SizeGB) GB - Status: $($d.Status)"
    }
    foreach ($ld in $logicalDisks) {
        Write-Gui "  Drive $($ld.Drive) - $($ld.FreeGB) GB free / $($ld.TotalGB) GB total ($($ld.UsedPct)% used)"
    }
    Write-Gui ""
    
    Write-Gui "  ┌──────────────────────────────────────────────┐" "DarkYellow"
    Write-Gui "  │             NETWORK                           │" "DarkYellow"
    Write-Gui "  └──────────────────────────────────────────────┘" "DarkYellow"
    Write-Gui "  Wi-Fi        : $wifiAdapter"
    Write-Gui "  Wi-Fi Signal : $wifiSignal"
    Write-Gui "  Ethernet     : $ethernetAdapters"
    Write-Gui "  Internet     : $(if($internetOk){'Connected'}else{'No Connection'}) ($pingLatency)"
    Write-Gui ""
    
    Write-Gui "  ┌──────────────────────────────────────────────┐" "DarkCyan"
    Write-Gui "  │             SECURITY                          │" "DarkCyan"
    Write-Gui "  └──────────────────────────────────────────────┘" "DarkCyan"
    Write-Gui "  Activation   : $activated"
    Write-Gui "  Antivirus    : $avStatus"
    Write-Gui "  Firewall     : $firewallStatus"
    Write-Gui "  BitLocker    : $bitlocker"
    Write-Gui "  TPM          : $tpmVersion"
    Write-Gui ""
    
    Write-Gui "  ┌──────────────────────────────────────────────┐" "Gray"
    Write-Gui "  │             PERIPHERALS                       │" "Gray"
    Write-Gui "  └──────────────────────────────────────────────┘" "Gray"
    Write-Gui "  Webcam       : $webcam"
    Write-Gui "  Bluetooth    : $bluetooth"
    Write-Gui "  Audio        : $audioDevices"
    Write-Gui "  USB Devices  : $($usbDevices.Count) connected"
    Write-Gui ""
    
    Write-Gui "  ┌──────────────────────────────────────────────┐" "White"
    Write-Gui "  │             PERFORMANCE                       │" "White"
    Write-Gui "  └──────────────────────────────────────────────┘" "White"
    Write-Gui "  Processes    : $processCount running"
    Write-Gui "  Startup Items: $($startupItems.Count)"
    if ($topMemProcs) {
        Write-Gui "  Top RAM Users:"
        foreach ($p in $topMemProcs) {
            Write-Gui "    - $($p.Name): $($p.MemMB) MB"
        }
    }
    if ($eventIssues -gt 0) {
        Write-Gui "  Event Errors : $eventIssues critical/error events in last 48h" "Red"
    } else {
        Write-Gui "  Event Errors : None in last 48h" "Green"
    }
    Write-Gui ""
    
    # ============================================================
    #  CHECK RESULTS TABLE
    # ============================================================
    Write-Gui "  ┌──────────────────────────────────────────────┐" "Yellow"
    Write-Gui "  │             CHECK RESULTS                     │" "Yellow"
    Write-Gui "  └──────────────────────────────────────────────┘" "Yellow"
    foreach ($c in $checks) {
        $icon = if ($c.Passed) { "[PASS]" } else { "[FAIL]" }
        $color = if ($c.Passed) { "Green" } else { "Red" }
        $weightStr = "x$($c.Weight)"
        Write-Gui "  $icon $($c.Name.PadRight(22)) $weightStr  $($c.Detail)" -ForegroundColor $color
    }
    
    Write-Gui ""
    Write-Gui "  ╔══════════════════════════════════════════════╗" -ForegroundColor $resultColor
    Write-Gui "  ║  RESULT: $($resultEmoji.PadRight(10)) SCORE: $earnedWeight / $totalWeight ($scorePct%)     ║" -ForegroundColor $resultColor
    Write-Gui "  ╚══════════════════════════════════════════════╝" -ForegroundColor $resultColor
    Write-Gui ""
    
    # ============================================================
    #  TEXT REPORT
    # ============================================================
    $textReport = @"
    ================================================================
      LAPTOP INSPECTION REPORT
      Generated: $timestamp
    ================================================================
    
    --- SYSTEM ---
    Manufacturer : $manufacturer
    Model        : $model
    Serial       : $serial
    CPU          : $cpu ($cpuCores cores / $cpuThreads threads)
    RAM          : $ram GB
    GPU          : $gpu (Driver: $gpuDriverVersion)
    Resolution   : $resolution @ $refreshRate Hz
    
    --- OS & SECURITY ---
    OS           : $osName ($osArch) Build $osBuild
    Installed    : $installDate
    Last Boot    : $lastBoot
    Uptime       : $uptime
    Activation   : $activated
    Antivirus    : $avStatus
    Firewall     : $firewallStatus
    BitLocker    : $bitlocker
    TPM          : $tpmVersion
    
    --- BATTERY ---
    Charge       : $batteryPercent %
    Chemistry    : $batteryChemistry
    Design Cap.  : $designCapacity mWh
    Full Charge  : $fullChargeCapacity mWh
    Wear Level   : $batteryWear %
    Cycle Count  : $cycleCount
    Status       : $batteryStatus
    Temperature  : $(if($temp -ne 'N/A'){"$temp C"}else{'N/A'})
    
    --- STORAGE ---
    $( ($disks | ForEach-Object { "[$($_.MediaType)] $($_.Model) - $($_.SizeGB) GB - S.M.A.R.T: $($_.Status)" }) -join "`n" )
    $( ($logicalDisks | ForEach-Object { "Drive $($_.Drive) - $($_.FreeGB) GB free / $($_.TotalGB) GB ($($_.UsedPct)% used)" }) -join "`n" )
    
    --- NETWORK ---
    Wi-Fi        : $wifiAdapter (Signal: $wifiSignal)
    Ethernet     : $ethernetAdapters
    Internet     : $(if($internetOk){'Connected'}else{'No Connection'}) ($pingLatency)
    
    --- PERIPHERALS ---
    Webcam       : $webcam
    Bluetooth    : $bluetooth
    Audio        : $audioDevices
    USB Devices  : $($usbDevices.Count) connected
    
    --- PERFORMANCE ---
    Processes    : $processCount running
    Startup Items: $($startupItems.Count)
    Power Plan   : $powerPlan
    Top RAM:
    $( ($topMemProcs | ForEach-Object { "  - $($_.Name): $($_.MemMB) MB" }) -join "`n" )
    
    Critical Events (48h): $eventIssues
    
    --- STARTUP PROGRAMS ---
    $( ($startupItems | ForEach-Object { "  - $($_.Name): $($_.Command)" }) -join "`n" )
    
    --- CHECK RESULTS ---
    $( ($checks | ForEach-Object { "$(if($_.Passed){'[PASS]'}else{'[FAIL]'}) $($_.Name.PadRight(22)) x$($_.Weight)  $($_.Detail)" }) -join "`n" )
    
    ================================================================
      FINAL RESULT: $result   SCORE: $earnedWeight / $totalWeight ($scorePct%)
    ================================================================
    "@
    
    $textReport | Out-File $reportTxt -Encoding UTF8
    
    # ============================================================
    #  CSV REPORT
    # ============================================================
    if (!(Test-Path $reportCsv)) {
        "Date,Model,Serial,CPU,RAM_GB,GPU,Battery_Pct,Battery_Wear,Disk_Status,Temp,OS,Activated,AV,Score_Pct,Result" | Out-File $reportCsv -Encoding UTF8
    }
    
    $csvLine = '"' + (@(
        $timestamp, $model, $serial, $cpu, $ram, $gpu, $batteryPercent, $batteryWear,
        (($disks | ForEach-Object { $_.Status }) -join '/'), $temp, $osName, $activated,
        $avStatus, $scorePct, $result
    ) -join '","') + '"'
    $csvLine | Out-File $reportCsv -Append -Encoding UTF8
    
    # ============================================================
    #  HTML REPORT
    # ============================================================
    $passedChecks = ($checks | Where-Object { $_.Passed }).Count
    $failedChecks = ($checks | Where-Object { -not $_.Passed }).Count
    
    $checkRowsHtml = ""
    foreach ($c in $checks) {
        $icon = if ($c.Passed) { "&#10004;" } else { "&#10008;" }
        $rowClass = if ($c.Passed) { "pass" } else { "fail" }
        $checkRowsHtml += "<tr class='$rowClass'><td>$icon</td><td>$($c.Name)</td><td>x$($c.Weight)</td><td>$($c.Detail)</td></tr>`n"
    }
    
    $diskRowsHtml = ""
    foreach ($d in $disks) {
        $diskRowsHtml += "<tr><td>$($d.Model)</td><td>$($d.MediaType)</td><td>$($d.SizeGB) GB</td><td>$($d.Status)</td></tr>`n"
    }
    
    $driveRowsHtml = ""
    foreach ($ld in $logicalDisks) {
        $pctClass = if ($ld.UsedPct -gt 90) { "fail" } elseif ($ld.UsedPct -gt 75) { "warn" } else { "pass" }
        $driveRowsHtml += "<tr class='$pctClass'><td>$($ld.Drive)</td><td>$($ld.TotalGB) GB</td><td>$($ld.FreeGB) GB</td><td>$($ld.UsedPct)%</td></tr>`n"
    }
    
    $topProcsHtml = ""
    foreach ($p in $topMemProcs) {
        $topProcsHtml += "<tr><td>$($p.Name)</td><td>$($p.MemMB) MB</td></tr>`n"
    }
    
    $startupHtml = ""
    foreach ($s in $startupItems) {
        $startupHtml += "<tr><td>$($s.Name)</td><td style='word-break:break-all;max-width:400px;'>$($s.Command)</td><td>$($s.Location)</td></tr>`n"
    }
    
    $eventHtml = ""
    foreach ($e in $criticalEvents) {
        $msgShort = if ($e.Message.Length -gt 200) { $e.Message.Substring(0,200) + "..." } else { $e.Message }
        $eventHtml += "<tr class='fail'><td>$($e.TimeCreated.ToString('yyyy-MM-dd HH:mm'))</td><td>$($e.Id)</td><td style='word-break:break-all;max-width:500px;'>$msgShort</td></tr>`n"
    }
    
    $resultBgColor = switch ($result) { "PASS" { "#27ae60" }; "WARNING" { "#f39c12" }; "FAIL" { "#e74c3c" } }
    
    $htmlContent = @"
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Laptop Inspection Report - $timestamp</title>
    <style>
      * { margin: 0; padding: 0; box-sizing: border-box; }
      body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #0f0f1a; color: #e0e0e0; padding: 20px; }
      .container { max-width: 1000px; margin: 0 auto; }
      .header { background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%); border-radius: 16px; padding: 30px; margin-bottom: 20px; text-align: center; border: 1px solid rgba(255,255,255,0.1); }
      .header h1 { font-size: 28px; color: #00d4ff; letter-spacing: 2px; }
      .header p { color: #8892b0; margin-top: 8px; font-size: 14px; }
      .result-banner { background: $resultBgColor; border-radius: 12px; padding: 20px; text-align: center; margin-bottom: 20px; }
      .result-banner h2 { font-size: 32px; color: white; }
      .result-banner p { color: rgba(255,255,255,0.9); font-size: 18px; margin-top: 5px; }
      .card { background: #1a1a2e; border-radius: 12px; padding: 20px; margin-bottom: 16px; border: 1px solid rgba(255,255,255,0.08); }
      .card h3 { color: #00d4ff; font-size: 16px; text-transform: uppercase; letter-spacing: 1.5px; margin-bottom: 16px; padding-bottom: 8px; border-bottom: 1px solid rgba(0,212,255,0.2); }
      .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px 24px; }
      .info-item { display: flex; justify-content: space-between; padding: 6px 0; border-bottom: 1px solid rgba(255,255,255,0.04); }
      .info-item .label { color: #8892b0; }
      .info-item .value { color: #e0e0e0; font-weight: 500; text-align: right; }
      table { width: 100%; border-collapse: collapse; font-size: 13px; }
      th { background: rgba(0,212,255,0.1); color: #00d4ff; padding: 10px; text-align: left; font-weight: 600; text-transform: uppercase; font-size: 11px; letter-spacing: 1px; }
      td { padding: 8px 10px; border-bottom: 1px solid rgba(255,255,255,0.05); }
      tr.pass td:first-child { color: #27ae60; font-weight: bold; }
      tr.fail td:first-child { color: #e74c3c; font-weight: bold; }
      tr.warn td { background: rgba(243,156,18,0.1); }
      .score-bar-container { background: rgba(255,255,255,0.1); border-radius: 10px; height: 20px; overflow: hidden; margin-top: 10px; }
      .score-bar { height: 100%; background: linear-gradient(90deg, $resultBgColor, $(if($result -eq 'PASS'){'#2ecc71'}elseif($result -eq 'WARNING'){'#f1c40f'}else{'#e74c3c'})); border-radius: 10px; transition: width 0.5s; }
      .stats-row { display: flex; gap: 12px; margin-bottom: 16px; }
      .stat-box { flex: 1; background: rgba(0,212,255,0.08); border-radius: 10px; padding: 16px; text-align: center; border: 1px solid rgba(0,212,255,0.15); }
      .stat-box .num { font-size: 28px; font-weight: 700; }
      .stat-box .lbl { color: #8892b0; font-size: 12px; text-transform: uppercase; letter-spacing: 1px; margin-top: 4px; }
      .pass-color { color: #27ae60; }
      .fail-color { color: #e74c3c; }
      .score-color { color: #00d4ff; }
      .footer { text-align: center; color: #555; font-size: 12px; margin-top: 30px; padding: 15px; }
      @media (max-width: 700px) { .info-grid { grid-template-columns: 1fr; } .stats-row { flex-direction: column; } }
    </style>
    </head>
    <body>
    <div class="container">
    
    <div class="header">
      <h1>LAPTOP INSPECTION REPORT</h1>
      <p>$manufacturer $model &mdash; $timestamp</p>
    </div>
    
    <div class="result-banner">
      <h2>$result</h2>
      <p>Score: $earnedWeight / $totalWeight ($scorePct%)</p>
      <div class="score-bar-container"><div class="score-bar" style="width:$scorePct%"></div></div>
    </div>
    
    <div class="stats-row">
      <div class="stat-box"><div class="num pass-color">$passedChecks</div><div class="lbl">Passed</div></div>
      <div class="stat-box"><div class="num fail-color">$failedChecks</div><div class="lbl">Failed</div></div>
      <div class="stat-box"><div class="num score-color">$scorePct%</div><div class="lbl">Score</div></div>
      <div class="stat-box"><div class="num" style="color:#f39c12;">$($checks.Count)</div><div class="lbl">Total Checks</div></div>
    </div>
    
    <div class="card">
      <h3>System Information</h3>
      <div class="info-grid">
        <div class="info-item"><span class="label">Manufacturer</span><span class="value">$manufacturer</span></div>
        <div class="info-item"><span class="label">Model</span><span class="value">$model</span></div>
        <div class="info-item"><span class="label">Serial</span><span class="value">$serial</span></div>
        <div class="info-item"><span class="label">CPU</span><span class="value">$cpu</span></div>
        <div class="info-item"><span class="label">Cores / Threads</span><span class="value">$cpuCores / $cpuThreads</span></div>
        <div class="info-item"><span class="label">RAM</span><span class="value">$ram GB</span></div>
        <div class="info-item"><span class="label">GPU</span><span class="value">$gpu</span></div>
        <div class="info-item"><span class="label">GPU Driver</span><span class="value">$gpuDriverVersion</span></div>
        <div class="info-item"><span class="label">Resolution</span><span class="value">$resolution @ $refreshRate Hz</span></div>
      </div>
    </div>
    
    <div class="card">
      <h3>Operating System &amp; Security</h3>
      <div class="info-grid">
        <div class="info-item"><span class="label">OS</span><span class="value">$osName</span></div>
        <div class="info-item"><span class="label">Architecture</span><span class="value">$osArch</span></div>
        <div class="info-item"><span class="label">Build</span><span class="value">$osBuild ($osVersion)</span></div>
        <div class="info-item"><span class="label">Installed</span><span class="value">$installDate</span></div>
        <div class="info-item"><span class="label">Last Boot</span><span class="value">$lastBoot</span></div>
        <div class="info-item"><span class="label">Uptime</span><span class="value">$uptime</span></div>
        <div class="info-item"><span class="label">Activation</span><span class="value">$activated</span></div>
        <div class="info-item"><span class="label">Antivirus</span><span class="value">$avStatus</span></div>
        <div class="info-item"><span class="label">Firewall</span><span class="value">$firewallStatus</span></div>
        <div class="info-item"><span class="label">BitLocker</span><span class="value">$bitlocker</span></div>
        <div class="info-item"><span class="label">TPM</span><span class="value">$tpmVersion</span></div>
      </div>
    </div>
    
    <div class="card">
      <h3>Battery &amp; Power</h3>
      <div class="info-grid">
        <div class="info-item"><span class="label">Charge</span><span class="value">$batteryPercent %</span></div>
        <div class="info-item"><span class="label">Chemistry</span><span class="value">$batteryChemistry</span></div>
        <div class="info-item"><span class="label">Design Capacity</span><span class="value">$designCapacity mWh</span></div>
        <div class="info-item"><span class="label">Full Charge Cap.</span><span class="value">$fullChargeCapacity mWh</span></div>
        <div class="info-item"><span class="label">Wear Level</span><span class="value">$batteryWear %</span></div>
        <div class="info-item"><span class="label">Cycle Count</span><span class="value">$cycleCount</span></div>
        <div class="info-item"><span class="label">Power Plan</span><span class="value">$powerPlan</span></div>
        <div class="info-item"><span class="label">Temperature</span><span class="value">$(if($temp -ne 'N/A'){"$temp C"}else{'N/A'})</span></div>
      </div>
    </div>
    
    <div class="card">
      <h3>Storage</h3>
      <table>
        <tr><th>Model</th><th>Type</th><th>Size</th><th>S.M.A.R.T</th></tr>
        $diskRowsHtml
      </table>
      <br>
      <table>
        <tr><th>Drive</th><th>Total</th><th>Free</th><th>Used</th></tr>
        $driveRowsHtml
      </table>
    </div>
    
    <div class="card">
      <h3>Network</h3>
      <div class="info-grid">
        <div class="info-item"><span class="label">Wi-Fi Adapter</span><span class="value">$wifiAdapter</span></div>
        <div class="info-item"><span class="label">Wi-Fi Signal</span><span class="value">$wifiSignal</span></div>
        <div class="info-item"><span class="label">Ethernet</span><span class="value">$ethernetAdapters</span></div>
        <div class="info-item"><span class="label">Internet</span><span class="value">$(if($internetOk){'Connected'}else{'Disconnected'}) ($pingLatency)</span></div>
      </div>
    </div>
    
    <div class="card">
      <h3>Peripherals</h3>
      <div class="info-grid">
        <div class="info-item"><span class="label">Webcam</span><span class="value">$webcam</span></div>
        <div class="info-item"><span class="label">Bluetooth</span><span class="value">$bluetooth</span></div>
        <div class="info-item"><span class="label">Audio</span><span class="value">$audioDevices</span></div>
        <div class="info-item"><span class="label">USB Devices</span><span class="value">$($usbDevices.Count) connected</span></div>
      </div>
    </div>
    
    <div class="card">
      <h3>Performance</h3>
      <div class="info-grid">
        <div class="info-item"><span class="label">Running Processes</span><span class="value">$processCount</span></div>
        <div class="info-item"><span class="label">Startup Items</span><span class="value">$($startupItems.Count)</span></div>
      </div>
      <br>
      <table><tr><th>Top RAM Consumers</th><th>Memory</th></tr>$topProcsHtml</table>
    </div>
    
    $(if($startupItems.Count -gt 0) { @"
    <div class="card">
      <h3>Startup Programs</h3>
      <table><tr><th>Name</th><th>Command</th><th>Location</th></tr>$startupHtml</table>
    </div>
    "@ })
    
    $(if($criticalEvents.Count -gt 0) { @"
    <div class="card">
      <h3>Critical System Events (Last 48h)</h3>
      <table><tr><th>Time</th><th>Event ID</th><th>Message</th></tr>$eventHtml</table>
    </div>
    "@ })
    
    <div class="card">
      <h3>Detailed Check Results</h3>
      <table>
        <tr><th>Status</th><th>Check</th><th>Weight</th><th>Detail</th></tr>
        $checkRowsHtml
      </table>
    </div>
    
    <div class="footer">
      Laptop Inspector - Portable Edition &mdash; Report generated $timestamp
    </div>
    
    </div>
    </body>
    </html>
    "@
    
    $htmlContent | Out-File $reportHtml -Encoding UTF8
    
    # ============================================================
    #  SPEAKER TEST (optional beep)
    # ============================================================
    Write-Gui "  Testing speaker (beep)..." "DarkCyan"
    try { [console]::Beep(800, 300); [console]::Beep(1000, 300); [console]::Beep(1200, 200) } catch {}
    
    # ============================================================
    #  FINAL OUTPUT
    # ============================================================
    Write-Gui ""
    Write-Gui "  Reports saved:" "Cyan"
    Write-Gui "    TXT  : $reportTxt" "White"
    Write-Gui "    CSV  : $reportCsv" "White"
    Write-Gui "    HTML : $reportHtml" "White"
    Write-Gui ""
    
    # Auto-open HTML report
    try { Invoke-Item $reportHtml } catch {}
    
    
    
    


    $lblMfg.Text = "$manufacturer $model"
    $lblSerial.Text = $serial
    $lblCpu.Text = $cpu
    $lblRam.Text = "$ram GB"
    $lblGpu.Text = $gpu
    $lblBatt.Text = "$batteryWear% Wear (${batteryPercent}% Charge)"
    $lblStorage.Text = "$( [math]::Round($totalStorage, 1) ) GB (SMART: $smartOk)"
    $lblSec.Text = "TPM: $tpmVersion | AV: $avStatus"
    
    $lblScore.Text = "$result ($scorePct%)"
    if ($result -eq "PASS") { $lblScore.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#2ecc71") }
    elseif ($result -eq "WARNING") { $lblScore.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#f1c40f") }
    else { $lblScore.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFromString("#e74c3c") }

    Update-ProgressBar 100 "Inspection Complete!"
    $btnStart.Content = "SCAN COMPLETE"
    $btnStart.Visibility = "Collapsed"
    $btnReport.Visibility = "Visible"
})

$Window.ShowDialog() | Out-Null
