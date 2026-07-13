#!/bin/bash
# Removes the MagHue privileged helper and hands the LED back to macOS.
# Runs as root, invoked by the app. Usage: uninstall-helper.sh [resources] [user]
set -uo pipefail

LABEL="com.kamenlevi.maghue.helper"
BIN="/Library/PrivilegedHelperTools/$LABEL"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
CONFIG_DIR="/Library/Application Support/MagHue"
LOG_DIR="/Library/Logs/MagHue"

# The daemon resets the LED on SIGTERM; the explicit --reset is a backstop.
launchctl bootout "system/$LABEL" 2>/dev/null || true
[ -x "$BIN" ] && "$BIN" --reset || true

rm -f "$BIN" "$PLIST"
rm -rf "$CONFIG_DIR" "$LOG_DIR"
echo "MagHue helper removed"
