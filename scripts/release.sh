#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Sailor"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$ROOT_DIR/build/${APP_NAME}.app"
ZIP_PATH="$DIST_DIR/${APP_NAME}-macos-arm64.zip"
DMG_PATH="$DIST_DIR/${APP_NAME}-macos-arm64.dmg"
SUMS_PATH="$DIST_DIR/SHA256SUMS.txt"

"$ROOT_DIR/scripts/build-app.sh"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "Creating ${ZIP_PATH}..."
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "Creating ${DMG_PATH}..."
DMG_STAGE="$DIST_DIR/dmg-stage"
mkdir -p "$DMG_STAGE"
cp -R "$APP_BUNDLE" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$DMG_STAGE"

echo "Generating SHA256SUMS.txt..."
(cd "$DIST_DIR" && shasum -a 256 "${APP_NAME}-macos-arm64.zip" "${APP_NAME}-macos-arm64.dmg" > "$SUMS_PATH")
cat "$SUMS_PATH"
