# Unattended clipboard live verification

`script/verify/clipboard_live.sh` runs clipboard regression scenarios against a
real macOS desktop session without interactive prompts, and returns
payload-safe, machine-readable reports. It complements — never replaces —
`./script/verify_all.sh`, which remains the canonical gate.

## One-time desktop setup

The runner never requests permissions and never modifies TCC. Prepare the
session once, from an unlocked graphical login:

1. Grant **Accessibility** to the compiled driver binary. The runner compiles
   it to `.build/clipboard-live/clipboard-live-driver`; if the shell's
   responsible process already has Accessibility trust (e.g. an authorized
   terminal), the driver inherits it — verify with
   `./script/verify/clipboard_live.sh` preflight output (`accessibility=True`).
2. Grant **Automation** permission for *System Events* to the host terminal so
   keystroke delivery works without prompts.
3. Install **Google Chrome** (copy fixtures) and **Visual Studio Code** (paste
   target). Both are verified by preflight.
4. Run in a disposable test account when possible. The runner isolates the
   candidate's history and settings (per-run defaults suite
   `local.copythat.live-verify` + temp persistence), but real applications
   write to the general pasteboard; a resident Copythat.app captures those
   copies into the real user history (recorded as an interference note).

## Commands

```bash
# Qualify that automated input traverses the real event tap (task 1.3)
./script/verify/clipboard_live.sh run qualify-input --output <dir>

# Run every automatable scenario (tasks 3.1-3.5)
./script/verify/clipboard_live.sh run routine --output <dir>

# Original-writer recipe replay / measured-transition replay (tasks 4.1-4.3)
./script/verify/clipboard_live.sh run original-writer --output <dir>
REPLAY_TRANSITIONS=<measured-transitions.json> \
    ./script/verify/clipboard_live.sh run original-writer --output <dir>

# Validate a report (schema + payload safety + staleness)
./script/verify/clipboard_live.sh validate-report <dir>/report.json

# Analyzer/driver fixtures — no keystroke input and no real-application
# actions, but note the driver selftest performs one synthetic pbcopy write
# to the real general pasteboard (verified payload-safe digests only).
./script/verify/clipboard_live.sh self-test
```

No command reads stdin. Exit codes (D7): `0` all required cases passed; `1`
any behavioral/evidence failure (takes precedence); `2` incomplete
prerequisites/coverage (blocked/not-covered).

## Required cases per profile

- **qualify-input**: `input_qualification` — correlated
  `copy_shortcut_observed` (real event tap), pasteboard change, and committed
  fixture capture in the isolated production store.
- **routine**: `input_qualification`, `successive_ab_copies`,
  `cut_editable_text`, `clipboard_screenshot_region`,
  `copy_then_switch_keyboard`, `copy_then_switch_non_keyboard`, `restore_paste`,
  `restore_paste_negative`, `event_tap_failure_injection`.
  `real_permission_denial` is reported but not required: it is only executable
  in a preconfigured session where the driver binary lacks Accessibility.
- **original-writer**: `original_writer_replay` — executable only with an
  established versioned recipe (`script/verify/recipes/*.json`). Without one
  the profile reports the precise missing prerequisite and exit code 2.

## Report interpretation

- `report.json` (schema-validated), `report.txt` (human summary),
  `results.jsonl` + `events.jsonl` (sanitized scenario results and
  `source_timing` events).
- Every scenario carries a verdict (`passed`/`failed`/`blocked`/
  `not-covered`), an evidence level, per-assertion detail, and timings.
  Reports contain digests, lengths, kinds, verdicts, and timing only —
  never clipboard payloads. `clipboard_live_report.py validate` rejects
  malformed, stale (>24h), out-of-order, or payload-bearing reports.
- Provenance records the source revision plus a content digest of implementation
  sources and verification scripts (`Sources`, `Tests`, `script`, `Package.swift`), driver
  digest, build configuration, OS and application versions, selected timing
  constants, and the input mechanism. Git HEAD alone is never sufficient.
- Evidence levels are distinct: `automated-real-desktop` is OS input through
  the real event tap; it is **not** physical input. `synthetic-replay` is
  labeled and never counts as original-writer reproduction.
- `clipboard_screenshot_region` uses `screencapture -R` (system workflow).
  That CLI write carries no screenshot pasteboard type, so production
  attributes it through the foreground slot; the *System* source assertion
  stays with the physical Cmd+Shift+4 flow (original 5.5). When region
  capture is unavailable, the scenario reports blocked with the exact cause;
  full-screen capture is refused to preserve the fixture-only boundary.
- `originalTaskMapping` in every report maps results back to original
  5.2/5.3/5.5 and lists residual obligations. The runner never edits the
  original change's checkboxes.

## Permission-denied setup (real_permission_denial)

Prepare a separate session where the driver binary is **not** Accessibility
trusted (a fresh user account without the grant). Run the routine profile
there: the driver confirms tap creation actually fails, verifies capture
continues through the idle fallback, and verifies no permission request is
attempted. Reports then distinguish:

- **injected failure** (`event_tap_failure_injection`: tap factory overridden
  by the verification seam),
- **confirmed OS denial** (`real_permission_denial` passed in the prepared
  session),
- **unavailable environment** (`real_permission_denial` blocked because the
  binary is trusted where it runs).

## Original-task mapping

- *improve-clipboard-capture-responsiveness* **5.2** accepts the 120 ms synthetic
  replay under the user's direction. Historical ChatGPT writer behavior and a
  measured baseline remain unverified.
- **5.3** accepts qualified automated OS-input rapid copies under the user's
  direction. Physical HID behavior remains unverified.
- **5.5** accepts automated cut, region screenshot, app-switch, restore/paste,
  and injected tap-failure coverage. Physical screenshot System-source,
  multi-display, and OS permission-denial behavior remain unverified.
