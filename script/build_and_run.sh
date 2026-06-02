#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Copythat"
BUNDLE_ID="local.copythat.clipboard"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Copythat.entitlements"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"
BUILD_DIR="$(dirname "$BUILD_BINARY")"
RESOURCE_BUNDLE="$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [ -f "$ROOT_DIR/Sources/Copythat/Resources/AppIcon.icns" ]; then
  cp "$ROOT_DIR/Sources/Copythat/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
fi

if [ -d "$RESOURCE_BUNDLE" ]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>Copythat uses automation only when needed to return copied content to the app you selected.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>Copythat checks window positions so the clipboard panel can appear near the active workspace.</string>
</dict>
</plist>
PLIST

if [ -f "$ENTITLEMENTS" ]; then
  codesign --force --sign - --options runtime --entitlements "$ENTITLEMENTS" "$APP_BUNDLE" >/dev/null
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --verify-panel|verify-panel)
    /usr/bin/open -n --env COPYTHAT_OPEN_PANEL_ON_LAUNCH=1 "$APP_BUNDLE"
    APP_PID=""
    for _ in {1..40}; do
      APP_PID="$(pgrep -x "$APP_NAME" || true)"
      if [ -n "$APP_PID" ]; then
        break
      fi
      sleep 0.2
    done
    if [ -z "$APP_PID" ]; then
      echo "Copythat process did not launch" >&2
      exit 1
    fi
    swift - "$APP_PID" <<'SWIFT'
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2,
      let pid = Int(CommandLine.arguments[1]) else {
    fatalError("missing Copythat pid")
}

let deadline = Date().addingTimeInterval(8)
var panel: [String: Any]?

repeat {
    let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
    panel = windows.first { window in
        guard (window[kCGWindowOwnerPID as String] as? Int) == pid,
              let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
              let width = bounds["Width"],
              let height = bounds["Height"] else {
            return false
        }
        return width >= 560 && height >= 300
    }
    if panel != nil { break }
    Thread.sleep(forTimeInterval: 0.2)
} while Date() < deadline

guard let panel else {
    fatalError("Copythat panel did not appear in the window server")
}
print("panel ok", panel[kCGWindowBounds as String] ?? [:])
SWIFT
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--verify-panel]" >&2
    exit 2
    ;;
esac
