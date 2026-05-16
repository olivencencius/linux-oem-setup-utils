#!/bin/bash
# ==============================================================================
#   Module:    diagnostics.sh
#   Purpose:   Automatic hardware / deployment QA report: inventory,
#              best-effort functional probes, and a printed manual-only list.
#              Writes /var/lib/oem-setup/diagnostics-report.txt (plain text).
#   Reads:     sysfs, /proc, lscpu, lsblk, lsusb, lspci, pactl, nmcli,
#              systemctl, xinput (best-effort), DMI, initramfs listing.
#   Writes:    /var/lib/oem-setup/diagnostics-report.txt
#   Step fn:   step_diagnostics
#   Docs:      docs/modules/diagnostics.md
#   Uninstall: step_uninstall removes diagnostics-report.txt (same dir as state).
#
#   IMPORTANT: This step NEVER raises — every probe uses || true patterns so
#              [FAIL] lines never abort the pipeline under set -e. Exit code
#              is always 0 from step_diagnostics.
#
#   IMPORTANT: Fully automatic — no prompts.
# ==============================================================================

step_diagnostics() {
    mkdir -p /var/lib/oem-setup

    local REPORT="/var/lib/oem-setup/diagnostics-report.txt"
    local PASS_COUNT=0 WARN_COUNT=0 FAIL_COUNT=0 MANUAL_COUNT=0

    local C_PASS="" C_WARN="" C_FAIL="" C_DIM="" C_RST=""
    if [ -t 1 ]; then
        C_PASS=$'\033[32m'
        C_WARN=$'\033[33m'
        C_FAIL=$'\033[31m'
        C_DIM=$'\033[90m'
        C_RST=$'\033[0m'
    fi

    # Plain line to file; coloured line to terminal when TTY.
    _diag_line() {
        local plain="$1"
        local colour="$2"
        printf '%s\n' "$plain" >> "$REPORT"
        if [ -n "$colour" ]; then
            printf '%b%s%b\n' "$colour" "$plain" "$C_RST"
        else
            printf '%s\n' "$plain"
        fi
    }

    _diag_hdr() {
        echo ""
        echo "-- $1"
        printf '%s\n' "" >> "$REPORT"
        printf '%s\n' "-- $1" >> "$REPORT"
    }

    _oem_runtime_dir() {
        if [ -n "${SUDO_USER:-}" ] && id "$SUDO_USER" &>/dev/null; then
            printf '/run/user/%s' "$(id -u "$SUDO_USER")"
        fi
    }

    _pactl() {
        local rt="$(_oem_runtime_dir || true)"
        if [ -n "${SUDO_USER:-}" ] && id "$SUDO_USER" &>/dev/null; then
            sudo -u "$SUDO_USER" env \
                XDG_RUNTIME_DIR="${rt:-}" \
                pactl "$@" 2>/dev/null
        else
            pactl "$@" 2>/dev/null
        fi
    }

    _xinput_list() {
        if [ -n "${SUDO_USER:-}" ] && id "$SUDO_USER" &>/dev/null; then
            local home
            home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
            sudo -u "$SUDO_USER" env \
                DISPLAY="${DISPLAY:-:0}" \
                XAUTHORITY="${home}/.Xauthority" \
                xinput list 2>/dev/null
        else
            DISPLAY="${DISPLAY:-:0}" xinput list 2>/dev/null
        fi
    }

    _xrandr_query() {
        if [ -n "${SUDO_USER:-}" ] && id "$SUDO_USER" &>/dev/null; then
            local home
            home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
            sudo -u "$SUDO_USER" env \
                DISPLAY="${DISPLAY:-:0}" \
                XAUTHORITY="${home}/.Xauthority" \
                xrandr --query 2>/dev/null
        else
            DISPLAY="${DISPLAY:-:0}" xrandr --query 2>/dev/null
        fi
    }

    _result() {
        local level="$1"
        local msg="$2"
        local hint="${3:-}"
        local plain tag colour=""
        case "$level" in
            PASS) tag="[PASS]"; colour="$C_PASS"; PASS_COUNT=$((PASS_COUNT + 1)) ;;
            WARN) tag="[WARN]"; colour="$C_WARN"; WARN_COUNT=$((WARN_COUNT + 1)) ;;
            FAIL) tag="[FAIL]"; colour="$C_FAIL"; FAIL_COUNT=$((FAIL_COUNT + 1)) ;;
            INFO) tag="[INFO]"; colour="$C_DIM" ;;
            *)    tag="[$level]" ;;
        esac
        plain="$tag $msg"
        [ -n "$hint" ] && plain="$plain — $hint"
        _diag_line "$plain" "$colour"
    }

    : > "$REPORT"

    echo "--> OEM diagnostics report (automatic, non-interactive)..."
    _diag_line "=== OEM diagnostics === $(date -Iseconds)" ""

    # ----- Section A: Inventory -----
    _diag_hdr "System"
    if [ -r /sys/class/dmi/id/sys_vendor ]; then
        _diag_line "  Vendor: $(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)" ""
    fi
    if [ -r /sys/class/dmi/id/product_name ]; then
        _diag_line "  Product: $(cat /sys/class/dmi/id/product_name 2>/dev/null)" ""
    fi
    if [ -r /sys/class/dmi/id/bios_version ]; then
        _diag_line "  BIOS: $(cat /sys/class/dmi/id/bios_version 2>/dev/null)" ""
    fi
    _diag_line "  Kernel: $(uname -r 2>/dev/null)" ""
    if command -v lsb_release &>/dev/null; then
        _diag_line "  OS: $(lsb_release -ds 2>/dev/null)" ""
    fi
    _diag_line "  Uptime: $(uptime -p 2>/dev/null || uptime 2>/dev/null)" ""

    _diag_hdr "CPU"
    if command -v lscpu &>/dev/null; then
        while IFS= read -r line; do
            [[ "$line" =~ Model\ name:|CPU\(s\):|Thread|Core|Socket|CPU\ max\ MHz ]] \
                && _diag_line "  $line" ""
        done < <(lscpu 2>/dev/null || true)
    else
        _diag_line "  (lscpu not available)" ""
    fi

    _diag_hdr "RAM"
    if [ -r /proc/meminfo ]; then
        _diag_line "  $(grep -E '^MemTotal:|^MemAvailable:' /proc/meminfo 2>/dev/null | tr '\n' ' ')" ""
    fi
    if command -v dmidecode &>/dev/null; then
        local dimm_out
        dimm_out=$(dmidecode -t memory 2>/dev/null \
            | grep -E '^\s*(Size|Locator|Speed|Type|Manufacturer):' \
            | head -80 || true)
        if [ -n "$dimm_out" ]; then
            _diag_line "  DIMMs (dmidecode):" ""
            while IFS= read -r line; do
                _diag_line "    $line" ""
            done <<< "$dimm_out"
        else
            _diag_line "  (no DIMM info from dmidecode)" ""
        fi
    else
        _diag_line "  (dmidecode not installed — DIMM details skipped)" ""
    fi

    _diag_hdr "Storage"
    if command -v lsblk &>/dev/null; then
        while IFS= read -r line; do
            _diag_line "  $line" ""
        done < <(lsblk -dnbo NAME,SIZE,MODEL,TYPE,ROTA 2>/dev/null | grep 'disk$' || true)
    fi
    _diag_line "  Root fs: $(df -h / 2>/dev/null | tail -1)" ""
    for blk in /sys/block/mmcblk*/device/type /sys/block/nvme*/queue/rotational; do
        [ -e "$blk" ] || continue
        :
    done

    _diag_hdr "Battery / AC"
    local bat_found=0
    for bat in /sys/class/power_supply/BAT*; do
        [ -e "$bat" ] || continue
        bat_found=1
        local name cap st ef efd health=""
        name=$(basename "$bat")
        cap="$(cat "$bat/capacity" 2>/dev/null || echo "?")"
        st="$(cat "$bat/status" 2>/dev/null || echo "?")"
        ef="$(cat "$bat/energy_full" 2>/dev/null || true)"
        efd="$(cat "$bat/energy_full_design" 2>/dev/null || true)"
        if [ -n "$ef" ] && [ -n "$efd" ] && [ "$efd" != "0" ]; then
            health=$((100 * ef / efd))
            _diag_line "  $name: ${cap}% ($st), health ~${health}% (energy_full/design)" ""
        else
            _diag_line "  $name: ${cap}% ($st)" ""
        fi
    done
    if [ "$bat_found" = "0" ]; then
        _diag_line "  (no BAT* power_supply — desktop or unknown ACPI)" ""
    fi
    for ac in /sys/class/power_supply/AC* /sys/class/power_supply/ADP*; do
        [ -e "$ac" ] || continue
        _diag_line "  $(basename "$ac") online: $(cat "$ac/online" 2>/dev/null || echo "?")" ""
    done

    _diag_hdr "GPU / display"
    if command -v lspci &>/dev/null; then
        while IFS= read -r line; do
            _diag_line "  $line" ""
        done < <(lspci -nnk 2>/dev/null | grep -iE 'vga|3d|display' -A2 || true)
    fi
    local bl_count=0
    for _ in /sys/class/backlight/*/brightness; do
        [ -e "$_" ] || continue
        bl_count=$((bl_count + 1))
    done
    _diag_line "  Backlight sysfs entries: $bl_count" ""
    local xr_out
    xr_out="$(_xrandr_query || true)"
    if [ -n "$xr_out" ]; then
        _diag_line "  xrandr (connected):" ""
        while IFS= read -r line; do
            [[ "$line" =~ connected ]] && _diag_line "    $line" ""
        done <<< "$xr_out"
    else
        _diag_line "  xrandr: (no display session / failed)" ""
    fi

    _diag_hdr "USB / Type-C"
    local usb_devs=0
    if command -v lsusb &>/dev/null; then
        usb_devs=$(lsusb 2>/dev/null | wc -l)
    fi
    _diag_line "  lsusb devices (enumerated buses): $usb_devs" ""
    local tc_ports=0
    for _ in /sys/class/typec/port*/; do
        [ -e "$_" ] || continue
        tc_ports=$((tc_ports + 1))
    done
    _diag_line "  Kernel Type-C ports (/sys/class/typec/port*): $tc_ports" ""

    _diag_hdr "Audio (inventory)"
    local sinks_short sources_short
    sinks_short="$(_pactl list short sinks 2>/dev/null || true)"
    sources_short="$(_pactl list short sources 2>/dev/null | grep -vi monitor || true)"
    _diag_line "  Sinks ($(echo "$sinks_short" | grep -c . || echo 0)):" ""
    while IFS= read -r line; do
        [ -n "$line" ] && _diag_line "    $line" ""
    done <<< "$sinks_short"
    _diag_line "  Sources (non-monitor):" ""
    while IFS= read -r line; do
        [ -n "$line" ] && _diag_line "    $line" ""
    done <<< "$sources_short"
    local hp_pin_total=0
    shopt -s nullglob
    for cf in /proc/asound/card*/codec#*; do
        [ -f "$cf" ] || continue
        local n
        n=$(grep -c Headphone "$cf" 2>/dev/null || echo 0)
        hp_pin_total=$((hp_pin_total + n))
    done
    shopt -u nullglob
    local pactl_jacks=0
    pactl_jacks=$(_pactl list cards 2>/dev/null | grep -ic jack || true)
    _diag_line "  Codec 'Headphone' lines (sum): $hp_pin_total; pactl cards 'jack' mentions: $pactl_jacks" ""

    _diag_hdr "Camera"
    shopt -s nullglob
    local vc=0
    for dev in /dev/video*; do
        [ -e "$dev" ] || continue
        vc=$((vc + 1))
    done
    _diag_line "  /dev/video* nodes: $vc" ""
    for v4l in /sys/class/video4linux/video*; do
        [ -e "$v4l" ] || continue
        local vn drv
        vn="$(cat "$v4l/name" 2>/dev/null || echo "?")"
        drv=""
        if [ -r "$v4l/device/uevent" ]; then
            drv=$(grep '^DRIVER=' "$v4l/device/uevent" 2>/dev/null | cut -d= -f2 || true)
        fi
        _diag_line "    $(basename "$v4l"): name=$vn driver=${drv:-?}" ""
    done
    shopt -u nullglob

    _diag_hdr "Network"
    if command -v nmcli &>/dev/null; then
        while IFS= read -r line; do
            _diag_line "  $line" ""
        done < <(nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device 2>/dev/null || true)
    else
        _diag_line "  (nmcli not available)" ""
    fi
    local bt_hci=0
    for _ in /sys/class/bluetooth/hci*; do
        [ -e "$_" ] || continue
        bt_hci=$((bt_hci + 1))
    done
    _diag_line "  Bluetooth hci adapters (sysfs): $bt_hci" ""
    if command -v rfkill &>/dev/null; then
        _diag_line "  rfkill bluetooth:" ""
        while IFS= read -r line; do
            _diag_line "    $line" ""
        done < <(rfkill list bluetooth 2>/dev/null || true)
    fi

    _diag_hdr "Input (best-effort)"
    local xi
    xi="$(_xinput_list || true)"
    if [ -n "$xi" ]; then
        local tp kb ptr
        tp=$(echo "$xi" | grep -ciE 'touchpad|trackpad' || true)
        kb=$(echo "$xi" | grep -ci 'keyboard' || true)
        ptr=$(echo "$xi" | grep -ci 'pointer' || true)
        _diag_line "  xinput: touchpad-ish=$tp keyboard=$kb pointer=$ptr" ""
        while IFS= read -r line; do
            _diag_line "    $line" ""
        done <<< "$xi"
    else
        _diag_line "  xinput: (no session / failed)" ""
    fi

    _diag_hdr "Sensors / lid"
    if compgen -G '/proc/acpi/button/lid/*/state' &>/dev/null; then
        for lf in /proc/acpi/button/lid/*/state; do
            _diag_line "  $lf → $(cat "$lf" 2>/dev/null)" ""
        done
    else
        _diag_line "  (no ACPI lid button nodes)" ""
    fi
    if compgen -G '/sys/bus/iio/devices/iio:device*/name' &>/dev/null; then
        for io in /sys/bus/iio/devices/iio:device*/name; do
            _diag_line "  $(dirname "$io"): $(cat "$io" 2>/dev/null)" ""
        done
    fi

    # ----- Section B: Auto checks -----
    _diag_hdr "Automated checks"

    local board=""
    [ -r /sys/class/dmi/id/product_name ] \
        && board=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)

    # Audio output
    local pactl_ok=0 def_sink="" mute_line=""
    if _pactl info &>/dev/null; then
        pactl_ok=1
        def_sink="$(_pactl info 2>/dev/null | awk -F': ' '/^Default Sink:/{print $2; exit}' || true)"
        mute_line="$(_pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null || true)"
    fi
    if [ "$pactl_ok" != "1" ]; then
        _result WARN "Audio stack (pactl)" "cannot query PipeWire/Pulse as root — log in as oem or check user session; see docs/handover-qa.md"
    elif [ -z "$def_sink" ]; then
        _result FAIL "Default audio sink" "re-run menu option 4 (hardware fixes) and reboot"
    elif echo "$def_sink" | grep -qi null; then
        _result FAIL "Default sink is null (${def_sink})" "re-run menu option 4 (hardware fixes) and reboot"
    elif echo "$mute_line" | grep -qi 'yes'; then
        _result WARN "Default sink is muted" "unmute in Sound settings or pactl"
    else
        _result PASS "Default audio sink present and not muted (${def_sink})" ""
    fi

    # Microphone
    local def_src=""
    if [ "$pactl_ok" = "1" ]; then
        def_src="$(_pactl info 2>/dev/null | awk -F': ' '/^Default Source:/{print $2; exit}' || true)"
        local src_mute
        src_mute="$(_pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null || true)"
        if [ -z "$def_src" ]; then
            _result FAIL "Default microphone source" "re-run menu option 4 and reboot"
        elif echo "$def_src" | grep -qi null; then
            _result FAIL "Default source is null (${def_src})" "re-run menu option 4 and reboot"
        elif echo "$src_mute" | grep -qi 'yes'; then
            _result WARN "Default source is muted" "unmute input in Sound settings"
        else
            _result PASS "Default capture source OK (${def_src})" ""
        fi
    fi

    # keyd / top-row map
    if systemctl is-active --quiet keyd 2>/dev/null \
        && compgen -G '/etc/keyd/*.conf' &>/dev/null; then
        _result PASS "keyd active with config under /etc/keyd/" ""
    elif systemctl is-active --quiet keyd 2>/dev/null; then
        _result WARN "keyd active but no /etc/keyd/*.conf found" "verify cros-keyboard-map install"
    else
        _result FAIL "keyd not active" "re-run menu option 4 (keyboard installer)"
    fi

    # Touchpad
    local xi2 tp_id
    xi2="$(_xinput_list || true)"
    tp_id=$(echo "$xi2" | grep -iE 'touchpad|trackpad|synaptics|elan' \
        | grep -o 'id=[0-9]*' | head -1 | cut -d= -f2 || true)
    if [ -f /etc/X11/xorg.conf.d/40-chromebook-touchpad.conf ] \
        && [ -n "$tp_id" ]; then
        _result PASS "Touchpad config + xinput detection (id=$tp_id)" ""
    elif [ -f /etc/X11/xorg.conf.d/40-chromebook-touchpad.conf ]; then
        _result WARN "Touchpad xorg snippet present but xinput did not find a touchpad" "re-login or check X session"
    else
        _result FAIL "Chromebook touchpad xorg snippet missing" "re-run menu option 10"
    fi

    # Webcam
    local vid_count=0
    shopt -s nullglob
    for _ in /dev/video*; do
        [ -e "$_" ] || continue
        vid_count=$((vid_count + 1))
    done
    shopt -u nullglob
    local cam_mod=0
    if lsmod 2>/dev/null | awk 'NR>1 {print $1}' | grep -qxiE 'uvcvideo|gc2145|intel_ipu6|intel_ipu3|imgu'; then
        cam_mod=1
    elif lsmod 2>/dev/null | awk 'NR>1 {print $1}' | grep -qiE 'ipu|camer|cras'; then
        cam_mod=1
    fi
    if [ "$vid_count" -ge 1 ] && [ "$cam_mod" = "1" ]; then
        _result PASS "Video devices ($vid_count) and camera-related kernel module loaded" ""
    elif [ "$vid_count" -ge 1 ]; then
        _result WARN "Video nodes present ($vid_count) but no common camera module matched in lsmod" "may be non-UVC; verify in Cheese"
    else
        _result FAIL "No /dev/video* nodes" "check cabling / drivers / reboot after option 4"
    fi

    # USB-C modules + initramfs on Tiger/Alder
    if echo "${board:-}" | grep -qi celes || dmesg 2>/dev/null | grep -qi celes; then
        if grep -q 'clocksource=hpet' /proc/cmdline 2>/dev/null; then
            _result PASS "CELES: HPET kernel params active in cmdline" ""
        else
            _result FAIL "CELES board but HPET params missing from /proc/cmdline" "re-run menu option 4 and reboot"
        fi
    fi

    if command -v lscpu &>/dev/null && lscpu 2>/dev/null | grep -qiE 'tiger|alder'; then
        local has_ct has_mux init_ok=0
        has_ct=0
        has_mux=0
        lsmod 2>/dev/null | awk '{print $1}' | grep -qxi cros_ec_typec && has_ct=1
        lsmod 2>/dev/null | awk '{print $1}' | grep -qxi intel_pmc_mux && has_mux=1
        local initrd="/boot/initrd.img-$(uname -r)"
        [ ! -f "$initrd" ] && initrd="/boot/initrd.img"
        if [ -f "$initrd" ] && command -v lsinitramfs &>/dev/null; then
            if lsinitramfs "$initrd" 2>/dev/null | grep -qE 'cros-ec-typec|intel-pmc-mux'; then
                init_ok=1
            fi
        fi
        if [ "$has_ct" = "1" ] && [ "$has_mux" = "1" ]; then
            if [ "$init_ok" = "1" ]; then
                _result PASS "Tiger/Alder: Type-C modules loaded and present in initramfs" ""
            else
                _result WARN "Tiger/Alder: modules loaded but initramfs probe inconclusive" "run sudo update-initramfs -u -k all and reboot"
            fi
        else
            _result FAIL "Tiger/Alder: cros_ec_typec/intel_pmc_mux not both loaded" "re-run menu option 4, update-initramfs, reboot"
        fi
        if ! grep -qx 'cros-ec-typec' /etc/initramfs-tools/modules 2>/dev/null; then
            _result WARN "/etc/initramfs-tools/modules missing cros-ec-typec line" "re-run option 4"
        fi
        if ! grep -qx 'intel-pmc-mux' /etc/initramfs-tools/modules 2>/dev/null; then
            _result WARN "/etc/initramfs-tools/modules missing intel-pmc-mux line" "re-run option 4"
        fi
    fi

    # TLP / ZRAM / touchegg  (TLP is typically Type=oneshot — "enabled" is the meaningful signal)
    if systemctl is-enabled --quiet tlp.service 2>/dev/null; then
        _result PASS "TLP unit is enabled" ""
    else
        _result FAIL "TLP unit not enabled" "re-run menu option 2 (updates)"
    fi

    if command -v zramctl &>/dev/null && zramctl --noheadings 2>/dev/null | grep -q .; then
        _result PASS "ZRAM device(s) present" ""
    else
        _result WARN "zramctl empty or missing" "check zram-tools / reboot"
    fi

    if systemctl is-active --quiet touchegg.service 2>/dev/null; then
        _result PASS "touchegg.service active" ""
    else
        _result FAIL "touchegg.service not active" "re-run menu option 11"
    fi

    # Web apps — 13 desktop files
    local webapps=(
        Netflix PrimeVideo DisneyPlus HBOMax Spotify YouTube
        Gmail GoogleDocs GoogleSheets GoogleSlides GoogleDrive Gemini ChromeRemoteDesktop
    )
    local w_ok=0
    for w in "${webapps[@]}"; do
        [ -f "/usr/share/applications/${w}.desktop" ] && w_ok=$((w_ok + 1))
    done
    if [ "$w_ok" -eq 13 ]; then
        _result PASS "All 13 web-app .desktop files present" ""
    else
        _result FAIL "Web-app shortcuts: $w_ok/13 present" "re-run menu option 8"
    fi

    if [ -f /usr/share/backgrounds/oem-setup/malta.jpg ]; then
        _result PASS "OEM wallpaper installed" ""
    else
        _result FAIL "OEM wallpaper missing" "re-run menu option 9"
    fi

    if [ -f /usr/share/applications/oem-powerwash.desktop ] \
        && pkaction --action-id org.linuxoem.powerwash.arm &>/dev/null; then
        _result PASS "Powerwash desktop entry + polkit action registered" ""
    else
        _result FAIL "Powerwash shortcut or polkit action missing" "re-run menu option 14"
    fi

    if [ -r /sys/power/state ] && grep -qw mem /sys/power/state 2>/dev/null; then
        _result PASS "Suspend (mem) advertised by kernel" ""
    else
        _result WARN "Suspend state unclear" "check /sys/power/state"
    fi

    local bw_ok=0
    for b in /sys/class/backlight/*/brightness; do
        [ -w "$b" ] && bw_ok=1 && break
    done
    if [ "$bw_ok" = "1" ]; then
        _result PASS "At least one backlight brightness control is writable" ""
    else
        _result WARN "No writable backlight sysfs node" "may be external-only display"
    fi

    # ----- Section C: Manual-only -----
    _diag_hdr "Manual-only checks (human required)"
    MANUAL_COUNT=8
    _diag_line "  The following cannot be verified automatically. See docs/handover-qa.md." ""
    _diag_line "  [MANUAL] Speakers actually produce sound (e.g. YouTube in Chrome)." ""
    _diag_line "  [MANUAL] Headphone jack switches output when 3.5mm plug is inserted." ""
    _diag_line "  [MANUAL] Each top-row key performs the expected action in the browser/OS." ""
    _diag_line "  [MANUAL] Each USB-A port detects and mounts a thumb drive." ""
    _diag_line "  [MANUAL] USB-C port detects a thumb drive after reboot (Tiger/Alder)." ""
    _diag_line "  [MANUAL] Webcam shows a live image (e.g. Cheese)." ""
    _diag_line "  [MANUAL] Closing the lid suspends; opening resumes." ""
    _diag_line "  [MANUAL] Wi-Fi reconnects after suspend/resume cycle." ""

    echo ""
    local summ="Summary: ${PASS_COUNT} PASS, ${WARN_COUNT} WARN, ${FAIL_COUNT} FAIL, ${MANUAL_COUNT} MANUAL"
    _diag_line "$summ" "$C_DIM"
    _diag_line "Report saved to: $REPORT" "$C_DIM"

    echo ""
    echo "    [+] Diagnostics complete (exit 0 by design — inspect [FAIL] lines above)."
    return 0
}
