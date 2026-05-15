#!/bin/bash
# ==============================================================================
#   Module:    powerwash.sh
#   Purpose:   Install the buyer-facing "factory reset" feature. This is just
#              the INSTALL step — the end-to-end flow (menu → polkit → arm →
#              boot finalize) is documented in docs/powerwash.md.
#   Reads:     REPO_DIR/assets/scripts/oem-powerwash{,-arm,-finalize}.sh
#              REPO_DIR/assets/configs/oem-powerwash{.desktop,.policy,
#                                                    -finalize.service}
#              REPO_DIR/assets/icons/oem-powerwash.svg
#              helpers: ensure_apt_fresh
#   Writes:    apt: zenity, policykit-1, oem-config-gtk
#              /usr/local/bin/oem-powerwash.sh                       (755)
#              /usr/local/sbin/oem-powerwash-arm.sh                  (700)
#              /usr/local/sbin/oem-powerwash-finalize.sh             (700)
#              /etc/systemd/system/oem-powerwash-finalize.service    (644)
#              /usr/share/applications/oem-powerwash.desktop         (644)
#              /usr/share/polkit-1/actions/org.linuxoem.powerwash.policy (644)
#              /usr/share/icons/hicolor/scalable/apps/oem-powerwash.svg
#              /var/lib/oem-setup/                                   (directory)
#              systemd: daemon-reload, disable oem-powerwash-finalize.service
#                       (stays inert until the arm script enables it)
#   Step fn:   step_powerwash
#   Docs:      docs/modules/powerwash.md   (this module)
#              docs/powerwash.md           (end-to-end multi-stage flow)
#   Uninstall: step_uninstall sub-step 8b removes every file listed above and
#              the runtime flag at /var/lib/oem-setup/powerwash.flag.
#              zenity / policykit-1 / oem-config-gtk are NOT purged — they
#              are commonly part of Mint OEM images already.
#
#   NOTE: This module never ENABLES the finalize service. The buyer's
#   pkexec-gated arm script does that, only after two zenity confirmations
#   and admin auth.
# ==============================================================================

step_powerwash() {
    echo "--> Installing Powerwash (factory reset) tool..."

    ensure_apt_fresh

    # -------------------------------------------------------------------------
    # Runtime dependencies
    #   - zenity:           GUI confirmation dialogs
    #   - policykit-1:      pkexec + admin auth prompt
    #   - oem-config-gtk:   provides oem-config-prepare and the first-boot
    #                       wizard the buyer is sent back to
    # -------------------------------------------------------------------------
    apt-get install -y zenity policykit-1 oem-config-gtk

    # -------------------------------------------------------------------------
    # Scripts
    # -------------------------------------------------------------------------
    install -m 755 "$REPO_DIR/assets/scripts/oem-powerwash.sh" \
                   /usr/local/bin/oem-powerwash.sh
    install -m 700 "$REPO_DIR/assets/scripts/oem-powerwash-arm.sh" \
                   /usr/local/sbin/oem-powerwash-arm.sh
    install -m 700 "$REPO_DIR/assets/scripts/oem-powerwash-finalize.sh" \
                   /usr/local/sbin/oem-powerwash-finalize.sh

    # -------------------------------------------------------------------------
    # systemd one-shot — fires on next boot only if the flag exists.
    # Stay disabled until the user actually arms it.
    # -------------------------------------------------------------------------
    install -m 644 "$REPO_DIR/assets/configs/oem-powerwash-finalize.service" \
                   /etc/systemd/system/oem-powerwash-finalize.service
    systemctl daemon-reload
    systemctl disable oem-powerwash-finalize.service 2>/dev/null || true

    # -------------------------------------------------------------------------
    # Icon + icon cache refresh
    # -------------------------------------------------------------------------
    mkdir -p /usr/share/icons/hicolor/scalable/apps
    cp "$REPO_DIR/assets/icons/oem-powerwash.svg" \
       /usr/share/icons/hicolor/scalable/apps/oem-powerwash.svg
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true

    # -------------------------------------------------------------------------
    # Application menu entry
    # -------------------------------------------------------------------------
    install -m 644 "$REPO_DIR/assets/configs/oem-powerwash.desktop" \
                   /usr/share/applications/oem-powerwash.desktop
    update-desktop-database /usr/share/applications 2>/dev/null || true

    # -------------------------------------------------------------------------
    # Polkit policy — friendly admin auth prompt instead of a terminal one
    # -------------------------------------------------------------------------
    mkdir -p /usr/share/polkit-1/actions
    install -m 644 "$REPO_DIR/assets/configs/oem-powerwash.policy" \
                   /usr/share/polkit-1/actions/org.linuxoem.powerwash.policy

    mkdir -p /var/lib/oem-setup

    echo "    [+] Powerwash installed."
    echo "        Buyer can launch it from the application menu (search 'Powerwash')."
}
