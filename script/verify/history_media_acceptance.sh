#!/usr/bin/env bash
# history_media_acceptance.sh - single-command unattended acceptance for the
# lazy-load-history-media change.
#
# Runs the required scenario suite plus the repository gates (swift build,
# swift test, verify_all.sh, git diff --check, openspec validate --strict and
# the preview_live driver self-test), then writes a machine-readable report to
# .build/history-media-acceptance/<run-id>/.
#
# No stdin, no manual steps and no system-permission prompts: scenarios only
# exercise injected platform seams and test-owned windows/pasteboards. Missing
# tooling or a missing GUI session is reported as `blocked` with a non-zero
# exit instead of pausing for a human.
#
# Usage: history_media_acceptance.sh [run] [--timeout <seconds>] [--output <dir>]
#        history_media_acceptance.sh self-test

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_PATH="$0"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
TIMEOUT_SECONDS="${HISTORY_MEDIA_ACCEPTANCE_TIMEOUT:-600}"

log() { echo "[history-media-acceptance] $*" >&2; }

# scenario definitions: id|command|evidence-type|required
SCENARIOS=(
  "history-restore|swift test --filter ClipboardHistoryPersistenceTests|real-persistence|yes"
  "history-gc-and-mutations|swift test --filter ClipboardStorePersistenceTests|real-persistence|yes"
  "history-worker-commit|swift test --filter ClipboardHistoryWorkerIntegrationTests|real-persistence|yes"
  "history-save-coordinator|swift test --filter ClipboardHistorySaveCoordinatorTests|real-persistence|yes"
  "history-performance-read-counters|swift test --filter ClipboardHistoryPerformanceTests|read-counters|yes"
  "media-loader|swift test --filter ClipboardHistoryMediaLoaderTests|read-counters|yes"
  "model-identity|swift test --filter ClipboardItemStorageOptimizationTests|unit|yes"
  "model-deletion-policy|swift test --filter ClipboardStoreImageDeletionTests|unit|yes"
  "link-preview-lazy|swift test --filter StoreLazyLinkPreviewTests|real-store|yes"
  "link-preview-regression|swift test --filter StoreLinkPreview|real-store|yes"
  "card-lazy-media|swift test --filter ClipboardCardLazyMediaTests|real-appkit|yes"
  "image-drag-cancellation|swift test --filter ClipboardImageDragCancellationTests|real-provider|yes"
  "panel-wiring|swift test --filter StorePanelWiringTests|real-appkit|yes"
  "panel-key-routing|swift test --filter PanelAcceptanceTests|synthetic-input|yes"
  "paste-materialization|swift test --filter PanelPasteMaterializationTests|real-pasteboard|yes"
  "paste-performer-regression|swift test --filter ClipboardPastePerformerTests|synthetic-input|yes"
  "paste-decision-and-target|swift test --filter PasteDecisionTests|unit|yes"
  "paste-target-resolution|swift test --filter PasteTargetTests|unit|yes"
  "multi-display-geometry|swift test --filter PanelFrameCalculatorTests|synthetic-geometry|yes"
  "app-model-wiring|swift test --filter AppModelWiringTests|real-store|yes"
  "termination-flush|swift test --filter AppDelegateTerminationTests|real-persistence|yes"
)

# gate definitions: id|command|evidence-type
GATES=(
  "swift-build|swift build|build"
  "swift-test-full|swift test|full-suite"
  "verify-all|./script/verify_all.sh|project-gates"
  "git-diff-check|git diff --check|worktree-hygiene"
  "openspec-validate|openspec validate --specs|spec-validation"
  "preview-live-self-test|./script/verify/preview_live.sh self-test|driver-self-test"
)

# ---------------------------------------------------------------------------
# Pure classification helpers (covered by `self-test`)
# ---------------------------------------------------------------------------

