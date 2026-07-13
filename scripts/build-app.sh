#!/bin/bash
# Builds MagHue.app into dist/. Usage: scripts/build-app.sh [version]
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${1:-1.0.0}"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
DIST="dist"
APP="$DIST/MagHue.app"

ARCH_FLAGS="--arch arm64"
swift build -c release $ARCH_FLAGS
BIN_DIR="$(swift build -c release $ARCH_FLAGS --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/MagHue" "$APP/Contents/MacOS/MagHue"
cp "$BIN_DIR/maghue-helper" "$APP/Contents/Resources/maghue-helper"
cp packaging/com.kamenlevi.maghue.helper.plist "$APP/Contents/Resources/"
cp scripts/install-helper.sh scripts/uninstall-helper.sh "$APP/Contents/Resources/"
chmod +x "$APP/Contents/Resources/"*.sh "$APP/Contents/Resources/maghue-helper"

sed -e "s/MAGHUE_VERSION/$VERSION/" -e "s/MAGHUE_BUILD/$BUILD_NUMBER/" \
    packaging/Info.plist > "$APP/Contents/Info.plist"

# App icon: render the base PNG, then build the .icns.
ICON_TMP="$DIST/icon-work"
rm -rf "$ICON_TMP"
mkdir -p "$ICON_TMP/AppIcon.iconset"
swift scripts/make-icon.swift "$ICON_TMP/AppIcon.png" >/dev/null
for s in 16 32 128 256 512; do
    sips -z $s $s "$ICON_TMP/AppIcon.png" --out "$ICON_TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d "$ICON_TMP/AppIcon.png" --out "$ICON_TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICON_TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICON_TMP"

codesign --force --sign - "$APP/Contents/Resources/maghue-helper"
codesign --force --sign - --deep "$APP"

echo "built $APP (version $VERSION)"
