#!/usr/bin/env python3
"""Report assembly, validation, and exit-code mapping for clipboard_live (D7).

The schema is strict on purpose: malformed, incomplete, stale, or
payload-bearing evidence can never validate as a passing report. Validation is
also the payload-safety gate — reports carry digests, lengths, kinds, verdicts,
and timing only.
"""
import argparse
import json
import sys
from datetime import datetime, timedelta, timezone

SCHEMA_VERSION = 1

VERDICTS = {"passed", "failed", "blocked", "not-covered"}
EVIDENCE_LEVELS = {
    "production-tests",
    "automated-real-desktop",
    "original-application-replay",
    "synthetic-replay",
    "unavailable",
}

RESULT_KEYS = {
    "scenario",
    "verdict",
    "evidenceLevel",
    "reason",
    "assertions",
    "timings",
    "inputMechanism",
}
ASSERTION_KEYS = {"name", "expected", "observed", "ok"}
PROVENANCE_KEYS = {
    "sourceRevision",
    "sourceSnapshotDigest",
    "driverDigest",
    "driverPath",
    "buildConfiguration",
    "osVersion",
    "osBuild",
    "chromeVersion",
    "codeVersion",
    "timingConstants",
    "inputMechanism",
}
REPORT_KEYS = {
    "schemaVersion",
    "tool",
    "profile",
    "startedAt",
    "endedAt",
    "provenance",
    "requiredScenarios",
    "scenarios",
    "summary",
    "originalTaskMapping",
    "evidenceBoundaries",
}
# Optional keys: present only when the observed environment warrants them.
OPTIONAL_REPORT_KEYS = {"interference"}

MAX_STRING = 512

# Payload-safety: forbidden key names and fixture-marker prefixes. Fixture
# values are unique per run (UUID suffixes), so any occurrence of these
# prefixes in a report means raw clipboard payload leaked into evidence.
FORBIDDEN_KEYS = {
    "text",
    "textValue",
    "url",
    "path",
    "fileURLs",
    "imageData",
    "preview",
    "content",
    "payload",
    "marker",
    "clipboard",
    "pbpaste",
}
FORBIDDEN_PREFIXES = (
    "copythat-live-",
    "cut-",
    "restore-",
    "menu-copy-",
    "idle-",
    "qualify-",
    "switch-",
    "data:text",
    "/Users/",
)

ORIGINAL_TASK_MAPPING = {
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
}

EVIDENCE_BOUNDARIES = (
    "automated-real-desktop evidence is OS input through the real event tap; "
    "it does not prove physical HID behavior. "
    "synthetic-replay evidence is labeled and never counts as original-writer "
    "reproduction."
)


def _fail(messages, message):
    messages.append(message)


def _check_string(value, messages, where, allow_empty=False, check_prefixes=True):
    if not isinstance(value, str):
        _fail(messages, f"{where}: expected string")
        return False
    if not allow_empty and not value:
        _fail(messages, f"{where}: empty string")
        return False
    if len(value) > MAX_STRING:
        _fail(messages, f"{where}: string exceeds {MAX_STRING} chars (possible payload)")
        return False
    if check_prefixes:
        for prefix in FORBIDDEN_PREFIXES:
            if prefix in value:
                _fail(messages, f"{where}: forbidden payload-like content ({prefix!r})")
                return False
    return True


