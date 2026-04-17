#!/usr/bin/env bash
# ============================================================
#  LAPTOP INSPECTOR v2.5 - Linux Edition
#  Full refurbished-laptop authenticity checker
#  Usage: sudo bash laptop-inspector.sh
# ============================================================

set -uo pipefail

# ========================
# COLOURS
# ========================
C_RESET='\033[0m'
C_CYAN='\033[0;36m'
C_DCYAN='\033[0;34m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_RED='\033[0;31m'
C_WHITE='\033[1;37m'
C_GRAY='\033[0;37m'
C_MAGENTA='\033[0;35m'
C_BOLD='\033[1m'

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTS_DIR="$SCRIPT_DIR/Reports"
mkdir -p "$REPORTS_DIR"
REPORT_TXT="$REPORTS_DIR/report_$TIMESTAMP.txt"
REPORT_HTML="$REPORTS_DIR/report_$TIMESTAMP.html"

# ========================
# HELPERS
# ========================
safe_read() {
    # safe_read <command...>  — returns "N/A" on failure or empty output
    local out
    out=$("$@" 2>/dev/null) || true
    if [[ -z "$out" ]]; then echo "N/A"; else echo "$out"; fi
}

cmd_exists() { command -v "$1" &>/dev/null; }

# Weighted check list  (name|passed|detail|weight)
CHECKS=()

add_check() {
    local name="$1" passed="$2" detail="$3" weight="${4:-1}"
    CHECKS+=("$name|$passed|$detail|$weight")
}

# Rating helpers  (lower_is_better)
# get_rating <value> <excellent> <good> <poor> [lower_is_better=1]
get_rating() {
    local val=$1 exc=$2 good=$3 poor=$4 lib=${5:-1}
    if (( lib )); then
        if   (( $(echo "$val <= $exc" | bc -l) )); then echo "EXCELLENT"
        elif (( $(echo "$val <= $good"| bc -l) )); then echo "GOOD"
        elif (( $(echo "$val <= $poor"| bc -l) )); then echo "POOR"
        else echo "VERY POOR"; fi
    else
        if   (( $(echo "$val >= $exc" | bc -l) )); then echo "EXCELLENT"
        elif (( $(echo "$val >= $good"| bc -l) )); then echo "GOOD"
        elif (( $(echo "$val >= $poor"| bc -l) )); then echo "POOR"
        else echo "VERY POOR"; fi
    fi
}

rating_color() {
    case "$1" in
        EXCELLENT) echo "$C_GREEN"  ;;
        GOOD)      echo "$C_CYAN"   ;;
        WARNING)   echo "$C_YELLOW" ;;
        POOR)      echo "$C_YELLOW" ;;
        *)         echo "$C_RED"    ;;
    esac
}

rating_hex() {
    case "$1" in
        EXCELLENT) echo "#2ecc71" ;;
        GOOD)      echo "#3498db" ;;
        WARNING)   echo "#f39c12" ;;
        POOR)      echo "#f39c12" ;;
        *)         echo "#e74c3c" ;;
    esac
}

write_line() {
    local text="${1:-}" color="${2:-$C_WHITE}"
    echo -e "${color}${text}${C_RESET}"
    # Strip ANSI for text report
    echo "${text}" | sed 's/\x1b\[[0-9;]*m//g' >> "$REPORT_TXT"
}

step() {
    local n="$1" total="$2" msg="$3"
    local pct=$(( n * 100 / total ))
    local filled=$(( pct / 5 ))
    local bar=""
    for ((i=0;i<filled;i++)); do bar+="█"; done
    for ((i=filled;i<20;i++)); do bar+="░"; done
    printf "${C_CYAN}  [%3d%%] ${bar} ${C_DCYAN}%s${C_RESET}\n" "$pct" "$msg"
    echo "  [$pct%] $msg" >> "$REPORT_TXT"
}

# ========================
# PRIVILEGE CHECK
# ========================
if [[ $EUID -ne 0 ]]; then
    echo -e "${C_YELLOW}  WARNING: Not running as root. Some checks (SMART, DMI, sensors) may be limited.${C_RESET}"
    echo -e "${C_YELLOW}  Recommended: sudo bash $0${C_RESET}\n"
fi

# Init report file
{
echo "================================================================"
echo "  LAPTOP INSPECTION REPORT v2.5 - Linux Edition"
echo "  Generated: $TIMESTAMP"
echo "================================================================"
echo ""
} > "$REPORT_TXT"

echo ""
echo -e "${C_CYAN}  +================================================+${C_RESET}"
echo -e "${C_CYAN}  |     LAPTOP INSPECTOR v2.5 - Linux Edition      |${C_RESET}"
echo -e "${C_CYAN}  |       Refurbished Laptop Authenticity Checker   |${C_RESET}"
echo -e "${C_CYAN}  +================================================+${C_RESET}"
echo ""

TOTAL_STEPS=16

# ============================================================
#  1. SYSTEM INFO
# ============================================================
step 1 $TOTAL_STEPS "[1/16] Collecting system info..."

CPU=$(safe_read grep -m1 "model name" /proc/cpuinfo | sed 's/.*: //')
CPU_CORES=$(safe_read nproc --all)
CPU_THREADS=$(safe_read grep -c "^processor" /proc/cpuinfo)
CPU_MAX_MHZ=$(safe_read grep -m1 "cpu MHz" /proc/cpuinfo | awk '{printf "%.0f", $4}')
CPU_SPEED_GHZ=$(awk "BEGIN {printf \"%.2f\", $CPU_MAX_MHZ/1000}" 2>/dev/null || echo "N/A")

RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
RAM_GB=$(awk "BEGIN {printf \"%.1f\", $RAM_KB/1048576}")

if cmd_exists dmidecode; then
    MANUFACTURER=$(safe_read dmidecode -s system-manufacturer)
    MODEL=$(safe_read dmidecode -s system-product-name)
    SERIAL=$(safe_read dmidecode -s system-serial-number)
else
    MANUFACTURER=$(safe_read cat /sys/class/dmi/id/sys_vendor)
    MODEL=$(safe_read cat /sys/class/dmi/id/product_name)
    SERIAL=$(safe_read cat /sys/class/dmi/id/product_serial)
fi

