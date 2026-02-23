#!/bin/bash
set -euo pipefail

APP_NAME="TaskManagement"
INSTALL_DIR="/Applications"
APP_BUNDLE="${INSTALL_DIR}/${APP_NAME}.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
STAGE_DIR="${PROJECT_DIR}/.build/install/staged"

cd "$PROJECT_DIR"

echo "Building ${APP_NAME} (release via xcodebuild)..."
xcodebuild \
    -scheme TaskManagement \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "${PROJECT_DIR}/.build/install" \
    CONFIGURATION_BUILD_DIR="${STAGE_DIR}" \
    CODE_SIGN_IDENTITY=- \
    2>&1 | grep -E '^\*\*|error:' || true

BINARY="${STAGE_DIR}/${APP_NAME}"
if [ ! -f "$BINARY" ]; then
    echo "Error: Build failed — binary not found"
    exit 1
fi
echo "Build succeeded."

echo "Creating app bundle at ${APP_BUNDLE}..."

# Remove previous install
if [ -d "$APP_BUNDLE" ]; then
    rm -rf "$APP_BUNDLE"
fi

# Create bundle structure
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy binary
cp "$BINARY" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Write Info.plist
cat > "${APP_BUNDLE}/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>TaskManagement</string>
    <key>CFBundleIdentifier</key>
    <string>com.nhle.taskmanagement</string>
    <key>CFBundleName</key>
    <string>Task Management</string>
    <key>CFBundleDisplayName</key>
    <string>Task Management</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Sign with the same flags xcodebuild uses
codesign --force --sign - \
    --timestamp=none --generate-entitlement-der \
    "${APP_BUNDLE}"

echo ""
echo "Installed ${APP_NAME}.app to ${INSTALL_DIR}"
echo ""
echo "Usage:"
echo "  open ${APP_BUNDLE}          # Launch from terminal"
echo "  # Or find 'Task Management' in Spotlight / Launchpad"
echo ""
echo "To uninstall:"
echo "  rm -rf ${APP_BUNDLE}"
