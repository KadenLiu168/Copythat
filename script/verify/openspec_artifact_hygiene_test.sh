#!/usr/bin/env bash
set -euo pipefail

# Focused fixtures for script/verify/openspec_artifact_hygiene.sh. Every fixture
# is a temporary miniature checkout and the gate is always invoked through its
# real entry point, so no repository file is modified.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT_DIR/script/verify/openspec_artifact_hygiene.sh"
FIXTURES="$(mktemp -d -t copythat-artifact-hygiene)"
trap 'rm -rf "$FIXTURES"' EXIT

[[ -x "$GATE" ]] || { echo "gate is not executable: $GATE" >&2; exit 1; }

GATE_STATUS=0
GATE_OUTPUT=""

die() {
    printf 'openspec artifact hygiene test failed: %s\n' "$*" >&2
    exit 1
}

run_gate() {
    GATE_STATUS=0
    GATE_OUTPUT="$("$GATE" "$1" 2>&1)" || GATE_STATUS=$?
}

expect_status() {
    run_gate "$2"
    [[ "$GATE_STATUS" -eq "$3" ]] ||
        die "$1: expected exit $3, got $GATE_STATUS: $GATE_OUTPUT"
}

# Reported paths are the only indented lines; guidance lines are not indented.
reported_lines() {
    sed -n 's/^  //p' <<<"$GATE_OUTPUT"
}

expect_offenders() {
    local label="$1" checkout="$2"
    shift 2
    expect_status "$label" "$checkout" 1
    grep -Fxq 'Unexpected documents under openspec/changes:' <<<"$GATE_OUTPUT" ||
        die "$label: missing the unexpected-documents header"
    [[ "$(reported_lines)" == "$(printf '%s\n' "$@")" ]] ||
        die "$label: reported paths differ from the expected sorted list: $(reported_lines)"
}

expect_link() {
    local label="$1" path="$2"
    grep -Fq "  $path -> " <<<"$GATE_OUTPUT" || die "$label: did not report the symlink $path"
}

refuse() {
    local label="$1" path="$2"
    if grep -Fq "$path" <<<"$GATE_OUTPUT"; then
        die "$label: unexpectedly reported $path"
    fi
}

# A clean miniature checkout: every allowed filename, single and nested
# capability specs, both active and archived changes, non-Markdown metadata, and
# long-lived documents outside openspec/changes/ that mention forbidden names.
scaffold() {
    local root="$1"
    mkdir -p "$root/openspec/changes/active-change/specs/capability/nested"
    mkdir -p "$root/openspec/changes/archive/2026-01-01-archived-change/specs/single"
    mkdir -p "$root/docs" "$root/.build/notes"
    printf 'proposal\n' >"$root/openspec/changes/active-change/proposal.md"
    printf 'design\n' >"$root/openspec/changes/active-change/design.md"
    printf 'tasks\n' >"$root/openspec/changes/active-change/tasks.md"
    printf 'spec\n' >"$root/openspec/changes/active-change/specs/capability/spec.md"
    printf 'spec\n' >"$root/openspec/changes/active-change/specs/capability/nested/spec.md"
    printf 'version: 2\n' >"$root/openspec/changes/active-change/.openspec.yaml"
    printf 'proposal\n' >"$root/openspec/changes/archive/2026-01-01-archived-change/proposal.md"
    printf 'design\n' >"$root/openspec/changes/archive/2026-01-01-archived-change/design.md"
    printf 'tasks\n' >"$root/openspec/changes/archive/2026-01-01-archived-change/tasks.md"
    printf 'spec\n' >"$root/openspec/changes/archive/2026-01-01-archived-change/specs/single/spec.md"
    printf 'The removed verification.md, stage3-findings.md and\nimplementation-summary.md names appear only as prose here.\n' >"$root/docs/clipboard-live-verification.md"
    printf '# fixture checkout\nverification.md review.md\n' >"$root/README.md"
    printf '# fixture agents\nKeep no verification-notes.md in a change.\n' >"$root/AGENTS.md"
    printf 'ephemeral\n' >"$root/.build/notes/verification.md"
    printf 'ephemeral\n' >"$root/docs/handoff.txt"
    ln -s clipboard-live-verification.md "$root/docs/linked-notes.md"
}

