#!/bin/bash
# Builds MagHue.app into dist/. Usage: scripts/build-app.sh [version]
set -euo pipefail

# Say which step failed rather than exiting silently — "the build failed" with
# no output is the one bug report nobody can act on.
trap 'echo "" >&2
      echo "build-app.sh failed at line $LINENO: $BASH_COMMAND" >&2
      echo "  macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)) · $(uname -m)" >&2
      echo "  $(swift --version 2>&1 | head -1)" >&2
      echo "Please open an issue with the output above:" >&2
      echo "  https://github.com/kamenlevi/MagHue/issues" >&2' ERR

cd "$(dirname "$0")/.."
VERSION="${1:-1.0.0}"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"
DIST="dist"
APP="$DIST/MagHue.app"

# Preflight: the usual reason a first build fails is no Swift toolchain at all.
if ! xcode-select -p >/dev/null 2>&1; then
    echo "Xcode Command Line Tools are missing. Install them with:" >&2
    echo "  xcode-select --install" >&2
    exit 1
fi
if ! command -v swift >/dev/null 2>&1; then
    echo "No 'swift' in PATH. Install the Xcode Command Line Tools:" >&2
    echo "  xcode-select --install" >&2
    exit 1
fi
echo "macOS $(sw_vers -productVersion) · $(swift --version 2>&1 | head -1)"

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

# Prove the bundle is actually there before claiming success.
if [ ! -x "$APP/Contents/MacOS/MagHue" ]; then
    echo "build finished but $APP/Contents/MacOS/MagHue is missing" >&2
    exit 1
fi

echo "built $APP (version $VERSION)"
