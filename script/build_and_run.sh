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
APP_RESOURCE_BUNDLE="$APP_RESOURCES/${APP_NAME}_${APP_NAME}.bundle"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Copythat.entitlements"
DEFAULT_SIGN_IDENTITY="Copythat Local Code Signing"
SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"

if [ -z "$SIGN_IDENTITY" ] &&
   security find-identity -p codesigning -v | grep -Fq "$DEFAULT_SIGN_IDENTITY"; then
  SIGN_IDENTITY="$DEFAULT_SIGN_IDENTITY"
fi

signing_identity() {
  if [ -n "$SIGN_IDENTITY" ] && [ "$SIGN_IDENTITY" != "-" ]; then
    echo "$SIGN_IDENTITY"
  else
    echo "-"
  fi
}

signing_label() {
  if [ -n "$SIGN_IDENTITY" ] && [ "$SIGN_IDENTITY" != "-" ]; then
    echo "$SIGN_IDENTITY"
  else
    echo "ad hoc"
  fi
}

validate_signing_identity() {
  if [ -z "$SIGN_IDENTITY" ] || [ "$SIGN_IDENTITY" = "-" ]; then
    return
  fi

  if ! security find-identity -p codesigning -v | grep -Fq "$SIGN_IDENTITY"; then
    echo "Code signing identity not found: $SIGN_IDENTITY" >&2
    echo "Create a local Code Signing certificate, or unset CODESIGN_IDENTITY to use ad hoc signing." >&2
    exit 1
  fi
}

sign_app() {
  validate_signing_identity

  local identity
  identity="$(signing_identity)"

  if [ -f "$ENTITLEMENTS" ]; then
    codesign --force --sign "$identity" --options runtime --entitlements "$ENTITLEMENTS" "$APP_BUNDLE" >/dev/null
  else
    codesign --force --sign "$identity" --options runtime "$APP_BUNDLE" >/dev/null
  fi

  echo "Signed $APP_BUNDLE with $(signing_label) signing."
}

verify_resource_bundle() {
  if [ ! -f "$APP_RESOURCE_BUNDLE/MenuBarIconTemplate.png" ]; then
    echo "Missing SwiftPM resource bundle at $APP_RESOURCE_BUNDLE" >&2
    exit 1
  fi
}

verify_signature() {
  if [ ! -d "$APP_BUNDLE" ]; then
    echo "$APP_BUNDLE does not exist. Run ./script/build_and_run.sh first." >&2
    exit 1
  fi

  codesign -dvvv "$APP_BUNDLE" 2>&1
}

verify_portable_app() {
  verify_resource_bundle

  PORTABLE_DIR="$(mktemp -d -t copythat_portable_app)"
  PORTABLE_APP="$PORTABLE_DIR/$APP_NAME.app"
  PORTABLE_HIDDEN_RESOURCE=""

  cleanup_portable_verify() {
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    if [ -n "$PORTABLE_HIDDEN_RESOURCE" ] && [ -d "$PORTABLE_HIDDEN_RESOURCE" ]; then
      mv "$PORTABLE_HIDDEN_RESOURCE" "$RESOURCE_BUNDLE"
    fi
    rm -rf "$PORTABLE_DIR"
  }
  trap cleanup_portable_verify EXIT

  cp -R "$APP_BUNDLE" "$PORTABLE_APP"

  if [ -d "$RESOURCE_BUNDLE" ]; then
    PORTABLE_HIDDEN_RESOURCE="$RESOURCE_BUNDLE.portable-hidden"
    rm -rf "$PORTABLE_HIDDEN_RESOURCE"
    mv "$RESOURCE_BUNDLE" "$PORTABLE_HIDDEN_RESOURCE"
  fi

  /usr/bin/open -n "$PORTABLE_APP"
  for _ in {1..40}; do
    if pgrep -x "$APP_NAME" >/dev/null; then
      echo "portable app ok"
      cleanup_portable_verify
      trap - EXIT
      return
    fi
    sleep 0.2
  done

  echo "Portable Copythat app did not launch without $RESOURCE_BUNDLE" >&2
  exit 1
}

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
  cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCE_BUNDLE"
fi

verify_resource_bundle

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

sign_app

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
  --verify-portable|verify-portable)
    verify_portable_app
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

let deadline = Date().addingTimeInterval(20)
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
  --verify-signature|verify-signature)
    verify_signature
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--verify-portable|--verify-panel|--verify-signature]" >&2
    exit 2
    ;;
esac
