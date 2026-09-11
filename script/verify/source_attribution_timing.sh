#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEFAULT_EVIDENCE="$ROOT_DIR/.build/source-attribution-events.jsonl"

cleanup_live_session() {
    local log_pid="$1"
    local task_tmp="$2"
    kill "$log_pid" 2>/dev/null || true
    wait "$log_pid" 2>/dev/null || true
    rm -rf -- "$task_tmp"
}

register_live_cleanup() {
    local log_pid="$1"
    local task_tmp="$2"
    local cleanup_command
    printf -v cleanup_command 'cleanup_live_session %q %q' "$log_pid" "$task_tmp"
    trap "$cleanup_command" EXIT
}

usage() {
    echo "Usage:" >&2
    echo "  $0 analyze <non-keyboard|shortcut> <events.jsonl>" >&2
    echo "  $0 live <non-keyboard|shortcut> [evidence.jsonl]" >&2
    exit 2
}

analyze() {
    local mode="$1"
    local events_file="$2"
    /usr/bin/python3 - "$mode" "$events_file" <<'PY'
import json
import math
import sys
from pathlib import Path

mode = sys.argv[1]
path = Path(sys.argv[2])

def fail(message):
    print(f"FAIL source attribution timing: {message}", file=sys.stderr)
    raise SystemExit(1)

event_fields = {
    "pasteboard_observed": {"event", "uptime", "changeCount", "sourceApp"},
    "app_activated": {"event", "uptime", "changeCount", "sourceApp"},
    "copy_shortcut_observed": {"event", "uptime", "changeCount", "sourceApp", "operation"},
    "source_resolved": {"event", "uptime", "changeCount", "sourceApp", "resolutionSlot"},
}
resolution_slots = {
    "shortcut",
    "firstObservedForeground",
    "currentForeground",
    "recentForeground",
    "system",
    "unknown",
}

def validated_event(line, line_number):
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        fail(f"invalid JSON on line {line_number}")
    if not isinstance(event, dict):
        fail(f"event on line {line_number} is not an object")
    name = event.get("event")
    expected_fields = event_fields.get(name)
    if expected_fields is None or set(event) != expected_fields:
        fail(f"invalid event schema on line {line_number}")
    uptime = event["uptime"]
    if type(uptime) not in (int, float) or not math.isfinite(uptime) or uptime < 0:
        fail(f"invalid uptime on line {line_number}")
    if type(event["changeCount"]) is not int or event["changeCount"] < 0:
        fail(f"invalid changeCount on line {line_number}")
    if not isinstance(event["sourceApp"], str) or not event["sourceApp"]:
        fail(f"invalid sourceApp on line {line_number}")
    if name == "copy_shortcut_observed" and event["operation"] not in {"copy", "cut"}:
        fail(f"invalid shortcut operation on line {line_number}")
    if name == "source_resolved" and event["resolutionSlot"] not in resolution_slots:
        fail(f"invalid resolution slot on line {line_number}")
    return event

events = [
    validated_event(line, line_number)
    for line_number, line in enumerate(path.read_text().splitlines(), start=1)
    if line.strip()
]

if mode == "non-keyboard":
    for observed in (event for event in events if event.get("event") == "pasteboard_observed"):
        count = observed.get("changeCount")
        activated = next((
            event for event in events
            if event.get("event") == "app_activated"
            and event.get("changeCount") == count
            and event.get("sourceApp") == "Code"
            and event.get("uptime", 0) > observed.get("uptime", 0)
        ), None)
        resolved = next((
            event for event in events
            if event.get("event") == "source_resolved"
            and event.get("changeCount") == count
            and event.get("uptime", 0) > observed.get("uptime", 0)
        ), None)
        if activated and resolved:
            if not activated["uptime"] < resolved["uptime"]:
                fail("expected observation < Code activation < resolution")
            if observed.get("sourceApp") != "Google Chrome":
                fail("first-observed source is not Google Chrome")
            if resolved.get("sourceApp") != "Google Chrome":
                fail("resolved source is not Google Chrome")
            if resolved.get("resolutionSlot") != "firstObservedForeground":
                fail("resolution slot is not firstObservedForeground")
            print(
                "PASS source attribution timing"
                f" mode={mode} changeCount={count}"
                f" observedAt={observed['uptime']}"
                f" activatedAt={activated['uptime']}"
                f" resolvedAt={resolved['uptime']}"
                " source=Google Chrome slot=firstObservedForeground"
            )
            break
    else:
        fail("no correlated non-keyboard event sequence found")
elif mode == "shortcut":
    for shortcut in (event for event in events if event.get("event") == "copy_shortcut_observed"):
        if shortcut.get("operation") != "copy" or shortcut.get("sourceApp") != "Google Chrome":
            continue
        resolved = next((
            event for event in events
            if event.get("event") == "source_resolved"
            and event.get("resolutionSlot") == "shortcut"
            and event.get("sourceApp") == "Google Chrome"
            and event.get("uptime", 0) > shortcut.get("uptime", 0)
            and event.get("changeCount", -1) > shortcut.get("changeCount", -1)
        ), None)
        if not resolved:
            continue
        activated = next((
            event for event in events
            if event.get("event") == "app_activated"
            and event.get("sourceApp") == "Code"
            and shortcut.get("uptime", 0) < event.get("uptime", 0) < resolved.get("uptime", 0)
            and event.get("changeCount") == resolved.get("changeCount")
        ), None)
        if not activated:
            continue
        print(
            "PASS source attribution timing"
            f" mode={mode} changeCount={resolved['changeCount']}"
            f" shortcutAt={shortcut['uptime']}"
            f" activatedAt={activated['uptime']}"
            f" resolvedAt={resolved['uptime']}"
            " source=Google Chrome slot=shortcut"
        )
        break
    else:
        fail("no correlated physical-shortcut event sequence found")
else:
    fail(f"unsupported mode: {mode}")
PY
}