# Maps a required-case status set to the overall run status. Blocked dominates
# because the environment could not run the required evidence; an unrun case is
# `not-covered` and never counts as a pass.
overall_status_for() {
  local status
  local saw_timeout=0 saw_failure=0 saw_not_covered=0 saw_blocked=0
  for status in "$@"; do
    case "$status" in
      passed) ;;
      blocked) saw_blocked=1 ;;
      not-covered) saw_not_covered=1 ;;
      timeout) saw_timeout=1 ;;
      failed) saw_failure=1 ;;
      *) saw_failure=1 ;;
    esac
  done
  if (( saw_blocked )); then echo "blocked"; return 0; fi
  if (( saw_not_covered )); then echo "not-covered"; return 0; fi
  if (( saw_timeout )); then echo "timeout"; return 0; fi
  if (( saw_failure )); then echo "failed"; return 0; fi
  echo "passed"
}

classify_exit_code() {
  local exit_code="$1"
  case "$exit_code" in
    0) echo "passed" ;;
    124|143) echo "timeout" ;;
    *) echo "failed" ;;
  esac
}

# A required scenario that ran green but produced no expected/observed readings
# is not-covered: a passing exit code alone is not the report evidence the
# change requires.
scenario_status_with_metrics() {
  local status="$1"
  local metrics_file="$2"
  if [[ "$status" == "passed" ]] && [[ ! -s "$metrics_file" ]]; then
    echo "not-covered"
    return 0
  fi
  echo "$status"
}

# ---------------------------------------------------------------------------
# Execution helpers
# ---------------------------------------------------------------------------

run_with_timeout() {
  local timeout_seconds="$1"
  local log_file="$2"
  local status_file="$3"
  shift 3

  "$@" >"$log_file" 2>&1 &
  local pid=$!
  local waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if (( waited >= timeout_seconds )); then
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      echo "124" >"$status_file"
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid"
  local status=$?
  echo "$status" >"$status_file"
  return 0
}

gui_session_available() {
  [[ "$(launchctl managername 2>/dev/null)" == "Aqua" ]]
}

swift_available() {
  command -v swift >/dev/null 2>&1
}

write_reports() {
  local out_dir="$1"
  local started_at="$2"
  local finished_at="$3"
  local overall="$4"
  local scenarios_file="$5"
  local gates_file="$6"
  local environment_status="$7"
  local metrics_dir="$8"

  python3 - "$out_dir" "$started_at" "$finished_at" "$overall" \
    "$scenarios_file" "$gates_file" "$environment_status" "$RUN_ID" "$ROOT_DIR" \
    "$metrics_dir" <<'PY'
import hashlib
import json
import subprocess
import sys
from pathlib import Path

(out_dir, started_at, finished_at, overall, scenarios_file, gates_file,
 environment_status, run_id, root_dir, metrics_dir) = sys.argv[1:11]

root = Path(root_dir)
out = Path(out_dir)
metrics_root = Path(metrics_dir)


def read_rows(path):
    rows = []
    for line in Path(path).read_text().splitlines():
        if not line.strip():
            continue
        rows.append(line.split("|"))
    return rows


def source_fingerprint():
    digest = hashlib.sha256()
    patterns = [
        "Sources/**/*.swift",
        "Tests/**/*.swift",
        "script/**/*.sh",
        "script/**/*.swift",
        "Package.swift",
        "openspec/specs/**/*.md",
        "openspec/changes/archive/2026-09-29-lazy-load-history-media/**/*",
    ]
    files = []
    for pattern in patterns:
        files.extend(sorted(p for p in root.glob(pattern) if p.is_file()))
    for path in sorted(set(files)):
        if "__pycache__" in path.parts:
            continue
        digest.update(str(path.relative_to(root)).encode())
        digest.update(path.read_bytes())
    return digest.hexdigest()


try:
    head = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=root, capture_output=True, text=True, check=True
    ).stdout.strip()
except Exception:
    head = "unknown"

def read_metrics(scenario_id):
    """Expected/observed readings the scenario's tests recorded for this run."""
    path = metrics_root / f"{scenario_id}.jsonl"
    rows = []
    if not path.is_file():
        return rows
    for line in path.read_text(errors="replace").splitlines():
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        if {"metric", "expected", "observed"} <= set(row):
            rows.append({key: str(row[key]) for key in ("metric", "expected", "observed")})
    return rows


