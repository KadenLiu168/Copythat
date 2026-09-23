#!/usr/bin/env bash
# clipboard_live.sh — unattended clipboard verification runner (D1).
#
# Profiles:
#   qualify-input    Qualify automated input delivery through the real event tap (task 1.3).
#   routine          Run all automatable clipboard scenarios (tasks 3.1-3.5).
#   original-writer  Run versioned original-writer recipes / replay support (tasks 4.1-4.3).
#
# Subcommands used by tests and tooling:
#   validate-report <report.json>   Validate a report against the D7 schema and
#                                   payload-safety rules (exit 0 valid, 1 invalid).
#
# Exit codes (D7): 0 all required cases passed; 1 behavioral/evidence failure;
# 2 incomplete prerequisites/coverage. Failures take precedence over blocked.
#
# The runner never reads stdin, never prompts for permissions, and never
# resets TCC. See docs/clipboard-live-verification.md for the one-time setup.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="$ROOT_DIR/script/verify"
DRIVER_SOURCE="$SCRIPT_DIR/clipboard_live_driver.swift"
REPORT_TOOL="$SCRIPT_DIR/clipboard_live_report.py"
BUILD_DIR="$ROOT_DIR/.build/clipboard-live"
DRIVER_BIN="$BUILD_DIR/clipboard-live-driver"
DEFAULT_REPORT_ROOT="$BUILD_DIR/reports"

usage() {
    echo "Usage:" >&2
    echo "  $0 run <qualify-input|routine|original-writer> [--output <dir>]" >&2
    echo "  $0 validate-report <report.json>" >&2
    echo "  $0 self-test" >&2
    exit 2
}

log() { printf '[clipboard-live] %s\n' "$*" >&2; }

die_blocked() {
    # Emit a blocked report-shaped message and exit 2.
    log "BLOCKED: $*"
    exit 2
}

# ---------------------------------------------------------------------------
# Owned-resource lifecycle (D6)
# ---------------------------------------------------------------------------

RUN_TMP=""
DRIVER_PID=""
CLEANED=0

cleanup() {
    [[ "$CLEANED" == "1" ]] && return
    CLEANED=1
    if [[ -n "${RUN_LOCK:-}" && -d "$RUN_LOCK" ]]; then
        rm -rf "$RUN_LOCK"
    fi
    if [[ -n "$DRIVER_PID" ]] && kill -0 "$DRIVER_PID" 2>/dev/null; then
        kill "$DRIVER_PID" 2>/dev/null || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            kill -0 "$DRIVER_PID" 2>/dev/null || break
            sleep 0.1
        done
        kill -9 "$DRIVER_PID" 2>/dev/null || true
    fi
    if [[ -n "$RUN_TMP" && -d "$RUN_TMP" ]]; then
        rm -rf -- "$RUN_TMP"
    fi
}
trap cleanup EXIT
trap 'cleanup; trap - INT; kill -INT $$' INT
trap 'cleanup; trap - TERM; kill -TERM $$' TERM

# Concurrent-run rejection (D6): one run at a time per checkout.
acquire_run_lock() {
    mkdir -p "$BUILD_DIR"
    local lock_dir="$BUILD_DIR/run.lock"
    if ! mkdir "$lock_dir" 2>/dev/null; then
        local owner_pid owner_state lock_age
        owner_pid="$(cat "$lock_dir/pid" 2>/dev/null || echo unknown)"
        owner_state="$(ps -o state= -p "$owner_pid" 2>/dev/null || echo dead)"
        lock_age="$(cat "$lock_dir/created" 2>/dev/null || echo 0)"
        # Self-healing: a dead OR zombie owner (killed runs linger as zombies
        # until reaped, fooling kill -0), or a lock older than an hour (crashed
        # run with a recycled pid), is stale and is cleaned up.
        if [[ "$owner_pid" == "unknown" || "$owner_state" == "dead" || "$owner_state" == *Z* ]] \
            || (( $(date +%s) - lock_age > 3600 )); then
            rm -rf "$lock_dir"
            mkdir "$lock_dir" 2>/dev/null || die_blocked "run lock directory cannot be recreated at $lock_dir"
        else
            die_blocked "another clipboard-live run is active (pid $owner_pid); concurrent runs are rejected; if this is stale, remove $lock_dir"
        fi
    fi
    echo $$ >"$lock_dir/pid"
    date +%s >"$lock_dir/created"
    RUN_LOCK="$lock_dir"
}

