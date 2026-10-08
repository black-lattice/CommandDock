#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
OUT="${OUT_DIR:-dist}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
APP="$OUT/CommandDock.app"
for ARCH in arm64 x86_64; do
  swift build -c release --arch "$ARCH" --scratch-path ".build/$ARCH"
done
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
ARM_BIN="$(swift build -c release --arch arm64 --scratch-path .build/arm64 --show-bin-path)/CommandDock"
INTEL_BIN="$(swift build -c release --arch x86_64 --scratch-path .build/x86_64 --show-bin-path)/CommandDock"
lipo -create "$ARM_BIN" "$INTEL_BIN" -output "$APP/Contents/MacOS/CommandDock"
lipo "$APP/Contents/MacOS/CommandDock" -verify_arch arm64 x86_64
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CommandDock</string>
<key>CFBundleIdentifier</key><string>vip.haoduo.CommandDock</string>
<key>CFBundleName</key><string>CommandDock</string>
<key>CFBundleDisplayName</key><string>CommandDock</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
swift scripts/icon.swift "$APP/Contents/Resources"
codesign --force --sign "${SIGNING_IDENTITY:--}" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
NAME="CommandDock-$VERSION-universal"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$NAME.zip"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/CommandDock.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname CommandDock -srcfolder "$STAGING" -ov -format UDZO "$OUT/$NAME.dmg"
(cd "$OUT" && shasum -a 256 "$NAME.zip" "$NAME.dmg" > SHA256SUMS.txt)
printf 'Built %s (Intel + Apple Silicon, macOS 13+)\n' "$APP"