def _validate_result(result, messages, index):
    where = f"scenarios[{index}]"
    if not isinstance(result, dict):
        _fail(messages, f"{where}: not an object")
        return
    keys = set(result)
    if not keys <= RESULT_KEYS:
        _fail(messages, f"{where}: unknown keys {sorted(keys - RESULT_KEYS)}")
    for key in ("scenario", "verdict", "evidenceLevel", "reason"):
        if key not in keys:
            _fail(messages, f"{where}: missing {key}")
            return
    _check_string(result["scenario"], messages, f"{where}.scenario")
    if result["verdict"] not in VERDICTS:
        _fail(messages, f"{where}.verdict: {result['verdict']!r}")
    if result["evidenceLevel"] not in EVIDENCE_LEVELS:
        _fail(messages, f"{where}.evidenceLevel: {result['evidenceLevel']!r}")
    _check_string(result["reason"], messages, f"{where}.reason", allow_empty=True)
    if result["verdict"] == "passed" and not result["reason"]:
        _fail(messages, f"{where}: passed requires a reason")

    assertions = result.get("assertions")
    if not isinstance(assertions, list):
        _fail(messages, f"{where}.assertions: not a list")
        return
    for position, assertion in enumerate(assertions):
        assertion_where = f"{where}.assertions[{position}]"
        if not isinstance(assertion, dict) or not set(assertion) <= ASSERTION_KEYS:
            _fail(messages, f"{assertion_where}: invalid assertion object")
            continue
        _check_string(assertion["name"], messages, f"{assertion_where}.name")
        _check_string(assertion["expected"], messages, f"{assertion_where}.expected")
        _check_string(assertion["observed"], messages, f"{assertion_where}.observed")
        if not isinstance(assertion["ok"], bool):
            _fail(messages, f"{assertion_where}.ok: not boolean")
            continue
        if not assertion["ok"] and result["verdict"] == "passed":
            _fail(messages, f"{assertion_where}: failed assertion inside a passed scenario")

    timings = result.get("timings")
    if not isinstance(timings, dict) or not all(
        isinstance(key, str) and isinstance(value, (int, float))
        for key, value in timings.items()
    ):
        _fail(messages, f"{where}.timings: not a string->number object")
    _check_string(result.get("inputMechanism", ""), messages, f"{where}.inputMechanism")


def _validate_provenance(provenance, messages):
    if not isinstance(provenance, dict):
        _fail(messages, "provenance: not an object")
        return
    keys = set(provenance)
    if not keys >= PROVENANCE_KEYS:
        _fail(messages, f"provenance: missing keys {sorted(PROVENANCE_KEYS - keys)}")
    if not keys <= PROVENANCE_KEYS:
        _fail(messages, f"provenance: unknown keys {sorted(keys - PROVENANCE_KEYS)}")
    # D3: artifact paths are execution metadata, not clipboard payload; the
    # payload-prefix scan applies to scenario strings, not provenance paths.
    _check_string(
        provenance.get("driverPath", ""), messages, "provenance.driverPath", check_prefixes=False
    )