release_run_lock() {
    if [[ -n "${RUN_LOCK:-}" && -d "$RUN_LOCK" ]]; then
        rm -rf "$RUN_LOCK"
    fi
}

# ---------------------------------------------------------------------------
# Provenance (D7): revision + implementation-source digest, binary digest, versions.
# No raw diffs, no clipboard payloads.
# ---------------------------------------------------------------------------

source_snapshot_digest() {
    python3 - "$ROOT_DIR" <<'PY'
import hashlib
import os
import stat
import subprocess
import sys

root = sys.argv[1]
paths = subprocess.check_output([
    "git", "-C", root, "ls-files", "-z", "--cached", "--others",
    "--exclude-standard", "--", "Sources", "Tests", "script", "Package.swift",
]).split(b"\0")
snapshot = hashlib.sha256()
for path in sorted(p for p in paths if p):
    full_path = os.path.join(os.fsencode(root), path)
    metadata = os.lstat(full_path) if os.path.lexists(full_path) else None
    snapshot.update(path + b"\0")
    snapshot.update((str(stat.S_IMODE(metadata.st_mode)) if metadata else "missing").encode() + b"\0")
    if metadata and stat.S_ISLNK(metadata.st_mode):
        snapshot.update(os.readlink(full_path) + b"\0")
    if metadata and stat.S_ISREG(metadata.st_mode):
        with open(full_path, "rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                snapshot.update(chunk)
    snapshot.update(b"\0")
print(snapshot.hexdigest())
PY
}

file_digest() {
    [[ -f "$1" ]] && shasum -a 256 "$1" | cut -d' ' -f1 || echo "missing"
}

app_version() {
    local app_path="$1"
    local plist="$app_path/Contents/Info.plist"
    [[ -f "$plist" ]] && /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || echo "missing"
}

collect_metadata_json() {
    local profile="$1"
    local os_version mac_build chrome_version code_version driver_digest snapshot_digest revision
    os_version="$(sw_vers -productVersion)"
    mac_build="$(sw_vers -buildVersion)"
    chrome_version="$(app_version "/Applications/Google Chrome.app")"
    code_version="$(app_version "/Applications/Visual Studio Code.app")"
    driver_digest="$(file_digest "$DRIVER_BIN")"
    snapshot_digest="$(source_snapshot_digest)"
    revision="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || echo "no-head")"
    cat <<JSON
{
    "profile": "$profile",
    "provenance": {
        "sourceRevision": "$revision",
        "sourceSnapshotDigest": "$snapshot_digest",
        "driverDigest": "$driver_digest",
        "driverPath": "$DRIVER_BIN",
        "buildConfiguration": "swiftc-asserts-release",
        "osVersion": "$os_version",
        "osBuild": "$mac_build",
        "chromeVersion": "$chrome_version",
        "codeVersion": "$code_version",
        "timingConstants": {"minimumStabilityInterval": 0.15, "burstPollInterval": 0.06, "burstWindow": 0.6},
        "inputMechanism": "osascript System Events keystroke (automated; not physical HID)"
    }
}
JSON
}

# Bounded osascript: if automation/Accessibility were not pre-authorized, an
# osascript call can block on a TCC prompt. The prepared-session contract (D2)
# forbids prompts, so every preflight osascript call is bounded and a hang is
# reported as blocked, never waited on.
bounded_osascript() {
    local script="$1"
    local timeout_seconds="${2:-5}"
    osascript -e "$script" >/dev/null 2>&1 &
    local osascript_pid=$!
    local waited=0
    while kill -0 "$osascript_pid" 2>/dev/null && (( waited < timeout_seconds * 10 )); do
        sleep 0.1
        waited=$((waited + 1))
    done
    if kill -0 "$osascript_pid" 2>/dev/null; then
        kill -9 "$osascript_pid" 2>/dev/null || true
        wait "$osascript_pid" 2>/dev/null || true
        return 124
    fi
    wait "$osascript_pid" 2>/dev/null || return 1
    return 0
}

# D6 sentinels: digests of the real user's clipboard defaults domain and
# history file. The runner itself must never change them. A resident Copythat
# process legitimately writes real history during runs, so changes are
# reported as interference metadata instead of runner failures.
HISTORY_FILE="$HOME/Library/Application Support/Copythat/clipboard-history.json"

user_state_digest() {
    {
        defaults export local.copythat.clipboard - 2>/dev/null | shasum -a 256 | cut -d' ' -f1
        if [[ -f "$HISTORY_FILE" ]]; then
            shasum -a 256 "$HISTORY_FILE" | cut -d' ' -f1
        else
            echo missing
        fi
    } | shasum -a 256 | cut -d' ' -f1
}

resident_copythat_pids() {
    pgrep -f "Copythat.app/Contents/MacOS/Copythat" 2>/dev/null || true
}

SENTINEL_BEFORE=""
INTERFERENCE_NOTE=""

capture_user_sentinel() {
    SENTINEL_BEFORE="$(user_state_digest)"
    if [[ -n "$(resident_copythat_pids)" ]]; then
        INTERFERENCE_NOTE="resident Copythat process is running; it captures scenario copies into the real user history independently of this runner"
        log "note: $INTERFERENCE_NOTE"
    fi
}

verify_user_sentinel() {
    local after
    after="$(user_state_digest)"
    if [[ "$after" == "$SENTINEL_BEFORE" ]]; then
        log "user history/settings sentinel unchanged"
        return 0
    fi
    if [[ -n "$(resident_copythat_pids)" ]]; then
        log "user history/settings sentinel changed while a resident Copythat process is running (expected interference source: the resident app, not this runner)"
        return 0
    fi
    log "FAIL: real user history/settings changed during the run with no resident Copythat process; this runner wrote outside its isolation"
    return 1
}

# ---------------------------------------------------------------------------
# Driver build + probe (preflight, D2)
# ---------------------------------------------------------------------------

build_driver() {
    mkdir -p "$BUILD_DIR"
    log "compiling driver"
    local sources=(
        Sources/Copythat/Models/ClipboardItem.swift
        Sources/Copythat/Support/ClipboardDiagnostics.swift
        Sources/Copythat/Support/ClipboardHistoryPersistence.swift
        Sources/Copythat/Support/ClipboardHistoryPolicy.swift
        Sources/Copythat/Support/CopySourceResolution.swift
        Sources/Copythat/Support/LinkPreviewFetcher.swift
        Sources/Copythat/Support/NSImage+PasteData.swift
        Sources/Copythat/Support/String+Truncate.swift
        Sources/Copythat/Stores/AppSettings.swift
        Sources/Copythat/Stores/ClipboardStore.swift
        Sources/Copythat/Services/CopySourceTracker.swift
        "$DRIVER_SOURCE"
    )
    if ! xcrun swiftc "${sources[@]}" \
        -o "$DRIVER_BIN" \
        -O -parse-as-library 2>"$BUILD_DIR/driver-build.log"; then
        sed -n '1,40p' "$BUILD_DIR/driver-build.log" >&2
        die_blocked "driver failed to compile"
    fi
    xattr -d com.apple.quarantine "$DRIVER_BIN" 2>/dev/null || true
    codesign -s - "$DRIVER_BIN" 2>/dev/null || true
}

driver_probe_json() {
    "$DRIVER_BIN" probe
}

preflight() {
    local profile="$1"

    build_driver

    # Session must answer frontmost queries (unlocked graphical session, D2).
    if ! bounded_osascript 'tell application "System Events" to name of first process whose frontmost is true'; then
        die_blocked "no unlocked graphical session: frontmost application query failed or timed out"
    fi

    # Automated input must be pre-authorized: never prompt (D2). key code 63 is
    # the inert function key; a hang here means a permission prompt would appear.
    if ! bounded_osascript 'tell application "System Events" to key code 63' 3; then
        die_blocked "System Events keystroke delivery is not authorized for this session; grant Accessibility/automation in a prepared session, then rerun"
    fi

    local probe
    probe="$(driver_probe_json)" || die_blocked "driver probe crashed"

    local trusted tap chrome code
    trusted="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["accessibilityTrusted"])' "$probe")"
    tap="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["eventTapCreated"])' "$probe")"
    chrome="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["chromeInstalled"])' "$probe")"
    code="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["codeInstalled"])' "$probe")"

    [[ "$trusted" == "True" ]] || die_blocked "driver binary lacks Accessibility trust (AXIsProcessTrusted=false); grant Accessibility to $DRIVER_BIN in a prepared session, then rerun"
    [[ "$chrome" == "True" ]] || die_blocked "Google Chrome is not installed; routine profile requires it"
    [[ "$code" == "True" ]] || die_blocked "Visual Studio Code is not installed; routine profile requires it as paste target"

    if [[ "$profile" == "routine" && "$tap" != "True" ]]; then
        # Event tap unavailable: shortcut-observation scenarios are blocked but
        # idle-fallback scenarios remain runnable (D2: no silent fallback).
        export CLIPBOARD_LIVE_TAP_BLOCKED=1
        log "event tap unavailable in probe; shortcut-observation scenarios will report blocked"
    fi

    log "preflight ok (accessibility=$trusted tap=$tap chrome=$chrome code=$code)"
}

# ---------------------------------------------------------------------------
# Report assembly (D7)
# ---------------------------------------------------------------------------

sanitized_report() {
    local profile="$1"
    local results_file="$2"
    local output_dir="$3"
    local started="$4"
    local ended
    ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    python3 "$REPORT_TOOL" assemble \
        --profile "$profile" \
        --results "$results_file" \
        --output-dir "$output_dir" \
        --started "$started" \
        --ended "$ended" \
        --metadata-json <(collect_metadata_json "$profile") \
        --original-root "$ROOT_DIR" \
        --interference-note "$INTERFERENCE_NOTE"
}

final_exit_code() {
    # D7: failures (1) take precedence over blocked/not-covered (2).
    local code
    code="$(python3 "$REPORT_TOOL" exit-code --report "$1")"
    exit "$code"
}

# ---------------------------------------------------------------------------
# Profiles
# ---------------------------------------------------------------------------

run_profile() {
    local profile="$1"
    shift || true
    local output_dir=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output) output_dir="$2"; shift 2 ;;
            *) usage ;;
        esac
    done
    [[ -n "$output_dir" ]] || output_dir="$DEFAULT_REPORT_ROOT/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$output_dir"

    acquire_run_lock

    # Test-only hooks (script/verify/clipboard_live_test.sh) exercising the
    # blocked paths without a second physical session; placed before the
    # driver build so self-tests stay fast.
    if [[ "${CLIPBOARD_LIVE_TEST_BLOCK_FRONTMOST:-0}" == "1" ]]; then
        die_blocked "no unlocked graphical session: frontmost application query failed"
    fi
    if [[ "${CLIPBOARD_LIVE_TEST_BLOCK_KEYSTROKE:-0}" == "1" ]]; then
        die_blocked "System Events keystroke delivery is not authorized for this session; grant Accessibility/automation in a prepared session, then rerun"
    fi
    if [[ "${CLIPBOARD_LIVE_TEST_BLOCK_APP:-0}" == "1" ]]; then
        die_blocked "Google Chrome is not installed; routine profile requires it"
    fi
    if [[ "${CLIPBOARD_LIVE_TEST_BLOCK_AX:-0}" == "1" ]]; then
        die_blocked "driver binary lacks Accessibility trust (AXIsProcessTrusted=false); grant Accessibility to $DRIVER_BIN in a prepared session, then rerun"
    fi

    preflight "$profile"
    capture_user_sentinel

    RUN_TMP="$(mktemp -d -t copythat-clipboard-live)"
    local results_file="$RUN_TMP/results.jsonl"
    local plan_file="$RUN_TMP/plan.json"

    python3 "$SCRIPT_DIR/clipboard_live_plan.py" plan --profile "$profile" --out "$plan_file"

    local started
    started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    log "running profile $profile (scenarios: $(python3 -c 'import json,sys;print(", ".join(s["name"] for s in json.load(open(sys.argv[1]))["scenarios"]))' "$plan_file"))"

    # Owned-process tracking (D6): the driver runs as a child whose PID is
    # recorded so EXIT/INT/TERM traps stop exactly this process, never others.
    set +e
    "$DRIVER_BIN" run --plan "$plan_file" \
        --events "$RUN_TMP/events.jsonl" \
        --results "$results_file" \
        --isolation "$RUN_TMP/isolation" \
        --work "$RUN_TMP/work" \
        --report-dir "$output_dir" &
    DRIVER_PID=$!
    wait "$DRIVER_PID"
    local driver_status=$?
    DRIVER_PID=""
    set -e
    if [[ $driver_status -ne 0 && $driver_status -ne 1 && $driver_status -ne 2 ]]; then
        die_blocked "driver exited with unexpected status $driver_status"
    fi

    # Preserve sanitized evidence in the report directory before the temp
    # cleanup runs (D6: reports survive cleanup even when assembly fails).
    cp "$results_file" "$output_dir/results.jsonl" 2>/dev/null || true
    cp "$RUN_TMP/events.jsonl" "$output_dir/events.jsonl" 2>/dev/null || true
    cp "$RUN_TMP/events.jsonl-injection" "$output_dir/events-injection.jsonl" 2>/dev/null || true

    local report="$output_dir/report.json"
    sanitized_report "$profile" "$results_file" "$output_dir" "$started" >"$report"

    # Payload-safety and schema gate: a report that cannot be validated fails (D7).
    if ! python3 "$REPORT_TOOL" validate --report "$report"; then
        log "report validation FAILED: $report"
        exit 1
    fi

    release_run_lock

    if ! verify_user_sentinel; then
        exit 1
    fi

    local human="$output_dir/report.txt"
    python3 "$REPORT_TOOL" summarize --report "$report" >"$human"
    cat "$human" >&2
    log "report: $report"
    log "events (sanitized): $RUN_TMP/events.jsonl -> $output_dir/events.jsonl"
    cp "$RUN_TMP/events.jsonl" "$output_dir/events.jsonl" 2>/dev/null || true

    final_exit_code "$report"
}

