#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Copythat"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="${COPYTHAT_DMG_PATH:-$DIST_DIR/$APP_NAME.dmg}"
DMG_VOLUME_NAME="$APP_NAME"
APP_RESOURCE_BUNDLE="$APP_BUNDLE/Contents/Resources/${APP_NAME}_${APP_NAME}.bundle"

cleanup_dir=""
mounted_volume=""

cleanup() {
  if [ -n "$mounted_volume" ] && [ -d "$mounted_volume" ]; then
    hdiutil detach "$mounted_volume" >/dev/null 2>&1 || true
  fi
  if [ -n "$cleanup_dir" ] && [ -d "$cleanup_dir" ]; then
    rm -rf "$cleanup_dir"
  fi
}
trap cleanup EXIT

echo "Building release app bundle..."
COPYTHAT_BUILD_CONFIGURATION=release "$ROOT_DIR/script/build_and_run.sh" --verify-portable

if [ ! -f "$APP_RESOURCE_BUNDLE/MenuBarIconTemplate.png" ]; then
  echo "Missing packaged SwiftPM resources at $APP_RESOURCE_BUNDLE" >&2
  exit 1
fi

echo "Inspecting app signature..."
codesign -dvvv "$APP_BUNDLE" 2>&1 | sed -n '1,24p'

if spctl -a -vv --type execute "$APP_BUNDLE" >/dev/null 2>&1; then
  echo "Gatekeeper accepted $APP_BUNDLE."
else
  echo "Gatekeeper rejected $APP_BUNDLE as expected for a non-notarized temporary build."
fi

cleanup_dir="$(mktemp -d -t copythat_dmg)"
mkdir -p "$cleanup_dir/dmg-root"
cp -R "$APP_BUNDLE" "$cleanup_dir/dmg-root/$APP_NAME.app"
ln -s /Applications "$cleanup_dir/dmg-root/Applications"
awk '/^## Developer Notes$/ { exit } { print }' "$ROOT_DIR/README.md" >"$cleanup_dir/dmg-root/README.md"

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

echo "Creating $DMG_PATH..."
hdiutil create \
  -volname "$DMG_VOLUME_NAME" \
  -srcfolder "$cleanup_dir/dmg-root" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "Verifying DMG contents..."
attach_output="$(hdiutil attach "$DMG_PATH" -nobrowse -readonly)"
mounted_volume="$(printf '%s\n' "$attach_output" | awk '/\/Volumes\// { print substr($0, index($0, "/Volumes/")); exit }')"

if [ -z "$mounted_volume" ] || [ ! -d "$mounted_volume" ]; then
  echo "Could not find mounted DMG volume." >&2
  echo "$attach_output" >&2
  exit 1
fi

test -d "$mounted_volume/$APP_NAME.app"
test -L "$mounted_volume/Applications"
test -f "$mounted_volume/README.md"
test ! -e "$mounted_volume/Install Copythat.txt"
grep -q "## 安装步骤" "$mounted_volume/README.md"
grep -q "## 当前版本主要功能" "$mounted_volume/README.md"
if grep -q "Developer Notes" "$mounted_volume/README.md"; then
  echo "DMG README should not include Developer Notes." >&2
  exit 1
fi

hdiutil detach "$mounted_volume" >/dev/null
mounted_volume=""

echo "DMG ready: $DMG_PATH"
