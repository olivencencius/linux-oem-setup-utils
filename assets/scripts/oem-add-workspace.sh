#!/bin/bash
# OEM: increment xfwm4 workspace count by one (cap 32). Bound to Super+Insert on
# first XFCE login by oem-first-run.sh; installed to /usr/local/bin by gestures.sh.
command -v xfconf-query >/dev/null || exit 0
c=$(xfconf-query -c xfwm4 -p /general/workspace_count -v 2>/dev/null || echo 1)
[[ "$c" =~ ^[0-9]+$ ]] || c=1
[ "$c" -ge 32 ] && exit 0
xfconf-query -c xfwm4 -p /general/workspace_count -s "$((c + 1))" 2>/dev/null || exit 0
