#!/bin/bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/var/lib/lubuntu-oem-setup}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/.state}"
MODULE_ID="13_touchpad_scroll_speed"

# libinput strictly limits ScrollPixelDistance to a range of [10, 50].
# 15 is the default. 50 is the maximum possible slowness.
# (Legacy synaptics accepted 100+, but libinput will reject it).
SCROLL_PIXEL_DISTANCE="${OEM_TOUCHPAD_SCROLL_PIXEL_DISTANCE:-30}"
SCROLL_FACTOR="${OEM_TOUCHPAD_SCROLL_FACTOR:-}"
SCROLL_CONF="/etc/X11/xorg.conf.d/91-touchpad-scroll-speed.conf"

is_done() { [ -f "$STATE_FILE" ] && grep -qxF "$MODULE_ID" "$STATE_FILE"; }
mark_done() { mkdir -p "$STATE_DIR"; grep -qxF "$MODULE_ID" "$STATE_FILE" || echo "$MODULE_ID" >> "$STATE_FILE"; }

if is_done; then
    echo "[${MODULE_ID}] Already completed — re-applying scroll settings."
fi

# Sanity check to prevent X11 crashes (integer out of range errors)
if [ "$SCROLL_PIXEL_DISTANCE" -gt 50 ]; then
    echo "    [!] Warning: libinput caps max distance at 50. Automatically capping value to 50."
    SCROLL_PIXEL_DISTANCE=50
elif [ "$SCROLL_PIXEL_DISTANCE" -lt 10 ]; then
    echo "    [!] Warning: libinput caps min distance at 10. Automatically rounding up to 10."
    SCROLL_PIXEL_DISTANCE=10
fi

echo "--> Slowing touchpad two-finger scroll (pointer movement unchanged)…"
echo "    [i] ScrollPixelDistance=${SCROLL_PIXEL_DISTANCE} (Valid range: 10-50, default is 15)."

mkdir -p /etc/X11/xorg.conf.d
{
    echo 'Section "InputClass"'
    echo '    Identifier      "oem-touchpad-scroll-speed"'
    echo '    MatchIsTouchpad "on"'
    echo '    Driver          "libinput"'
    echo "    Option \"ScrollPixelDistance\" \"${SCROLL_PIXEL_DISTANCE}\""
    if [ -n "$SCROLL_FACTOR" ]; then
        echo "    Option \"ScrollFactor\" \"${SCROLL_FACTOR}\""
        echo "    [i] Also setting ScrollFactor=${SCROLL_FACTOR} (may be ignored if unsupported)."
    fi
    echo 'EndSection'
} > "$SCROLL_CONF"
echo "    [+] ${SCROLL_CONF}"

apply_xinput_scroll() {
    local dev_id="$1"
    local did=0

    if xinput list-props "$dev_id" 2>/dev/null | grep -q 'Scrolling Pixel Distance'; then
        if xinput set-prop "$dev_id" "libinput Scrolling Pixel Distance" "${SCROLL_PIXEL_DISTANCE}" 2>/dev/null; then
            echo "    [+] Device ${dev_id}: Scrolling Pixel Distance=${SCROLL_PIXEL_DISTANCE}"
            did=1
        fi
    fi
    if [ -n "$SCROLL_FACTOR" ] && xinput list-props "$dev_id" 2>/dev/null | grep -q 'Scroll Factor'; then
        if xinput set-prop "$dev_id" "libinput Scroll Factor" "${SCROLL_FACTOR}" 2>/dev/null; then
            echo "    [+] Device ${dev_id}: Scroll Factor=${SCROLL_FACTOR}"
            did=1
        fi
    fi
    [ "$did" -eq 1 ]
}

# --- Live preview for technician session ---
if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    TECH_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
    TECH_UID=$(id -u "${SUDO_USER}")
    TECH_DISPLAY="${TECH_DISPLAY:-$(grep -z DISPLAY= /proc/"${TECH_UID}"/environ 2>/dev/null | tr '\0' '\n' | cut -d= -f2- || true)}"
    TECH_DISPLAY="${TECH_DISPLAY:-:0}"
    TECH_XAUTH="${TECH_XAUTH:-${TECH_HOME}/.Xauthority}"

    if [ -f "$TECH_XAUTH" ] && command -v xinput &>/dev/null; then
        echo "--> Applying scroll settings live (${SUDO_USER} on ${TECH_DISPLAY})…"
        export DISPLAY="$TECH_DISPLAY" XAUTHORITY="$TECH_XAUTH"
        applied=0
        while IFS= read -r dev_id; do
            if apply_xinput_scroll "$dev_id"; then
                applied=1
            fi
        done < <(xinput list --id-only 2>/dev/null || true)
        if [ "$applied" -eq 0 ]; then
            echo "    [!] No libinput scroll properties found on any device."
            echo "        After login, run: xinput list-props <id> | grep -i scroll"
            echo "        Then log out/in so ${SCROLL_CONF} is loaded by X."
        fi
    else
        echo "    [i] Log out and back in (or reboot) so X loads ${SCROLL_CONF}."
    fi
else
    echo "    [i] Log out and back in (or reboot) so X loads ${SCROLL_CONF}."
fi

echo ""
echo "    Quick tune (desktop session):"
echo "      xinput list"
echo "      xinput list-props <touchpad-id> | grep -i scroll"
echo "      xinput set-prop <id> \"libinput Scrolling Pixel Distance\" 30"
echo "    Re-apply module: sudo OEM_TOUCHPAD_SCROLL_PIXEL_DISTANCE=30 bash modules/13_touchpad_scroll_speed.sh"
echo ""

mark_done
echo "[${MODULE_ID}] Done."