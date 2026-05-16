#!/bin/bash
# ==============================================================================
#   Snippet:   chrome-exec-flags.sh
#   Purpose:   Shared Google Chrome CLI flags (keyring + scrollbar) for main
#              browser and web-app launchers. Sourced by modules/chrome.sh and
#              modules/webapps.sh after REPO_DIR is set.
#   Docs:      docs/modules/webapps.md (keyring / OverlayScrollbar rationale)
# ==============================================================================

OEM_CHROME_EXEC_FLAGS='--password-store=basic --enable-features=OverlayScrollbar'
