#!/bin/bash
# MagHue one-line installer:
#
#   curl -fsSL https://raw.githubusercontent.com/kamenlevi/MagHue/main/scripts/install.sh | bash
#
# Downloads the latest release and puts MagHue.app into /Applications.
# curl doesn't set the com.apple.quarantine attribute browsers do, so the
# app opens straight away — no "Apple could not verify…" dialog, no trip
# to System Settings. Everything runs as you (no sudo); the only admin
# prompt is the app's own "Install Helper…" button afterwards.
set -euo pipefail

ZIP_URL="https://github.com/kamenlevi/MagHue/releases/latest/download/MagHue.zip"

DEST="/Applications"
if [ ! -w "$DEST" ]; then
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading MagHue…"
curl -fsSL "$ZIP_URL" -o "$TMP/MagHue.zip"

ditto -xk "$TMP/MagHue.zip" "$TMP/unpacked"
APP=$(find "$TMP/unpacked" -maxdepth 2 -name "MagHue.app" -print -quit)
if [ -z "$APP" ]; then
    echo "error: MagHue.app not found in the downloaded archive" >&2
    exit 1
fi

# Replace any existing copy (which may be browser-quarantined), quitting a
# running instance first so the swap is clean.
osascript -e 'tell application "MagHue" to quit' >/dev/null 2>&1 || true
pkill -x MagHue 2>/dev/null || true
rm -rf "$DEST/MagHue.app"
ditto "$APP" "$DEST/MagHue.app"

open "$DEST/MagHue.app"
echo "MagHue installed in $DEST and started."
echo "Click its MagSafe icon in the menu bar, then \"Install Helper…\" to finish setup."
