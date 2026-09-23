#!/usr/bin/env bash
# clipboard_live_test.sh — analyzer fixtures for the clipboard_live report
# contract (D7). Proves malformed, missing, stale, out-of-order, and
# payload-bearing evidence can never validate as passing, and that exit codes
# follow the failure-precedence rule. No live input is performed.
set -euo pipefail

ROOT_DIR="${CLIPBOARD_LIVE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SCRIPT_DIR="$ROOT_DIR/script/verify"
REPORT_TOOL="$SCRIPT_DIR/clipboard_live_report.py"
PLAN_TOOL="$SCRIPT_DIR/clipboard_live_plan.py"

WORK="$(mktemp -d -t copythat-clipboard-live-test)"
trap 'rm -rf "$WORK"' EXIT

pass() { echo "ok: $1"; }

expect_validate_ok() {
    if ! python3 "$REPORT_TOOL" validate --report "$1" >/dev/null; then
        echo "expected valid report: $1" >&2
        python3 "$REPORT_TOOL" validate --report "$1" >&2 || true
        exit 1
    fi
    pass "valid report accepted: $2"
}

expect_validate_fails() {
    if python3 "$REPORT_TOOL" validate --report "$1" >/dev/null 2>&1; then
        echo "expected invalid report: $1 ($2)" >&2
        exit 1
    fi
    pass "invalid report rejected: $2"
}

# The source identity must change when bytes change without a Git status change.
(
    repo="$WORK/source-identity"
    mkdir -p "$repo/Sources" "$repo/script"
    git -C "$repo" init -q
    printf 'first\n' >"$repo/Sources/tracked.swift"
    git -C "$repo" add Sources/tracked.swift
    git -C "$repo" -c user.name=Tests -c user.email=tests@example.invalid commit -qm initial
    printf 'second\n' >"$repo/Sources/tracked.swift"
    source "$SCRIPT_DIR/clipboard_live.sh"
    ROOT_DIR="$repo"
    before="$(source_snapshot_digest)"
    printf 'third\n' >"$repo/Sources/tracked.swift"
    after_tracked="$(source_snapshot_digest)"
    [[ "$before" != "$after_tracked" ]] || { echo "tracked content did not change source identity" >&2; exit 1; }
    printf 'first\n' >"$repo/script/untracked.sh"
    before_untracked="$(source_snapshot_digest)"
    printf 'second\n' >"$repo/script/untracked.sh"
    after_untracked="$(source_snapshot_digest)"
    [[ "$before_untracked" != "$after_untracked" ]] || { echo "untracked content did not change source identity" >&2; exit 1; }
)
pass "source identity changes with tracked and untracked file contents"

# --- Base valid report ------------------------------------------------------

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

python3 - "$WORK/valid.json" "$NOW" <<'PY'
import json, sys

