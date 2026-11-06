#!/bin/bash
# Builds Magic Middle Click as a universal app (Apple Silicon + Intel) and creates
# dist/MagicMiddleClick.zip and dist/MagicMiddleClick.dmg.
#
# Optional variables:
#   SIGN_IDENTITY  signing identity ("Developer ID Application: …"). Defaults to "Magic Middle Click Local" if it
#                  exists (see scripts/create-signing-cert.sh), otherwise ad hoc (-).
#   NOTARY_PROFILE profile created with `xcrun notarytool store-credentials`, to notarize (needs Developer ID).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Magic Middle Click"   # what users see (the .app name)
EXECUTABLE="MagicMiddleClick"   # binary name, must match CFBundleExecutable in Resources/Info.plist
ARTIFACT="MagicMiddleClick"     # name of the .zip and .dmg (no spaces, for download URLs)
VERSION="1.0.0"
BUILD_NUMBER="1"
MIN_OS="13.0"
LOCAL_IDENTITY="Magic Middle Click Local"
if [ -z "${SIGN_IDENTITY:-}" ]; then
  if security find-identity -p codesigning 2>/dev/null | grep -q "$LOCAL_IDENTITY"; then
    SIGN_IDENTITY="$LOCAL_IDENTITY"
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
    -o "$BUILD/$EXECUTABLE-$ARCH" \
    Sources/*.swift
done
lipo -create -output "$BUILD/$EXECUTABLE" "$BUILD/$EXECUTABLE-arm64" "$BUILD/$EXECUTABLE-x86_64"

echo "▸ Icon…"
swiftc -O scripts/make-icon.swift -o "$BUILD/make-icon"
"$BUILD/make-icon" "$BUILD/AppIcon.iconset"
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$BUILD/AppIcon.icns"

echo "▸ Assembling $APP_NAME.app…"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▸ Signing ($SIGN_IDENTITY)…"
if [ "$SIGN_IDENTITY" = "-" ] || [ "$SIGN_IDENTITY" = "$LOCAL_IDENTITY" ]; then
  codesign --force --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

echo "▸ Packaging…"
ditto -c -k --keepParent "$APP" "$DIST/$ARTIFACT.zip"

STAGE="$BUILD/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/README.txt" <<'TXT'
Magic Middle Click — middle click for the Apple Magic Mouse

1. Drag Magic Middle Click to the Applications folder.
2. Open it. Because it isn't notarized by Apple, macOS blocks it the first time:
   - Close the warning and go to System Settings → Privacy & Security.
   - At the bottom it says "Magic Middle Click was blocked…": click "Open Anyway" and enter your password.
   (On macOS 13 and 14 you can also right-click the app → Open → Open.)
   Or, in Terminal: xattr -dr com.apple.quarantine "/Applications/Magic Middle Click.app"
3. Grant the Accessibility permission when asked
   (System Settings → Privacy & Security → Accessibility → turn on Magic Middle Click).
4. A mouse icon appears in the menu bar. Open the settings from there.

https://github.com/gonzaroman/magic-middle-click
TXT
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$ARTIFACT.dmg"

if [ -n "${NOTARY_PROFILE:-}" ] && [ "$SIGN_IDENTITY" != "-" ]; then
  echo "▸ Notarizing…"
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DIST/$ARTIFACT.dmg"
  xcrun notarytool submit "$DIST/$ARTIFACT.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DIST/$ARTIFACT.dmg"
fi

echo
echo "✓ $APP"
echo "✓ $DIST/$ARTIFACT.zip"
echo "✓ $DIST/$ARTIFACT.dmg"
