#!/bin/bash
set -euo pipefail

STATE_DIR="${STATE_DIR:-/var/lib/lubuntu-oem-setup}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/.state}"
MODULE_ID="13_touchpad_scroll_speed"

# Scroll delta multiplier for libinput touchpads only (< 1.0 = slower two-finger scroll).
# Override at run time: sudo OEM_TOUCHPAD_SCROLL_FACTOR=0.3 bash modules/13_touchpad_scroll_speed.sh
SCROLL_FACTOR="${OEM_TOUCHPAD_SCROLL_FACTOR:-0.4}"
SCROLL_CONF="/etc/X11/xorg.conf.d/91-touchpad-scroll-speed.conf"

is_done() { [ -f "$STATE_FILE" ] && grep -qxF "$MODULE_ID" "$STATE_FILE"; }
mark_done() { mkdir -p "$STATE_DIR"; grep -qxF "$MODULE_ID" "$STATE_FILE" || echo "$MODULE_ID" >> "$STATE_FILE"; }

if is_done; then
    echo "[${MODULE_ID}] Already completed — skipping."
    exit 0
fi

echo "--> Slowing touchpad two-finger scroll (pointer movement unchanged)…"
echo "    [i] Using libinput ScrollFactor=${SCROLL_FACTOR} (default wheel/mouse devices unaffected)."

mkdir -p /etc/X11/xorg.conf.d
cat > "$SCROLL_CONF" <<EOF
Section "InputClass"
    Identifier      "oem-touchpad-scroll-speed"
    MatchIsTouchpad "on"
    Driver          "libinput"
    Option "ScrollFactor" "${SCROLL_FACTOR}"
EndSection
EOF
echo "    [+] ${SCROLL_CONF}"

# --- OPTIONAL LIVE PREVIEW FOR TECHNICIAN (X11 session) ---
if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    TECH_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
    TECH_UID=$(id -u "${SUDO_USER}")
    TECH_DISPLAY="${TECH_DISPLAY:-$(grep -z DISPLAY= /proc/"${TECH_UID}"/environ 2>/dev/null | tr '\0' '\n' | cut -d= -f2- || true)}"
    TECH_DISPLAY="${TECH_DISPLAY:-:0}"
    TECH_XAUTH="${TECH_XAUTH:-${TECH_HOME}/.Xauthority}"

    if [ -f "$TECH_XAUTH" ] && command -v xinput &>/dev/null; then
        echo "--> Applying scroll factor to active session for QA (${SUDO_USER} on ${TECH_DISPLAY})…"
        export DISPLAY="$TECH_DISPLAY" XAUTHORITY="$TECH_XAUTH"
        applied=0
        while IFS= read -r dev_id; do
            if xinput list-props "$dev_id" 2>/dev/null | grep -q 'libinput Scroll Factor'; then
                if xinput set-prop "$dev_id" "libinput Scroll Factor" "${SCROLL_FACTOR}" 2>/dev/null; then
                    applied=1
                fi
            fi
        done < <(xinput list --id-only 2>/dev/null || true)
        if [ "$applied" -eq 1 ]; then
            echo "    [+] Live scroll factor applied (no reboot needed for this test)."
        else
            echo "    [i] Could not set live property; log out/in or reboot for ${SCROLL_CONF} to take effect."
        fi
    else
        echo "    [i] Log out and back in (or reboot) so X picks up ${SCROLL_CONF}."
    fi
else
    echo "    [i] Log out and back in (or reboot) so X picks up ${SCROLL_CONF}."
fi
# -----------------------------------------------------------

echo ""
echo "    Tune before re-running module:"
echo "      xinput list"
echo "      xinput list-props <touchpad-id> | grep -i scroll"
echo "      xinput set-prop <touchpad-id> \"libinput Scroll Factor\" 0.3   # try 0.25–0.6"
echo "    Persist: edit ScrollFactor in ${SCROLL_CONF}, then re-login."
echo ""

mark_done
echo "[${MODULE_ID}] Done."