wait_for_pattern() {
    local path="$1"
    local pattern="$2"
    local attempts="$3"
    local index
    for ((index = 0; index < attempts; index++)); do
        if grep -q "$pattern" "$path"; then
            return 0
        fi
        sleep 0.05
    done
    echo "Timed out waiting for diagnostic event: $pattern" >&2
    return 1
}

extract_events() {
    local raw_log="$1"
    local evidence="$2"
    /usr/bin/python3 - "$raw_log" "$evidence" <<'PY'
import json
import math
import sys
from pathlib import Path

raw_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
events = []
event_fields = {
    "pasteboard_observed": {"event", "uptime", "changeCount", "sourceApp"},
    "app_activated": {"event", "uptime", "changeCount", "sourceApp"},
    "copy_shortcut_observed": {"event", "uptime", "changeCount", "sourceApp", "operation"},
    "source_resolved": {"event", "uptime", "changeCount", "sourceApp", "resolutionSlot"},
}
resolution_slots = {
    "shortcut",
    "firstObservedForeground",
    "currentForeground",
    "recentForeground",
    "system",
    "unknown",
}

def is_safe_event(event):
    if not isinstance(event, dict):
        return False
    name = event.get("event")
    expected_fields = event_fields.get(name)
    if expected_fields is None or set(event) != expected_fields:
        return False
    uptime = event["uptime"]
    if type(uptime) not in (int, float) or not math.isfinite(uptime) or uptime < 0:
        return False
    if type(event["changeCount"]) is not int or event["changeCount"] < 0:
        return False
    if not isinstance(event["sourceApp"], str) or not event["sourceApp"]:
        return False
    if name == "copy_shortcut_observed" and event["operation"] not in {"copy", "cut"}:
        return False
    if name == "source_resolved" and event["resolutionSlot"] not in resolution_slots:
        return False
    return True

for line in raw_path.read_text(errors="replace").splitlines():
    try:
        outer = json.loads(line)
    except json.JSONDecodeError:
        continue
    message = outer.get("eventMessage") or outer.get("composedMessage") or ""
    prefix = "source_timing "
    if not message.startswith(prefix):
        continue
    try:
        event = json.loads(message[len(prefix):])
    except json.JSONDecodeError:
        continue
    if is_safe_event(event):
        events.append(event)

output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text("".join(json.dumps(event, sort_keys=True) + "\n" for event in events))
PY
}

live() {
    local mode="$1"
    local evidence="${2:-$DEFAULT_EVIDENCE}"
    local diagnostics_enabled
    diagnostics_enabled="$(defaults read local.copythat.clipboard clipboardDiagnosticsEnabled 2>/dev/null || true)"
    if [[ "$diagnostics_enabled" != "1" ]]; then
        echo "Enable diagnostics and relaunch Copythat first:" >&2
        echo "  defaults write local.copythat.clipboard clipboardDiagnosticsEnabled -bool true" >&2
        exit 1
    fi

    local task_tmp
    task_tmp="$(mktemp -d -t copythat-source-attribution)"
    local raw_log="$task_tmp/oslog.jsonl"
    /usr/bin/log stream --style ndjson --level info \
        --predicate 'subsystem == "local.copythat.clipboard" AND category == "ClipboardDiagnostics" AND eventMessage BEGINSWITH "source_timing "' \
        >"$raw_log" 2>/dev/null &
    local log_pid=$!
    register_live_cleanup "$log_pid" "$task_tmp"
    sleep 0.5

    if [[ "$mode" == "non-keyboard" ]]; then
        local marker
        marker="copythat-acceptance-$(uuidgen)"
        osascript -e 'tell application id "com.google.Chrome" to activate'
        sleep 0.3
        printf '%s' "$marker" | /usr/bin/pbcopy
        wait_for_pattern "$raw_log" 'pasteboard_observed' 100
        osascript -e 'tell application id "com.microsoft.VSCode" to activate'
        wait_for_pattern "$raw_log" 'source_resolved' 100
    elif [[ "$mode" == "shortcut" ]]; then
        echo "Chrome will activate. Physically press Cmd+C, then switch to Visual Studio Code." >&2
        sleep 2
        osascript -e 'tell application id "com.google.Chrome" to activate'
        wait_for_pattern "$raw_log" 'copy_shortcut_observed' 1200
        wait_for_pattern "$raw_log" 'app_activated' 1200
        wait_for_pattern "$raw_log" 'source_resolved' 200
    else
        usage
    fi

    sleep 0.3
    kill "$log_pid" 2>/dev/null || true
    wait "$log_pid" 2>/dev/null || true
    extract_events "$raw_log" "$evidence"
    analyze "$mode" "$evidence"
    echo "Sanitized evidence: $evidence"
}

main() {
    [[ $# -ge 1 ]] || usage
    case "$1" in
        analyze)
            [[ $# -eq 3 ]] || usage
            analyze "$2" "$3"
            ;;
        live)
            [[ $# -ge 2 && $# -le 3 ]] || usage
            live "$2" "${3:-$DEFAULT_EVIDENCE}"
            ;;
        *)
            usage
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
