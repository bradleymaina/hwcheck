# 🆕 Update: Cross-Platform Support — v2.0

## 📝 What Changed

The Laptop Inspector has been upgraded from a Windows-only tool to a **cross-platform diagnostic solution** that now runs on Windows, Linux, and macOS using PowerShell Core.

---

## ✨ Major Updates

### 🔄 PowerShell Core Migration
- **Before:** Windows PowerShell 5.1 (Windows only)
- **After:** PowerShell Core 7.0+ (Windows, Linux, macOS)
- All platform-specific code has been refactored for cross-platform compatibility
- Uses built-in variables: `$IsWindows`, `$IsLinux`, `$IsMacOS` for OS detection

### 🐧 Linux Support
- Full hardware diagnostics on Linux systems
- Detects CPU, RAM, GPU, storage, and network configurations
- Automatic platform-aware system calls
- Works with all major Linux distributions

### 🍎 macOS Support
- Comprehensive hardware audits on Apple Silicon and Intel Macs
- Leverages native macOS command-line tools
- Same feature set as Windows and Linux versions

### 🛠️ Technical Improvements
- Enhanced error handling for cross-platform execution
- Platform-aware command compatibility
- Graceful fallback for platform-specific checks
- Improved exception handling for missing tools

---

## 🚀 How to Run on Linux

### Step 1: Install PowerShell Core

# For linux devices install this tool for better results
```bash
`sudo apt install smartmontools upower pciutils lshw mokutil`

```
**Ubuntu/Debian:**
```bash
# Add Microsoft repository
wget https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update

# Install PowerShell
sudo apt-get install -y powershell
```

**Fedora/RHEL/CentOS:**
```bash
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo dnf install -y powershell
```

**Alpine:**
```bash
apk add --no-cache powershell
```

**Verify installation:**
```bash
pwsh --version
```

### Step 2: Download the Script

```bash
# Clone the repository
git clone https://github.com/bradleymaina/hwcheck.git
cd hwcheck

# Or download directly
wget https://raw.githubusercontent.com/bradleymaina/hwcheck/main/LaptopInspector_v2.ps1
```

### Step 3: Run the Diagnostic

**Basic scan:**
```bash
pwsh -File ./LaptopInspector_v2.ps1
```

**With elevated privileges** (for complete hardware info):
```bash
sudo pwsh -File ./LaptopInspector_v2.ps1
```

**Custom output directory:**
```bash
pwsh -File ./LaptopInspector_v2.ps1 -OutputDir ./my-reports
```

**Generate CSV for tracking:**
```bash
pwsh -File ./LaptopInspector_v2.ps1 -Csv
```

**Generate JSON for automation:**
```bash
pwsh -File ./LaptopInspector_v2.ps1 -Json
```

**All formats:**
```bash
pwsh -File ./LaptopInspector_v2.ps1 -Csv -Json
```

---

## 📊 Output Format

Reports are automatically generated in `./Reports/` directory:

```
./Reports/
├── inspection_2026-04-27.txt      # Plain text (archival)
├── inspection_2026-04-27.html     # Beautiful HTML (browser-friendly)
├── inspection_2026-04-27.json     # JSON (automation-friendly)
└── inspection_history.csv         # CSV history (for tracking)
```

---

## 🔧 Linux Troubleshooting

| Issue | Solution |
|-------|----------|
| `pwsh: command not found` | Install PowerShell Core (see Step 1 above) |
| Permission denied | Run with `sudo pwsh -File ./LaptopInspector_v2.ps1` |
| Hardware info shows "N/A" | Requires sudo access for full hardware detection |
| Script won't execute | Use `pwsh -ExecutionPolicy Bypass -File ./LaptopInspector_v2.ps1` |

---

## 🎯 Requirements by Platform

### Windows
- PowerShell 5.1+ (pre-installed) or PowerShell Core 7.0+ (recommended)
- Administrator privileges for full diagnostics

### Linux
- PowerShell Core 7.0+
- `sudo` access for hardware information
- Standard tools: `lscpu`, `free`, `lsblk`, `uname`, `ip`

### macOS
- PowerShell Core 7.0+
- Standard macOS command-line tools

---

## 📦 Key Features (Cross-Platform)

✅ CPU, RAM, GPU detection  
✅ Storage diagnostics (SSD/HDD detection)  
✅ Battery health analysis (Windows/Linux)  
✅ Network adapter detection  
✅ Security status checks  
✅ Performance metrics  
✅ Multi-format reports (TXT, HTML, CSV, JSON)  
✅ Automatic OS detection  
✅ Portable — no installation required  

---

## 🔄 Breaking Changes

- **Windows PowerShell 5.1 Support:** Still works, but PowerShell Core 7.0+ is recommended
- **Script filename:** Changed from `LaptopInspector.bat` to `LaptopInspector_v2.ps1` for clarity
- **Parameter handling:** Now uses `-File` parameter with PowerShell directly

---

## 🚀 Next Steps

1. Install PowerShell Core on your Linux system
2. Download `LaptopInspector_v2.ps1`
3. Run the script: `pwsh -File ./LaptopInspector_v2.ps1`
4. Check reports in `./Reports/` directory

---

## 📝 Files Included

- `LaptopInspector_v2.ps1` — Main cross-platform diagnostic script
- `LaptopInspector.bat` — Windows wrapper (legacy)
- `README.md` — Full project documentation
- `LICENSE` — MIT License
- `Commit_README.md` — This changelog

---

## 🔗 References

- [PowerShell Core Documentation](https://learn.microsoft.com/powershell/)
- [Install PowerShell on Linux](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux)
- [Project Repository](https://github.com/bradleymaina/hwcheck)

---

**Version:** 2.0  
**Date:** April 2026  
**Compatibility:** Windows 10+ | Ubuntu/Debian | Fedora/RHEL | Alpine | macOS 