fingerprint() {
    python3 - "$1" <<'PY'
import hashlib, os, sys

root = sys.argv[1]
digest = hashlib.sha256()
for dirpath, dirnames, filenames in os.walk(root):
    dirnames.sort()
    for name in sorted(dirnames + filenames):
        path = os.path.join(dirpath, name)
        digest.update(os.path.relpath(path, root).encode() + b"\0")
        if os.path.islink(path):
            digest.update(b"link\0" + os.readlink(path).encode())
        elif os.path.isfile(path):
            with open(path, "rb") as handle:
                digest.update(b"file\0" + hashlib.sha256(handle.read()).hexdigest().encode())
        else:
            digest.update(b"dir\0")
print(digest.hexdigest())
PY
}

# --- Allowed structures pass -------------------------------------------------

scaffold "$FIXTURES/official"
expect_status "official artifacts" "$FIXTURES/official" 0
grep -Fxq 'PASS openspec artifact hygiene' <<<"$GATE_OUTPUT" ||
    die "official artifacts: missing the PASS line"

mkdir -p "$FIXTURES/empty/openspec/changes"
expect_status "empty changes directory" "$FIXTURES/empty" 0

# --- Unknown Markdown fails in active and archived changes -------------------

for name in verification.md verification-notes.md review.md stage3-findings.md \
    implementation-summary.md activity-report.md stage3-report.txt paste-timings.txt; do
    root="$FIXTURES/forbidden-$name"
    scaffold "$root"
    printf 'ephemeral\n' >"$root/openspec/changes/active-change/$name"
    printf 'ephemeral\n' >"$root/openspec/changes/archive/2026-01-01-archived-change/$name"
    expect_offenders "forbidden $name" "$root" \
        "openspec/changes/active-change/$name" \
        "openspec/changes/archive/2026-01-01-archived-change/$name"
done

# --- Path shapes: containers, nesting, case, hidden directories --------------

root="$FIXTURES/path-shapes"
scaffold "$root"
mkdir -p "$root/openspec/changes/active-change/notes" \
    "$root/openspec/changes/active-change/.hidden" \
    "$root/openspec/changes/active-change/specs/capability/reports"
printf 'ephemeral\n' >"$root/openspec/changes/notes.md"
printf 'ephemeral\n' >"$root/openspec/changes/notes.txt"
printf 'ephemeral\n' >"$root/openspec/changes/proposal.md"
printf 'ephemeral\n' >"$root/openspec/changes/archive/notes.md"
printf 'ephemeral\n' >"$root/openspec/changes/archive/report.txt"
printf 'ephemeral\n' >"$root/openspec/changes/archive/tasks.md"
printf 'ephemeral\n' >"$root/openspec/changes/active-change/notes/tasks.md"
printf 'ephemeral\n' >"$root/openspec/changes/active-change/notes/proposal.md"
printf 'ephemeral\n' >"$root/openspec/changes/active-change/.hidden/review.md"
printf 'ephemeral\n' >"$root/openspec/changes/active-change/.hidden/raw.txt"
printf 'ephemeral\n' >"$root/openspec/changes/active-change/specs/capability/reports/design.md"
printf 'ephemeral\n' >"$root/openspec/changes/active-change/VERIFICATION.MD"
printf 'ephemeral\n' >"$root/openspec/changes/active-change/NOTES.TXT"
expect_offenders "path shapes" "$root" \
    'openspec/changes/active-change/.hidden/raw.txt' \
    'openspec/changes/active-change/.hidden/review.md' \
    'openspec/changes/active-change/NOTES.TXT' \
    'openspec/changes/active-change/VERIFICATION.MD' \
    'openspec/changes/active-change/notes/proposal.md' \
    'openspec/changes/active-change/notes/tasks.md' \
    'openspec/changes/active-change/specs/capability/reports/design.md' \
    'openspec/changes/archive/notes.md' \
    'openspec/changes/archive/report.txt' \
    'openspec/changes/archive/tasks.md' \
    'openspec/changes/notes.md' \
    'openspec/changes/notes.txt' \
    'openspec/changes/proposal.md'

