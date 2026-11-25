#!/bin/bash
set -euo pipefail

ARTIFACT="$1"
APP="$2"
IDENTITY="$3"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP/Contents/Frameworks" "$APP/Contents/Resources"
ditto "$ARTIFACT/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$FRAMEWORK"
ditto "$ARTIFACT/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
lipo "$FRAMEWORK/Sparkle" -verify_arch arm64 x86_64

# Sparkle ships signed helpers. Re-sign from the inside out for the host app.
sign_options=(--force --sign "$IDENTITY" --options runtime --timestamp)
if [[ "$IDENTITY" == - ]]; then
  sign_options=(--force --sign - --timestamp=none)
fi
VERSION_DIR="$FRAMEWORK/Versions/Current"
codesign "${sign_options[@]}" "$VERSION_DIR/XPCServices/Installer.xpc"
codesign "${sign_options[@]}" --preserve-metadata=entitlements "$VERSION_DIR/XPCServices/Downloader.xpc"
codesign "${sign_options[@]}" "$VERSION_DIR/Autoupdate"
codesign "${sign_options[@]}" "$VERSION_DIR/Updater.app"
codesign "${sign_options[@]}" "$FRAMEWORK"
