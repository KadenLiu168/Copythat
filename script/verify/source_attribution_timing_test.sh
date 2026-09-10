#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANALYZER="$ROOT_DIR/script/verify/source_attribution_timing.sh"
FIXTURES="$ROOT_DIR/script/verify/fixtures/source_attribution_timing"

assert_passes() {
    local mode="$1"
    local fixture="$2"
    local output
    output="$($ANALYZER analyze "$mode" "$FIXTURES/$fixture")"
    grep -q 'PASS source attribution timing' <<<"$output"
    if grep -q 'secret-marker' <<<"$output"; then
        echo "analyzer exposed a clipboard marker" >&2
        exit 1
    fi
}

assert_fails() {
    local mode="$1"
    local fixture="$2"
    if "$ANALYZER" analyze "$mode" "$FIXTURES/$fixture" >/dev/null 2>&1; then
        echo "expected analyzer failure for $fixture" >&2
        exit 1
    fi
}

assert_passes non-keyboard valid-non-keyboard.jsonl
assert_passes shortcut valid-shortcut.jsonl
assert_fails non-keyboard wrong-order.jsonl
assert_fails non-keyboard wrong-source.jsonl
assert_fails non-keyboard wrong-slot.jsonl
assert_fails non-keyboard invalid-change-count-type.jsonl
assert_fails non-keyboard unsafe-extra-field.jsonl

bash -c '
    source "$1"
    exercise_cleanup_after_local_scope() {
        local cleanup_dir cleanup_pid
        cleanup_dir="$(mktemp -d -t copythat-source-cleanup-test)"
        sleep 30 &
        cleanup_pid=$!
        register_live_cleanup "$cleanup_pid" "$cleanup_dir"
    }
    exercise_cleanup_after_local_scope
' _ "$ANALYZER"

echo "source attribution timing analyzer tests passed"