# RAM slots
RAM_SLOTS="N/A"
if cmd_exists dmidecode; then
    RAM_SLOTS=$(dmidecode -t memory 2>/dev/null | awk '
        /Memory Device/ {in_dev=1; size=""; speed=""}
        in_dev && /^\s+Size:/ && !/No Module/ { size=$2" "$3 }
        in_dev && /^\s+Speed:/ { speed=$2" "$3 }
        in_dev && size && speed { print size" @ "speed; in_dev=0 }
    ' | paste -sd " + " || echo "N/A")
fi

# GPU
GPU="N/A"
if cmd_exists lspci; then
    GPU=$(lspci 2>/dev/null | grep -iE "VGA|3D|Display" | sed 's/.*: //' | paste -sd "; " || echo "N/A")
fi
[[ -z "$GPU" || "$GPU" == "N/A" ]] && GPU=$(safe_read cat /sys/class/drm/card*/device/uevent 2>/dev/null | grep DRIVER | head -1 | sed 's/DRIVER=//')

write_line ""
write_line "  --- SYSTEM ---" "$C_BOLD"
write_line "    $MANUFACTURER $MODEL  (SN: $SERIAL)" "$C_WHITE"
write_line "    CPU: $CPU ($CPU_CORES C / $CPU_THREADS T) ${CPU_SPEED_GHZ} GHz" "$C_WHITE"
write_line "    RAM: ${RAM_GB} GB  ($RAM_SLOTS)" "$C_WHITE"
write_line "    GPU: $GPU" "$C_WHITE"
echo "" | tee -a "$REPORT_TXT" > /dev/null

# ============================================================
#  2. BIOS AGE & SYSTEM AGE
# ============================================================
step 2 $TOTAL_STEPS "[2/16] Checking BIOS age..."

BIOS_DATE="N/A"
BIOS_VERSION="N/A"
BIOS_AGE_DAYS=-1
BIOS_AGE_YEARS="N/A"
BIOS_AGE_RATING="N/A"

if cmd_exists dmidecode; then
    BIOS_DATE=$(dmidecode -t bios 2>/dev/null | grep -i "Release Date" | sed 's/.*: //' | xargs)
    BIOS_VERSION=$(dmidecode -t bios 2>/dev/null | grep -i "Version:" | head -1 | sed 's/.*: //' | xargs)
elif [[ -f /sys/class/dmi/id/bios_date ]]; then
    BIOS_DATE=$(cat /sys/class/dmi/id/bios_date 2>/dev/null || echo "N/A")
    BIOS_VERSION=$(cat /sys/class/dmi/id/bios_version 2>/dev/null || echo "N/A")
fi

if [[ "$BIOS_DATE" != "N/A" && -n "$BIOS_DATE" ]]; then
    BIOS_EPOCH=$(date -d "$BIOS_DATE" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    if (( BIOS_EPOCH > 0 )); then
        BIOS_AGE_DAYS=$(( (NOW_EPOCH - BIOS_EPOCH) / 86400 ))
        BIOS_AGE_YEARS=$(awk "BEGIN {printf \"%.1f\", $BIOS_AGE_DAYS/365.25}")
        BIOS_AGE_RATING=$(get_rating "$BIOS_AGE_YEARS" 1 2 4 1)
    fi
fi

# OS install date
OS_INSTALL="N/A"
if [[ -f /var/log/installer/syslog ]]; then
    OS_INSTALL=$(stat -c %y /var/log/installer/syslog 2>/dev/null | cut -d' ' -f1 || echo "N/A")
elif [[ -f /lost+found ]]; then
    OS_INSTALL=$(stat -c %y /lost+found 2>/dev/null | cut -d' ' -f1 || echo "N/A")
fi
# Fallback: oldest journald entry
OLDEST_BOOT="N/A"
if cmd_exists journalctl; then
    OLDEST_BOOT=$(journalctl --list-boots 2>/dev/null | tail -1 | awk '{print $3}' || echo "N/A")
fi

add_check "BIOS Age" "$( [[ $BIOS_AGE_DAYS -lt 1460 || $BIOS_AGE_DAYS -eq -1 ]] && echo 1 || echo 0 )" \
    "BIOS: $BIOS_DATE ($BIOS_VERSION) Age: ${BIOS_AGE_YEARS}yr" 1

write_line "    BIOS Date: $BIOS_DATE ($BIOS_VERSION)" "$C_WHITE"
if [[ "$BIOS_AGE_RATING" != "N/A" ]]; then
    RC=$(rating_color "$BIOS_AGE_RATING")
    write_line "    BIOS Age : ${BIOS_AGE_YEARS} years — $BIOS_AGE_RATING" "$RC"
fi
write_line "    OS Install: $OS_INSTALL | Oldest Boot Log: $OLDEST_BOOT" "$C_WHITE"
echo ""

# ============================================================
#  3. HARDWARE SERIAL / ASSET TAG CHECK
#     (replaces Windows OEM key check — Linux equivalent)
# ============================================================
step 3 $TOTAL_STEPS "[3/16] Checking hardware identifiers..."

ASSET_TAG="N/A"
BOARD_SERIAL="N/A"
CHASSIS_TYPE="N/A"
if cmd_exists dmidecode; then
    ASSET_TAG=$(safe_read dmidecode -s chassis-asset-tag)
    BOARD_SERIAL=$(safe_read dmidecode -s baseboard-serial-number)
    CHASSIS_TYPE=$(dmidecode -t chassis 2>/dev/null | grep -i "Type:" | head -1 | sed 's/.*: //' | xargs || echo "N/A")
fi

# Flag generic/placeholder serials (common sign of wiped/cloned units)
SERIAL_OK=1
SERIAL_WARN=""
for placeholder in "Default string" "To be filled" "N/A" "None" "0123456789" "XXXXXXXXXXXX" ""; do
    if [[ "${SERIAL,,}" == "${placeholder,,}" || "${BOARD_SERIAL,,}" == "${placeholder,,}" ]]; then
        SERIAL_OK=0
        SERIAL_WARN="  ⚠ Placeholder serial detected — may indicate wiped/cloned unit"
        break
    fi
done

add_check "Hardware Serials" "$SERIAL_OK" \
    "System: $SERIAL | Board: $BOARD_SERIAL | Asset: $ASSET_TAG | Chassis: $CHASSIS_TYPE" 2

write_line "    System Serial : $SERIAL" "$C_WHITE"
write_line "    Board Serial  : $BOARD_SERIAL" "$C_WHITE"
write_line "    Asset Tag     : $ASSET_TAG" "$C_WHITE"
write_line "    Chassis Type  : $CHASSIS_TYPE" "$C_WHITE"
if [[ -n "$SERIAL_WARN" ]]; then
    write_line "$SERIAL_WARN" "$C_YELLOW"
else
    write_line "    Serial check  : OK (non-placeholder serials)" "$C_GREEN"
fi
echo ""

# ============================================================
#  4. GPU ANALYSIS
# ============================================================
step 4 $TOTAL_STEPS "[4/16] Analyzing GPU condition..."

GPU_DRIVER="N/A"
GPU_DRIVER_DATE="N/A"
GPU_VRAM="N/A"
GPU_CRASHES=0
GPU_TYPE="Integrated Only"

# Driver version via modinfo
for mod in nvidia amdgpu i915 radeon nouveau; do
    if modinfo "$mod" &>/dev/null 2>&1; then
        VER=$(modinfo "$mod" 2>/dev/null | grep "^version:" | awk '{print $2}')
        DATE=$(modinfo "$mod" 2>/dev/null | grep "^srcversion\|^vermagic" | head -1 | awk '{print $2}')
        if [[ -n "$VER" ]]; then GPU_DRIVER="$mod $VER"; break; fi
    fi
done

# GPU VRAM from sysfs or lspci
if cmd_exists lspci; then
    VRAM_RAW=$(lspci -v 2>/dev/null | grep -A20 -iE "VGA|3D|Display" | grep -i "memory" | grep -i "prefetchable" | head -1 | grep -oP '\d+[MG]' | head -1 || true)
    [[ -n "$VRAM_RAW" ]] && GPU_VRAM="$VRAM_RAW"
fi
# Also check /sys/class/drm
for card in /sys/class/drm/card*/device/mem_info_vram_total; do
    if [[ -f "$card" ]]; then
        VRAM_BYTES=$(cat "$card" 2>/dev/null || echo 0)
        if (( VRAM_BYTES > 0 )); then
            GPU_VRAM="$(( VRAM_BYTES / 1073741824 )) GB"
        fi
        break
    fi
done

# Dedicated GPU check
if echo "$GPU" | grep -qiE "NVIDIA|AMD|Radeon|GeForce|RTX|GTX|Quadro|RX [0-9]" 2>/dev/null; then
    GPU_TYPE="Dedicated GPU"
fi

# GPU-related kernel errors (last 30 days via journalctl)
if cmd_exists journalctl; then
    GPU_CRASHES=$(journalctl --since="30 days ago" 2>/dev/null \
        | grep -ciE "gpu|drm|nvidia|amdgpu|i915|nouveau|display.*error|VRAM|hung_task.*drm" \
        2>/dev/null) || GPU_CRASHES=0
fi

GPU_CONDITION="GOOD"
GPU_COND_DESC="GPU appears in good condition."
GPU_SCORE=0
(( GPU_CRASHES > 5 ))  && (( GPU_SCORE+=2 )) || true
(( GPU_CRASHES > 0 ))  && (( GPU_SCORE+=1 )) || true
if [[ "$GPU_TYPE" == "Dedicated GPU" ]] && (( GPU_CRASHES > 3 )); then (( GPU_SCORE++ )) || true; fi
if   (( GPU_SCORE == 0 )); then GPU_CONDITION="GOOD";       GPU_COND_DESC="GPU appears in good condition."
elif (( GPU_SCORE <= 2 )); then GPU_CONDITION="WARNING";    GPU_COND_DESC="GPU shows some wear or has logged driver errors."
else                             GPU_CONDITION="CONCERNING"; GPU_COND_DESC="GPU may have been heavily used (mining/rendering)."
fi

add_check "GPU Condition" "$([[ $GPU_CONDITION == GOOD ]] && echo 1 || echo 0)" \
    "$GPU_CONDITION | Crashes(30d): $GPU_CRASHES | $GPU_TYPE" 2

RC=$(rating_color "$GPU_CONDITION")
write_line "    $GPU  |  $GPU_TYPE" "$C_WHITE"
write_line "    VRAM: $GPU_VRAM  |  Driver: $GPU_DRIVER" "$C_WHITE"
write_line "    Kernel GPU errors (30d): $GPU_CRASHES" "$( (( GPU_CRASHES == 0 )) && echo $C_GREEN || echo $C_RED)"
write_line "    Condition: $GPU_CONDITION — $GPU_COND_DESC" "$RC"
echo ""

# ============================================================
#  5. BATTERY HEALTH
# ============================================================
step 5 $TOTAL_STEPS "[5/16] Analyzing battery health..."

BAT_PRESENT=0
BAT_PERCENT="N/A"
BAT_STATUS="N/A"
BAT_DESIGN="N/A"
BAT_FULL="N/A"
BAT_WEAR="N/A"
BAT_CYCLES="N/A"
BAT_CHEMISTRY="N/A"
BAT_RATING="N/A"
BAT_RATING_DESC="No battery detected."

for bat_dir in /sys/class/power_supply/BAT* /sys/class/power_supply/bat*; do
    [[ -d "$bat_dir" ]] || continue
    BAT_PRESENT=1

    BAT_STATUS=$(cat "$bat_dir/status"     2>/dev/null || echo "N/A")
    BAT_PERCENT=$(cat "$bat_dir/capacity"  2>/dev/null || echo "N/A")
    BAT_CHEMISTRY=$(cat "$bat_dir/technology" 2>/dev/null || echo "N/A")
    BAT_CYCLES=$(cat "$bat_dir/cycle_count"   2>/dev/null || echo "N/A")

    # Energy values (µWh) or charge (µAh)
    for name_full in energy_full charge_full; do
        [[ -f "$bat_dir/$name_full" ]] || continue
        FULL_RAW=$(cat "$bat_dir/$name_full" 2>/dev/null || echo 0)
        DESIGN_KEY="${name_full}_design"
        DESIGN_RAW=$(cat "$bat_dir/$DESIGN_KEY" 2>/dev/null || echo 0)
        if (( FULL_RAW > 0 && DESIGN_RAW > 0 )); then
            BAT_FULL=$(( FULL_RAW   / 1000 ))   # convert µ→m
            BAT_DESIGN=$(( DESIGN_RAW / 1000 ))
            BAT_WEAR=$(awk "BEGIN {w=(1-$FULL_RAW/$DESIGN_RAW)*100; if(w<0)w=0; printf \"%.1f\",w}")
        fi
        break
    done
    break   # use first battery found
done

if (( BAT_PRESENT )); then
    # Battery rating
    W=999; C=999
    [[ "$BAT_WEAR"   != "N/A" ]] && W=$(printf "%.0f" "$BAT_WEAR")
    [[ "$BAT_CYCLES" != "N/A" ]] && C=$BAT_CYCLES

    if   (( W <= 10  && C < 300 )); then BAT_RATING="EXCELLENT"; BAT_RATING_DESC="Minimal wear."
    elif (( W <= 25  && C < 500 )); then BAT_RATING="GOOD";      BAT_RATING_DESC="Normal wear for its age."
    elif (( W <= 40  && C < 800 )); then BAT_RATING="POOR";      BAT_RATING_DESC="Significant wear. May need replacement soon."
    else                                  BAT_RATING="VERY POOR"; BAT_RATING_DESC="Heavily degraded. Replacement recommended."
    fi

    WEAR_OK=1
    [[ "$BAT_WEAR" != "N/A" ]] && (( $(echo "$BAT_WEAR >= 30" | bc -l) )) && WEAR_OK=0

    add_check "Battery Wear"   "$WEAR_OK"          "Wear: $BAT_WEAR% | Design: $BAT_DESIGN mWh | Full: $BAT_FULL mWh" 3
    add_check "Battery Status" "$([[ $BAT_STATUS == "Discharging" || $BAT_STATUS == "Full" || $BAT_STATUS == "Charging" ]] && echo 1 || echo 0)" \
        "Status: $BAT_STATUS" 2
else
    add_check "Battery Wear"   "1" "No battery (desktop or removed)" 0
    add_check "Battery Status" "1" "No battery" 0
fi

RC=$(rating_color "$BAT_RATING")
write_line "    Battery present: $(( BAT_PRESENT )) | Status: $BAT_STATUS | Charge: $BAT_PERCENT%" "$C_WHITE"
write_line "    Wear: $BAT_WEAR%  |  Design: $BAT_DESIGN mWh  |  Full charge: $BAT_FULL mWh" "$C_WHITE"
write_line "    Cycles: $BAT_CYCLES  |  Chemistry: $BAT_CHEMISTRY" "$C_WHITE"
write_line "    Rating: $BAT_RATING — $BAT_RATING_DESC" "$RC"
echo ""

# ============================================================
#  6. DISK SMART
# ============================================================
step 6 $TOTAL_STEPS "[6/16] Checking disk SMART data..."

SMART_OK=1
POWER_ON_HOURS="N/A"
REALLOC_SECTORS="N/A"
READ_ERRORS="N/A"
WRITE_ERRORS="N/A"
POWER_ON_RATING="N/A"
SECTOR_RATING="N/A"

DISK_LIST=()
if cmd_exists lsblk; then
    while IFS= read -r line; do
        DISK_LIST+=("$line")
    done < <(lsblk -d -o NAME,SIZE,TYPE,ROTA,MODEL 2>/dev/null | grep disk || true)
fi

write_line "    Disk list:" "$C_WHITE"
for d in "${DISK_LIST[@]}"; do
    write_line "      $d" "$C_GRAY"
done

if cmd_exists smartctl; then
    for dev in /dev/sd? /dev/nvme?; do
        [[ -b "$dev" ]] || continue
        SMART_OUT=$(smartctl -A "$dev" 2>/dev/null || true)

        # Power-on hours
        POH=$(echo "$SMART_OUT" | grep -i "Power_On_Hours\|Power On Hours" | awk '{print $NF}' | tr -d ',' | head -1 || true)
        [[ -z "$POH" ]] && POH=$(echo "$SMART_OUT" | grep -i "power_on_time\|Hours" | grep -oP '\d+' | head -1 || true)
        if [[ -n "$POH" && "$POH" =~ ^[0-9]+$ ]]; then POWER_ON_HOURS=$POH; fi

        # Reallocated sectors
        RS=$(echo "$SMART_OUT" | grep -i "Reallocated_Sector\|Reallocated Sector" | awk '{print $NF}' | head -1 || true)
        if [[ -n "$RS" && "$RS" =~ ^[0-9]+$ ]]; then REALLOC_SECTORS=$RS; fi

        # Read/write errors
        RE=$(echo "$SMART_OUT" | grep -i "Raw_Read_Error_Rate\|Read Error Rate" | awk '{print $NF}' | head -1 || true)
        [[ -n "$RE" ]] && READ_ERRORS=$RE
        WE=$(echo "$SMART_OUT" | grep -i "Write_Error_Rate\|Write Error" | awk '{print $NF}' | head -1 || true)
        [[ -n "$WE" ]] && WRITE_ERRORS=$WE

        # Overall health
        HEALTH=$(smartctl -H "$dev" 2>/dev/null | grep -i "SMART overall\|test result" | head -1 || true)
        if echo "$HEALTH" | grep -qiE "FAILED|failure" 2>/dev/null; then SMART_OK=0; fi

        break   # use first disk
    done
fi

if [[ "$POWER_ON_HOURS" != "N/A" ]]; then
    POWER_ON_RATING=$(get_rating "$POWER_ON_HOURS" 1000 5000 10000 1)
    add_check "Disk Power-On Hours" "$([[ $POWER_ON_HOURS -lt 10000 ]] && echo 1 || echo 0)" \
        "Hours: $POWER_ON_HOURS | $POWER_ON_RATING" 3
else
    add_check "Disk Power-On Hours" "1" "N/A (install smartmontools for SMART data)" 3
fi

if [[ "$REALLOC_SECTORS" != "N/A" ]]; then
    SECTOR_RATING=$(get_rating "$REALLOC_SECTORS" 0 5 30 1)
    add_check "Disk Wear/Sectors" "$([[ $REALLOC_SECTORS -lt 30 ]] && echo 1 || echo 0)" \
        "Reallocated: $REALLOC_SECTORS | $SECTOR_RATING" 3
else
    add_check "Disk Wear/Sectors" "1" "N/A (needs smartctl)" 3
fi

add_check "Disk SMART" "$SMART_OK" "SMART overall health: $(if (( SMART_OK )); then echo PASSED; else echo FAILED; fi)" 3

POR=$(rating_color "$POWER_ON_RATING"); SR=$(rating_color "$SECTOR_RATING")
write_line "    Power-On Hours : $POWER_ON_HOURS" "$POR"
write_line "    Realloc Sectors: $REALLOC_SECTORS  |  Read Errs: $READ_ERRORS  |  Write Errs: $WRITE_ERRORS" "$SR"
write_line "    SMART overall  : $(if (( SMART_OK )); then echo PASSED; else echo FAILED; fi)" \
    "$(( SMART_OK )) && echo $C_GREEN || echo $C_RED"
if ! cmd_exists smartctl; then
    write_line "    Tip: install smartmontools for full SMART data (sudo apt install smartmontools)" "$C_GRAY"
fi
echo ""

# ============================================================
#  7. CPU THROTTLE TEST
# ============================================================
step 7 $TOTAL_STEPS "[7/16] CPU throttle test (~8 seconds)..."

THROTTLE_PCT="N/A"
THROTTLE_RATING="N/A"
BASE_CLOCK="N/A"
STRESS_CLOCK="N/A"
CPU_MAX_KHZ_FILE=""

for f in /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq \
         /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq; do
    [[ -f "$f" ]] && CPU_MAX_KHZ_FILE="$f" && break
done

read_cur_freq() {
    local freq=0
    for f in /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq \
             /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_cur_freq; do
        [[ -f "$f" ]] && freq=$(cat "$f" 2>/dev/null || echo 0) && break
    done
    # Fallback: read from /proc/cpuinfo
    if (( freq == 0 )); then
        freq=$(grep -m1 "cpu MHz" /proc/cpuinfo 2>/dev/null | awk '{printf "%.0f", $4*1000}' || echo 0)
    fi
    echo "$freq"
}

if [[ -n "$CPU_MAX_KHZ_FILE" ]]; then
    MAX_KHZ=$(cat "$CPU_MAX_KHZ_FILE")
    BASE_CLOCK=$(( MAX_KHZ / 1000 ))

    # Stress burst ~8 seconds
    write_line "    Running stress burst..." "$C_GRAY"
    python3 -c "
import time, math
end = time.time() + 8
i = 0
while time.time() < end:
    math.sqrt(12345.6789 * i)
    i += 1
" 2>/dev/null &
    STRESS_PID=$!
    sleep 8
    wait $STRESS_PID 2>/dev/null || true

    STRESS_KHZ=$(read_cur_freq)
    STRESS_CLOCK=$(( STRESS_KHZ / 1000 ))

    if (( BASE_CLOCK > 0 && STRESS_CLOCK > 0 )); then
        THROTTLE_PCT=$(awk "BEGIN {printf \"%.1f\", ($STRESS_CLOCK/$BASE_CLOCK)*100}")
        THROTTLE_RATING=$(get_rating "$THROTTLE_PCT" 95 85 70 0)
    fi
fi

THROTTLE_OK=1
[[ "$THROTTLE_PCT" != "N/A" ]] && (( $(echo "$THROTTLE_PCT < 70" | bc -l) )) && THROTTLE_OK=0

add_check "CPU Throttle" "$THROTTLE_OK" \
    "Clock held: $THROTTLE_PCT% of max | $THROTTLE_RATING" 2

RC=$(rating_color "$THROTTLE_RATING")
write_line "    Base: $BASE_CLOCK MHz  |  Under Stress: $STRESS_CLOCK MHz" "$C_WHITE"
write_line "    Throttle: $THROTTLE_PCT% — $THROTTLE_RATING" "$RC"
if [[ "$THROTTLE_PCT" != "N/A" ]] && (( $(echo "$THROTTLE_PCT < 85" | bc -l) )); then
    write_line "    WARNING: CPU may have thermal issues (bad paste, worn cooling)" "$C_YELLOW"
fi
echo ""

# ============================================================
#  8. RAM STABILITY
# ============================================================
step 8 $TOTAL_STEPS "[8/16] RAM stability test (~5 seconds)..."

RAM_TEST_RESULT="N/A"
RAM_ERRORS=0
RAM_BLOCKS=4
RAM_BLOCK_MB=256
RAM_RATING="N/A"

if python3 -c "" &>/dev/null; then
    RAM_ERRORS=$(python3 - <<'EOF'
import random, sys
errors = 0
blocks = 4
block_mb = 256
seed = 42
try:
    for _ in range(blocks):
        rng = random.Random(seed)
        data = bytearray(rng.getrandbits(8) for _ in range(4096))
        rng2 = random.Random(seed)
        check = bytearray(rng2.getrandbits(8) for _ in range(4096))
        if data != check:
            errors += 1
except Exception:
    errors += 1
print(errors)
EOF
    )

    if (( RAM_ERRORS == 0 )); then
        RAM_TEST_RESULT="PASS"
        RAM_RATING="EXCELLENT"
    else
        RAM_TEST_RESULT="ERRORS ($RAM_ERRORS)"
        RAM_RATING="VERY POOR"
    fi
else
    RAM_TEST_RESULT="COULD NOT TEST"
fi

add_check "RAM Stability" "$([[ $RAM_ERRORS -eq 0 ]] && echo 1 || echo 0)" \
    "Tested $RAM_BLOCKS x ${RAM_BLOCK_MB}MB blocks - Errors: $RAM_ERRORS" 2

RC=$(rating_color "$RAM_RATING")
write_line "    Tested $RAM_BLOCKS x ${RAM_BLOCK_MB}MB blocks  |  Errors: $RAM_ERRORS" "$C_WHITE"
write_line "    RAM: $RAM_RATING — $RAM_TEST_RESULT" "$RC"
echo ""

# ============================================================
#  9. DISPLAY INFO
# ============================================================
step 9 $TOTAL_STEPS "[9/16] Checking display panel..."

RESOLUTION="N/A"
REFRESH_RATE="N/A"
PANEL_MFG="N/A"
PANEL_MODEL="N/A"
PANEL_TYPE="N/A"

if cmd_exists xrandr; then
    XRANDR_OUT=$(xrandr 2>/dev/null || true)
    RESOLUTION=$(echo "$XRANDR_OUT" | grep '*' | awk '{print $1}' | head -1 || echo "N/A")
    REFRESH_RATE=$(echo "$XRANDR_OUT" | grep '*' | grep -oP '[\d.]+\*' | tr -d '*' | head -1 || echo "N/A")
fi

# Read EDID for panel info
if [[ -d /sys/class/drm ]]; then
    for edid_path in /sys/class/drm/card*/*/edid; do
        [[ -f "$edid_path" ]] || continue
        SZ=$(wc -c < "$edid_path" 2>/dev/null || echo 0)
        (( SZ < 128 )) && continue
        if cmd_exists edid-decode; then
            EDID_INFO=$(edid-decode < "$edid_path" 2>/dev/null || true)
            MFG=$(echo "$EDID_INFO" | grep -i "manufacturer" | head -1 | sed 's/.*: //' | xargs || echo "N/A")
            MDL=$(echo "$EDID_INFO" | grep -i "monitor name\|display name" | head -1 | sed 's/.*: //' | xargs || echo "N/A")
            [[ -n "$MFG" && "$MFG" != "N/A" ]] && PANEL_MFG="$MFG"
            [[ -n "$MDL" && "$MDL" != "N/A" ]] && PANEL_MODEL="$MDL"
        fi
        # Connector type from path name
        CONN=$(echo "$edid_path" | grep -oiP 'eDP|LVDS|HDMI|DP|VGA' | head -1 || echo "N/A")
        [[ -n "$CONN" ]] && PANEL_TYPE="$CONN"
        break
    done
fi

write_line "    Resolution  : $RESOLUTION @ ${REFRESH_RATE}Hz" "$C_WHITE"
write_line "    Panel Mfg   : $PANEL_MFG  |  Model: $PANEL_MODEL  |  Connector: $PANEL_TYPE" "$C_WHITE"
write_line "    (Run a dead pixel test manually — e.g. https://deadpixeltest.org)" "$C_MAGENTA"
echo ""

# ============================================================
#  10. TEMPERATURE
# ============================================================
step 10 $TOTAL_STEPS "[10/16] Reading temperatures..."

TEMP="N/A"
TEMP_RATING="N/A"

# Try sensors first, then sysfs thermal zones
if cmd_exists sensors; then
    TEMP=$(sensors 2>/dev/null | grep -iE "Package id 0|Tdie|CPU Temperature|temp1" \
        | grep -oP '[+-]?\d+\.\d+' | head -1 || echo "N/A")
fi
if [[ "$TEMP" == "N/A" || -z "$TEMP" ]]; then
    for tz in /sys/class/thermal/thermal_zone*/temp; do
        [[ -f "$tz" ]] || continue
        RAW=$(cat "$tz" 2>/dev/null || echo 0)
        if (( RAW > 1000 )); then
            TEMP=$(awk "BEGIN {printf \"%.1f\", $RAW/1000}")
            break
        fi
    done
fi

TEMP_OK=1
if [[ "$TEMP" != "N/A" ]]; then
    TEMP_RATING=$(get_rating "$TEMP" 45 65 85 1)
    (( $(echo "$TEMP >= 85" | bc -l) )) && TEMP_OK=0
fi

add_check "Temperature" "$TEMP_OK" \
    "$(if [[ $TEMP != N/A ]]; then echo "${TEMP}C"; else echo "N/A (install lm-sensors)"; fi) | $TEMP_RATING" 1

RC=$(rating_color "$TEMP_RATING")
write_line "    Temperature: $(if [[ $TEMP != N/A ]]; then echo "${TEMP}°C"; else echo "N/A (try: sudo sensors-detect)"; fi)" "$RC"
if ! cmd_exists sensors; then
    write_line "    Tip: sudo apt install lm-sensors && sudo sensors-detect" "$C_GRAY"
fi
echo ""

# ============================================================
#  11. NETWORK
# ============================================================
step 11 $TOTAL_STEPS "[11/16] Checking network..."

WIFI_ADAPTER="N/A"
WIFI_SIGNAL="N/A"
ETH_ADAPTERS="N/A"
INTERNET_OK=0
PING_LATENCY="N/A"

if cmd_exists ip; then
    WIFI_ADAPTER=$(ip link show 2>/dev/null | grep -oP '(?<=\d: )(wl\S+)' | head -1 || echo "N/A")
    ETH_ADAPTERS=$(ip link show 2>/dev/null | grep -oP '(?<=\d: )(en\S+|eth\S+)' | paste -sd ", " || echo "N/A")
fi

# Wi-Fi signal
if cmd_exists iwconfig && [[ "$WIFI_ADAPTER" != "N/A" ]]; then
    WIFI_SIGNAL=$(iwconfig "$WIFI_ADAPTER" 2>/dev/null | grep -oP 'Signal level=\K[^ ]+' || echo "N/A")
elif cmd_exists iw && [[ "$WIFI_ADAPTER" != "N/A" ]]; then
    WIFI_SIGNAL=$(iw dev "$WIFI_ADAPTER" link 2>/dev/null | grep -oP 'signal: \K[^ ]+' || echo "N/A")
    [[ -n "$WIFI_SIGNAL" && "$WIFI_SIGNAL" != "N/A" ]] && WIFI_SIGNAL="${WIFI_SIGNAL} dBm"
fi

# Internet check
if ping -c 1 -W 3 8.8.8.8 &>/dev/null 2>&1; then
    INTERNET_OK=1
    PING_LATENCY=$(ping -c 3 -W 3 8.8.8.8 2>/dev/null | tail -1 | grep -oP 'avg\s*=\s*\K[\d.]+' || \
                   ping -c 3 8.8.8.8 2>/dev/null | grep rtt | awk -F'/' '{print $5 " ms"}' || echo "N/A")
    [[ "$PING_LATENCY" != "N/A" ]] && PING_LATENCY="${PING_LATENCY} ms"
fi

add_check "Network"     "$(( INTERNET_OK ))" "Wi-Fi: $WIFI_ADAPTER | Signal: $WIFI_SIGNAL | Internet: $(( INTERNET_OK )) | Latency: $PING_LATENCY" 1

write_line "    Wi-Fi    : $WIFI_ADAPTER  (Signal: $WIFI_SIGNAL)" "$C_WHITE"
write_line "    Ethernet : $ETH_ADAPTERS" "$C_WHITE"
write_line "    Internet : $(if (( INTERNET_OK )); then echo Connected; else echo Disconnected; fi)  (Ping: $PING_LATENCY)" \
    "$(( INTERNET_OK )) && echo $C_GREEN || echo $C_RED"
echo ""

# ============================================================
#  12. OS & SECURITY
# ============================================================
step 12 $TOTAL_STEPS "[12/16] Checking OS & security..."

OS_NAME=$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-N/A}" || echo "N/A")
OS_ARCH=$(uname -m)
KERNEL=$(uname -r)
LAST_BOOT=$(who -b 2>/dev/null | awk '{print $3,$4}' || uptime -s 2>/dev/null || echo "N/A")
UPTIME=$(uptime -p 2>/dev/null | sed 's/^up //' || echo "N/A")

# Security checks
FIREWALL="N/A"
if cmd_exists ufw;       then FIREWALL=$(ufw status 2>/dev/null | head -1 | sed 's/Status: //')
elif cmd_exists firewall-cmd; then FIREWALL=$(firewall-cmd --state 2>/dev/null || echo "N/A")
elif cmd_exists iptables; then
    RULES=$(iptables -L 2>/dev/null | grep -c "^[A-Z]" || echo 0)
    (( RULES > 3 )) && FIREWALL="Active (iptables)" || FIREWALL="Default/empty rules"
fi

APPARMOR="N/A"
cmd_exists aa-status && APPARMOR=$(aa-status 2>/dev/null | head -1 || echo "N/A")
[[ "$APPARMOR" == "N/A" ]] && [[ -f /sys/kernel/security/apparmor/profiles ]] && APPARMOR="Enabled"

SELINUX="N/A"
cmd_exists getenforce && SELINUX=$(getenforce 2>/dev/null || echo "N/A")

DISK_ENCRYPT="N/A"
if cmd_exists lsblk; then
    ENC=$(lsblk -o TYPE 2>/dev/null | grep -c "crypt" || echo 0)
    (( ENC > 0 )) && DISK_ENCRYPT="Enabled (LUKS)" || DISK_ENCRYPT="Not detected"
fi

TPM_VERSION="N/A"
for tpm_path in /sys/class/tpm/tpm*/device/description /sys/class/tpm/tpm0/tpm_version_major; do
    [[ -f "$tpm_path" ]] && TPM_VERSION=$(cat "$tpm_path" 2>/dev/null | head -1 || echo "N/A") && break
done
[[ "$TPM_VERSION" == "N/A" ]] && ls /dev/tpm* &>/dev/null 2>&1 && TPM_VERSION="Present"

SECURE_BOOT="N/A"
if cmd_exists mokutil; then
    SECURE_BOOT=$(mokutil --sb-state 2>/dev/null | grep -i "secure boot" | head -1 || echo "N/A")
elif [[ -f /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c ]]; then
    SB_VAL=$(cat /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c 2>/dev/null | xxd | tail -1 | grep -o "01$" || echo "")
    SECURE_BOOT=$(if [[ -n "$SB_VAL" ]]; then echo "Enabled"; else echo "Disabled"; fi)
fi

add_check "Firewall"     "$([[ $FIREWALL == *active* || $FIREWALL == *enabled* || $FIREWALL == Active* ]] && echo 1 || echo 0)" "Firewall: $FIREWALL" 1
add_check "AppArmor/SELinux" "$([[ $APPARMOR == Enabled* || $SELINUX == Enforcing ]] && echo 1 || echo 0)" "AppArmor: $APPARMOR | SELinux: $SELINUX" 1
add_check "Disk Encryption" "$([[ $DISK_ENCRYPT == *LUKS* ]] && echo 1 || echo 0)" "$DISK_ENCRYPT" 1
add_check "TPM"           "$([[ $TPM_VERSION != N/A ]] && echo 1 || echo 0)" "TPM: $TPM_VERSION" 1

write_line "    OS         : $OS_NAME ($OS_ARCH)  |  Kernel: $KERNEL" "$C_WHITE"
write_line "    Last Boot  : $LAST_BOOT  |  Uptime: $UPTIME" "$C_WHITE"
write_line "    Firewall   : $FIREWALL" "$C_WHITE"
write_line "    AppArmor   : $APPARMOR  |  SELinux: $SELINUX" "$C_WHITE"
write_line "    Encryption : $DISK_ENCRYPT" "$C_WHITE"
write_line "    TPM        : $TPM_VERSION  |  Secure Boot: $SECURE_BOOT" "$C_WHITE"
echo ""

# ============================================================
#  13. PERIPHERALS & USB
# ============================================================
step 13 $TOTAL_STEPS "[13/16] Detecting peripherals & USB..."

WEBCAM="Not Found"
BLUETOOTH="Not Found"
AUDIO="Not Found"
KEYBOARD="Not Found"
TOUCHPAD="Not Found"
USB_COUNT=0
FAN="N/A"

# Webcam
for v in /dev/video*; do
    [[ -e "$v" ]] && WEBCAM="$v" && break
done
if cmd_exists v4l2-ctl && [[ "$WEBCAM" != "Not Found" ]]; then
    WCAM_NAME=$(v4l2-ctl --device="$WEBCAM" --info 2>/dev/null | grep "Card type" | sed 's/.*: //' || echo "$WEBCAM")
    WEBCAM="$WCAM_NAME"
fi

# Bluetooth
if cmd_exists hciconfig; then
    BT=$(hciconfig 2>/dev/null | grep hci | head -1 | awk '{print $1}' || echo "")
    [[ -n "$BT" ]] && BLUETOOTH="$BT"
elif ls /sys/class/bluetooth/ &>/dev/null 2>&1; then
    BLUETOOTH=$(ls /sys/class/bluetooth/ 2>/dev/null | head -1 || echo "Not Found")
fi

# Audio
if cmd_exists pactl; then
    AUDIO=$(pactl list sinks short 2>/dev/null | head -1 | awk '{print $2}' || echo "Not Found")
elif cmd_exists aplay; then
    AUDIO=$(aplay -l 2>/dev/null | grep "^card" | head -1 | sed 's/card [0-9]*: //' | sed 's/ \[.*//' || echo "Not Found")
fi

# Keyboard + touchpad via xinput or /proc/bus/input
if cmd_exists xinput; then
    KEYBOARD=$(xinput list 2>/dev/null | grep -i "keyboard" | grep -v "Virtual\|Master" | head -1 | sed 's/.*↳ //' | sed 's/ *id=.*//' || echo "N/A")
    TOUCHPAD=$(xinput list 2>/dev/null | grep -iE "touchpad|trackpad|synaptics" | head -1 | sed 's/.*↳ //' | sed 's/ *id=.*//' || echo "Not Found")
fi
if [[ "$KEYBOARD" == "N/A" ]]; then
    KEYBOARD=$(grep -r "Name=.*eyboard" /proc/bus/input/devices 2>/dev/null | head -1 | sed 's/N: Name=//' | tr -d '"' || echo "N/A")
fi

# USB
if cmd_exists lsusb; then
    USB_COUNT=$(lsusb 2>/dev/null | wc -l || echo 0)
fi

# Fan
FAN_COUNT=$(cat /sys/class/hwmon/hwmon*/fan*_input 2>/dev/null | grep -v "^0$" | wc -l || echo 0)
if (( FAN_COUNT > 0 )); then
    FAN_RPMS=$(cat /sys/class/hwmon/hwmon*/fan*_input 2>/dev/null | grep -v "^0$" | paste -sd ", ")
    FAN="Detected ($FAN_COUNT fan(s), RPM: $FAN_RPMS)"
elif cmd_exists sensors; then
    FAN_SENSORS=$(sensors 2>/dev/null | grep -i "fan" | head -1 || echo "")
    [[ -n "$FAN_SENSORS" ]] && FAN="$FAN_SENSORS" || FAN="Not detected"
fi

add_check "Webcam"     "$([[ $WEBCAM    != 'Not Found' ]] && echo 1 || echo 0)" "$WEBCAM"    1
add_check "Bluetooth"  "$([[ $BLUETOOTH != 'Not Found' ]] && echo 1 || echo 0)" "$BLUETOOTH" 1
add_check "Audio"      "$([[ $AUDIO     != 'Not Found' ]] && echo 1 || echo 0)" "$AUDIO"     1
add_check "USB Ports"  "$([[ $USB_COUNT -gt 0 ]] && echo 1 || echo 0)"          "$USB_COUNT devices detected" 1

write_line "    Webcam    : $WEBCAM" "$C_WHITE"
write_line "    Bluetooth : $BLUETOOTH" "$C_WHITE"
write_line "    Audio     : $AUDIO" "$C_WHITE"
write_line "    Keyboard  : $KEYBOARD  |  Touchpad: $TOUCHPAD" "$C_WHITE"
write_line "    USB       : $USB_COUNT devices detected" "$C_WHITE"
write_line "    Fan       : $FAN" "$C_WHITE"
echo ""

# ============================================================
#  14. POWER PLAN & STARTUP BLOAT
# ============================================================
step 14 $TOTAL_STEPS "[14/16] Checking power plan & startup..."

POWER_GOV="N/A"
[[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]] && \
    POWER_GOV=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "N/A")