scenarios = []
for row in read_rows(scenarios_file):
    scenario_id, command, evidence, required, status, exit_code, log_name = row
    metrics = read_metrics(scenario_id)
    scenarios.append({
        "id": scenario_id,
        "command": command,
        "evidenceType": evidence,
        "required": required == "yes",
        "expected": {m["metric"]: m["expected"] for m in metrics},
        "observed": {m["metric"]: m["observed"] for m in metrics},
        "metrics": metrics,
        "status": status,
        "exitCode": int(exit_code),
        "log": log_name,
    })

gates = []
for row in read_rows(gates_file):
    gate_id, command, evidence, status, exit_code, log_name = row
    gates.append({
        "id": gate_id,
        "command": command,
        "evidenceType": evidence,
        "status": status,
        "exitCode": int(exit_code),
        "log": log_name,
    })

report = {
    "change": "lazy-load-history-media",
    "runId": run_id,
    "startedAtUTC": started_at,
    "finishedAtUTC": finished_at,
    "head": head,
    "sourceFingerprint": source_fingerprint(),
    "environment": {"guiSession": environment_status},
    "overall": overall,
    "scenarios": scenarios,
    "gates": gates,
    "evidenceBoundaries": [
        "Real macOS TCC permission dialogs are not exercised: the performer trust check is injected.",
        "No global synthetic input or physical keyboard/mouse events are posted; panel keys use local NSEvents.",
        "No third-party receiving application is driven for image drag; a test NSItemProvider receiver is used.",
        "Physical multi-display placement is not exercised; synthesized screen/Very frame geometry is used.",
        "Command-V delivery is counted through an injected send seam, never posted to the system.",
    ],
}
(out / "report.json").write_text(json.dumps(report, indent=2) + "\n")

status_icon = {"passed": "PASS", "failed": "FAIL", "timeout": "TIMEOUT",
               "blocked": "BLOCKED", "not-covered": "NOT-COVERED"}

lines = []
lines.append(f"# History media acceptance - {overall.upper()}")
lines.append("")
lines.append(f"- Run: `{run_id}`")
lines.append(f"- Started (UTC): {started_at}")
lines.append(f"- Finished (UTC): {finished_at}")
lines.append(f"- HEAD: `{head}`")
lines.append(f"- Source fingerprint: `{report['sourceFingerprint']}`")
lines.append(f"- GUI session available: {environment_status}")
lines.append("")
lines.append("## Required scenarios")
lines.append("")
lines.append("| Scenario | Evidence | Status | Exit |")
lines.append("| --- | --- | --- | --- |")
for scenario in scenarios:
    lines.append(
        f"| {scenario['id']} | {scenario['evidenceType']} | "
        f"{status_icon.get(scenario['status'], scenario['status'])} | {scenario['exitCode']} |"
    )
lines.append("")
lines.append("## Scenario metrics")
lines.append("")
lines.append("| Scenario | Metric | Expected | Observed |")
lines.append("| --- | --- | --- | --- |")
for scenario in scenarios:
    for row in scenario["metrics"]:
        lines.append(
            f"| {scenario['id']} | {row['metric']} | {row['expected']} | {row['observed']} |"
        )
lines.append("")
lines.append("## Gates")
lines.append("")
lines.append("| Gate | Status | Exit |")
lines.append("| --- | --- | --- |")
for gate in gates:
    lines.append(
        f"| {gate['id']} | {status_icon.get(gate['status'], gate['status'])} | {gate['exitCode']} |"
    )
lines.append("")
lines.append("## Evidence boundaries (not covered, not pending manual work)")
lines.append("")
for boundary in report["evidenceBoundaries"]:
    lines.append(f"- {boundary}")
lines.append("")
(out / "summary.md").write_text("\n".join(lines) + "\n")

print(overall)
PY
}

# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

