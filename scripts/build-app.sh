#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
ARCHS="${ARCHS:-$(uname -m)}"
OUT="${OUT:-dist}"

ARGS=(-c release)
for arch in $ARCHS; do
  ARGS+=(--arch "$arch")
done

echo "› Building Downly $VERSION ($BUILD_NUMBER) for: $ARCHS"
swift build "${ARGS[@]}" --product Downly
BIN_DIR="$(swift build "${ARGS[@]}" --show-bin-path)"

APP="$OUT/Downly.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Downly" "$APP/Contents/MacOS/Downly"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if command -v iconutil >/dev/null 2>&1 && command -v sips >/dev/null 2>&1; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size design/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double design/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
else
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
cp design/AppIcon-1024.png "$APP/Contents/Resources/AppIcon.png"

codesign --force --deep --sign - "$APP"
echo "› Built $APP"

if [[ "${MAKE_DMG:-1}" == "1" ]]; then
  STAGE="$(mktemp -d)/Downly"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  DMG="$OUT/Downly.dmg"
  rm -f "$DMG"
  hdiutil create -volname "Downly" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
  echo "› Created $DMG"
fi