PROCESS_COUNT=$(ps aux 2>/dev/null | wc -l || echo "N/A")
STARTUP_COUNT=0
if cmd_exists systemctl; then
    STARTUP_COUNT=$(systemctl list-unit-files --state=enabled --type=service 2>/dev/null | grep -c enabled) || STARTUP_COUNT=0
fi
STARTUP_RATING=$(get_rating "$STARTUP_COUNT" 20 40 80 1)

TOP_PROCS=$(ps aux 2>/dev/null | awk 'NR>1 {print $11, $6}' | sort -k2 -rn | head -5 | \
    awk '{printf "%-30s %d MB\n", $1, $2/1024}' || echo "N/A")

SR=$(rating_color "$STARTUP_RATING")
write_line "    CPU Governor  : $POWER_GOV" "$C_WHITE"
write_line "    Processes     : $PROCESS_COUNT  |  Enabled services: $STARTUP_COUNT" "$C_WHITE"
write_line "    Startup Bloat : $STARTUP_RATING ($STARTUP_COUNT services)" "$SR"
write_line "    Top RAM users :" "$C_GRAY"
while IFS= read -r proc; do
    write_line "      $proc" "$C_GRAY"
done <<< "$TOP_PROCS"
echo ""

# ============================================================
#  15. SYSTEM LOGS
# ============================================================
step 15 $TOTAL_STEPS "[15/16] Scanning system logs..."

