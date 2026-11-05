#!/bin/bash
# Builds CentralClic as a universal app (Apple Silicon + Intel) and creates dist/CentralClic.zip and .dmg.
#
# Optional variables:
#   SIGN_IDENTITY  signing identity ("Developer ID Application: …"). Defaults to "CentralClic Local" if it
#                  exists (see scripts/create-signing-cert.sh), otherwise ad hoc (-).
#   NOTARY_PROFILE profile created with `xcrun notarytool store-credentials`, to notarize (needs Developer ID).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="CentralClic"
VERSION="1.0.0"
BUILD_NUMBER="1"
MIN_OS="13.0"
if [ -z "${SIGN_IDENTITY:-}" ]; then
  if security find-identity -p codesigning 2>/dev/null | grep -q "CentralClic Local"; then
    SIGN_IDENTITY="CentralClic Local"
  else
    SIGN_IDENTITY="-"
  fi
fi

BUILD="build"
DIST="dist"
APP="$BUILD/$APP_NAME.app"

rm -rf "$BUILD" "$DIST"
mkdir -p "$BUILD" "$DIST"

echo "▸ Checking translations…"
swiftc -O scripts/check-localizations.swift -o "$BUILD/check-localizations"
"$BUILD/check-localizations" .

echo "▸ Compiling…"
for ARCH in arm64 x86_64; do
  swiftc -O -swift-version 5 \
    -target "$ARCH-apple-macos$MIN_OS" \
    -import-objc-header Sources/Bridge.h \
    -o "$BUILD/$APP_NAME-$ARCH" \
    Sources/*.swift
done
lipo -create -output "$BUILD/$APP_NAME" "$BUILD/$APP_NAME-arm64" "$BUILD/$APP_NAME-x86_64"

echo "▸ Icon…"
swiftc -O scripts/make-icon.swift -o "$BUILD/make-icon"
"$BUILD/make-icon" "$BUILD/AppIcon.iconset"
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$BUILD/AppIcon.icns"

echo "▸ Assembling $APP_NAME.app…"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▸ Signing ($SIGN_IDENTITY)…"
if [ "$SIGN_IDENTITY" = "-" ] || [ "$SIGN_IDENTITY" = "CentralClic Local" ]; then
  codesign --force --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

echo "▸ Packaging…"
ditto -c -k --keepParent "$APP" "$DIST/$APP_NAME.zip"

STAGE="$BUILD/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/README.txt" <<'TXT'
CentralClic — middle click for the Magic Mouse

1. Drag CentralClic to the Applications folder.
2. Open it. Because it isn't notarized by Apple, macOS blocks it the first time:
   - Close the warning and go to System Settings → Privacy & Security.
   - At the bottom it says "CentralClic was blocked…": click "Open Anyway" and enter your password.
   (On macOS 13 and 14 you can also right-click CentralClic → Open → Open.)
   Or, in Terminal: xattr -dr com.apple.quarantine /Applications/CentralClic.app
3. Grant the Accessibility permission when asked
   (System Settings → Privacy & Security → Accessibility → turn on CentralClic).
4. A mouse icon appears in the menu bar. Open the settings from there.

https://github.com/gonzaroman/CentralClic
TXT
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$APP_NAME.dmg"

if [ -n "${NOTARY_PROFILE:-}" ] && [ "$SIGN_IDENTITY" != "-" ]; then
  echo "▸ Notarizing…"
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DIST/$APP_NAME.dmg"
  xcrun notarytool submit "$DIST/$APP_NAME.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DIST/$APP_NAME.dmg"
fi

echo
echo "✓ $APP"
echo "✓ $DIST/$APP_NAME.zip"
echo "✓ $DIST/$APP_NAME.dmg"
