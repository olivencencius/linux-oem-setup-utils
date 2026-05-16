#!/bin/bash
# ==============================================================================
#   Module:    touchpad.sh
#   Purpose:   Touchpad tuning: natural scrolling, slower two-finger scroll,
#              tap-to-click, and clickfinger (1-finger / 2-finger physical
#              press = left / right anywhere — not left/right tap zones).
#   Reads:     xinput list (touchpad detection)
#              SUDO_USER (optional), DISPLAY (defaults to :0)
#   Writes:    /etc/X11/xorg.conf.d/40-chromebook-touchpad.conf
#              (live) xinput set-prop on the detected touchpad
#   Step fn:   step_touchpad
#   Docs:      docs/modules/touchpad.md
#   Uninstall: step_uninstall removes the xorg.conf snippet (sub-step 7).
#              imwheel cleanup also stays in step_uninstall for the benefit
#              of users who installed earlier revisions of this toolkit.
#
#   NOTE — WHY SCROLLPIXELDISTANCE? libinput's xorg driver exposes
#   `Option "ScrollPixelDistance" "N"` (5..150, default ~15). It is the
#   distance in pixels a finger has to travel on the touchpad to emit one
#   scroll event. INCREASING it makes scrolling SLOWER, which is exactly
#   what the OEM setup wants. The same knob is reachable live via the
#   xinput property "libinput Scrolling Pixel Distance".
#
#   We deliberately do NOT ship imwheel anymore. imwheel can only
#   *multiply* scroll events (faster), never divide them, and our previous
#   3x setting was the opposite of what we want.
# ==============================================================================

# Pixels of finger travel that map to one scroll event. Default is ~15.
# Higher = slower scroll. 40 was picked as a comfortable browser feel on
# Lenovo / HP / Acer Chromebook touchpads — bump it higher (e.g. 60) for
# even slower scroll, or lower toward the libinput default of 15 for
# faster.
OEM_SCROLL_PIXEL_DISTANCE=40

step_touchpad() {
    echo "--> Configuring touchpad (natural scroll, slower scroll, tap-to-click, clickfinger)..."

    # -------------------------------------------------------------------------
    # 1. Persistent xorg.conf.d snippet (survives reboot, applies to all users
    #    and to the buyer when they create their account).
    # -------------------------------------------------------------------------
    mkdir -p /etc/X11/xorg.conf.d
    cat > /etc/X11/xorg.conf.d/40-chromebook-touchpad.conf << EOF
Section "InputClass"
    Identifier      "chromebook-touchpad"
    MatchIsTouchpad "on"
    Driver          "libinput"
    Option "NaturalScrolling"      "true"
    Option "AccelProfile"          "adaptive"
    Option "Tapping"               "on"
    Option "TappingDrag"           "on"
    Option "ClickMethod"           "clickfinger"
    Option "DisableWhileTyping"    "on"
    # Higher = slower scroll. Default ~15. See modules/touchpad.sh
    # (OEM_SCROLL_PIXEL_DISTANCE) to change the canonical value.
    Option "ScrollPixelDistance"   "${OEM_SCROLL_PIXEL_DISTANCE}"
EndSection
EOF
    echo "    [+] /etc/X11/xorg.conf.d/40-chromebook-touchpad.conf written"
    echo "        (ScrollPixelDistance=${OEM_SCROLL_PIXEL_DISTANCE} → slower than default)"

    # -------------------------------------------------------------------------
    # 2. Live-session apply — find the touchpad and push the same values
    #    via xinput so the technician feels the slower scroll immediately
    #    without waiting for an X restart.
    # -------------------------------------------------------------------------
    local TP_ID
    TP_ID=$(xinput list 2>/dev/null \
        | grep -iE 'touchpad|trackpad|synaptics|elan' \
        | grep -o 'id=[0-9]*' | head -1 | cut -d= -f2 || true)

    if [ -n "$TP_ID" ]; then
        echo "    [i] Touchpad detected: id=$TP_ID — applying live"
        xinput set-prop "$TP_ID" "libinput Natural Scrolling Enabled" 1 \
            2>/dev/null || true
        xinput set-prop "$TP_ID" "libinput Tapping Enabled" 1 \
            2>/dev/null || true
        xinput set-prop "$TP_ID" "libinput Click Method Enabled" 0 1 \
            2>/dev/null \
            || echo "    [!] 'libinput Click Method Enabled' not exposed by this driver"
        xinput set-prop "$TP_ID" "libinput Scrolling Pixel Distance" \
            "$OEM_SCROLL_PIXEL_DISTANCE" 2>/dev/null \
            || echo "    [!] 'libinput Scrolling Pixel Distance' not exposed by this driver"
        echo "    [+] Live touchpad properties applied"
    else
        echo "    [!] No touchpad found via xinput — xorg.conf will apply on next login."
    fi
}