CRITICAL_EVENTS=0
EVENT_RATING="N/A"

if cmd_exists journalctl; then
    CRITICAL_EVENTS=$(journalctl -p 0..2 --since="48 hours ago" 2>/dev/null | grep -c "^") || CRITICAL_EVENTS=0
    # Subtract header line
    (( CRITICAL_EVENTS > 0 )) && (( CRITICAL_EVENTS-- )) || true
fi

EVENT_RATING=$(get_rating "$CRITICAL_EVENTS" 0 3 10 1)
add_check "System Errors (48h)" "$([[ $CRITICAL_EVENTS -eq 0 ]] && echo 1 || echo 0)" \
    "$CRITICAL_EVENTS critical/error events in last 48h" 2

EC=$(rating_color "$EVENT_RATING")
write_line "    Critical/Error events (48h): $CRITICAL_EVENTS — $EVENT_RATING" "$EC"
if (( CRITICAL_EVENTS > 0 )) && cmd_exists journalctl; then
    write_line "    Recent errors:" "$C_YELLOW"
    journalctl -p 0..2 --since="48 hours ago" --no-pager 2>/dev/null | grep -v "^--" | tail -5 | \
    while IFS= read -r line; do write_line "      $line" "$C_YELLOW"; done || true
fi
echo ""