def validate_report(report, messages, now=None):
    """Validates a parsed report dict; appends problems to messages."""
    if not isinstance(report, dict):
        _fail(messages, "report: not an object")
        return
    keys = set(report)
    if not keys >= REPORT_KEYS or not keys <= REPORT_KEYS | OPTIONAL_REPORT_KEYS:
        _fail(
            messages,
            f"report keys mismatch: missing={sorted(REPORT_KEYS - keys)} "
            f"unknown={sorted(keys - REPORT_KEYS - OPTIONAL_REPORT_KEYS)}",
        )
        return
    if "interference" in keys:
        _check_string(
            report["interference"], messages, "report.interference", check_prefixes=False
        )
    if report.get("tool") != "clipboard-live":
        _fail(messages, "report.tool: expected 'clipboard-live'")
    if report.get("schemaVersion") != SCHEMA_VERSION:
        _fail(messages, "report.schemaVersion: unsupported")
    for key in ("startedAt", "endedAt"):
        _check_string(report.get(key, ""), messages, f"report.{key}")

    _validate_provenance(report.get("provenance", {}), messages)

    required = report.get("requiredScenarios")
    if not isinstance(required, list) or not required:
        _fail(messages, "requiredScenarios: must be a non-empty list")

    scenarios = report.get("scenarios")
    if not isinstance(scenarios, list) or not scenarios:
        _fail(messages, "scenarios: must be a non-empty list")
        return

    seen = {}
    for index, result in enumerate(scenarios):
        _validate_result(result, messages, index)
        name = result.get("scenario")
        if isinstance(name, str):
            if name in seen:
                _fail(messages, f"scenarios: duplicate scenario {name}")
            seen[name] = result.get("verdict")

    # A required scenario that ran but did not pass is a valid report with a
    # nonzero exit code (D7: incomplete prerequisites -> exit 2), not an
    # invalid report. Only structural absence is invalid. The exit-code
    # mapping applies this rule in cmd_exit_code.
    for name in required or []:
        if name not in seen:
            _fail(messages, f"requiredScenarios: {name} missing from scenarios")

    summary = report.get("summary")
    if not isinstance(summary, dict):
        _fail(messages, "summary: not an object")
    else:
        counted = {"passed": 0, "failed": 0, "blocked": 0, "not-covered": 0}
        for result in scenarios:
            verdict = result.get("verdict")
            if verdict in counted:
                counted[verdict] += 1
        if summary != counted:
            _fail(messages, f"summary mismatch: {summary} vs counted {counted}")

    if report.get("originalTaskMapping") != ORIGINAL_TASK_MAPPING:
        _fail(messages, "originalTaskMapping: must map original 5.2/5.3/5.5 obligations")
    if report.get("evidenceBoundaries") != EVIDENCE_BOUNDARIES:
        _fail(messages, "evidenceBoundaries: statement missing or altered")

    # Staleness gate: reports older than 24h cannot validate as current (D7).
    ended = report.get("endedAt")
    if isinstance(ended, str):
        try:
            ended_at = datetime.fromisoformat(ended.replace("Z", "+00:00"))
            reference = now or datetime.now(timezone.utc)
            if ended_at < reference - timedelta(hours=24):
                _fail(messages, "report: evidence is stale (>24h old)")
            if ended_at > reference + timedelta(minutes=5):
                _fail(messages, "report: endedAt is in the future")
        except ValueError:
            _fail(messages, "endedAt: not an ISO-8601 timestamp")


