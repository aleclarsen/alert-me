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

# Ship the animation as a plain resource in Contents/Resources, loaded at runtime
# via Bundle.main. We deliberately do NOT copy SwiftPM's *.bundle directories:
# they have no Info.plist, so codesign rejects them ("bundle format unrecognized"),
# and SwiftPM's generated Bundle.module accessor wouldn't find them inside the
# .app anyway. Keeping the .app free of nested bundles lets codesign succeed.
cp "Sources/${APP_NAME}/Resources/train-animation.json" "${APP_DIR}/Contents/Resources/"

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

# Sign with a stable identity if provided (so the Keychain "Always Allow" for the
# OAuth token persists across rebuilds), otherwise fall back to ad-hoc ("-").
# Set one with, e.g.:  CODESIGN_IDENTITY="My Dev Cert" ./scripts/build-app.sh
# The .app has no nested bundles, so a plain signature seals everything cleanly.
IDENTITY="${CODESIGN_IDENTITY:--}"
echo "==> Codesigning with identity: ${IDENTITY}"
codesign --force --sign "${IDENTITY}" "${APP_DIR}"

echo "==> Done: ${APP_DIR}"
echo "    Run it with: open ${APP_DIR}"