path, now = sys.argv[1], sys.argv[2]
scenario = {
    "scenario": "input_qualification",
    "verdict": "passed",
    "evidenceLevel": "automated-real-desktop",
    "reason": "shortcut observation, pasteboard change, and committed capture correlated",
    "assertions": [
        {"name": "shortcutObserved", "expected": "true", "observed": "true", "ok": True},
        {"name": "pasteboardChanged", "expected": "true", "observed": "true", "ok": True},
        {"name": "fixtureCommitted", "expected": "true", "observed": "true", "ok": True},
    ],
    "timings": {"shortcutLatency": 0.1},
    "inputMechanism": "osascript System Events keystroke (automated)",
}
report = {
    "schemaVersion": 1,
    "tool": "clipboard-live",
    "profile": "qualify-input",
    "startedAt": now,
    "endedAt": now,
    "provenance": {
        "sourceRevision": "deadbeef",
        "sourceSnapshotDigest": "a" * 64,
        "driverDigest": "b" * 64,
        "driverPath": "/repo/.build/clipboard-live/clipboard-live-driver",
        "buildConfiguration": "swiftc-asserts-release",
        "osVersion": "27.0",
        "osBuild": "26A428",
        "chromeVersion": "153.0.8010.48",
        "codeVersion": "1.99.0",
        "timingConstants": {"minimumStabilityInterval": 0.15, "burstPollInterval": 0.06, "burstWindow": 0.6},
        "inputMechanism": "osascript System Events keystroke (automated; not physical HID)",
    },
    "requiredScenarios": ["input_qualification"],
    "scenarios": [scenario],
    "summary": {"passed": 1, "failed": 0, "blocked": 0, "not-covered": 0},
    "originalTaskMapping": {
        "improve-clipboard-capture-responsiveness 5.2": (
            "120 ms synthetic replay accepted by user for this Change; historical "
            "writer behavior and measured baseline remain unverified"
        ),
        "improve-clipboard-capture-responsiveness 5.3": (
            "qualified automated OS-input copies accepted by user for this Change; "
            "physical HID behavior remains unverified"
        ),
        "improve-clipboard-capture-responsiveness 5.5": (
            "automated coverage accepted for cut, region screenshot, app switching, "
            "restore/paste, and injected tap failure; physical screenshot System "
            "source, multi-display, and OS permission denial remain unverified"
        ),
    },
    "evidenceBoundaries": (
        "automated-real-desktop evidence is OS input through the real event tap; "
        "it does not prove physical HID behavior. "
        "synthetic-replay evidence is labeled and never counts as original-writer "
        "reproduction."
    ),
}
with open(path, "w") as handle:
    json.dump(report, handle)
PY

expect_validate_ok "$WORK/valid.json" "base report"
python3 "$REPORT_TOOL" exit-code --report "$WORK/valid.json" | grep -qx 0
pass "all-passed report maps to exit 0"

# --- Optional interference key (D6 sentinel metadata) ------------------------

python3 - "$WORK/interference.json" <<'PY'
import json, sys
path = sys.argv[1]
base = path.rsplit("/", 1)[0] + "/valid.json"
with open(base) as handle:
    report = json.load(handle)
report["interference"] = "resident Copythat process is running; it captures scenario copies into the real user history independently of this runner"
with open(path, "w") as handle:
    json.dump(report, handle)
PY
expect_validate_ok "$WORK/interference.json" "interference note accepted"

python3 - "$WORK/unknown-key.json" <<'PY'
import json, sys
path = sys.argv[1]
base = path.rsplit("/", 1)[0] + "/valid.json"
with open(base) as handle:
    report = json.load(handle)
report["mystery"] = 1
with open(path, "w") as handle:
    json.dump(report, handle)
PY
expect_validate_fails "$WORK/unknown-key.json" "unknown top-level key rejected"

# --- Runner blocked paths (no input, no prompts, exit 2) ---------------------

RUNNER="$SCRIPT_DIR/clipboard_live.sh"
assert_runner_blocked() {
    local hook="$1"
    local message_fragment="$2"
    local output status
    set +e
    output="$(env "$hook" "$RUNNER" run qualify-input --output "$WORK/blocked-out" 2>&1)"
    status=$?
    set -e
    if [[ "$status" != "2" ]]; then
        echo "expected exit 2 for $hook, got $status" >&2
        echo "$output" >&2
        exit 1
    fi
    if ! grep -q "$message_fragment" <<<"$output"; then
        echo "expected actionable message for $hook: $message_fragment" >&2
        echo "$output" >&2
        exit 1
    fi
    if grep -qi 'press return\|enter password\|allow.*access?' <<<"$output"; then
        echo "blocked path must not prompt" >&2
        exit 1
    fi
    pass "blocked path actionable: $hook"
}

assert_runner_blocked "CLIPBOARD_LIVE_TEST_BLOCK_FRONTMOST=1" "no unlocked graphical session"
assert_runner_blocked "CLIPBOARD_LIVE_TEST_BLOCK_KEYSTROKE=1" "keystroke delivery is not authorized"
assert_runner_blocked "CLIPBOARD_LIVE_TEST_BLOCK_APP=1" "Google Chrome is not installed"
assert_runner_blocked "CLIPBOARD_LIVE_TEST_BLOCK_AX=1" "lacks Accessibility trust"