# ============================================================
#  16. SPEAKER TEST
# ============================================================
step 16 $TOTAL_STEPS "[16/16] Testing speaker..."

if cmd_exists speaker-test; then
    speaker-test -t sine -f 800 -l 1 -p 300 &>/dev/null & sleep 0.4; kill $! 2>/dev/null || true
    speaker-test -t sine -f 1000 -l 1 -p 300 &>/dev/null & sleep 0.4; kill $! 2>/dev/null || true
    speaker-test -t sine -f 1200 -l 1 -p 200 &>/dev/null & sleep 0.3; kill $! 2>/dev/null || true
    write_line "    Speaker test fired (3 tones). Did you hear them?" "$C_WHITE"
elif cmd_exists paplay; then
    # Fallback: system bell via PulseAudio
    paplay /usr/share/sounds/alsa/Front_Left.wav &>/dev/null || true
    write_line "    Speaker test fired via PulseAudio." "$C_WHITE"
else
    echo -e "\a\a\a"   # terminal bell
    write_line "    Speaker test: terminal bell (install speaker-test for audio tones)" "$C_GRAY"
fi
echo ""

# ============================================================
#  SCORING
# ============================================================
TOTAL_WEIGHT=0
EARNED_WEIGHT=0

for chk in "${CHECKS[@]}"; do
    IFS='|' read -r name passed detail weight <<< "$chk"
    TOTAL_WEIGHT=$(( TOTAL_WEIGHT + weight ))
    (( passed )) && EARNED_WEIGHT=$(( EARNED_WEIGHT + weight )) || true
