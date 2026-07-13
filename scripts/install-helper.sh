#!/bin/bash
# Installs the MagHue privileged helper. Runs as root, invoked by the app.
# Usage: install-helper.sh <app-resources-dir> <console-user>
set -euo pipefail

RESOURCES="$1"
CONSOLE_USER="$2"
LABEL="com.kamenlevi.maghue.helper"
BIN="/Library/PrivilegedHelperTools/$LABEL"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
CONFIG_DIR="/Library/Application Support/MagHue"
LOG_DIR="/Library/Logs/MagHue"

# Stop any previous version.
launchctl bootout "system/$LABEL" 2>/dev/null || true

mkdir -p /Library/PrivilegedHelperTools "$LOG_DIR"
install -m 755 -o root -g wheel "$RESOURCES/maghue-helper" "$BIN"
install -m 644 -o root -g wheel "$RESOURCES/$LABEL.plist" "$PLIST"

# The config dir belongs to the installing user so the app can update the
# threshold without asking for a password every time. The helper only reads
# a mode + percentage from it, so this is safe.
mkdir -p "$CONFIG_DIR"
chown "$CONSOLE_USER" "$CONFIG_DIR"
chmod 755 "$CONFIG_DIR"

launchctl bootstrap system "$PLIST"
echo "MagHue helper installed"
