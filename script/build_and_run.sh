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
BUILD_CONFIGURATION="${COPYTHAT_BUILD_CONFIGURATION:-debug}"

case "$BUILD_CONFIGURATION" in
  debug)
    ;;
  release)
    ;;
  *)
    echo "Unsupported COPYTHAT_BUILD_CONFIGURATION: $BUILD_CONFIGURATION" >&2
    echo "Use debug or release." >&2
    exit 2
    ;;
esac

swift_build() {
  if [ "$BUILD_CONFIGURATION" = "release" ]; then
    swift build -c release "$@"
  else
    swift build "$@"
  fi
}

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
  if [ ! -f "$APP_RESOURCE_BUNDLE/MenuBarIconTemplate.png" ] &&
     [ ! -f "$APP_RESOURCE_BUNDLE/Contents/Resources/MenuBarIconTemplate.png" ]; then
    echo "Missing SwiftPM resource bundle image at $APP_RESOURCE_BUNDLE or $APP_RESOURCE_BUNDLE/Contents/Resources" >&2
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

VERIFY_PID=""
VERIFY_ROOT=""
VERIFY_SUITE=""

cleanup_isolated_verify() {
  if [ -n "$VERIFY_PID" ]; then
    kill "$VERIFY_PID" 2>/dev/null || true
    wait "$VERIFY_PID" 2>/dev/null || true
    VERIFY_PID=""
  fi
  if [ -n "$VERIFY_SUITE" ]; then
    /usr/bin/defaults delete "$VERIFY_SUITE" >/dev/null 2>&1 || true
  fi
  if [ -n "$VERIFY_ROOT" ]; then rm -rf "$VERIFY_ROOT"; fi
}

launch_isolated_verify() {
  local binary="$1"
  local open_panel="${2:-0}"
  VERIFY_ROOT="$(mktemp -d -t copythat_verify)"
  VERIFY_SUITE="local.copythat.verify.$(uuidgen)"
  trap cleanup_isolated_verify EXIT
  COPYTHAT_VERIFY_ROOT="$VERIFY_ROOT" \
  COPYTHAT_VERIFY_DEFAULTS_SUITE="$VERIFY_SUITE" \
  COPYTHAT_TEST_PASTEBOARD_NAME="$VERIFY_SUITE.pasteboard" \
  COPYTHAT_OPEN_PANEL_ON_LAUNCH="$open_panel" \
    "$binary" &
  VERIFY_PID=$!
  echo "isolation root=$VERIFY_ROOT defaults=$VERIFY_SUITE pasteboard=$VERIFY_SUITE.pasteboard pid=$VERIFY_PID"
  for _ in {1..100}; do
    if ! kill -0 "$VERIFY_PID" 2>/dev/null; then
      echo "Isolated app exited before launch completed" >&2
      return 1
    fi
    if [ -f "$VERIFY_ROOT/ready" ]; then return 0; fi
    sleep 0.2
  done
  echo "Isolated app did not complete launch" >&2
  return 1
}

verify_portable_app() {
  verify_resource_bundle

  PORTABLE_DIR="$(mktemp -d -t copythat_portable_app)"
  PORTABLE_APP="$PORTABLE_DIR/$APP_NAME.app"
  PORTABLE_HIDDEN_RESOURCE=""

  cleanup_portable_verify() {
    cleanup_isolated_verify
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

  launch_isolated_verify "$PORTABLE_APP/Contents/MacOS/$APP_NAME"
  trap cleanup_portable_verify EXIT
  for _ in {1..40}; do
    if kill -0 "$VERIFY_PID" 2>/dev/null; then
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

case "$MODE" in
  --verify|verify|--verify-portable|verify-portable|--verify-panel|verify-panel)
    if [ "$BUILD_CONFIGURATION" != "debug" ]; then
      echo "Isolated verification requires a debug build" >&2
      exit 2
    fi
    ;;
  *) pkill -x "$APP_NAME" >/dev/null 2>&1 || true ;;
esac

swift_build
BUILD_BINARY="$(swift_build --show-bin-path)/$APP_NAME"
BUILD_DIR="$(dirname "$BUILD_BINARY")"
RESOURCE_BUNDLE="$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

SOURCE_APP_ICON="$ROOT_DIR/Sources/Copythat/Resources/AppIcon.icns"
if [ ! -f "$SOURCE_APP_ICON" ]; then
  echo "Missing app icon source at $SOURCE_APP_ICON" >&2
  exit 1
fi
cp "$SOURCE_APP_ICON" "$APP_RESOURCES/AppIcon.icns"

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
</dict>
</plist>
PLIST

validate_app_icon() {
  local icon_file

  if ! plutil -lint "$INFO_PLIST" >/dev/null; then
    echo "Invalid outer app Info.plist at $INFO_PLIST" >&2
    exit 1
  fi

  if ! icon_file="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$INFO_PLIST" 2>/dev/null)"; then
    echo "Missing CFBundleIconFile in $INFO_PLIST" >&2
    exit 1
  fi

  if [ "$icon_file" != "AppIcon" ]; then
    echo "CFBundleIconFile must be AppIcon in $INFO_PLIST" >&2
    exit 1
  fi

  if [ ! -f "$APP_RESOURCES/${icon_file}.icns" ]; then
    echo "Missing outer app icon resource at $APP_RESOURCES/${icon_file}.icns" >&2
    exit 1
  fi
}

validate_app_icon
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
    launch_isolated_verify "$APP_BINARY"
    sleep 1
    kill -0 "$VERIFY_PID"
    ;;
  --verify-portable|verify-portable)
    verify_portable_app
    ;;
  --verify-panel|verify-panel)
    launch_isolated_verify "$APP_BINARY" 1
    APP_PID="$VERIFY_PID"
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