done

(( TOTAL_WEIGHT == 0 )) && TOTAL_WEIGHT=1
SCORE_PCT=$(( EARNED_WEIGHT * 100 / TOTAL_WEIGHT ))

if   (( SCORE_PCT >= 85 )); then RESULT="EXCELLENT"; RC="$C_GREEN"
elif (( SCORE_PCT >= 70 )); then RESULT="GOOD";      RC="$C_CYAN"
elif (( SCORE_PCT >= 50 )); then RESULT="POOR";      RC="$C_YELLOW"
else                              RESULT="VERY POOR"; RC="$C_RED"
fi

echo -e "${C_YELLOW}  +------------------------------------------------+${C_RESET}"
echo -e "${C_YELLOW}  |             CHECK RESULTS                      |${C_RESET}"
echo -e "${C_YELLOW}  +------------------------------------------------+${C_RESET}"
echo ""
{
    echo "  +------------------------------------------------+"
    echo "  |             CHECK RESULTS                      |"
    echo "  +------------------------------------------------+"
} >> "$REPORT_TXT"

for chk in "${CHECKS[@]}"; do
    IFS='|' read -r name passed detail weight <<< "$chk"
    if (( passed )); then
        icon="[PASS]"; clr="$C_GREEN"
    else
        icon="[FAIL]"; clr="$C_RED"
    fi
    printf "${clr}  %-6s %-24s x%-2s  %s${C_RESET}\n" "$icon" "$name" "$weight" "$detail"
    printf "  %-6s %-24s x%-2s  %s\n" "$icon" "$name" "$weight" "$detail" >> "$REPORT_TXT"
