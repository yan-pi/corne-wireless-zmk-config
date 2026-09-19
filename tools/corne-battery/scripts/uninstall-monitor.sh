#!/bin/sh
set -eu

PLIST="$HOME/Library/LaunchAgents/sh.indianboy.corne-battery.plist"
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
printf '%s\n' "Removed Corne battery monitor."
