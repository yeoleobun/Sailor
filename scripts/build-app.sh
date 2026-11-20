#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Sailor"
APP_BUNDLE="$ROOT_DIR/build/${APP_NAME}.app"

echo "Building ${APP_NAME} (release)..."
cd "$ROOT_DIR"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${APP_NAME}"

echo "Packaging ${APP_BUNDLE}..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
cp "$ROOT_DIR/assets/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Sailor</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.sailor.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Sailor</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.2</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSLocationUsageDescription</key>
    <string>Sailor uses Location Services solely to read the current Wi-Fi network name (SSID) so it can automatically switch your macOS Network Location.</string>
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>Sailor uses Location Services solely to read the current Wi-Fi network name (SSID) so it can automatically switch your macOS Network Location.</string>
</dict>
</plist>
PLIST

SIGN_IDENTITY="${SIGN_IDENTITY:-yeoleobun}"
if security find-identity -v -p codesigning | grep -Fq "\"${SIGN_IDENTITY}\""; then
  echo "Signing ${APP_BUNDLE} with identity \"${SIGN_IDENTITY}\"..."
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
  echo "Signing identity \"${SIGN_IDENTITY}\" not found; falling back to ad-hoc signing..."
  codesign --force --deep --sign - "$APP_BUNDLE"
fi

echo "Done! Built: ${APP_BUNDLE}"
