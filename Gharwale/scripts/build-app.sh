#!/bin/bash
# Builds build/Gharwale.app by calling the Swift compiler directly.
# Works with only the Command Line Tools installed (no full Xcode needed).
# Usage: ./scripts/build-app.sh            (this Mac's architecture)
#        UNIVERSAL=1 ./scripts/build-app.sh (Apple Silicon + Intel)
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="$(xcrun --sdk macosx --show-sdk-path)"
MIN_OS="13.0"
OUT="build"
APP="$OUT/Gharwale.app"
mkdir -p "$OUT/obj"

compile() {
  local arch="$1"
  echo "==> Compiling for $arch"
  xcrun swiftc \
    -sdk "$SDK" \
    -target "$arch-apple-macos$MIN_OS" \
    -O \
    -parse-as-library \
    -module-name Gharwale \
    Sources/Gharwale/*.swift \
    -o "$OUT/obj/Gharwale-$arch"
}

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  compile arm64
  compile x86_64
  lipo -create "$OUT/obj/Gharwale-arm64" "$OUT/obj/Gharwale-x86_64" -output "$OUT/obj/Gharwale"
else
  ARCH="$(uname -m)"
  compile "$ARCH"
  cp "$OUT/obj/Gharwale-$ARCH" "$OUT/obj/Gharwale"
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OUT/obj/Gharwale" "$APP/Contents/MacOS/Gharwale"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp ContentPacks/*.json "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/Characters"
cp Characters/*.png "$APP/Contents/Resources/Characters/"

echo "==> Signing (ad-hoc; use your Developer ID for distribution)"
codesign --force --deep --sign "${SIGN_IDENTITY:--}" "$APP"

echo "==> Done. Run it with: open $APP"