# --- Concurrent-run rejection (D6) -------------------------------------------

LOCK_DIR="$ROOT_DIR/.build/clipboard-live/run.lock"
if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo $$ >"$LOCK_DIR/pid"
    date +%s >"$LOCK_DIR/created"
    set +e
    output="$("$RUNNER" run qualify-input --output "$WORK/lock-out" 2>&1)"
    status=$?
    set -e
    rm -rf "$LOCK_DIR"
    if [[ "$status" != "2" ]]; then
        echo "expected exit 2 for concurrent run, got $status" >&2
        echo "$output" >&2
        exit 1
    fi
    pass "concurrent run rejected while lock is held by a live pid"
else
    echo "could not create test lock; is another run active?" >&2
    exit 1
fi

# --- User sentinel verification helpers (D6) ---------------------------------

(
    set -euo pipefail
    source "$RUNNER"
    # Case 1: unchanged sentinel passes.
    user_state_digest() { echo same; }
    resident_copythat_pids() { true; }
    SENTINEL_BEFORE="same"
    verify_user_sentinel >/dev/null
    # Case 2: changed sentinel with no resident copythat fails the run.
    user_state_digest() { echo changed; }
    if verify_user_sentinel >/dev/null 2>&1; then
        echo "sentinel change without resident app must fail verification" >&2
        exit 1
    fi
    # Case 3: changed sentinel with a resident copythat is reported, not failed.
    resident_copythat_pids() { echo 4242; }
    verify_user_sentinel >/dev/null
)
pass "user sentinel verification: unchanged ok, unexplained change fails, resident-interference reported"

# --- Owned-resource cleanup on SIGINT (D6) -----------------------------------

(
    set -euo pipefail
    source "$RUNNER"
    victim="$(mktemp -d -t copythat-live-victim)"
    unrelated="$(mktemp -d -t copythat-live-unrelated)"
    sleep 30 & victim_pid=$!
    sleep 30 & unrelated_pid=$!
    DRIVER_PID="$victim_pid"
    RUN_TMP="$victim"
    # Release only owned resources, exactly as the INT/TERM traps do.
    cleanup
    if kill -0 "$victim_pid" 2>/dev/null; then
        echo "owned driver process survived cleanup" >&2
        kill -9 "$victim_pid" 2>/dev/null || true
        exit 1
    fi
    if ! kill -0 "$unrelated_pid" 2>/dev/null; then
        echo "unrelated process was killed by cleanup" >&2
        exit 1
    fi
    if [[ -e "$victim" ]]; then
        echo "owned temp file survived cleanup" >&2
        exit 1
    fi
    kill -9 "$unrelated_pid" 2>/dev/null || true
    wait "$unrelated_pid" 2>/dev/null || true
    rm -rf "$unrelated"
)
pass "cleanup releases owned process/temp state and leaves unrelated processes intact"

# --- Driver selftest through the report contract (D1/D7) ---------------------

(
    set -euo pipefail
    source "$RUNNER"
    build_driver
    selftest_dir="$(mktemp -d -t copythat-clipboard-live-selftest)"
    cleanup_selftest() { rm -rf "$selftest_dir"; }
    trap cleanup_selftest EXIT
    "$DRIVER_BIN" selftest \
        --events "$selftest_dir/events.jsonl" \
        --results "$selftest_dir/results.jsonl" \
        --work "$selftest_dir/work"
    started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '{"provenance": {"sourceRevision": "selftest", "sourceSnapshotDigest": "selftest", "driverDigest": "selftest", "driverPath": "%s", "buildConfiguration": "swiftc-asserts-release", "osVersion": "selftest", "osBuild": "selftest", "chromeVersion": "selftest", "codeVersion": "selftest", "timingConstants": {}, "inputMechanism": "selftest"}}' "$DRIVER_BIN" >"$selftest_dir/meta.json"
    python3 "$REPORT_TOOL" assemble \
        --profile selftest \
        --results "$selftest_dir/results.jsonl" \
        --output-dir "$selftest_dir" \
        --started "$started" \
        --ended "$ended" \
        --metadata-json "$selftest_dir/meta.json" \
        >"$selftest_dir/report.json"
    python3 "$REPORT_TOOL" validate --report "$selftest_dir/report.json" >/dev/null
    python3 "$REPORT_TOOL" exit-code --report "$selftest_dir/report.json" | grep -qx 0
)
pass "driver selftest produces a valid all-passed report (exit 0)"

