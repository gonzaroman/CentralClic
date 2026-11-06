#!/bin/bash
# Regenerates docs/screenshots/*.png (the README pictures) from the real settings window.
# The renderer runs inside a temporary .app bundle with the real Info.plist, translations and icon,
# but its own bundle id, so it never reads or changes your Magic Middle Click settings.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(sed -n 's/^VERSION="\(.*\)"/\1/p' build.sh)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
APP="$TMP/Screenshots.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$TMP/src"

cp Sources/*.swift "$TMP/src/"
cp scripts/screenshots.swift "$TMP/src/main.swift" # replaces the app's main.swift
swiftc -swift-version 5 -import-objc-header Sources/Bridge.h -o "$APP/Contents/MacOS/MagicMiddleClick" "$TMP/src"/*.swift

swiftc -O scripts/make-icon.swift -o "$TMP/make-icon"
"$TMP/make-icon" "$TMP/AppIcon.iconset"
iconutil -c icns "$TMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cp "$TMP/AppIcon.iconset/icon_256x256.png" docs/icon.png
cp -R Resources/*.lproj "$APP/Contents/Resources/"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/1/" \
    -e "s/com.gonzaroman.magicmiddleclick/com.gonzaroman.magicmiddleclick.screenshots/" \
    Resources/Info.plist > "$APP/Contents/Info.plist"

# English text and US number format, whatever the Mac's language.
"$APP/Contents/MacOS/MagicMiddleClick" docs/screenshots -AppleLanguages '(en)' -AppleLocale en_US
