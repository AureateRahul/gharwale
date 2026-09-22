#!/bin/bash
# Makes build/Gharwale.dmg — the file users download, open, and drag to Applications.
#
# Easiest: build for all Macs + make the DMG in one go:
#   UNIVERSAL=1 ./scripts/build-app.sh && ./scripts/make-dmg.sh
#
# With an Apple Developer account (removes the "cannot be verified" warning):
#   SIGN_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE="gharwale" ./scripts/make-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Gharwale"
APP="build/${APP_NAME}.app"
DMG="build/${APP_NAME}.dmg"
ENTITLEMENTS="scripts/Gharwale.entitlements"

if [ ! -d "$APP" ]; then
  echo "❌ $APP not found. Build the app first: ./scripts/build-app.sh"
  exit 1
fi

# Warn if the app only runs natively on one chip type (Intel or Apple Silicon)
BIN="$APP/Contents/MacOS/$APP_NAME"
if [ -f "$BIN" ]; then
  ARCHS=$(lipo -archs "$BIN" 2>/dev/null || echo "unknown")
  echo "==> App is built for: $ARCHS"
  if [[ "$ARCHS" != *arm64* || "$ARCHS" != *x86_64* ]]; then
    echo "⚠️  Not a universal build. Works best if build-app.sh builds for both arm64 and x86_64."
  fi
fi

# 1) Sign the app (only if a Developer ID is given)
if [ -n "${SIGN_ID:-}" ]; then
  echo "==> Signing app"
  codesign --force --deep --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" --sign "$SIGN_ID" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
fi

# 2) Build the DMG: app + shortcut to Applications, so users can drag and drop
echo "==> Making DMG"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

# 3) Sign + notarize the DMG (only with a Developer account)
if [ -n "${SIGN_ID:-}" ]; then
  codesign --sign "$SIGN_ID" --timestamp "$DMG"
fi
if [ -n "${NOTARY_PROFILE:-}" ]; then
  echo "==> Sending to Apple for notarization (takes a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo "✅ Done: $DMG"
if [ -z "${SIGN_ID:-}" ]; then
  echo "   Note: not signed. Other Macs will warn 'Apple could not verify' until you sign + notarize."
fi