# --- Recipe driver: schema and writer-identity prerequisites (4.1) -----------

(
    set -euo pipefail
    source "$RUNNER"
    recipe_dir="$(mktemp -d -t copythat-recipe-fixtures)"
    results_dir="$(mktemp -d -t copythat-recipe-results)"
    cleanup_recipes() { rm -rf "$recipe_dir" "$results_dir"; }
    trap cleanup_recipes EXIT

    # (a) malformed recipe -> blocked, evidence unavailable
    printf '{"recipeVersion": 1, "name":' >"$recipe_dir/broken.json"
    "$DRIVER_BIN" recipe --recipe-dir "$recipe_dir" \
        --events "$results_dir/ev.jsonl" --results "$results_dir/res.jsonl" \
        --work "$results_dir/wk" || true
    python3 - "$results_dir/res.jsonl" <<'PY'
import json, sys
results = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
assert len(results) == 1, results
assert results[0]["verdict"] == "blocked", results
assert results[0]["evidenceLevel"] == "unavailable", results
print("recipe schema fixture ok")
PY

    # (b) installed-writer mismatch -> blocked with precise prerequisite
    printf '{"recipeVersion": 1, "name": "absent-writer", "writer": {"bundleId": "com.example.absent", "name": "Absent App", "version": "1.0"}, "fixtureText": null, "copyMethod": "menu-copy", "actions": []}' >"$recipe_dir/absent-writer.json"
    rm -f "$recipe_dir/broken.json"
    "$DRIVER_BIN" recipe --recipe-dir "$recipe_dir" \
        --events "$results_dir/ev2.jsonl" --results "$results_dir/res2.jsonl" \
        --work "$results_dir/wk2" || true
    python3 - "$results_dir/res2.jsonl" <<'PY'
import json, sys
results = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
assert len(results) == 1, results
assert results[0]["verdict"] == "blocked", results
assert "not installed" in results[0]["reason"], results
print("recipe writer-identity fixture ok")
PY
)
pass "recipe driver reports schema and writer-identity prerequisites explicitly"

# --- Replay semantics (4.3, live pasteboard; opt-in) -------------------------

if [[ "${CLIPBOARD_LIVE_TEST_LIVE:-0}" == "1" ]]; then
    (
        set -euo pipefail
        source "$RUNNER"
        build_driver
        replay_dir="$(mktemp -d -t copythat-replay-test)"
        trap 'rm -rf "$replay_dir"' EXIT
        printf '[{"delayMs": 120, "value": "replay-transient-%s"}, {"delayMs": 0, "value": "replay-final-%s"}]' "$(date +%s)" "$(date +%s)" >"$replay_dir/transitions.json"
        set +e
        "$DRIVER_BIN" replay --transitions "$replay_dir/transitions.json" \
            --events "$replay_dir/ev.jsonl" --results "$replay_dir/res.jsonl" \
            --work "$replay_dir/wk"
        status=$?
        set -e
        [[ "$status" == "0" ]]
        grep -q 'onlyFinalCommitted' "$replay_dir/res.jsonl"
    )
    pass "replay commits only the final value for a transient+final sequence"
else
    pass "replay live check skipped (set CLIPBOARD_LIVE_TEST_LIVE=1 to run)"
fi

# --- Malformed / missing evidence -------------------------------------------

printf '{"schemaVersion": 1, "tool":' >"$WORK/malformed.json"
expect_validate_fails "$WORK/malformed.json" "malformed JSON"

: >"$WORK/empty.json"
expect_validate_fails "$WORK/empty.json" "empty evidence file"

