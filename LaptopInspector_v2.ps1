[CmdletBinding()]
param(
    [string]$OutputDir = "./Reports",
    [switch]$OpenReport,
    [switch]$Json,
    [switch]$Csv,
    [switch]$Strict
)

$ErrorActionPreference = 'SilentlyContinue'

function Safe-Invoke {
    param(
        [scriptblock]$ScriptBlock,
        $Fallback = 'N/A'
    )
    try {
        $result = & $ScriptBlock
        if ($null -eq $result) { return $Fallback }
        if ($result -is [string] -and [string]::IsNullOrWhiteSpace($result)) { return $Fallback }
        return $result
    } catch {
        return $Fallback
    }
}

function Test-Command {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-OsFamily {
    if ($IsWindows) { return 'Windows' }
    if ($IsLinux) { return 'Linux' }
    if ($IsMacOS) { return 'macOS' }
    return 'Unknown'
}

function Convert-SizeToGB {
    param($Value)
    if ($null -eq $Value -or $Value -eq 'N/A') { return 'N/A' }
    try {
        if ($Value -is [string]) {
            if ($Value -match '^\s*(?<num>[\d.]+)\s*(?<unit>[KMGTP]?B?)?\s*$') {
                $n = [double]$matches.num
                $u = ($matches.unit).ToUpper()
                switch ($u) {
                    'TB' { return [math]::Round($n * 1024, 1) }
                    'T'  { return [math]::Round($n * 1024, 1) }
                    'GB' { return [math]::Round($n, 1) }
                    'G'  { return [math]::Round($n, 1) }
                    'MB' { return [math]::Round($n / 1024, 1) }
                    'M'  { return [math]::Round($n / 1024, 1) }
                    default { return [math]::Round($n, 1) }
                }
            }
            return $Value
        }
        return [math]::Round(([double]$Value / 1GB), 1)
    } catch {
        return $Value
    }
}

function Normalize-BatteryCapacity {
    param($Value)
    if ($null -eq $Value -or $Value -eq 'N/A') { return 'N/A' }
    try {
        $n = [double]$Value
        if ($n -gt 1000000) { return [math]::Round($n / 1000, 0) }
        return [math]::Round($n, 0)
    } catch {
        return $Value
    }
}

function Get-Rating {
    param(
        [double]$Value,
        [double]$Excellent,
        [double]$Good,
        [double]$Poor,
        [bool]$LowerIsBetter = $true
    )
    if ($LowerIsBetter) {
        if ($Value -le $Excellent) { return 'EXCELLENT' }
        elseif ($Value -le $Good) { return 'GOOD' }
        elseif ($Value -le $Poor) { return 'POOR' }
        else { return 'VERY POOR' }
    } else {
        if ($Value -ge $Excellent) { return 'EXCELLENT' }
        elseif ($Value -ge $Good) { return 'GOOD' }
        elseif ($Value -ge $Poor) { return 'POOR' }
        else { return 'VERY POOR' }
    }
}

function Get-ScoreLabel {
    param([double]$Score)
    if ($Score -ge 85) { 'EXCELLENT' }
    elseif ($Score -ge 70) { 'GOOD' }
    elseif ($Score -ge 50) { 'FAIR' }
    else { 'POOR' }
}

function Get-SeverityColor {
    param([string]$Status)
    switch ($Status) {
        'PASS' { 'Green' }
        'INFO' { 'Cyan' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
        default { 'Gray' }
    }
}

$script:Checks = New-Object 'System.Collections.Generic.List[object]'

function Add-Check {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Detail,
        [int]$Weight = 1
    )
    $script:Checks.Add([pscustomobject]@{
        Name   = $Name
        Status = $Status
        Passed = ($Status -eq 'PASS' -or $Status -eq 'INFO')
        Detail = $Detail
        Weight = $Weight
    }) | Out-Null
}

function Get-OverallScore {
    param([System.Collections.Generic.List[object]]$Checks)
    $totalWeight = ($Checks | Measure-Object -Property Weight -Sum).Sum
    if (-not $totalWeight) { return 0 }

    $earned = 0.0
    foreach ($check in $Checks) {
        switch ($check.Status) {
            'PASS' { $earned += $check.Weight }
            'INFO' { $earned += ($check.Weight * 0.9) }
            'WARN' { $earned += ($check.Weight * 0.45) }
            'FAIL' { $earned += 0 }
            default { $earned += ($check.Weight * 0.3) }
        }
    }
    return [math]::Round(($earned / $totalWeight) * 100, 1)
}

function Get-SystemInfo {
    $osFamily = Get-OsFamily
    $info = [ordered]@{
        OSFamily      = $osFamily
        Manufacturer  = 'N/A'
        Model         = 'N/A'
        Serial        = 'N/A'
        CPU           = 'N/A'
        CpuCores      = 'N/A'
        CpuThreads    = 'N/A'
        RamGB         = 'N/A'
        GPU           = 'N/A'
        Storage       = 'N/A'
        Display       = 'N/A'
        OS            = 'N/A'
        BiosDate      = 'N/A'
        BiosVersion   = 'N/A'
        InstallDate   = 'N/A'
        BootEstimate  = 'N/A'
        SecureBoot    = 'N/A'
        TPM           = 'N/A'
    }

    if ($osFamily -eq 'Windows') {
        $cs   = Safe-Invoke { Get-CimInstance Win32_ComputerSystem }
        $bios = Safe-Invoke { Get-CimInstance Win32_BIOS }
        $cpu  = Safe-Invoke { Get-CimInstance Win32_Processor | Select-Object -First 1 }
        $gpu  = Safe-Invoke { (Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name) -join '; ' }
        $os   = Safe-Invoke { Get-CimInstance Win32_OperatingSystem }
        $disk = Safe-Invoke { Get-CimInstance Win32_DiskDrive | ForEach-Object { "{0} ({1:N1} GB)" -f $_.Model, ($_.Size / 1GB) } }

        $info.Manufacturer = if ($cs -ne 'N/A') { $cs.Manufacturer } else { 'N/A' }
        $info.Model        = if ($cs -ne 'N/A') { $cs.Model } else { 'N/A' }
        $info.Serial       = if ($bios -ne 'N/A') { $bios.SerialNumber } else { 'N/A' }
        $info.CPU          = if ($cpu -ne 'N/A') { $cpu.Name } else { 'N/A' }
        $info.CpuCores     = if ($cpu -ne 'N/A') { $cpu.NumberOfCores } else { 'N/A' }
        $info.CpuThreads   = if ($cpu -ne 'N/A') { $cpu.NumberOfLogicalProcessors } else { 'N/A' }
        $info.RamGB        = if ($cs -ne 'N/A') { [math]::Round($cs.TotalPhysicalMemory / 1GB, 2) } else { 'N/A' }
        $info.GPU          = $gpu
        $info.Storage      = if ($disk -ne 'N/A') { $disk -join '; ' } else { 'N/A' }
        $info.OS           = if ($os -ne 'N/A') { "$($os.Caption) build $($os.BuildNumber)" } else { 'N/A' }
        $info.InstallDate  = if ($os -ne 'N/A' -and $os.InstallDate) { $os.InstallDate.ToString('yyyy-MM-dd') } else { 'N/A' }
        $info.BiosDate     = if ($bios -ne 'N/A' -and $bios.ReleaseDate) { $bios.ReleaseDate.ToString('yyyy-MM-dd') } else { 'N/A' }
        $info.BiosVersion  = if ($bios -ne 'N/A') { $bios.SMBIOSBIOSVersion } else { 'N/A' }
        $info.BootEstimate = Safe-Invoke { (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('yyyy-MM-dd HH:mm:ss') }
        $info.Display      = Safe-Invoke {
            $video = Get-CimInstance Win32_VideoController | Select-Object -First 1
            if ($video.CurrentHorizontalResolution -and $video.CurrentVerticalResolution) {
                "{0} x {1} @ {2}Hz" -f $video.CurrentHorizontalResolution, $video.CurrentVerticalResolution, $video.CurrentRefreshRate
            } else { 'N/A' }
        }
        $info.SecureBoot   = Safe-Invoke { if (Confirm-SecureBootUEFI) { 'Enabled' } else { 'Disabled' } } 'N/A'
        $info.TPM          = Safe-Invoke {
            $tpm = Get-Tpm
            if ($tpm -and $tpm.TpmPresent) {
                if ($tpm.TpmReady) { 'Present and ready' } else { 'Present, not ready' }
            } else { 'Not present' }
        } 'N/A'
    }
    elseif ($osFamily -eq 'Linux') {
        $memInfo = Safe-Invoke { Get-Content /proc/meminfo }
        $osRelease = Safe-Invoke { Get-Content /etc/os-release }

        $info.Manufacturer = Safe-Invoke { (Get-Content /sys/devices/virtual/dmi/id/sys_vendor -Raw).Trim() }
        $info.Model        = Safe-Invoke { (Get-Content /sys/devices/virtual/dmi/id/product_name -Raw).Trim() }
        $info.Serial       = Safe-Invoke { (Get-Content /sys/devices/virtual/dmi/id/product_serial -Raw).Trim() }
        $info.CPU          = Safe-Invoke { ((Select-String -Path /proc/cpuinfo -Pattern '^model name\s*:\s*(.+)$' | Select-Object -First 1).Matches[0].Groups[1].Value).Trim() }
        $info.CpuThreads   = Safe-Invoke { (nproc --all).ToString() }
        $info.CpuCores     = Safe-Invoke {
            $physical = @(Get-Content /proc/cpuinfo | Select-String '^cpu cores\s*:\s*(\d+)' | ForEach-Object { [int]$_.Matches[0].Groups[1].Value })
            if ($physical.Count -gt 0) { ($physical | Measure-Object -Maximum).Maximum } else { $info.CpuThreads }
        }
        $info.RamGB        = Safe-Invoke {
            $line = ($memInfo | Select-String '^MemTotal:\s+(\d+)').Matches[0].Groups[1].Value
            [math]::Round(([double]$line * 1KB) / 1GB, 2)
        }
        $info.GPU          = Safe-Invoke {
            if (Test-Command 'lspci') {
                $g = lspci | Select-String -Pattern 'VGA|3D|Display'
                if ($g) { ($g | ForEach-Object { ($_ -replace '^[0-9a-fA-F:.]+\s+', '').Trim() }) -join '; ' } else { 'N/A' }
            } else { 'N/A' }
        }
        $info.Storage      = Safe-Invoke {
            if (Test-Command 'lsblk') {
                $rows = lsblk -d -o MODEL,SIZE,TRAN,TYPE -n | Where-Object { $_ -match '\bdisk$' }
                if ($rows) { ($rows | ForEach-Object { $_.Trim() }) -join '; ' } else { 'N/A' }
            } else { 'N/A' }
        }
        $info.OS = Safe-Invoke {
            $pretty = ($osRelease | Select-String '^PRETTY_NAME=(.+)$').Matches[0].Groups[1].Value.Trim('"')
            if ($pretty) { $pretty } else { 'Linux' }
        }
        $info.BootEstimate = Safe-Invoke {
            $uptimeSeconds = [double](Get-Content /proc/uptime).Split(' ')[0]
            (Get-Date).AddSeconds(-$uptimeSeconds).ToString('yyyy-MM-dd HH:mm:ss')
        }
        $info.BiosDate    = Safe-Invoke { (Get-Content /sys/devices/virtual/dmi/id/bios_date -Raw).Trim() }
        $info.BiosVersion = Safe-Invoke { (Get-Content /sys/devices/virtual/dmi/id/bios_version -Raw).Trim() }
        $info.Display     = Safe-Invoke {
            if (Test-Command 'xrandr') {
                $active = xrandr --current 2>$null | Select-String ' connected' | Select-Object -First 1
                if ($active) { $active.Line.Trim() } else { 'N/A' }
            } elseif (Test-Path '/sys/class/drm') {
                $modes = Get-ChildItem /sys/class/drm -Recurse -Filter modes -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($modes) { (Get-Content $modes.FullName -Raw).Trim() } else { 'N/A' }
            } else { 'N/A' }
        }
        $info.SecureBoot = Safe-Invoke {
            if (Test-Path '/sys/firmware/efi/efivars') {
                if (Test-Command 'mokutil') {
                    $state = mokutil --sb-state 2>$null
                    if ($state) { ($state | Select-Object -First 1).Trim() } else { 'UEFI detected' }
                } else { 'UEFI detected' }
            } else { 'Legacy/unknown' }
        }
        $info.TPM = Safe-Invoke {
            if (Test-Path '/dev/tpm0' -or Test-Path '/dev/tpmrm0') { 'Present' } else { 'Not detected' }
        }
    }
    else {
        $info.OS = Safe-Invoke { [System.Runtime.InteropServices.RuntimeInformation]::OSDescription }
    }

    [pscustomobject]$info
}

function Get-BatteryInfo {
    $osFamily = Get-OsFamily
    $battery = [ordered]@{
        Present            = $false
        ChargePercent      = 'N/A'
        State              = 'N/A'
        WearPercent        = 'N/A'
        CycleCount         = 'N/A'
        DesignCapacitymWh  = 'N/A'
        FullChargemWh      = 'N/A'
        HealthRating       = 'N/A'
        Source             = 'N/A'
        Notes              = 'Battery data unavailable.'
    }

    if ($osFamily -eq 'Windows') {
        $winBattery = Safe-Invoke { Get-CimInstance Win32_Battery | Select-Object -First 1 }
        if ($winBattery -ne 'N/A') {
            $battery.Present = $true
            $battery.ChargePercent = Safe-Invoke { $winBattery.EstimatedChargeRemaining }
            $battery.State = Safe-Invoke { $winBattery.BatteryStatus }
            $battery.Source = 'Win32_Battery + powercfg'
        }

        $tmpReport = Join-Path ([IO.Path]::GetTempPath()) ("battery_report_{0}.html" -f ([guid]::NewGuid().ToString('N')))
        try {
            powercfg /batteryreport /output $tmpReport | Out-Null
            Start-Sleep -Milliseconds 400
            if (Test-Path $tmpReport) {
                $html = Get-Content $tmpReport -Raw
                if ($html -match 'DESIGN CAPACITY[\s\S]*?(\d[\d,]+)\s*mWh') { $battery.DesignCapacitymWh = ($matches[1] -replace ',') }
                if ($html -match 'FULL CHARGE CAPACITY[\s\S]*?(\d[\d,]+)\s*mWh') { $battery.FullChargemWh = ($matches[1] -replace ',') }
                if ($html -match 'CYCLE COUNT[\s\S]*?(\d+)') { $battery.CycleCount = $matches[1] }
            }
        } finally {
            Remove-Item $tmpReport -Force -ErrorAction SilentlyContinue
        }
    }
    elseif ($osFamily -eq 'Linux') {
        $batPath = Get-ChildItem /sys/class/power_supply -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^BAT' } | Select-Object -First 1
        if ($batPath) {
            $battery.Present = $true
            $battery.Source = '/sys/class/power_supply'
            $battery.ChargePercent = Safe-Invoke { (Get-Content (Join-Path $batPath.FullName 'capacity') -Raw).Trim() }
            $battery.State = Safe-Invoke { (Get-Content (Join-Path $batPath.FullName 'status') -Raw).Trim() }
            $battery.CycleCount = Safe-Invoke { (Get-Content (Join-Path $batPath.FullName 'cycle_count') -Raw).Trim() }

            $design = Safe-Invoke {
                foreach ($name in 'energy_full_design','charge_full_design') {
                    $p = Join-Path $batPath.FullName $name
                    if (Test-Path $p) { return (Get-Content $p -Raw).Trim() }
                }
                'N/A'
            }
            $full = Safe-Invoke {
                foreach ($name in 'energy_full','charge_full') {
                    $p = Join-Path $batPath.FullName $name
                    if (Test-Path $p) { return (Get-Content $p -Raw).Trim() }
                }
                'N/A'
            }

            if (($design -eq 'N/A' -or $full -eq 'N/A') -and (Test-Command 'upower')) {
                $upDevice = Safe-Invoke { upower -e | Select-String 'battery' | Select-Object -First 1 }
                if ($upDevice -ne 'N/A' -and $upDevice) {
                    $up = Safe-Invoke { upower -i $upDevice.ToString().Trim() }
                    if ($up -ne 'N/A') {
                        $battery.Source = 'upower + /sys/class/power_supply'
                        $designUP = ($up | Select-String 'energy-full-design|charge-full-design' | Select-Object -First 1)
                        $fullUP   = ($up | Select-String 'energy-full:|charge-full:' | Select-Object -First 1)
                        $cycleUP  = ($up | Select-String 'cycle count' | Select-Object -First 1)
                        if ($design -eq 'N/A' -and $designUP) {
                            $design = (($designUP.Line -split ':',2)[1] -replace '[^0-9.]','').Trim()
                            if ($design) { $design = [math]::Round([double]$design * 1000,0) }
                        }
                        if ($full -eq 'N/A' -and $fullUP) {
                            $full = (($fullUP.Line -split ':',2)[1] -replace '[^0-9.]','').Trim()
                            if ($full) { $full = [math]::Round([double]$full * 1000,0) }
                        }
                        if ($battery.CycleCount -eq 'N/A' -and $cycleUP) {
                            $battery.CycleCount = (($cycleUP.Line -split ':',2)[1] -replace '[^0-9]','').Trim()
                        }
                    }
                }
            }

            $battery.DesignCapacitymWh = Normalize-BatteryCapacity $design
            $battery.FullChargemWh = Normalize-BatteryCapacity $full
        }
    }

    if ($battery.Present -and $battery.DesignCapacitymWh -ne 'N/A' -and $battery.FullChargemWh -ne 'N/A') {
        try {
            $dc = [double]$battery.DesignCapacitymWh
            $fc = [double]$battery.FullChargemWh
            if ($dc -gt 0) { $battery.WearPercent = [math]::Round((1 - ($fc / $dc)) * 100, 1) }
        } catch {}
    }

    if ($battery.Present) {
        $wear = 999; $cycles = 999
        try { if ($battery.WearPercent -ne 'N/A') { $wear = [double]$battery.WearPercent } } catch {}
        try { if ($battery.CycleCount -ne 'N/A' -and "$($battery.CycleCount)" -match '^\d+$') { $cycles = [int]$battery.CycleCount } } catch {}

        if ($wear -le 10 -and $cycles -lt 300) {
            $battery.HealthRating = 'EXCELLENT'
            $battery.Notes = 'Battery looks fresh with low wear.'
        } elseif ($wear -le 25 -and $cycles -lt 500) {
            $battery.HealthRating = 'GOOD'
            $battery.Notes = 'Battery wear looks normal.'
        } elseif ($wear -le 40 -and $cycles -lt 800) {
            $battery.HealthRating = 'POOR'
            $battery.Notes = 'Battery is aging and may need replacement soon.'
        } else {
            if ($battery.WearPercent -eq 'N/A') {
                $battery.HealthRating = 'UNKNOWN'
                $battery.Notes = 'Battery exists, but wear data could not be calculated.'
            } else {
                $battery.HealthRating = 'VERY POOR'
                $battery.Notes = 'Battery is heavily worn.'
            }
        }
    }

    [pscustomobject]$battery
}

function Get-DiskInfo {
    $osFamily = Get-OsFamily
    $items = New-Object System.Collections.Generic.List[object]

    if ($osFamily -eq 'Windows') {
        $physicalMap = @{}
        $physicalDisks = Safe-Invoke { Get-PhysicalDisk }
        if ($physicalDisks -ne 'N/A') {
            foreach ($pd in $physicalDisks) {
                $physicalMap[$pd.FriendlyName] = $pd
            }
        }

        $disks = Safe-Invoke { Get-CimInstance Win32_DiskDrive }
        if ($disks -ne 'N/A') {
            foreach ($disk in $disks) {
                $pd = $null
                foreach ($key in $physicalMap.Keys) {
                    if ($disk.Model -like "*$key*" -or $key -like "*$($disk.Model)*") { $pd = $physicalMap[$key]; break }
                }
                $items.Add([pscustomobject]@{
                    Device        = $disk.DeviceID
                    Model         = $disk.Model
                    Serial        = $disk.SerialNumber
                    SizeGB        = [math]::Round($disk.Size / 1GB, 1)
                    MediaType     = if ($pd) { $pd.MediaType } else { 'Unknown' }
                    Health        = if ($pd) { $pd.HealthStatus } else { ($disk.Status ?? 'Unknown') }
                    BusType       = if ($pd) { $pd.BusType } else { 'Unknown' }
                    PowerOnHours  = 'N/A'
                    Reallocated   = 'N/A'
                    SmartOverall  = 'N/A'
                }) | Out-Null
            }
        }
    }
    elseif ($osFamily -eq 'Linux' -and (Test-Command 'lsblk')) {
        $json = Safe-Invoke { lsblk -J -d -o NAME,MODEL,SERIAL,SIZE,ROTA,TRAN,TYPE }
        if ($json -ne 'N/A') {
            try {
                $parsed = $json | ConvertFrom-Json
                foreach ($d in $parsed.blockdevices) {
                    if ($d.type -ne 'disk') { continue }
                    $smartOverall = 'N/A'; $smartPower = 'N/A'; $smartRealloc = 'N/A'; $health = 'Unknown'
                    if (Test-Command 'smartctl') {
                        $smartA = Safe-Invoke { smartctl -A "/dev/$($d.name)" 2>$null }
                        $smartH = Safe-Invoke { smartctl -H "/dev/$($d.name)" 2>$null }
                        if ($smartH -ne 'N/A') {
                            $line = ($smartH | Select-String 'SMART overall-health self-assessment test result|SMART Health Status|SMART overall-health').Line | Select-Object -First 1
                            if ($line) {
                                $smartOverall = $line.Trim()
                                if ($line -match 'PASSED|OK') { $health = 'Healthy' }
                                elseif ($line -match 'FAILED|BAD') { $health = 'Failing' }
                            }
                        }
                        if ($smartA -ne 'N/A') {
                            $po = ($smartA | Select-String 'Power_On_Hours|Power on Hours').Line | Select-Object -First 1
                            $re = ($smartA | Select-String 'Reallocated_Sector_Ct|Reallocated Sector Count').Line | Select-Object -First 1
                            if ($po) { $smartPower = $po.Trim() }
                            if ($re) { $smartRealloc = $re.Trim() }
                        }
                    }

                    $items.Add([pscustomobject]@{
                        Device        = "/dev/$($d.name)"
                        Model         = if ($d.model) { $d.model.Trim() } else { 'Unknown' }
                        Serial        = if ($d.serial) { $d.serial } else { 'N/A' }
                        SizeGB        = Convert-SizeToGB $d.size
                        MediaType     = if ($d.rota -eq $false -or "$($d.rota)" -eq '0') { 'SSD/NVMe' } else { 'HDD' }
                        Health        = $health
                        BusType       = if ($d.tran) { $d.tran } else { 'Unknown' }
                        PowerOnHours  = $smartPower
                        Reallocated   = $smartRealloc
                        SmartOverall  = $smartOverall
                    }) | Out-Null
                }
            } catch {}
        }
    }

    return $items
}

function Get-GpuCondition {
    param(
        [string]$DriverDate = 'N/A',
        [int]$CrashCount = 0,
        [string]$GpuName = 'N/A'
    )

    $score = 0
    if ($DriverDate -ne 'N/A') {
        try {
            $ageDays = ((Get-Date) - [datetime]::Parse($DriverDate)).Days
            if ($ageDays -gt 730) { $score++ }
            if ($ageDays -gt 1095) { $score++ }
        } catch {}
    }
    if ($CrashCount -gt 5) { $score += 2 }
    elseif ($CrashCount -gt 0) { $score += 1 }
    if ($GpuName -match 'NVIDIA|AMD|Radeon|GeForce|RTX|GTX|Quadro' -and $CrashCount -gt 3) { $score++ }

    if ($score -le 0) { return 'GOOD' }
    elseif ($score -le 2) { return 'WARNING' }
    return 'CONCERNING'
}

function Get-GpuInfo {
    $osFamily = Get-OsFamily
    $gpu = [ordered]@{
        Name         = 'N/A'
        Driver       = 'N/A'
        DriverDate   = 'N/A'
        CrashCount   = 0
        Condition    = 'N/A'
    }

    if ($osFamily -eq 'Windows') {
        $video = Safe-Invoke { Get-CimInstance Win32_VideoController | Select-Object -First 1 }
        if ($video -ne 'N/A') {
            $gpu.Name = $video.Name
            $gpu.Driver = $video.DriverVersion
            $gpu.DriverDate = Safe-Invoke { $video.DriverDate.ToString('yyyy-MM-dd') }
        }
        $gpu.CrashCount = Safe-Invoke {
            @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = (Get-Date).AddDays(-30) } -MaxEvents 500 |
                Where-Object { $_.Message -match 'display|nvlddmkm|atikmdag|igfx|gpu|dxgkrnl|video' }).Count
        } 0
    }
    elseif ($osFamily -eq 'Linux') {
        $gpu.Name = Safe-Invoke {
            if (Test-Command 'lspci') {
                ((lspci | Select-String 'VGA|3D|Display') | ForEach-Object { ($_ -replace '^[0-9a-fA-F:.]+\s+', '').Trim() }) -join '; '
            } else { 'N/A' }
        }
        $gpu.Driver = Safe-Invoke {
            if (Test-Command 'lshw') {
                $out = lshw -C display 2>$null
                (($out | Select-String 'driver=').Line | ForEach-Object { $_.Trim() }) -join '; '
            } elseif (Test-Command 'lspci') {
                ((lspci -k | Select-String 'Kernel driver in use').Line | ForEach-Object { ($_ -split ':',2)[1].Trim() }) -join '; '
            } else { 'N/A' }
        }
        $gpu.CrashCount = Safe-Invoke {
            if (Test-Command 'journalctl') {
                @(journalctl --since '30 days ago' 2>$null | Select-String 'amdgpu|nvidia|i915|nouveau|gpu|drm|hangcheck').Count
            } else { 0 }
        } 0
    }

    $gpu.Condition = Get-GpuCondition -DriverDate $gpu.DriverDate -CrashCount ([int]$gpu.CrashCount) -GpuName $gpu.Name
    [pscustomobject]$gpu
}

