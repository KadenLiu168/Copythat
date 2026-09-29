#!/usr/bin/env bash
# preview_live.sh - live verification for the link preview pipeline (8.2).
#
# Builds an in-process driver that hosts the production ClipboardStore with
# the REAL LinkPreviewFetcher (LPMetadataProvider + WebKit) against local
# fixture pages, runs the 8.2 scenarios, and writes an automated-real-providers
# report. Events carry item ids, outcome kinds and uptime only - the runner
# re-validates that no URL or payload text appears in the event stream.
#
# Usage: preview_live.sh run [--port <n>] [--output <dir>]
#        preview_live.sh self-test

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/script/verify"
BUILD_DIR="$ROOT_DIR/.build/preview-live"
DRIVER_BIN="$BUILD_DIR/preview-live-driver"
DRIVER_PORT="${PREVIEW_FIXTURE_PORT:-8765}"

log() { echo "[preview-live] $*" >&2; }

usage() {
  echo "Usage:" >&2
  grep -E "^# (Usage:| +preview_live)" "$0" | sed 's/^# //' >&2
  exit 2
}

build_driver() {
  mkdir -p "$BUILD_DIR"
  log "compiling driver"
  local sources=(
    Sources/Copythat/Models/ClipboardItem.swift
    Sources/Copythat/Support/ClipboardDiagnostics.swift
    Sources/Copythat/Support/ClipboardHistoryPersistence.swift
    Sources/Copythat/Support/ClipboardHistoryPolicy.swift
    Sources/Copythat/Support/ClipboardHistoryMediaLoader.swift
    Sources/Copythat/Support/CopySourceResolution.swift
    Sources/Copythat/Support/LinkPreviewFetcher.swift
    Sources/Copythat/Support/LinkPreviewSnapshotController.swift
    Sources/Copythat/Support/NSImage+PasteData.swift
    Sources/Copythat/Support/String+Truncate.swift
    Sources/Copythat/Stores/AppSettings.swift
    Sources/Copythat/Stores/ClipboardStore.swift
    Sources/Copythat/Stores/ClipboardStore+LinkPreview.swift
    Sources/Copythat/Stores/Pinboard.swift
    Sources/Copythat/Services/CopySourceTracker.swift
    "$SCRIPT_DIR/preview_live_driver.swift"
    "$SCRIPT_DIR/preview_live_scenarios.swift"
  )
  if ! xcrun swiftc "${sources[@]}" \
      -o "$DRIVER_BIN" \
      -O -parse-as-library 2>"$BUILD_DIR/driver-build.log"; then
    sed -n '1,40p' "$BUILD_DIR/driver-build.log" >&2
    echo "[preview-live] driver failed to compile" >&2
    exit 2
  fi
  xattr -d com.apple.quarantine "$DRIVER_BIN" 2>/dev/null || true
  codesign -s - "$DRIVER_BIN" 2>/dev/null || true
}

start_fixture() {
  python3 "$SCRIPT_DIR/preview_fixture_server.py" "$DRIVER_PORT" &
  FIXTURE_PID=$!
  trap 'kill "$FIXTURE_PID" 2>/dev/null || true' EXIT
  # Wait until the fixture answers.
  for _ in {1..50}; do
    if python3 - "$DRIVER_PORT" <<'PY'
import socket, sys
try:
    socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=0.3).close()
    sys.exit(0)
except OSError:
    sys.exit(1)
PY
    then
      return 0
    fi
    sleep 0.1
  done
  echo "[preview-live] fixture server did not start" >&2
  exit 2
}

validate_payload_safety() {
  local report="$1"
  if grep -q "http" "$report"; then
    echo "[preview-live] payload-safety violation: URL token found in report" >&2
    exit 1
  fi
}

run_scenarios() {
  local DRIVER_PORT="${PREVIEW_FIXTURE_PORT:-8765}"
  local output_dir="$BUILD_DIR/reports/$(date +%Y%m%d-%H%M%S)"
  while (($#)); do
    case "$1" in
      --port)
        if [ "$#" -lt 2 ]; then usage; fi
        DRIVER_PORT="$2"
        shift 2
        ;;
      --output)
        if [ "$#" -lt 2 ]; then usage; fi
        output_dir="$2"
        shift 2
        ;;
      *)
        echo "Unknown run option: $1" >&2
        usage
        ;;
    esac
  done
  mkdir -p "$output_dir"
  build_driver
  start_fixture
  local status=0
  "$DRIVER_BIN" preview --port "$DRIVER_PORT" --report "$output_dir/report.json" || status=$?
  if grep -q "://" "$output_dir/report.json"; then
    echo "[preview-live] payload-safety violation in report" >&2
    exit 1
  fi
  log "report: $output_dir/report.json"
  case "$status" in
    0) log "all scenarios passed" ;;
    1) log "behavioral failure" ;;
    2) log "blocked - prerequisites incomplete" ;;
    *) log "unexpected exit $status" ;;
  esac
  exit "$status"
}

case "${1:-}" in
  run)
    shift
    run_scenarios "$@"
    ;;
  self-test)
    build_driver
    log "self-test passed (driver compiles)"
    ;;
  *)
    usage
    ;;
esac