python3 - "$WORK/missing-required.json" "$NOW" <<'PY'
import json, sys
path, now = sys.argv[1], sys.argv[2]
with open(path.rsplit("/", 1)[0] + "/valid.json") as handle:
    report = json.load(handle)
report["scenarios"] = []  # evidence lost
report["summary"] = {"passed": 0, "failed": 0, "blocked": 0, "not-covered": 0}
with open(path, "w") as handle:
    json.dump(report, handle)
PY
expect_validate_fails "$WORK/missing-required.json" "missing required scenario"

python3 - "$WORK/duplicate.json" <<'PY'
import json, sys
path = sys.argv[1]
base = path.rsplit("/", 1)[0] + "/valid.json"
with open(base) as handle:
    report = json.load(handle)
report["scenarios"].append(dict(report["scenarios"][0]))
report["summary"]["passed"] = 2
with open(path, "w") as handle:
    json.dump(report, handle)
PY
expect_validate_fails "$WORK/duplicate.json" "duplicate scenario lines"

# --- Out-of-order / lying evidence ------------------------------------------

python3 - "$WORK/order-lie.json" <<'PY'
import json, sys
path = sys.argv[1]
base = path.rsplit("/", 1)[0] + "/valid.json"
with open(base) as handle:
    report = json.load(handle)
# A passed verdict that contains a failed assertion cannot pass (D7).
report["scenarios"][0]["assertions"][2]["ok"] = False
report["scenarios"][0]["assertions"][2]["observed"] = "false"
with open(path, "w") as handle:
    json.dump(report, handle)
PY
expect_validate_fails "$WORK/order-lie.json" "failed assertion inside passed scenario"

python3 - "$WORK/summary-lie.json" <<'PY'
import json, sys
path = sys.argv[1]
base = path.rsplit("/", 1)[0] + "/valid.json"
with open(base) as handle:
    report = json.load(handle)
report["summary"]["passed"] = 5  # counts no longer match scenario verdicts
with open(path, "w") as handle:
    json.dump(report, handle)
PY
expect_validate_fails "$WORK/summary-lie.json" "summary does not match verdicts"

# --- Stale evidence ----------------------------------------------------------

python3 - "$WORK/stale.json" <<'PY'
import json, sys
from datetime import datetime, timedelta, timezone
path = sys.argv[1]
base = path.rsplit("/", 1)[0] + "/valid.json"
with open(base) as handle:
    report = json.load(handle)
stale = (datetime.now(timezone.utc) - timedelta(hours=25)).strftime("%Y-%m-%dT%H:%M:%SZ")
report["startedAt"] = stale
report["endedAt"] = stale
with open(path, "w") as handle:
    json.dump(report, handle)
PY
expect_validate_fails "$WORK/stale.json" "stale evidence (>24h)"

python3 - "$WORK/future.json" <<'PY'
import json, sys
from datetime import datetime, timedelta, timezone
path = sys.argv[1]
base = path.rsplit("/", 1)[0] + "/valid.json"
with open(base) as handle:
    report = json.load(handle)
future = (datetime.now(timezone.utc) + timedelta(hours=2)).strftime("%Y-%m-%dT%H:%M:%SZ")
report["endedAt"] = future
with open(path, "w") as handle:
    json.dump(report, handle)
PY
expect_validate_fails "$WORK/future.json" "future endedAt"

# --- Payload safety ----------------------------------------------------------

python3 - "$WORK/payload.json" <<'PY'
import json, sys
path = sys.argv[1]
base = path.rsplit("/", 1)[0] + "/valid.json"
with open(base) as handle:
    report = json.load(handle)
# A unique copied marker leaked into the reason field.
report["scenarios"][0]["reason"] = "captured copythat-live-a-9f2c41ab from the page"
with open(path, "w") as handle:
    json.dump(report, handle)
PY
expect_validate_fails "$WORK/payload.json" "clipboard marker in reason"

python3 - "$WORK/payload-key.json" <<'PY'
import json, sys
path = sys.argv[1]
base = path.rsplit("/", 1)[0] + "/valid.json"
with open(base) as handle:
    report = json.load(handle)