run_original_writer() {
    # Tasks 4.1-4.3: recipe-driven replay. Recipes live in script/verify/recipes/.
    local profile="original-writer"
    local output_dir=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output) output_dir="$2"; shift 2 ;;
            *) usage ;;
        esac
    done
    [[ -n "$output_dir" ]] || output_dir="$DEFAULT_REPORT_ROOT/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$output_dir"

    # Concurrent-run rejection (D6): the original-writer profile runs the
    # driver too, so it must hold the same single-run lock as routine runs.
    acquire_run_lock

    preflight "$profile"
    capture_user_sentinel

    RUN_TMP="$(mktemp -d -t copythat-clipboard-live)"
    local results_file="$RUN_TMP/results.jsonl"

    local started
    started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    log "running original-writer profile"

    # Historical reproduction prerequisite (D5): an established recipe must
    # exist; without one the profile records the precise missing evidence,
    # including the installed writer candidates' versions as metadata.
    local recipe_dir="$SCRIPT_DIR/recipes"
    local chatgpt_version="" doubao_version=""
    [[ -d "/Applications/ChatGPT.app" ]] && chatgpt_version="$(app_version "/Applications/ChatGPT.app")"
    [[ -d "/Applications/Doubao.app" ]] && doubao_version="$(app_version "/Applications/Doubao.app")"
    if [[ ! -d "$recipe_dir" ]] || ! ls "$recipe_dir"/*.json >/dev/null 2>&1; then
        python3 "$REPORT_TOOL" blocked-scenario \
            --scenario "original_writer_replay" \
            --reason "no established original-writer recipe exists: the archived Doubao-to-ChatGPT sequence lacks a recorded application identity/version and exact action list. Installed writer candidates found: ChatGPT.app ${chatgpt_version:-absent}, Doubao.app ${doubao_version:-absent}; installed metadata alone cannot establish the historical action sequence or the measured baseline, so original 5.2 stays pending" \
            --evidence-level "unavailable" \
            >"$results_file"
    else
        set +e
        "$DRIVER_BIN" recipe --recipe-dir "$recipe_dir" \
            --events "$RUN_TMP/events.jsonl" \
            --results "$results_file" \
            --work "$RUN_TMP/work"
        local recipe_status=$?
        set -e
        if [[ $recipe_status -ne 0 && $recipe_status -ne 1 && $recipe_status -ne 2 ]]; then
            die_blocked "recipe driver exited with unexpected status $recipe_status"
        fi
    fi

    # Deterministic replay support (task 4.3): when a measured-transition
    # fixture exists, replay it with synthetic content (labeled synthetic).
    if [[ -n "${REPLAY_TRANSITIONS:-}" && -f "$REPLAY_TRANSITIONS" ]]; then
        set +e
        "$DRIVER_BIN" replay --transitions "$REPLAY_TRANSITIONS" \
            --events "$RUN_TMP/events-replay.jsonl" \
            --results "$RUN_TMP/results-replay.jsonl" \
            --work "$RUN_TMP/work-replay"
        set -e
        cat "$RUN_TMP/results-replay.jsonl" >>"$results_file" 2>/dev/null || true
    fi

    # Preserve sanitized evidence before temp cleanup (D6).
    cp "$results_file" "$output_dir/results.jsonl" 2>/dev/null || true
    cp "$RUN_TMP/events.jsonl" "$output_dir/events.jsonl" 2>/dev/null || true

    local report="$output_dir/report.json"
    sanitized_report "$profile" "$results_file" "$output_dir" "$started" >"$report"
    if ! python3 "$REPORT_TOOL" validate --report "$report"; then
        log "report validation FAILED: $report"
        exit 1
    fi
    release_run_lock

    if ! verify_user_sentinel; then
        exit 1
    fi

    python3 "$REPORT_TOOL" summarize --report "$report" >&2
    log "report: $report"
    final_exit_code "$report"
}

# ---------------------------------------------------------------------------
# Self-test (fixtures; no live input, D7 malformed/missing/stale cannot pass)
# ---------------------------------------------------------------------------

run_self_test() {
    # No run lock here: the self-test is fixtures, not a profile run, and its
    # nested runner invocations must reach their own blocked-path hooks and
    # lock semantics (the concurrent-rejection fixture creates its own lock).
    log "self-test: report validation fixtures"
    if CLIPBOARD_LIVE_ROOT="$ROOT_DIR" bash "$SCRIPT_DIR/clipboard_live_test.sh"; then
        log "self-test passed"
        return 0
    fi
    log "self-test FAILED"
    return 1
}

main() {
    [[ $# -ge 1 ]] || usage
    case "$1" in
        run)
            [[ $# -ge 2 ]] || usage
            case "$2" in
                qualify-input|routine) run_profile "$2" "${@:3}" ;;
                original-writer) run_original_writer "${@:3}" ;;
                *) usage ;;
            esac
            ;;
        validate-report)
            [[ $# -eq 2 ]] || usage
            python3 "$REPORT_TOOL" validate --report "$2"
            ;;
        self-test)
            run_self_test
            ;;
        *) usage ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
