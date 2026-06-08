#!/usr/bin/env bash
# Builds AlertMe.app — a self-contained menu-bar app bundle (no Dock icon).
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="AlertMe"
BUNDLE_ID="com.alertme.app"
APP_DIR="${APP_NAME}.app"

echo "==> Building release binary…"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"

echo "==> Assembling ${APP_DIR}…"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BIN_PATH}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# SPM emits resource bundles (e.g. AlertMe_AlertMe.bundle) next to the binary.
# Bundle.module resolves them relative to the executable, so copy them alongside it.
for b in "${BIN_PATH}"/*.bundle; do
  [ -e "$b" ] && cp -R "$b" "${APP_DIR}/Contents/MacOS/"
done

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>alert-me</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>MIT Licensed</string>
</dict>
</plist>
PLIST

echo "==> Done: ${APP_DIR}"
echo "    Run it with: open ${APP_DIR}"
