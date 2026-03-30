#!/bin/bash
set -euo pipefail

# Build Wave.app and package it into a .dmg for drag-and-drop installation
# Usage: ./build-dmg.sh

# The Xcode project/scheme is still named FlowSpeech (folder rename pending)
XCODE_PROJECT="FlowSpeech"
SCHEME="FlowSpeech"
DISPLAY_NAME="Wave"
BUILD_DIR="$(pwd)/build"
DMG_NAME="${DISPLAY_NAME}.dmg"
DMG_PATH="$(pwd)/${DMG_NAME}"

echo "==> Cleaning previous build..."
rm -rf "${BUILD_DIR}"
rm -f "${DMG_PATH}"

echo "==> Building ${DISPLAY_NAME} (Release)..."
xcodebuild -project "${XCODE_PROJECT}.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    build \
    CODE_SIGN_IDENTITY="-" \
    2>&1 | tail -20

# Find the built .app in DerivedData (may still be named FlowSpeech.app)
EXPORTED_APP=$(find "${BUILD_DIR}/DerivedData" -name "*.app" -type d | head -1)

if [ -z "${EXPORTED_APP}" ] || [ ! -d "${EXPORTED_APP}" ]; then
    echo "ERROR: Could not find built app"
    exit 1
fi

echo "==> Found app at: ${EXPORTED_APP}"

echo "==> Creating DMG..."
DMG_STAGING="${BUILD_DIR}/dmg-staging"
mkdir -p "${DMG_STAGING}"

# Copy app to staging (rename to Wave.app if needed)
BUILT_APP_NAME=$(basename "${EXPORTED_APP}")
if [ "${BUILT_APP_NAME}" != "${DISPLAY_NAME}.app" ]; then
    cp -R "${EXPORTED_APP}" "${DMG_STAGING}/${DISPLAY_NAME}.app"
else
    cp -R "${EXPORTED_APP}" "${DMG_STAGING}/"
fi

# Create a symlink to /Applications for drag-and-drop install
ln -s /Applications "${DMG_STAGING}/Applications"

# Create the DMG
hdiutil create -volname "${DISPLAY_NAME}" \
    -srcfolder "${DMG_STAGING}" \
    -ov -format UDZO \
    "${DMG_PATH}"

echo ""
echo "==> Done! DMG created at: ${DMG_PATH}"
echo "    Open it and drag ${DISPLAY_NAME}.app to Applications."
echo ""
ls -lh "${DMG_PATH}"