function Get-LicenseInfo {
    $result = [ordered]@{
        OEMKeyStatus = 'N/A'
        InstalledKey = 'N/A'
        MatchStatus  = 'N/A'
        Activation   = 'N/A'
    }

    if ($IsWindows) {
        $oemKey = Safe-Invoke { (Get-CimInstance -Query 'SELECT OA3xOriginalProductKey FROM SoftwareLicensingService').OA3xOriginalProductKey }
        $installed = Safe-Invoke { (Get-CimInstance SoftwareLicensingProduct | Where-Object { $_.PartialProductKey -and $_.Name -like '*Windows*' } | Select-Object -First 1).PartialProductKey }
        $activation = Safe-Invoke { (Get-CimInstance SoftwareLicensingProduct | Where-Object { $_.Name -like '*Windows*' -and $_.PartialProductKey } | Select-Object -First 1).LicenseStatus }

        $result.OEMKeyStatus = if ($oemKey -and $oemKey -ne 'N/A') { 'Embedded' } else { 'Not embedded / unavailable' }
        $result.InstalledKey = $installed
        $result.Activation = switch ($activation) {
            1 { 'Licensed' }
            0 { 'Unlicensed' }
            2 { 'Out-of-Box Grace' }
            3 { 'Out-of-Tolerance Grace' }
            4 { 'Non-Genuine Grace' }
            5 { 'Notification' }
            6 { 'Extended Grace' }
            default { 'Unknown' }
        }

        if ($oemKey -and $installed -and $oemKey -ne 'N/A' -and $installed -ne 'N/A') {
            $result.MatchStatus = if ($oemKey.EndsWith($installed)) { 'MATCH' } else { 'MISMATCH' }
        }
    }

    [pscustomobject]$result
}

