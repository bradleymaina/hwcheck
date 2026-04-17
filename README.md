# hwcheck

# 🔍 Laptop Inspector — Portable Edition

> **All-in-one laptop diagnostic tool** — Run from a flash drive on Windows, or directly on Linux. No installation required.

[![Windows](https://img.shields.io/badge/Platform-Windows%2010%2F11-0078D6?logo=windows)](https://www.microsoft.com/windows)
[![Linux](https://img.shields.io/badge/Platform-Linux-FCC624?logo=linux&logoColor=black)](https://www.kernel.org/)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)](https://docs.microsoft.com/powershell/)
[![Bash](https://img.shields.io/badge/Bash-5.0%2B-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Portable](https://img.shields.io/badge/Portable-USB%20Ready-orange)](#usage)

---

## ✨ What It Does

Laptop Inspector is a **portable, single-file** diagnostic tool that performs a comprehensive hardware and software audit of any laptop — available for both **Windows** and **Linux**. Double-click or run the script on any supported machine and get a full inspection report in under two minutes.

Perfect for:
- 🛒 **Buying a used/refurbished laptop** — verify specs before you pay
- 🔧 **IT technicians** — quickly audit machines in the field
- 📊 **Fleet management** — track laptop health over time with CSV history
- 🏫 **Schools & offices** — inspect donated or returned equipment

---

## 🚀 Features

Both editions perform the same core checks. Platform-specific differences are noted where relevant.

### 🖥️ System Information
- CPU model, cores, threads, and clock speed
- RAM capacity and slot details
- GPU model, VRAM, and driver version
- Display resolution and refresh rate
- Manufacturer, model, and serial number

### 🔋 Battery Health (Deep Analysis)
- Current charge level
- Battery chemistry (Li-ion, LiPo, etc.)
- Design vs. full charge capacity
- **Wear level** percentage
- Cycle count

### 💾 Storage Diagnostics
- Physical disk detection (SSD/HDD/NVMe)
- S.M.A.R.T. status monitoring
- Power-on hours and reallocated sectors
- Per-drive capacity and free space

### 🛡️ Security & OS
- Windows: activation status, BitLocker, Defender, TPM, Secure Boot
- Linux: firewall (ufw/iptables), AppArmor/SELinux, LUKS encryption, TPM, Secure Boot
- OS build/version and install date

### 🌐 Network
- Wi-Fi adapter and signal strength
- Ethernet adapter detection
- Internet connectivity test with latency

### 🎛️ Peripherals
- Webcam, Bluetooth, audio device detection
- USB device enumeration
- Fan detection and RPM (Linux)

### 📈 Performance Tests
- **CPU throttle test** — 8-second stress burst to detect thermal throttling
- **RAM stability test** — pattern fill and verify across multiple blocks
- Running process count, top RAM consumers, startup item audit
- Critical system event log scan (last 48 hours)

### 📝 Auto-generated Reports
| Format | Description |
|--------|-------------|
| **TXT** | Full plain-text report for archival |
| **CSV** | Append-only history for tracking multiple inspections (Windows) |
| **HTML** | Dark-themed styled report that opens in any browser |

---

## 🎯 Weighted Scoring System

Each check is weighted by importance and produces a colour-coded rating:

| Rating | Threshold |
|--------|-----------|
| 🟢 **EXCELLENT** | Score ≥ 85% |
| 🔵 **GOOD** | Score 70–84% |
| 🟡 **POOR** | Score 50–69% |
| 🔴 **VERY POOR** | Score < 50% |

Higher-weighted checks (disk SMART, battery wear, CPU throttle) affect the score more than lower-weighted ones (peripherals, audio).

---

## 📦 Usage

### Windows (`LaptopInspector.bat`)

**Option 1: Run from USB Flash Drive**
1. Copy `LaptopInspector.bat` to any USB flash drive
2. Plug the USB into the target laptop
3. Double-click `LaptopInspector.bat`
4. Click **START SCAN** in the GUI
5. Reports are saved to a `Reports/` folder next to the script

**Option 2: Run Directly**
1. Download `LaptopInspector.bat`
2. Right-click → **Run as Administrator** (recommended for full access)
3. Click **START SCAN**

> Some checks (temperature, BitLocker, TPM) require Administrator privileges for full results.

---

### Linux (`laptop-inspector.sh`)

**Quick start:**
```bash
sudo bash laptop-inspector.sh
```

Running as root is recommended for full SMART data, `dmidecode` (BIOS/serial info), and hardware sensor readings. The script will warn you and proceed with reduced output if run without `sudo`.

**Optional dependencies** (install for best results):
```bash
# Debian/Ubuntu
sudo apt install smartmontools lm-sensors dmidecode

# Fedora/RHEL
sudo dnf install smartmontools lm_sensors dmidecode

# After installing lm-sensors, run once:
sudo sensors-detect
```

Reports are saved to a `Reports/` folder next to the script. The HTML report opens automatically in your default browser at the end of the scan.

---

## 🖼️ Interface

**Windows** — Modern dark-themed WPF GUI:
- Left panel: system dashboard with key specs at a glance
- Right panel: real-time scrolling log with colour-coded output
- Progress bar tracking scan completion
- Score display with colour coding
- One-click HTML report button

**Linux** — Colour-coded terminal output with a progress bar, followed by the same dark-themed HTML report.

---

## 📁 Project Structure

```
hwcheck/
├── LaptopInspector.bat      # Windows edition (WPF GUI, PowerShell)
├── laptop-inspector.sh      # Linux edition (Bash, terminal + HTML report)
├── README.md                # This file
├── LICENSE                  # MIT License
├── .gitignore               # Ignores generated reports
└── Reports/                 # Auto-created on first run
    ├── report_YYYY-MM-DD_HH-mm-ss.txt
    ├── report_YYYY-MM-DD_HH-mm-ss.html
    └── history.csv          # Windows only
```

---

## ⚙️ Customization

**Windows** — Edit the `$expected` block at the top of `LaptopInspector.bat`:

```powershell
$expected = @{
    CPU = "i7"                    # CPU must contain this string
    RAM = 8                       # Minimum RAM in GB
    GPU = "Intel"                 # GPU must contain this string
    BATTERY = 40                  # Minimum battery percentage
    STORAGE_MIN_GB = 200          # Minimum total storage in GB
    RESOLUTION_MIN_WIDTH = 1920   # Minimum horizontal resolution
}
```

**Linux** — Rating thresholds are defined as constants near the top of `laptop-inspector.sh` and can be adjusted to match your fleet's acceptance criteria.

---

## 🔒 Requirements

| | Windows | Linux |
|---|---|---|
| **OS** | Windows 10 / 11 | Any modern distro (Ubuntu, Fedora, Arch, etc.) |
| **Shell** | PowerShell 5.1+ (pre-installed) | Bash 5.0+, Python 3 |
| **Privileges** | Standard user (Admin recommended) | Standard user (sudo recommended) |
| **Dependencies** | None — fully self-contained | Optional: `smartmontools`, `lm-sensors`, `dmidecode` |
| **Disk Space** | ~53 KB | ~50 KB |

---

## 🤝 Contributing

Contributions are welcome! Here are some open ideas:

- [ ] Add keyboard backlight detection (Windows & Linux)
- [ ] Add Thunderbolt/USB-C port detection
- [ ] Export reports as PDF
- [ ] Multi-language support
- [ ] macOS edition
- [ ] Add NVMe-specific SMART attributes (Linux)
- [ ] Improve fan speed reading on more Linux laptop models

### How to Contribute
1. Fork this repository
2. Create a feature branch (`git checkout -b feature/add-nvme-smart`)
3. Commit your changes (`git commit -m 'Add NVMe SMART attribute parsing'`)
4. Push to the branch (`git push origin feature/add-nvme-smart`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

---

## ⭐ Star This Repo

If this tool helped you, please give it a ⭐ — it helps others find it!

---

<p align="center">
  <b>Laptop Inspector</b> — Built with ❤️ for the IT community
</p>
