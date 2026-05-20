#!/bin/bash
# Read-only hardware / system diagnostics (does not modify the system).
set -euo pipefail

print_rule() {
    printf '\n%s\n' "────────────────────────────────────────"
    printf '%s\n' "$1"
    printf '%s\n' "────────────────────────────────────────"
}

print_rule "Operating System"
if [ -f /etc/os-release ]; then
    grep -E '^(PRETTY_NAME|VERSION_ID|ID)=' /etc/os-release | sed 's/^/  /'
else
    echo "  ( /etc/os-release not found )"
fi

print_rule "Kernel"
uname -a | sed 's/^/  /'

print_rule "CPU (lscpu)"
if command -v lscpu &>/dev/null; then
    lscpu | sed 's/^/  /'
else
    echo "  lscpu not installed"
fi

print_rule "Memory (free -m)"
if command -v free &>/dev/null; then
    free -m | sed 's/^/  /'
else
    echo "  free not available"
fi

print_rule "Battery"
bat=""
if command -v upower &>/dev/null; then
    bat=$(upower -e 2>/dev/null | grep -i BAT | head -1 || true)
fi
if [ -n "$bat" ]; then
    upower -i "$bat" | grep -E 'state|to[[:space:]]+full|percentage|capacity' | sed 's/^[[:space:]]*/  /'
else
    echo "  No battery device found via upower"
fi

print_rule "USB devices (lsusb)"
if command -v lsusb &>/dev/null; then
    lsusb | sed 's/^/  /'
else
    echo "  lsusb not installed"
fi

print_rule "Audio cards (aplay -l)"
if command -v aplay &>/dev/null; then
    aplay -l | sed 's/^/  /'
else
    echo "  aplay not installed"
fi

echo ""