# --- Invocable from another working directory, read-only, deterministic ------

before="$(fingerprint "$root")"
expect_status "path shapes from here" "$root" 1
here_output="$GATE_OUTPUT"
(cd / && "$GATE" "$root" >"$FIXTURES/elsewhere.out" 2>&1) &&
    elsewhere_status=0 || elsewhere_status=$?
[[ "$elsewhere_status" -eq 1 ]] ||
    die "path shapes from elsewhere: expected exit 1, got $elsewhere_status"
[[ "$(cat "$FIXTURES/elsewhere.out")" == "$here_output" ]] ||
    die "path shapes: output depends on the caller's working directory"
[[ "$(fingerprint "$root")" == "$before" ]] ||
    die "path shapes: the gate changed the fixture"

# --- Spaces and newlines in path names --------------------------------------

root="$FIXTURES/odd-names"
scaffold "$root"
mkdir -p "$root/openspec/changes/odd change"
printf 'ephemeral\n' >"$root/openspec/changes/odd change/verification notes.md"
printf 'ephemeral\n' >"$root/openspec/changes/odd change/two"$'\n'"lines.md"
printf 'ephemeral\n' >"$root/openspec/changes/odd change/proposal.md "
printf 'ephemeral\n' >"$root/openspec/changes/odd change/notes.txt "
printf 'ephemeral\n' >"$root/openspec/changes/odd change/tasks.md."
printf 'ephemeral\n' >"$root/openspec/changes/odd change/proposal.md"$'\n'
expect_offenders "spaces and newlines" "$root" \
    'openspec/changes/odd change/notes.txt\x20' \
    'openspec/changes/odd change/proposal.md\n' \
    'openspec/changes/odd change/proposal.md\x20' \
    'openspec/changes/odd change/tasks.md.' \
    'openspec/changes/odd change/two\nlines.md' \
    'openspec/changes/odd change/verification notes.md'

# --- Symlinks are rejected and never followed --------------------------------

root="$FIXTURES/symlinks"
scaffold "$root"
outside="$FIXTURES/outside-tree"
mkdir -p "$outside"
printf 'ephemeral\n' >"$outside/verification.md"
rm "$root/openspec/changes/active-change/proposal.md"
ln -s "$outside/verification.md" "$root/openspec/changes/active-change/proposal.md"
ln -s "$outside" "$root/openspec/changes/active-change/specs/linked"
ln -s "$outside/absent.md" "$root/openspec/changes/active-change/notes.md"
expect_status "symlinks" "$root" 1
expect_link "symlinks" 'openspec/changes/active-change/proposal.md'
expect_link "symlinks" 'openspec/changes/active-change/notes.md'
expect_link "symlinks" 'openspec/changes/active-change/specs/linked'
refuse "symlinks" 'specs/linked/verification.md'
if grep -Fxq 'Unexpected Markdown under openspec/changes:' <<<"$GATE_OUTPUT"; then
    die "symlinks: reported symlinks as unexpected Markdown"
fi
[[ "$(grep -c ' -> ' <<<"$(reported_lines)")" -eq 3 ]] ||
    die "symlinks: expected exactly three link reports: $(reported_lines)"
if grep -v '^openspec/changes/' <<<"$(reported_lines)" | grep -q .; then
    die "symlinks: reported a path outside openspec/changes: $(reported_lines)"
fi

# --- Ignored and untracked artifacts are still inspected ---------------------

root="$FIXTURES/ignored"
scaffold "$root"
printf 'openspec/changes/**/*.md\n' >"$root/.gitignore"
git -C "$root" init -q
printf 'ephemeral\n' >"$root/openspec/changes/active-change/verification.md"
git -C "$root" check-ignore -q "$root/openspec/changes/active-change/verification.md" ||
    die "ignored: fixture artifact is not actually git-ignored"