report["scenarios"][0]["text"] = "secret pasted content"
with open(path, "w") as handle:
    json.dump(report, handle)
PY
expect_validate_fails "$WORK/payload-key.json" "forbidden payload key"

python3 - "$WORK/payload-url.json" <<'PY'
import json, sys
path = sys.argv[1]
base = path.rsplit("/", 1)[0] + "/valid.json"
with open(base) as handle:
    report = json.load(handle)
report["scenarios"][0]["reason"] = "observed data:text/html,<body>secret</body> copy"
with open(path, "w") as handle:
    json.dump(report, handle)
PY
expect_validate_fails "$WORK/payload-url.json" "data URL in reason"

# --- Exit-code precedence (failures over blocked) ----------------------------

python3 - "$WORK/mixed.json" <<'PY'
import json, sys
path = sys.argv[1]
base = path.rsplit("/", 1)[0] + "/valid.json"
with open(base) as handle:
    report = json.load(handle)
failed = dict(report["scenarios"][0])
blocked = dict(report["scenarios"][0])
failed["scenario"] = "cut_editable_text"
failed["verdict"] = "failed"
blocked["scenario"] = "real_permission_denial"
blocked["verdict"] = "blocked"
blocked["evidenceLevel"] = "unavailable"
report["scenarios"] = [report["scenarios"][0], failed, blocked]
report["summary"] = {"passed": 1, "failed": 1, "blocked": 1, "not-covered": 0}
report["requiredScenarios"] = ["input_qualification"]
with open(path, "w") as handle:
    json.dump(report, handle)
PY
expect_validate_ok "$WORK/mixed.json" "mixed report"
python3 "$REPORT_TOOL" exit-code --report "$WORK/mixed.json" | grep -qx 1
pass "failure takes precedence over blocked (exit 1)"

python3 - "$WORK/blocked-only.json" <<'PY'
import json, sys
path = sys.argv[1]
base = path.rsplit("/", 1)[0] + "/valid.json"
with open(base) as handle:
    report = json.load(handle)
report["scenarios"][0]["verdict"] = "blocked"
report["scenarios"][0]["evidenceLevel"] = "unavailable"
report["summary"] = {"passed": 0, "failed": 0, "blocked": 1, "not-covered": 0}
with open(path, "w") as handle:
    json.dump(report, handle)
PY
python3 "$REPORT_TOOL" exit-code --report "$WORK/blocked-only.json" | grep -qx 2
pass "blocked-only maps to exit 2"

# --- Plan generator ----------------------------------------------------------

python3 "$PLAN_TOOL" plan --profile routine --out "$WORK/plan-routine.json"
python3 - "$WORK/plan-routine.json" <<'PY'
import json, sys
with open(sys.argv[1]) as handle:
    plan = json.load(handle)
names = [s["name"] for s in plan["scenarios"]]
assert "input_qualification" in names
assert "restore_paste_negative" in names
assert plan["requiredScenarios"] == [n for n in names if n != "real_permission_denial"]
print("plan ok")
PY
pass "routine plan lists required scenarios and excludes denial from required"

if python3 "$PLAN_TOOL" plan --profile bogus --out "$WORK/plan-bogus.json" 2>/dev/null; then
    echo "unknown profile should fail" >&2
    exit 1
fi
pass "unknown profile rejected"

# --- blocked-scenario emitter produces schema-shaped results ------------------

python3 "$REPORT_TOOL" blocked-scenario \
    --scenario "original_writer_replay" \
    --reason "missing prerequisite recorded" \
    --evidence-level "unavailable" >"$WORK/blocked-result.json"
python3 - "$WORK/blocked-result.json" <<'PY'
import json, sys
with open(sys.argv[1]) as handle:
    result = json.load(handle)
assert result["verdict"] == "blocked"
assert result["evidenceLevel"] == "unavailable"
print("blocked result ok")
PY
pass "blocked-scenario emitter output well-formed"

echo "clipboard_live report/plan fixtures passed"
