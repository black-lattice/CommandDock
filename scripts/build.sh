#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-1.1.1}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
NOTARIZE="${NOTARIZE:-0}"
if [[ "$NOTARIZE" == 1 ]]; then
  [[ "$SIGNING_IDENTITY" != - ]] || { echo '公证需要 Developer ID Application 签名。' >&2; exit 1; }
  : "${APPLE_ID:?缺少 APPLE_ID}" "${APPLE_TEAM_ID:?缺少 APPLE_TEAM_ID}" "${APPLE_APP_PASSWORD:?缺少 APPLE_APP_PASSWORD}"
fi
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-$(cat scripts/sparkle-public-key.txt)}"
SU_FEED_URL="${SU_FEED_URL:-https://github.com/black-lattice/CommandDock/releases/latest/download/appcast.xml}"
if ! [[ "$SPARKLE_PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
  echo '缺少有效的 Sparkle Ed25519 公钥。' >&2
  exit 1
fi
OUT="${OUT_DIR:-dist}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
STAGING="$(mktemp -d "$OUT/.package.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/payload/CommandDock.app"
SPARKLE_ARTIFACT=".build/arm64/artifacts/sparkle/Sparkle"
for ARCH in arm64 x86_64; do
  swift build -c release --arch "$ARCH" --scratch-path ".build/$ARCH" \
    -Xlinker -rpath -Xlinker '@executable_path/../Frameworks'
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
<key>CFBundleIdentifier</key><string>yunfenggroup.CommandDock</string>
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
plutil -insert SUFeedURL -string "$SU_FEED_URL" "$APP/Contents/Info.plist"
plutil -insert SURequireSignedFeed -bool YES "$APP/Contents/Info.plist"
plutil -insert SUPublicEDKey -string "$SPARKLE_PUBLIC_KEY" "$APP/Contents/Info.plist"
swift scripts/icon.swift "$APP/Contents/Resources"
bash scripts/embed-sparkle.sh "$SPARKLE_ARTIFACT" "$APP" "$SIGNING_IDENTITY"
if [[ "$SIGNING_IDENTITY" == - ]]; then
  codesign --force --sign - --timestamp=none "$APP"
else
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$APP"
fi
codesign --verify --deep --strict "$APP"
NAME="CommandDock-$VERSION-universal"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$NAME.zip"
notarize() {
  xcrun notarytool submit "$1" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" --wait --output-format plist > "$OUT/notarization.plist"
  if [[ "$(/usr/libexec/PlistBuddy -c 'Print :status' "$OUT/notarization.plist")" != Accepted ]]; then
    cat "$OUT/notarization.plist" >&2
    echo 'Apple 公证未通过，停止分发。' >&2
    exit 1
  fi
}
if [[ "$NOTARIZE" == 1 ]]; then
  notarize "$OUT/$NAME.zip"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
  rm "$OUT/$NAME.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$NAME.zip"
fi
ln -s /Applications "$STAGING/payload/Applications"
hdiutil create -volname CommandDock -srcfolder "$STAGING/payload" -ov -format UDZO "$OUT/$NAME.dmg"
if [[ "$NOTARIZE" == 1 ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$OUT/$NAME.dmg"
  notarize "$OUT/$NAME.dmg"
  xcrun stapler staple "$OUT/$NAME.dmg"
  xcrun stapler validate "$OUT/$NAME.dmg"
fi
(cd "$OUT" && shasum -a 256 "$NAME.zip" "$NAME.dmg" > SHA256SUMS.txt)
if [[ -e "$OUT/CommandDock.app" ]]; then
  mv "$OUT/CommandDock.app" "$STAGING/previous.app"
fi
if ! mv "$APP" "$OUT/CommandDock.app"; then
  [[ ! -e "$STAGING/previous.app" ]] || mv "$STAGING/previous.app" "$OUT/CommandDock.app"
  exit 1
fi
printf 'Built %s (Intel + Apple Silicon, macOS 13+)\n' "$OUT/CommandDock.app"