expect_offenders "ignored artifact" "$root" \
    'openspec/changes/active-change/verification.md'

# --- Missing, non-directory and symlinked scan roots -------------------------

expect_status "absent checkout" "$FIXTURES/absent" 2
grep -Fq 'ERROR openspec artifact hygiene' <<<"$GATE_OUTPUT" ||
    die "absent checkout: missing the scan failure report"

mkdir -p "$FIXTURES/no-changes/openspec"
expect_status "missing changes root" "$FIXTURES/no-changes" 2

mkdir -p "$FIXTURES/changes-is-file/openspec"
printf 'not a directory\n' >"$FIXTURES/changes-is-file/openspec/changes"
expect_status "changes root is a file" "$FIXTURES/changes-is-file" 2

mkdir -p "$FIXTURES/linked-root/openspec"
ln -s "$outside" "$FIXTURES/linked-root/openspec/changes"
expect_status "symlinked changes root" "$FIXTURES/linked-root" 2

# --- The gate guards the real verification chain -----------------------------

# A failing gate must stop a `set -euo pipefail` chain before later checks run,
# exactly as it does in script/verify_all.sh.
cat >"$FIXTURES/chain.sh" <<'SH'
set -euo pipefail
"$1" "$2"
touch "$3"
SH

chain="$FIXTURES/chain-broken"
scaffold "$chain"
printf 'ephemeral\n' >"$chain/openspec/changes/active-change/verification.md"
if bash "$FIXTURES/chain.sh" "$GATE" "$chain" "$FIXTURES/sentinel-broken" >/dev/null 2>&1; then
    die "chain: a failing gate did not stop the chain"
fi
if [[ -e "$FIXTURES/sentinel-broken" ]]; then
    die "chain: a later command ran after the gate failed"
fi

chain="$FIXTURES/chain-clean"
scaffold "$chain"
bash "$FIXTURES/chain.sh" "$GATE" "$chain" "$FIXTURES/sentinel-clean" >/dev/null ||
    die "chain: a clean fixture did not reach the next check"
if [[ ! -e "$FIXTURES/sentinel-clean" ]]; then
    die "chain: the next check did not run for a clean fixture"
fi

# script/verify_all.sh must keep running the gate and its fixtures before the
# existing packaging check, without reordering anything else.
gate_line="$(grep -n 'openspec_artifact_hygiene\.sh$' "$ROOT_DIR/script/verify_all.sh" | head -1 | cut -d: -f1)"
test_line="$(grep -n 'openspec_artifact_hygiene_test\.sh$' "$ROOT_DIR/script/verify_all.sh" | head -1 | cut -d: -f1)"
packaging_line="$(grep -n 'packaging_test\.sh$' "$ROOT_DIR/script/verify_all.sh" | head -1 | cut -d: -f1)"
[[ -n "$gate_line" && -n "$test_line" && -n "$packaging_line" ]] ||
    die "verify_all: a hygiene check is missing from script/verify_all.sh"
[[ "$gate_line" -eq $((test_line - 1)) ]] ||
    die "verify_all: the fixtures do not follow the gate"
[[ "$gate_line" -lt "$packaging_line" ]] ||
    die "verify_all: the hygiene gate does not run before the packaging check"
grep -q '^set -euo pipefail$' "$ROOT_DIR/script/verify_all.sh" ||
    die "verify_all: set -euo pipefail is missing"

# --- The gate is anchored to its own checkout --------------------------------

"$GATE" >"$FIXTURES/anchored-here.out" 2>&1 && here_status=0 || here_status=$?
(cd "$FIXTURES" && "$GATE" >"$FIXTURES/anchored-away.out" 2>&1) &&
    away_status=0 || away_status=$?
[[ "$here_status" -eq "$away_status" ]] ||
    die "anchoring: exit status depends on the caller's working directory"
[[ "$(cat "$FIXTURES/anchored-here.out")" == "$(cat "$FIXTURES/anchored-away.out")" ]] ||
    die "anchoring: output depends on the caller's working directory"

echo "openspec artifact hygiene tests passed"
