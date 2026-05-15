#!/bin/bash
# ==============================================================================
#   Module:    touchpad.sh
#   Purpose:   Three touchpad concerns: natural scrolling (X11 xinput live +
#              persistent xorg.conf), and the imwheel 3x scroll multiplier.
#   Reads:     xinput list (touchpad detection)
#              SUDO_USER (optional), DISPLAY (defaults to :0)
#              REPO_DIR/skel/.imwheelrc
#   Writes:    /etc/X11/xorg.conf.d/40-chromebook-touchpad.conf
#              ~SUDO_USER/.imwheelrc (mode 644, owned by user)
#              runs: imwheel for SUDO_USER (background)
#   Step fn:   step_touchpad
#   Docs:      docs/modules/touchpad.md
#   Uninstall: step_uninstall purges imwheel (sub-step 2), pkills it
#              (sub-step 1), removes the xorg.conf snippet (sub-step 7),
#              removes per-user ~/.imwheelrc (sub-step 13) and
#              /etc/skel/.imwheelrc (sub-step 12).
#
#   NOTE: WHY IMWHEEL? libinput exposes no scroll-speed property —
#   AccelSpeed only affects cursor movement, not scroll delta. imwheel
#   intercepts X11 scroll events and re-emits them N times (N=3 per
#   skel/.imwheelrc). Most portable fix across Lenovo, Acer, HP, Dell,
#   Samsung Chromebook touchpads.
# ==============================================================================

step_touchpad() {
    echo "--> Configuring touchpad (natural scrolling + scroll speed)..."

    # -------------------------------------------------------------------------
    # 1. Detect touchpad for the live session and apply natural scrolling now.
    # -------------------------------------------------------------------------
    local TP_ID
    TP_ID=$(xinput list 2>/dev/null \
        | grep -iE 'touchpad|trackpad|synaptics|elan' \
        | grep -o 'id=[0-9]*' | head -1 | cut -d= -f2 || true)

    if [ -n "$TP_ID" ]; then
        echo "    [i] Touchpad detected: id=$TP_ID"
        xinput set-prop "$TP_ID" "libinput Natural Scrolling Enabled" 1 2>/dev/null || true
    else
        echo "    [!] No touchpad found via xinput — xorg.conf will apply on next login."
    fi

    # -------------------------------------------------------------------------
    # 2. Persistent xorg.conf.d snippet (survives reboot, applies to all users)
    #    HighResolutionWheelScrolling=false prevents scroll double-count on
    #    Chromebook HID touchpads (seen on HP, Lenovo, ELAN devices).
    # -------------------------------------------------------------------------
    mkdir -p /etc/X11/xorg.conf.d
    cat > /etc/X11/xorg.conf.d/40-chromebook-touchpad.conf << 'EOF'
Section "InputClass"
    Identifier      "chromebook-touchpad"
    MatchIsTouchpad "on"
    Driver          "libinput"
    Option "NaturalScrolling"              "true"
    Option "AccelProfile"                  "adaptive"
    Option "HighResolutionWheelScrolling"  "false"
    Option "Tapping"                       "on"
    Option "TappingDrag"                   "on"
    Option "DisableWhileTyping"            "on"
EndSection
EOF
    echo "    [+] /etc/X11/xorg.conf.d/40-chromebook-touchpad.conf written."

    # -------------------------------------------------------------------------
    # 3. imwheel scroll multiplier. The canonical config is skel/.imwheelrc
    #    (single source of truth); we copy it into the live oem user's home
    #    and (re)start imwheel so the technician sees the multiplier during
    #    QA. New users get it via /etc/skel on first login.
    # -------------------------------------------------------------------------
    if [ -n "${SUDO_USER:-}" ] && id "$SUDO_USER" &>/dev/null; then
        local USER_HOME
        USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

        install -m 644 -o "$SUDO_USER" -g "$SUDO_USER" \
            "$REPO_DIR/skel/.imwheelrc" "$USER_HOME/.imwheelrc"

        sudo -u "$SUDO_USER" pkill -x imwheel 2>/dev/null || true
        sudo -u "$SUDO_USER" \
            DISPLAY="${DISPLAY:-:0}" \
            XAUTHORITY="$USER_HOME/.Xauthority" \
            imwheel 2>/dev/null &

        echo "    [+] imwheel started for $SUDO_USER (3x scroll multiplier)."
    else
        echo "    [!] \$SUDO_USER not set — imwheel autostart on next login only."
    fi
}
