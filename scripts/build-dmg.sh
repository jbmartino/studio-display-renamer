#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-1.0.0}"
APP_NAME="StudioDisplayRenamer"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
DMG_STAGING=".build/dmg-staging"

# Code signing identity (set via environment, or skip signing for local builds)
SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"

echo "==> Building ${APP_NAME} v${VERSION}..."
swift build -c release

echo "==> Creating app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"
cp Info.plist "${APP_BUNDLE}/Contents/"

# Copy app icon if it exists
if [ -f "AppIcon.icns" ]; then
    mkdir -p "${APP_BUNDLE}/Contents/Resources"
    cp AppIcon.icns "${APP_BUNDLE}/Contents/Resources/"
fi

# Code sign the app bundle
if [ -n "${SIGN_IDENTITY}" ]; then
    echo "==> Signing app bundle with: ${SIGN_IDENTITY}..."
    codesign --force --options runtime --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
    codesign --force --options runtime --sign "${SIGN_IDENTITY}" "${APP_BUNDLE}"
    echo "==> Verifying signature..."
    codesign --verify --verbose "${APP_BUNDLE}"
else
    echo "==> Skipping code signing (no CODESIGN_IDENTITY set)"
fi

echo "==> Creating DMG..."
rm -rf "${DMG_STAGING}"
mkdir -p "${DMG_STAGING}"
cp -R "${APP_BUNDLE}" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"

rm -f "${DMG_NAME}"
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_STAGING}" \
    -ov \
    -format UDZO \
    "${DMG_NAME}"

rm -rf "${DMG_STAGING}"

# Sign the DMG itself
if [ -n "${SIGN_IDENTITY}" ]; then
    echo "==> Signing DMG..."
    codesign --force --sign "${SIGN_IDENTITY}" "${DMG_NAME}"
fi

# Notarize if credentials are available
if [ -n "${NOTARIZE_APPLE_ID:-}" ] && [ -n "${NOTARIZE_PASSWORD:-}" ] && [ -n "${NOTARIZE_TEAM_ID:-}" ]; then
    echo "==> Submitting for notarization..."
    xcrun notarytool submit "${DMG_NAME}" \
        --apple-id "${NOTARIZE_APPLE_ID}" \
        --password "${NOTARIZE_PASSWORD}" \
        --team-id "${NOTARIZE_TEAM_ID}" \
        --wait

    echo "==> Stapling notarization ticket..."
    xcrun stapler staple "${DMG_NAME}"
else
    echo "==> Skipping notarization (credentials not set)"
fi

echo ""
echo "==> Done! Created ${DMG_NAME}"
echo "    Size: $(du -h "${DMG_NAME}" | cut -f1)"
