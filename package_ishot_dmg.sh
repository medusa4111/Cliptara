#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="Cliptara.app"
APP_DIR="$DIST_DIR/$APP_NAME"
ICONSET_DIR="$DIST_DIR/Cliptara.iconset"
ICNS_PATH="$DIST_DIR/Cliptara.icns"
STAGING_DIR="$DIST_DIR/dmg-root"
TMP_RW_DMG="$DIST_DIR/Cliptara-temp.dmg"
VOLUME_NAME="Cliptara"
BACKGROUND_DIR="$STAGING_DIR/.background"
BACKGROUND_SRC="$DIST_DIR/dmg-bg-src.png"
BACKGROUND_PNG="$BACKGROUND_DIR/dmg-background.png"

OUTPUT_DMG="$ROOT_DIR/dist/Cliptara.dmg"
ICON_PNG="/Users/maksim/Documents/вопросы/сайт/assets/ishot-accent.png"
UPDATE_MANIFEST_URL="${UPDATE_MANIFEST_URL:-}"

if [[ ! -f "$ICON_PNG" ]]; then
  echo "Icon not found: $ICON_PNG"
  exit 1
fi

detach_image_if_mounted() {
  local image_path="$1"
  local dev

  while IFS= read -r dev; do
    [[ -n "$dev" ]] || continue
    hdiutil detach "$dev" -force >/dev/null 2>&1 || true
  done < <(
    hdiutil info | awk -v image_path="$image_path" '
      $1 == "image-path" {
        mounted_image = (index($0, image_path) > 0)
        next
      }
      mounted_image && $1 ~ /^\/dev\// {
        print $1
        mounted_image = 0
      }
    '
  )
}

echo "==> Building release binary"
cd "$ROOT_DIR"
swift build -c release

echo "==> Preparing distribution folders"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "==> Generating Cliptara.icns"
mkdir -p "$ICONSET_DIR"
sips -z 16 16 "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$ICON_PNG" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"

echo "==> Building Cliptara.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$ROOT_DIR/.build/release/iShot" "$APP_DIR/Contents/MacOS/Cliptara"
chmod +x "$APP_DIR/Contents/MacOS/Cliptara"
cp "$ICNS_PATH" "$APP_DIR/Contents/Resources/Cliptara.icns"

cat >"$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Cliptara</string>
  <key>CFBundleExecutable</key>
  <string>Cliptara</string>
  <key>CFBundleIconFile</key>
  <string>Cliptara</string>
  <key>CFBundleIdentifier</key>
  <string>com.maksim.cliptara</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Cliptara</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.2.0</string>
  <key>CFBundleVersion</key>
  <string>5</string>
  <key>CliptaraUpdateManifestURL</key>
  <string>$UPDATE_MANIFEST_URL</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"

echo "==> Preparing DMG staging"
mkdir -p "$STAGING_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Preparing colorful DMG background"
mkdir -p "$BACKGROUND_DIR"
sips -z 420 420 "$ICON_PNG" --out "$BACKGROUND_SRC" >/dev/null
sips --padToHeightWidth 420 760 --padColor 101a45 "$BACKGROUND_SRC" --out "$BACKGROUND_PNG" >/dev/null

detach_image_if_mounted "$OUTPUT_DMG"
detach_image_if_mounted "$TMP_RW_DMG"

rm -f "$OUTPUT_DMG"
rm -f "$TMP_RW_DMG"

echo "==> Creating writable DMG template"
hdiutil create -srcfolder "$STAGING_DIR" -fs HFS+ -volname "$VOLUME_NAME" -format UDRW "$TMP_RW_DMG" >/dev/null

echo "==> Mounting writable DMG"
attach_output="$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_RW_DMG")"
device="$(echo "$attach_output" | awk '/Apple_HFS/ {print $1; exit}')"
mount_point="$(echo "$attach_output" | awk '/Apple_HFS/ {print $NF; exit}')"

if [[ -z "${device:-}" || -z "${mount_point:-}" ]]; then
  echo "error: failed to mount writable DMG"
  exit 1
fi

cleanup() {
  if [[ -n "${device:-}" ]]; then
    hdiutil detach "$device" -force >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "==> Applying Finder layout"
set +e
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {180, 110, 860, 520}
    set viewOptions to icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 104
    set text size of viewOptions to 12
    set background picture of viewOptions to file ".background:dmg-background.png"
    try
      set position of item "Cliptara.app" of container window to {190, 180}
    on error
      set position of item "Cliptara" of container window to {190, 180}
    end try
    set position of item "Applications" of container window to {470, 180}
    update without registering applications
    delay 1
    close
    open
    delay 1
  end tell
end tell
APPLESCRIPT
osascript_rc=$?
set -e
if [[ $osascript_rc -ne 0 ]]; then
  echo "warning: Finder layout step failed; DMG is still usable"
fi

sync

echo "==> Detaching writable DMG"
hdiutil detach "$device" -force >/dev/null
device=""
trap - EXIT

echo "==> Converting to compressed DMG"
hdiutil convert "$TMP_RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT_DMG" >/dev/null
rm -f "$TMP_RW_DMG"
cp -f "$OUTPUT_DMG" "$ROOT_DIR/dist/iShot.dmg"

echo "Done:"
echo "  App: $APP_DIR"
echo "  DMG: $OUTPUT_DMG"