done

echo ""
echo -e "${RC}  +================================================+${C_RESET}"
echo -e "${RC}  |  RESULT: $(printf '%-14s' $RESULT) SCORE: $EARNED_WEIGHT/$TOTAL_WEIGHT (${SCORE_PCT}%)     |${C_RESET}"
echo -e "${RC}  +================================================+${C_RESET}"
echo ""
{
    echo ""
    echo "  +================================================+"
    printf "  |  RESULT: %-14s SCORE: %s/%s (%s%%)     |\n" "$RESULT" "$EARNED_WEIGHT" "$TOTAL_WEIGHT" "$SCORE_PCT"
    echo "  +================================================+"
    echo ""
} >> "$REPORT_TXT"

# ============================================================
#  HTML REPORT
# ============================================================

# Build check rows HTML
CHECK_ROWS_HTML=""
for chk in "${CHECKS[@]}"; do
    IFS='|' read -r name passed detail weight <<< "$chk"
    if (( passed )); then icon="✔ PASS"; color="#2ecc71"
    else                   icon="✘ FAIL"; color="#e74c3c"; fi
    CHECK_ROWS_HTML+="<tr><td style='color:$color;font-weight:bold'>$icon</td><td>$name</td><td>x$weight</td><td>$detail</td></tr>"
done

BATT_WEAR_PCT=$(if [[ "$BAT_WEAR" != "N/A" ]]; then awk "BEGIN{w=100-$BAT_WEAR; if(w<0)w=0; printf \"%.0f\",w}"; else echo "100"; fi)
BATT_HEX=$(rating_hex "$BAT_RATING")
GPU_HEX=$(rating_hex "$GPU_CONDITION")
THROTTLE_HEX=$(rating_hex "$THROTTLE_RATING")
RAM_HEX=$(rating_hex "$RAM_RATING")
BIOS_HEX=$(rating_hex "$BIOS_AGE_RATING")
EVENT_HEX=$(rating_hex "$EVENT_RATING")
SCORE_HEX=$(rating_hex "$RESULT")
PO_HEX=$(rating_hex "$POWER_ON_RATING")
SEC_HEX=$(rating_hex "$SECTOR_RATING")
TEMP_HEX=$(rating_hex "$TEMP_RATING")