def parse_timestamp(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def cmd_validate(args):
    messages = []
    try:
        with open(args.report, encoding="utf-8") as handle:
            report = json.load(handle)
    except (OSError, json.JSONDecodeError) as error:
        print(f"INVALID report: unreadable or malformed JSON: {error}")
        return 1
    validate_report(report, messages)
    if messages:
        for message in messages:
            print(f"INVALID report: {message}")
        return 1
    print(f"VALID report: {args.report}")
    return 0


def cmd_assemble(args):
    messages = []
    results = []
    try:
        with open(args.results, encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                results.append(json.loads(line))
    except (OSError, json.JSONDecodeError) as error:
        print(f"cannot read results: {error}", file=sys.stderr)
        return 2
    if not results:
        print("no scenario results recorded; the run produced no evidence", file=sys.stderr)
        return 2

    try:
        with args.metadata_json:
            metadata = json.load(args.metadata_json)
    except json.JSONDecodeError as error:
        print(f"cannot read metadata: {error}", file=sys.stderr)
        return 2

    profile = args.profile
    counted = {"passed": 0, "failed": 0, "blocked": 0, "not-covered": 0}
    for result in results:
        if not isinstance(result, dict) or set(result) != RESULT_KEYS:
            print(f"invalid result line: {result!r}", file=sys.stderr)
            return 2
        if result["verdict"] in counted:
            counted[result["verdict"]] += 1

    required = REQUIRED_BY_PROFILE.get(profile, [r["scenario"] for r in results])

    report = {
        "schemaVersion": SCHEMA_VERSION,
        "tool": "clipboard-live",
        "profile": profile,
        "startedAt": args.started,
        "endedAt": args.ended,
        "provenance": metadata.get("provenance", {}),
        "requiredScenarios": required,
        "scenarios": results,
        "summary": counted,
        "originalTaskMapping": ORIGINAL_TASK_MAPPING,
        "evidenceBoundaries": EVIDENCE_BOUNDARIES,
    }
    if args.interference_note:
        report["interference"] = args.interference_note
    validate_report(report, messages)
    if messages:
        for message in messages:
            print(f"assembled report is invalid: {message}", file=sys.stderr)
        return 1
    json.dump(report, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


def cmd_exit_code(args):
    """D7 mapping: 0 all required passed; 1 any behavioral/evidence failure
    (takes precedence); 2 incomplete prerequisites/coverage."""
    try:
        with open(args.report, encoding="utf-8") as handle:
            report = json.load(handle)
    except (OSError, json.JSONDecodeError):
        print(1)
        return
    summary = report.get("summary", {})
    if summary.get("failed", 0) > 0:
        print(1)
        return
    required = report.get("requiredScenarios") or []
    verdicts = {s.get("scenario"): s.get("verdict") for s in report.get("scenarios", [])}
    required_not_passed = any(verdicts.get(name) != "passed" for name in required)
    if required_not_passed or summary.get("blocked", 0) > 0 or summary.get("not-covered", 0) > 0:
        print(2)
        return
    print(0)


def cmd_summarize(args):
    try:
        with open(args.report, encoding="utf-8") as handle:
            report = json.load(handle)
    except (OSError, json.JSONDecodeError) as error:
        print(f"cannot read report: {error}", file=sys.stderr)
        return 2
    summary = report.get("summary", {})
    print(
        f"clipboard-live {report.get('profile')} "
        f"passed={summary.get('passed', 0)} failed={summary.get('failed', 0)} "
        f"blocked={summary.get('blocked', 0)} not-covered={summary.get('not-covered', 0)}"
    )
    for result in report.get("scenarios", []):
        line = f"  {result['verdict'].upper():12} {result['scenario']}"
        if result.get("reason"):
            line += f" - {result['reason']}"
        print(line)
        for assertion in result.get("assertions", []):
            if not assertion["ok"]:
                print(f"      assertion failed: {assertion['name']}")
    print("  evidence boundaries:")
    print(f"    {report.get('evidenceBoundaries', '')}")
    for task, obligation in report.get("originalTaskMapping", {}).items():
        print(f"    {task}: {obligation}")
    return 0


def cmd_blocked_scenario(args):
    result = {
        "scenario": args.scenario,
        "verdict": "blocked",
        "evidenceLevel": args.evidence_level,
        "reason": args.reason,
        "assertions": [],
        "timings": {},
        "inputMechanism": "none",
    }
    json.dump(result, sys.stdout, sort_keys=True)
    sys.stdout.write("\n")
    return 0


REQUIRED_BY_PROFILE = {}
try:
    sys.path.insert(0, __file__.rsplit("/", 1)[0])
    from clipboard_live_plan import REQUIRED as _REQUIRED  # type: ignore

    REQUIRED_BY_PROFILE = _REQUIRED
except Exception:  # pragma: no cover - fall back to results-derived requirements
    REQUIRED_BY_PROFILE = {}


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    validate = sub.add_parser("validate")
    validate.add_argument("--report", required=True)
    validate.set_defaults(func=cmd_validate)

    assemble = sub.add_parser("assemble")
    assemble.add_argument("--profile", required=True)
    assemble.add_argument("--results", required=True)
    assemble.add_argument("--output-dir", default="")
    assemble.add_argument("--started", required=True)
    assemble.add_argument("--ended", required=True)
    assemble.add_argument("--metadata-json", type=argparse.FileType("r"), required=True)
    assemble.add_argument("--original-root", default="")
    assemble.add_argument("--interference-note", default="")
    assemble.set_defaults(func=cmd_assemble)

    exit_code = sub.add_parser("exit-code")
    exit_code.add_argument("--report", required=True)
    exit_code.set_defaults(func=cmd_exit_code)

    summarize = sub.add_parser("summarize")
    summarize.add_argument("--report", required=True)
    summarize.set_defaults(func=cmd_summarize)

    blocked = sub.add_parser("blocked-scenario")
    blocked.add_argument("--scenario", required=True)
    blocked.add_argument("--reason", required=True)
    blocked.add_argument("--evidence-level", default="unavailable")
    blocked.set_defaults(func=cmd_blocked_scenario)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