function New-HtmlReport {
    param(
        [string]$Path,
        $SystemInfo,
        $BatteryInfo,
        $GpuInfo,
        $DiskInfo,
        $LicenseInfo,
        [System.Collections.Generic.List[object]]$Checks,
        [double]$Score,
        [string]$ScoreLabel
    )

    $checkRows = foreach ($check in $Checks) {
        $cls = $check.Status.ToLower()
        "<tr class='$cls'><td>$($check.Name)</td><td>$($check.Status)</td><td>$($check.Detail)</td><td>$($check.Weight)</td></tr>"
    }

    $diskRows = foreach ($disk in $DiskInfo) {
        "<tr><td>$($disk.Device)</td><td>$($disk.Model)</td><td>$($disk.SizeGB)</td><td>$($disk.MediaType)</td><td>$($disk.Health)</td><td>$($disk.BusType)</td><td>$($disk.PowerOnHours)</td><td>$($disk.Reallocated)</td></tr>"
    }

    if (-not $diskRows) { $diskRows = '<tr><td colspan="8">No disk data available.</td></tr>' }

    $html = @"
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Laptop Inspector Report</title>
<style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; background: #0f172a; color: #e2e8f0; }
h1, h2 { color: #67e8f9; }
.card { background: #111827; border: 1px solid #334155; border-radius: 14px; padding: 16px; margin-bottom: 16px; }
table { width: 100%; border-collapse: collapse; }
th, td { border: 1px solid #334155; padding: 10px; text-align: left; vertical-align: top; }
th { background: #1e293b; }
.score { font-size: 34px; font-weight: 700; }
.muted { color: #94a3b8; }
.pass td { background: rgba(34,197,94,.08); }
.info td { background: rgba(34,211,238,.08); }
.warn td { background: rgba(245,158,11,.08); }
.fail td { background: rgba(239,68,68,.08); }
.grid { display:grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 16px; }
</style>
</head>
<body>
<h1>Laptop Inspector v2</h1>
<div class="card">
<div class="score">$Score% - $ScoreLabel</div>
<div class="muted">Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</div>
<div class="muted">OS Family: $($SystemInfo.OSFamily)</div>
</div>
<div class="grid">
<div class="card">
<h2>System</h2>
<table>
<tr><th>Field</th><th>Value</th></tr>
<tr><td>Manufacturer</td><td>$($SystemInfo.Manufacturer)</td></tr>
<tr><td>Model</td><td>$($SystemInfo.Model)</td></tr>
<tr><td>Serial</td><td>$($SystemInfo.Serial)</td></tr>
<tr><td>CPU</td><td>$($SystemInfo.CPU)</td></tr>
<tr><td>CPU Cores / Threads</td><td>$($SystemInfo.CpuCores) / $($SystemInfo.CpuThreads)</td></tr>
<tr><td>RAM</td><td>$($SystemInfo.RamGB) GB</td></tr>
<tr><td>GPU</td><td>$($SystemInfo.GPU)</td></tr>
<tr><td>Storage</td><td>$($SystemInfo.Storage)</td></tr>
<tr><td>Display</td><td>$($SystemInfo.Display)</td></tr>
<tr><td>OS</td><td>$($SystemInfo.OS)</td></tr>
<tr><td>BIOS</td><td>$($SystemInfo.BiosDate) / $($SystemInfo.BiosVersion)</td></tr>
<tr><td>Install Date</td><td>$($SystemInfo.InstallDate)</td></tr>
<tr><td>Last Boot</td><td>$($SystemInfo.BootEstimate)</td></tr>
<tr><td>Secure Boot</td><td>$($SystemInfo.SecureBoot)</td></tr>
<tr><td>TPM</td><td>$($SystemInfo.TPM)</td></tr>
</table>
</div>
<div class="card">
<h2>Battery</h2>
<table>
<tr><th>Field</th><th>Value</th></tr>
<tr><td>Present</td><td>$($BatteryInfo.Present)</td></tr>
<tr><td>Charge</td><td>$($BatteryInfo.ChargePercent)%</td></tr>
<tr><td>State</td><td>$($BatteryInfo.State)</td></tr>
<tr><td>Wear</td><td>$($BatteryInfo.WearPercent)%</td></tr>
<tr><td>Cycle Count</td><td>$($BatteryInfo.CycleCount)</td></tr>
<tr><td>Design Capacity</td><td>$($BatteryInfo.DesignCapacitymWh) mWh</td></tr>
<tr><td>Full Charge Capacity</td><td>$($BatteryInfo.FullChargemWh) mWh</td></tr>
<tr><td>Health</td><td>$($BatteryInfo.HealthRating)</td></tr>
<tr><td>Source</td><td>$($BatteryInfo.Source)</td></tr>
<tr><td>Notes</td><td>$($BatteryInfo.Notes)</td></tr>
</table>
</div>
<div class="card">
<h2>GPU</h2>
<table>
<tr><th>Field</th><th>Value</th></tr>
<tr><td>Name</td><td>$($GpuInfo.Name)</td></tr>
<tr><td>Driver</td><td>$($GpuInfo.Driver)</td></tr>
<tr><td>Driver Date</td><td>$($GpuInfo.DriverDate)</td></tr>
<tr><td>Crash Count (30d approx)</td><td>$($GpuInfo.CrashCount)</td></tr>
<tr><td>Condition</td><td>$($GpuInfo.Condition)</td></tr>
</table>
</div>
<div class="card">
<h2>License</h2>
<table>
<tr><th>Field</th><th>Value</th></tr>
<tr><td>OEM Key Status</td><td>$($LicenseInfo.OEMKeyStatus)</td></tr>
<tr><td>Installed Key</td><td>$($LicenseInfo.InstalledKey)</td></tr>
<tr><td>Match</td><td>$($LicenseInfo.MatchStatus)</td></tr>
<tr><td>Activation</td><td>$($LicenseInfo.Activation)</td></tr>
</table>
</div>
</div>
<div class="card">
<h2>Disks</h2>
<table>
<tr><th>Device</th><th>Model</th><th>Size (GB)</th><th>Media Type</th><th>Health</th><th>Bus</th><th>Power-On / SMART</th><th>Reallocated / SMART</th></tr>
$($diskRows -join "`n")
</table>
</div>
<div class="card">
<h2>Checks</h2>
<table>
<tr><th>Check</th><th>Status</th><th>Detail</th><th>Weight</th></tr>
$($checkRows -join "`n")
</table>
</div>
</body>
</html>
"@

    Set-Content -Path $Path -Value $html -Encoding UTF8
}

$timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$fullOutputDir = [IO.Path]::GetFullPath($OutputDir)
New-Item -Path $fullOutputDir -ItemType Directory -Force | Out-Null
$textReport = Join-Path $fullOutputDir "report_$timestamp.txt"
$htmlReport = Join-Path $fullOutputDir "report_$timestamp.html"
$jsonReport = Join-Path $fullOutputDir "report_$timestamp.json"
$csvReport  = Join-Path $fullOutputDir "checks_$timestamp.csv"

Write-Host "Laptop Inspector v2 (PowerShell Core)" -ForegroundColor Cyan
Write-Host "Running on $(Get-OsFamily)..." -ForegroundColor DarkCyan

$systemInfo  = Get-SystemInfo
$batteryInfo = Get-BatteryInfo
$gpuInfo     = Get-GpuInfo
$diskInfo    = Get-DiskInfo
$licenseInfo = Get-LicenseInfo

if ($systemInfo.BiosDate -ne 'N/A') {
    try {
        $biosYears = [math]::Round((((Get-Date) - [datetime]::Parse($systemInfo.BiosDate)).Days / 365.25), 1)
        $rating = Get-Rating -Value $biosYears -Excellent 1 -Good 3 -Poor 5 -LowerIsBetter $true
        if ($biosYears -ge ($(if ($Strict) { 5 } else { 7 }))) {
            Add-Check -Name 'BIOS Age' -Status 'WARN' -Detail "BIOS age: $biosYears years ($rating)" -Weight 1
        } else {
            Add-Check -Name 'BIOS Age' -Status 'PASS' -Detail "BIOS age: $biosYears years ($rating)" -Weight 1
        }
    } catch {
        Add-Check -Name 'BIOS Age' -Status 'INFO' -Detail 'BIOS date found but could not be parsed.' -Weight 1
    }
} else {
    Add-Check -Name 'BIOS Age' -Status 'INFO' -Detail 'No BIOS date available.' -Weight 1
}

if ($batteryInfo.Present) {
    if ($batteryInfo.WearPercent -eq 'N/A') {
        Add-Check -Name 'Battery Wear' -Status 'INFO' -Detail "Battery present, but wear could not be computed. Source: $($batteryInfo.Source)" -Weight 2
    } else {
        $wear = [double]$batteryInfo.WearPercent
        $threshold = if ($Strict) { 20 } else { 30 }
        if ($wear -lt $threshold) {
            Add-Check -Name 'Battery Wear' -Status 'PASS' -Detail "Wear: $wear% | Cycles: $($batteryInfo.CycleCount) | Rating: $($batteryInfo.HealthRating)" -Weight 3
        } elseif ($wear -lt 40) {
            Add-Check -Name 'Battery Wear' -Status 'WARN' -Detail "Wear: $wear% | Cycles: $($batteryInfo.CycleCount) | Rating: $($batteryInfo.HealthRating)" -Weight 3
        } else {
            Add-Check -Name 'Battery Wear' -Status 'FAIL' -Detail "Wear: $wear% | Cycles: $($batteryInfo.CycleCount) | Rating: $($batteryInfo.HealthRating)" -Weight 3
        }
    }
} else {
    Add-Check -Name 'Battery Presence' -Status 'INFO' -Detail 'No battery detected or data unavailable.' -Weight 1
}

switch ($gpuInfo.Condition) {
    'GOOD' { Add-Check -Name 'GPU Condition' -Status 'PASS' -Detail "Condition: $($gpuInfo.Condition) | Crashes: $($gpuInfo.CrashCount)" -Weight 2 }
    'WARNING' { Add-Check -Name 'GPU Condition' -Status 'WARN' -Detail "Condition: $($gpuInfo.Condition) | Crashes: $($gpuInfo.CrashCount)" -Weight 2 }
    default { Add-Check -Name 'GPU Condition' -Status 'FAIL' -Detail "Condition: $($gpuInfo.Condition) | Crashes: $($gpuInfo.CrashCount)" -Weight 2 }
}

if ($systemInfo.SecureBoot -ne 'N/A') {
    if ($systemInfo.SecureBoot -match 'Enabled|enabled') {
        Add-Check -Name 'Secure Boot' -Status 'PASS' -Detail "$($systemInfo.SecureBoot)" -Weight 1
    } else {
        Add-Check -Name 'Secure Boot' -Status 'INFO' -Detail "$($systemInfo.SecureBoot)" -Weight 1
    }
}

if ($systemInfo.TPM -ne 'N/A') {
    if ($systemInfo.TPM -match 'Present') {
        Add-Check -Name 'TPM Presence' -Status 'PASS' -Detail "$($systemInfo.TPM)" -Weight 1
    } else {
        Add-Check -Name 'TPM Presence' -Status 'INFO' -Detail "$($systemInfo.TPM)" -Weight 1
    }
}

if ($licenseInfo.MatchStatus -eq 'MISMATCH') {
    Add-Check -Name 'OEM Key Match' -Status 'FAIL' -Detail 'Embedded OEM key and installed Windows key do not match.' -Weight 2
} elseif ($licenseInfo.MatchStatus -eq 'MATCH') {
    Add-Check -Name 'OEM Key Match' -Status 'PASS' -Detail 'Embedded OEM key aligns with installed Windows key.' -Weight 2
} elseif ($IsWindows) {
    Add-Check -Name 'OEM Key Match' -Status 'INFO' -Detail "Status: $($licenseInfo.MatchStatus) | Activation: $($licenseInfo.Activation)" -Weight 2
}

foreach ($disk in $diskInfo) {
    $status = 'PASS'
    $detail = "Health: $($disk.Health) | SMART: $($disk.SmartOverall) | Power-On: $($disk.PowerOnHours) | Reallocated: $($disk.Reallocated)"
    if ($disk.Health -match 'Failing|Bad') {
        $status = 'FAIL'
    } elseif ($disk.Reallocated -ne 'N/A' -and $disk.Reallocated -match '[1-9]') {
        $status = 'WARN'
    } elseif ($disk.Health -eq 'Unknown') {
        $status = 'INFO'
    }
    Add-Check -Name "Disk: $($disk.Model)" -Status $status -Detail $detail -Weight 2
}

if ($systemInfo.RamGB -ne 'N/A') {
    $ram = [double]$systemInfo.RamGB
    if ($ram -ge 16) {
        Add-Check -Name 'RAM Capacity' -Status 'PASS' -Detail "$ram GB installed." -Weight 1
    } elseif ($ram -ge 8) {
        Add-Check -Name 'RAM Capacity' -Status 'WARN' -Detail "$ram GB installed. Usable, but not ideal for heavier workloads." -Weight 1
    } else {
        Add-Check -Name 'RAM Capacity' -Status 'FAIL' -Detail "$ram GB installed. Low for a modern daily-driver laptop." -Weight 1
    }
}

$score = Get-OverallScore -Checks $script:Checks
$scoreLabel = Get-ScoreLabel -Score $score

$summary = @()
$summary += 'Laptop Inspector v2 Report'
$summary += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$summary += ''
$summary += "Overall Score: $score% ($scoreLabel)"
$summary += ''
$summary += 'SYSTEM'
$summary += "OS Family     : $($systemInfo.OSFamily)"
$summary += "Manufacturer  : $($systemInfo.Manufacturer)"
$summary += "Model         : $($systemInfo.Model)"
$summary += "Serial        : $($systemInfo.Serial)"
$summary += "CPU           : $($systemInfo.CPU)"
$summary += "Cores/Threads : $($systemInfo.CpuCores)/$($systemInfo.CpuThreads)"
$summary += "RAM           : $($systemInfo.RamGB) GB"
$summary += "GPU           : $($systemInfo.GPU)"
$summary += "Storage       : $($systemInfo.Storage)"
$summary += "Display       : $($systemInfo.Display)"
$summary += "OS            : $($systemInfo.OS)"
$summary += "BIOS          : $($systemInfo.BiosDate) / $($systemInfo.BiosVersion)"
$summary += "Last Boot     : $($systemInfo.BootEstimate)"
$summary += "Secure Boot   : $($systemInfo.SecureBoot)"
$summary += "TPM           : $($systemInfo.TPM)"
$summary += ''
$summary += 'BATTERY'
$summary += "Present       : $($batteryInfo.Present)"
$summary += "Charge        : $($batteryInfo.ChargePercent)%"
$summary += "State         : $($batteryInfo.State)"
$summary += "Wear          : $($batteryInfo.WearPercent)%"
$summary += "Cycle Count   : $($batteryInfo.CycleCount)"
$summary += "Design Cap    : $($batteryInfo.DesignCapacitymWh) mWh"
$summary += "Full Charge   : $($batteryInfo.FullChargemWh) mWh"
$summary += "Health        : $($batteryInfo.HealthRating)"
$summary += "Source        : $($batteryInfo.Source)"
$summary += "Notes         : $($batteryInfo.Notes)"
$summary += ''
$summary += 'GPU'
$summary += "Name          : $($gpuInfo.Name)"
$summary += "Driver        : $($gpuInfo.Driver)"
$summary += "Driver Date   : $($gpuInfo.DriverDate)"
$summary += "Crash Count   : $($gpuInfo.CrashCount)"
$summary += "Condition     : $($gpuInfo.Condition)"
$summary += ''
$summary += 'LICENSE'
$summary += "OEM Key       : $($licenseInfo.OEMKeyStatus)"
$summary += "Installed Key : $($licenseInfo.InstalledKey)"
$summary += "Match         : $($licenseInfo.MatchStatus)"
$summary += "Activation    : $($licenseInfo.Activation)"
$summary += ''
$summary += 'CHECKS'
foreach ($check in $script:Checks) {
    $summary += "- [$($check.Status)] $($check.Name): $($check.Detail)"
}

Set-Content -Path $textReport -Value ($summary -join [Environment]::NewLine) -Encoding UTF8
New-HtmlReport -Path $htmlReport -SystemInfo $systemInfo -BatteryInfo $batteryInfo -GpuInfo $gpuInfo -DiskInfo $diskInfo -LicenseInfo $licenseInfo -Checks $script:Checks -Score $score -ScoreLabel $scoreLabel

if ($Json) {
    [pscustomobject]@{
        generatedAt = (Get-Date).ToString('o')
        score       = $score
        scoreLabel  = $scoreLabel
        system      = $systemInfo
        battery     = $batteryInfo
        gpu         = $gpuInfo
        disks       = $diskInfo
        license     = $licenseInfo
        checks      = $script:Checks
    } | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonReport -Encoding UTF8
}

if ($Csv) {
    $script:Checks | Export-Csv -Path $csvReport -NoTypeInformation -Encoding UTF8
}

Write-Host ''
Write-Host "Overall score: $score% ($scoreLabel)" -ForegroundColor Cyan
foreach ($check in $script:Checks) {
    Write-Host ("[{0}] {1} - {2}" -f $check.Status, $check.Name, $check.Detail) -ForegroundColor (Get-SeverityColor $check.Status)
}

Write-Host ''
Write-Host 'Saved reports:' -ForegroundColor DarkCyan
Write-Host "- $textReport"
Write-Host "- $htmlReport"
if ($Json) { Write-Host "- $jsonReport" }
if ($Csv)  { Write-Host "- $csvReport" }

if ($OpenReport) {
    try {
        if ($IsWindows) { Start-Process $htmlReport }
        elseif ($IsLinux) { & xdg-open $htmlReport }
        elseif ($IsMacOS) { & open $htmlReport }
    } catch {}
}
