#!/bin/bash
set -euo pipefail

# Build Wave.app and package it into a .dmg for local installation
# Usage: ./build-dmg.sh

APP_NAME="Wave"
SCHEME="Wave"
BUILD_DIR="$(pwd)/build"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
DMG_NAME="${APP_NAME}.dmg"
DMG_PATH="$(pwd)/${DMG_NAME}"
VOLUME_NAME="${APP_NAME}"

echo "==> Cleaning previous build..."
rm -rf "${BUILD_DIR}"
rm -f "${DMG_PATH}"

echo "==> Building ${APP_NAME} (Release)..."
xcodebuild -project "${APP_NAME}.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    build \
    CODE_SIGN_IDENTITY="-" \
    2>&1 | tail -20

# Find the built .app in DerivedData
EXPORTED_APP=$(find "${BUILD_DIR}/DerivedData" -name "${APP_NAME}.app" -type d | head -1)

if [ -z "${EXPORTED_APP}" ] || [ ! -d "${EXPORTED_APP}" ]; then
    echo "ERROR: Could not find built app"
    exit 1
fi

echo "==> Found app at: ${EXPORTED_APP}"

echo "==> Creating DMG..."
# Create a temporary directory for DMG contents
DMG_STAGING="${BUILD_DIR}/dmg-staging"
mkdir -p "${DMG_STAGING}"
cp -R "${EXPORTED_APP}" "${DMG_STAGING}/"

# Create a symlink to /Applications for drag-and-drop install
ln -s /Applications "${DMG_STAGING}/Applications"

# Create the DMG
hdiutil create -volname "${VOLUME_NAME}" \
    -srcfolder "${DMG_STAGING}" \
    -ov -format UDZO \
    "${DMG_PATH}"

echo ""
echo "==> Done! DMG created at: ${DMG_PATH}"
echo "    Open it and drag ${APP_NAME}.app to Applications."
echo ""
ls -lh "${DMG_PATH}"