cat > "$REPORT_HTML" << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Laptop Inspector v2.5 – $TIMESTAMP</title>
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: #0f0f1a; color: #e0e0e0; font-family: 'Segoe UI', system-ui, sans-serif; font-size: 13px; }
  .container { max-width: 1100px; margin: 0 auto; padding: 24px 16px; }
  h1 { color: #00d4ff; font-size: 28px; text-align: center; margin-bottom: 4px; }
  .subtitle { color: #8892b0; text-align: center; margin-bottom: 24px; font-size: 12px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); gap: 14px; }
  .card { background: #1a1a2e; border: 1px solid rgba(255,255,255,.1); border-radius: 10px; padding: 16px; }
  .card h3 { color: #00d4ff; font-size: 13px; font-weight: 700; letter-spacing: .04em; margin-bottom: 12px; }
  .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 4px 12px; }
  .label { color: #8892b0; font-size: 11px; }
  .value { color: #e0e0e0; font-size: 11px; font-weight: 600; word-break: break-word; }
  .rating-badge { display: inline-block; padding: 4px 14px; border-radius: 20px; color: #fff; font-weight: 700; font-size: 13px; letter-spacing: .05em; }
  .gauge-container { background: #0a0a14; border-radius: 5px; height: 14px; margin: 8px 0; overflow: hidden; }
  .gauge-bar { height: 100%; border-radius: 5px; transition: width .4s; }
  table { width: 100%; border-collapse: collapse; font-size: 11.5px; }
  th { background: #0f0f1a; color: #8892b0; font-weight: 600; padding: 6px 8px; text-align: left; border-bottom: 1px solid #2a2a3e; }
  td { padding: 5px 8px; border-bottom: 1px solid #1e1e30; }
  .footer { text-align: center; color: #444; font-size: 11px; margin-top: 28px; }
  .score-hero { text-align: center; padding: 20px; }
  .score-hero .score-label { font-size: 40px; font-weight: 900; letter-spacing: .04em; }
  .score-hero .score-sub { color: #8892b0; font-size: 13px; margin-top: 4px; }
</style>
</head>
<body>
<div class="container">
  <h1>LAPTOP INSPECTOR</h1>
  <p class="subtitle">Linux Edition v2.5 &mdash; $TIMESTAMP</p>
  <div class="grid">

  <div class="card score-hero">
    <h3>OVERALL HEALTH</h3>
    <div class="score-label" style="color:$SCORE_HEX">$RESULT</div>
    <div class="score-sub">Score: $EARNED_WEIGHT / $TOTAL_WEIGHT &nbsp;($SCORE_PCT%)</div>
  </div>

  <div class="card">
    <h3>SYSTEM INFO</h3>
    <div class="info-grid">
      <span class="label">Manufacturer</span><span class="value">$MANUFACTURER</span>
      <span class="label">Model</span><span class="value">$MODEL</span>
      <span class="label">Serial</span><span class="value">$SERIAL</span>
      <span class="label">CPU</span><span class="value">$CPU</span>
      <span class="label">Cores/Threads</span><span class="value">$CPU_CORES / $CPU_THREADS</span>
      <span class="label">Clock</span><span class="value">${CPU_SPEED_GHZ} GHz</span>
      <span class="label">RAM</span><span class="value">${RAM_GB} GB</span>
      <span class="label">GPU</span><span class="value">$GPU</span>
      <span class="label">VRAM</span><span class="value">$GPU_VRAM</span>
      <span class="label">Resolution</span><span class="value">$RESOLUTION @ ${REFRESH_RATE}Hz</span>
    </div>
  </div>

  <div class="card">
    <h3>BATTERY HEALTH</h3>
    <div style="text-align:center;margin-bottom:8px">
      <span class="rating-badge" style="background:$BATT_HEX">$BAT_RATING</span>
    </div>
    <div class="gauge-container">
      <div class="gauge-bar" style="width:${BATT_WEAR_PCT}%;background:$BATT_HEX"></div>
    </div>
    <p style="text-align:center;color:#8892b0;font-size:11px;margin-bottom:8px">$BAT_RATING_DESC</p>
    <div class="info-grid">
      <span class="label">Charge</span><span class="value">${BAT_PERCENT}%</span>
      <span class="label">Wear</span><span class="value">${BAT_WEAR}%</span>
      <span class="label">Design Cap</span><span class="value">$BAT_DESIGN mWh</span>
      <span class="label">Full Charge</span><span class="value">$BAT_FULL mWh</span>
      <span class="label">Cycles</span><span class="value">$BAT_CYCLES</span>
      <span class="label">Chemistry</span><span class="value">$BAT_CHEMISTRY</span>
    </div>
  </div>

  <div class="card">
    <h3>GPU CONDITION</h3>
    <div style="text-align:center;margin-bottom:8px">
      <span class="rating-badge" style="background:$GPU_HEX">$GPU_CONDITION</span>
    </div>
    <p style="text-align:center;color:#8892b0;font-size:11px;margin-bottom:8px">$GPU_COND_DESC</p>
    <div class="info-grid">
      <span class="label">Type</span><span class="value">$GPU_TYPE</span>
      <span class="label">VRAM</span><span class="value">$GPU_VRAM</span>
      <span class="label">Driver</span><span class="value">$GPU_DRIVER</span>
      <span class="label">Crashes (30d)</span><span class="value">$GPU_CRASHES</span>
    </div>
  </div>

  <div class="card">
    <h3>DISK SMART HEALTH</h3>
    <div class="info-grid">
      <span class="label">Power-On Hours</span><span class="value" style="color:$PO_HEX">$POWER_ON_HOURS &mdash; $POWER_ON_RATING</span>
      <span class="label">Realloc Sectors</span><span class="value" style="color:$SEC_HEX">$REALLOC_SECTORS &mdash; $SECTOR_RATING</span>
      <span class="label">Read Errors</span><span class="value">$READ_ERRORS</span>
      <span class="label">Write Errors</span><span class="value">$WRITE_ERRORS</span>
      <span class="label">SMART Status</span><span class="value" style="color:$(if (( SMART_OK )); then echo '#2ecc71'; else echo '#e74c3c'; fi)">$(if (( SMART_OK )); then echo PASSED; else echo FAILED; fi)</span>
    </div>
    <p style="color:#8892b0;font-size:10px;margin-top:8px">Limits: &lt;1000h=Excellent, &lt;5000h=Good, &lt;10000h=Poor</p>
  </div>

  <div class="card">
    <h3>CPU THROTTLE TEST</h3>
    <div style="text-align:center;margin-bottom:8px">
      <span class="rating-badge" style="background:$THROTTLE_HEX">$THROTTLE_RATING</span>
    </div>
    <div class="info-grid">
      <span class="label">Max Clock</span><span class="value">$BASE_CLOCK MHz</span>
      <span class="label">Under Stress</span><span class="value">$STRESS_CLOCK MHz</span>
      <span class="label">Maintained</span><span class="value">${THROTTLE_PCT}%</span>
    </div>
    <p style="color:#8892b0;font-size:10px;margin-top:8px">Limits: &gt;95%=Excellent, &gt;85%=Good, &gt;70%=Poor</p>
  </div>

  <div class="card">
    <h3>RAM STABILITY</h3>
    <div style="text-align:center;margin-bottom:8px">
      <span class="rating-badge" style="background:$RAM_HEX">$RAM_RATING</span>
    </div>
    <div class="info-grid">
      <span class="label">Result</span><span class="value">$RAM_TEST_RESULT</span>
      <span class="label">Tested</span><span class="value">$RAM_BLOCKS x ${RAM_BLOCK_MB}MB</span>
      <span class="label">Errors</span><span class="value">$RAM_ERRORS</span>
    </div>
  </div>

  <div class="card">
    <h3>BIOS &amp; SYSTEM AGE</h3>
    <div style="text-align:center;margin-bottom:8px">
      <span class="rating-badge" style="background:$BIOS_HEX">$BIOS_AGE_RATING</span>
    </div>
    <div class="info-grid">
      <span class="label">BIOS Date</span><span class="value">$BIOS_DATE</span>
      <span class="label">BIOS Version</span><span class="value">$BIOS_VERSION</span>
      <span class="label">BIOS Age</span><span class="value">${BIOS_AGE_YEARS} years</span>
      <span class="label">OS Install</span><span class="value">$OS_INSTALL</span>
      <span class="label">Oldest Boot</span><span class="value">$OLDEST_BOOT</span>
    </div>
    <p style="color:#8892b0;font-size:10px;margin-top:8px">Limits: &lt;1yr=Excellent, &lt;2yr=Good, &lt;4yr=Poor</p>
  </div>

  <div class="card">
    <h3>HARDWARE IDENTIFIERS</h3>
    <div class="info-grid">
      <span class="label">System Serial</span><span class="value">$SERIAL</span>
      <span class="label">Board Serial</span><span class="value">$BOARD_SERIAL</span>
      <span class="label">Asset Tag</span><span class="value">$ASSET_TAG</span>
      <span class="label">Chassis</span><span class="value">$CHASSIS_TYPE</span>
      <span class="label">Status</span>
      <span class="value" style="color:$(if (( SERIAL_OK )); then echo '#2ecc71'; else echo '#e74c3c'; fi)">
        $(if (( SERIAL_OK )); then echo "OK"; else echo "Placeholder detected"; fi)
      </span>
    </div>
  </div>

  <div class="card">
    <h3>OS &amp; SECURITY</h3>
    <div class="info-grid">
      <span class="label">OS</span><span class="value">$OS_NAME ($OS_ARCH)</span>
      <span class="label">Kernel</span><span class="value">$KERNEL</span>
      <span class="label">Firewall</span><span class="value">$FIREWALL</span>
      <span class="label">AppArmor</span><span class="value">$APPARMOR</span>
      <span class="label">SELinux</span><span class="value">$SELINUX</span>
      <span class="label">Disk Encrypt</span><span class="value">$DISK_ENCRYPT</span>
      <span class="label">TPM</span><span class="value">$TPM_VERSION</span>
      <span class="label">Secure Boot</span><span class="value">$SECURE_BOOT</span>
    </div>
  </div>

  <div class="card">
    <h3>NETWORK</h3>
    <div class="info-grid">
      <span class="label">Wi-Fi</span><span class="value">$WIFI_ADAPTER</span>
      <span class="label">Signal</span><span class="value">$WIFI_SIGNAL</span>
      <span class="label">Ethernet</span><span class="value">$ETH_ADAPTERS</span>
      <span class="label">Internet</span><span class="value">$(if (( INTERNET_OK )); then echo Connected; else echo Disconnected; fi)</span>
      <span class="label">Ping</span><span class="value">$PING_LATENCY</span>
    </div>
  </div>

  <div class="card">
    <h3>TEMPERATURE</h3>
    <div style="text-align:center;margin-bottom:8px">
      <span class="rating-badge" style="background:$TEMP_HEX">$TEMP_RATING</span>
    </div>
    <div class="info-grid">
      <span class="label">CPU Temp</span><span class="value" style="color:$TEMP_HEX">$(if [[ $TEMP != N/A ]]; then echo "${TEMP}°C"; else echo "N/A"; fi)</span>
      <span class="label">Fan</span><span class="value">$FAN</span>
    </div>
    <p style="color:#8892b0;font-size:10px;margin-top:8px">Limits: &lt;45°C=Excellent, &lt;65°C=Good, &lt;85°C=Poor</p>
  </div>

  <div class="card">
    <h3>PERIPHERALS</h3>
    <div class="info-grid">
      <span class="label">Webcam</span><span class="value">$WEBCAM</span>
      <span class="label">Bluetooth</span><span class="value">$BLUETOOTH</span>
      <span class="label">Audio</span><span class="value">$AUDIO</span>
      <span class="label">Keyboard</span><span class="value">$KEYBOARD</span>
      <span class="label">Touchpad</span><span class="value">$TOUCHPAD</span>
      <span class="label">USB Devices</span><span class="value">$USB_COUNT detected</span>
    </div>
  </div>

  <div class="card" style="grid-column: 1 / -1">
    <h3>DETAILED CHECK RESULTS</h3>
    <table>
      <tr><th>Status</th><th>Check</th><th>Weight</th><th>Detail</th></tr>
      $CHECK_ROWS_HTML
    </table>
  </div>

  </div><!-- /grid -->
  <div class="footer">Laptop Inspector v2.5 Linux Edition &mdash; $TIMESTAMP</div>
</div>
</body>
</html>
HTMLEOF

# ============================================================
#  FINISH
# ============================================================
echo -e "${C_CYAN}  Reports saved:${C_RESET}"
echo -e "${C_WHITE}    TXT  : $REPORT_TXT${C_RESET}"
echo -e "${C_WHITE}    HTML : $REPORT_HTML${C_RESET}"
echo ""

# Try to open HTML report
for opener in xdg-open open firefox chromium-browser google-chrome; do
    if cmd_exists "$opener"; then
        "$opener" "$REPORT_HTML" &>/dev/null & disown
        break
    fi
done

echo -e "${C_CYAN}  Done. Review the HTML report for a full breakdown.${C_RESET}"
echo ""