run_self_tests() {
  local failures=0
  local tmp
  tmp="$(mktemp -d)"

  check() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$expected" == "$actual" ]]; then
      log "self-test ok: $description"
    else
      log "self-test FAIL: $description expected=$expected actual=$actual"
      failures=$((failures + 1))
    fi
  }

  check "all passed" "passed" "$(overall_status_for passed passed passed)"
  check "behavior failure" "failed" "$(overall_status_for passed failed)"
  check "timeout" "timeout" "$(overall_status_for passed timeout)"
  check "blocked dominates" "blocked" "$(overall_status_for passed blocked timeout)"
  check "not covered" "not-covered" "$(overall_status_for passed not-covered)"
  check "exit 0" "passed" "$(classify_exit_code 0)"
  check "exit 124" "timeout" "$(classify_exit_code 124)"
  check "exit 1" "failed" "$(classify_exit_code 1)"

  # Report generation for every classified outcome, including failures.
  local started finished
  started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local case_name status
  for case_name in passed failed timeout blocked not-covered; do
    local case_dir="$tmp/$case_name"
    mkdir -p "$case_dir/logs" "$case_dir/metrics"
    printf 'scenario-a|swift test --filter A|unit|yes|%s|1|logs/scenario-a.log\n' "$case_name" >"$case_dir/scenarios.tsv"
    printf 'gate-a|swift build|build|%s|1|logs/gate-a.log\n' "$case_name" >"$case_dir/gates.tsv"
    # Readings a scenario would record through AcceptanceMetrics.
    printf '{"metric":"heavyBlobReads","expected":"0","observed":"0"}\n' \
      >"$case_dir/metrics/scenario-a.jsonl"
    status="$(write_reports "$case_dir" "$started" "$finished" "$case_name" \
      "$case_dir/scenarios.tsv" "$case_dir/gates.tsv" "true" "$case_dir/metrics" 2>/dev/null)"
    check "report status $case_name" "$case_name" "$status"
    if [[ -f "$case_dir/report.json" && -f "$case_dir/summary.md" ]]; then
      for field in runId head sourceFingerprint overall scenarios gates evidenceBoundaries; do
        if ! grep -q "\"$field\"" "$case_dir/report.json"; then
          log "self-test FAIL: $case_name report missing $field"
          failures=$((failures + 1))
        fi
      done
      for field in '"metrics"' '"heavyBlobReads"' '"expected": "0"' '"observed": "0"'; do
        if ! grep -q "$field" "$case_dir/report.json"; then
          log "self-test FAIL: $case_name report missing metric field $field"
          failures=$((failures + 1))
        fi
      done
    else
      log "self-test FAIL: $case_name report files missing"
      failures=$((failures + 1))
    fi
  done

  # Readings, not exit codes, decide whether required evidence exists.
  printf '{"metric":"reads","expected":"0","observed":"0"}\n' >"$tmp/has-metrics.jsonl"
  : >"$tmp/no-metrics.jsonl"
  check "metrics present keeps passed" "passed" \
    "$(scenario_status_with_metrics passed "$tmp/has-metrics.jsonl")"
  check "required passed without metrics" "not-covered" \
    "$(scenario_status_with_metrics passed "$tmp/no-metrics.jsonl")"
  check "failed without metrics stays failed" "failed" \
    "$(scenario_status_with_metrics failed "$tmp/no-metrics.jsonl")"

  # A required case that never ran is not-covered, never passed.
  check "missing required case" "not-covered" "$(overall_status_for passed not-covered)"

  if (( failures > 0 )); then
    log "self-test failed with $failures issue(s)"
    rm -rf "$tmp"
    return 1
  fi
  log "self-test passed"
  rm -rf "$tmp"
  return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  local mode="run"
  local output_root="$ROOT_DIR/.build/history-media-acceptance"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      run) mode="run"; shift ;;
      self-test) mode="self-test"; shift ;;
      --timeout) TIMEOUT_SECONDS="$2"; shift 2 ;;
      --output) output_root="$2"; shift 2 ;;
      *) log "unknown argument: $1"; return 2 ;;
    esac
  done

  if [[ "$mode" == "self-test" ]]; then
    run_self_tests
    return $?
  fi

  local out_dir="$output_root/$RUN_ID"
  mkdir -p "$out_dir/logs"
  local started_at finished_at
  started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  log "run $RUN_ID -> $out_dir"

  local scenarios_file="$out_dir/scenarios.tsv"
  local gates_file="$out_dir/gates.tsv"
  local metrics_dir="$out_dir/metrics"
  mkdir -p "$metrics_dir"
  : >"$scenarios_file"
  : >"$gates_file"

  local gui_ok="false"
  local env_blocked="false"
  if gui_session_available; then
    gui_ok="true"
  else
    env_blocked="true"
  fi
  if ! swift_available; then
    env_blocked="true"
  fi

  # Required scenarios.
  local definition
  for definition in "${SCENARIOS[@]}"; do
    IFS='|' read -r scenario_id command evidence required <<<"$definition"
    local log_name="logs/scenario-$scenario_id.log"
    local status_file="$out_dir/logs/scenario-$scenario_id.exit"
    local status exit_code
    if [[ "$env_blocked" == "true" ]]; then
      status="blocked"
      exit_code=78
      log "scenario $scenario_id blocked (environment)"
      : >"$out_dir/$log_name"
    else
      log "scenario $scenario_id"
      : >"$metrics_dir/$scenario_id.jsonl"
      ( cd "$ROOT_DIR" && COPYTHAT_ACCEPTANCE_METRICS_DIR="$metrics_dir" \
        run_with_timeout "$TIMEOUT_SECONDS" "$out_dir/$log_name" "$status_file" \
        bash -c "$command" )
      exit_code="$(cat "$status_file" 2>/dev/null || echo 1)"
      status="$(classify_exit_code "$exit_code")"
      # SwiftPM exits successfully even when a filter matches no tests.
      if [[ "$status" == "passed" ]] &&
         ! grep -Eq 'Test run with [1-9][0-9]* tests?' "$out_dir/$log_name"; then
        status="not-covered"
        log "scenario $scenario_id matched no tests"
      fi
      status="$(scenario_status_with_metrics "$status" "$metrics_dir/$scenario_id.jsonl")"
      if [[ "$status" == "not-covered" ]]; then
        log "scenario $scenario_id produced no expected/observed metrics"
      fi
    fi
    printf '%s|%s|%s|%s|%s|%s|%s\n' \
      "$scenario_id" "$command" "$evidence" "$required" "$status" "$exit_code" "$log_name" >>"$scenarios_file"
  done

  # Gates.
  local gate_blocked="false"
  if ! swift_available; then gate_blocked="true"; fi
  for definition in "${GATES[@]}"; do
    IFS='|' read -r gate_id command evidence <<<"$definition"
    local log_name="logs/gate-$gate_id.log"
    local status_file="$out_dir/logs/gate-$gate_id.exit"
    local status exit_code
    if [[ "$gate_blocked" == "true" ]]; then
      status="blocked"
      exit_code=78
      : >"$out_dir/$log_name"
    else
      log "gate $gate_id"
      ( cd "$ROOT_DIR" && run_with_timeout "$TIMEOUT_SECONDS" "$out_dir/$log_name" "$status_file" \
        bash -c "$command" )
      exit_code="$(cat "$status_file" 2>/dev/null || echo 1)"
      status="$(classify_exit_code "$exit_code")"
    fi
    printf '%s|%s|%s|%s|%s|%s\n' \
      "$gate_id" "$command" "$evidence" "$status" "$exit_code" "$log_name" >>"$gates_file"
  done

  local scenario_statuses=()
  while IFS='|' read -r _sid _cmd _ev required status _exit _log; do
    [[ "$required" == "yes" ]] && scenario_statuses+=("$status")
  done <"$scenarios_file"

  local overall
  overall="$(overall_status_for "${scenario_statuses[@]}")"
  if [[ "$overall" == "passed" ]]; then
    local gate_status
    while IFS='|' read -r _gid _cmd _ev gate_status _exit _log; do
      if [[ "$gate_status" != "passed" ]]; then
        overall="$(overall_status_for "$gate_status")"
        break
      fi
    done <"$gates_file"
  fi

  finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  write_reports "$out_dir" "$started_at" "$finished_at" "$overall" \
    "$scenarios_file" "$gates_file" "$gui_ok" "$metrics_dir" >/dev/null

  log "overall: $overall"
  log "report: $out_dir/report.json"
  log "summary: $out_dir/summary.md"

  if [[ "$overall" == "passed" ]]; then
    return 0
  fi
  return 1
}

main "$@"
