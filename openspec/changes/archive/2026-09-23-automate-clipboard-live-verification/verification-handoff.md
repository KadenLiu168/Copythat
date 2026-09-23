# Verification handoff — automate-clipboard-live-verification

Status: **implementation delivered; live routine profile delivered on this
machine (post stage-3 independent review); original-writer reproduction and
real-permission denial remain blocked with precisely recorded prerequisites.**
No task of `improve-clipboard-capture-responsiveness` was checked, archived, or
accepted from this work; that change's checkboxes are untouched.

## Stage-3 independent review (repairs applied)

The post-implementation review found and fixed defects in the delivered
tooling, then re-ran every gate and rebuilt the live evidence below:

- `successive_ab_copies`: the burst-precondition assertion was measured ~1.3s
  before copy B (a page load in between guaranteed the 0.6s burst window had
  expired), so the delivered runs never actually exercised the
  rapid-succession boundary they claimed. Both fixture tabs are now prepared
  before copy A; the burst is measured immediately before B's copy.
- `copy_then_switch_non_keyboard`: the change count was sampled after the menu
  click returned, blinding the write observation and forcing a spurious retry;
  the late-switch check was evaluated before the copy instead of at switch
  time. Retained pre-review runs show the fixture had already resolved ~5s
  before the switch while the scenario claimed race coverage. Both fixed; the
  race check is now evaluated at switch initiation.
- `runRecipes`: the isolated candidate was started AFTER the recipe actions,
  so no recipe execution could ever commit (the store snapshotted the
  post-write change count). The candidate now monitors before the actions;
  the executor was verified live with a throwaway Chrome recipe (2 observed
  transitions + committed result, evidence level `original-application-replay`).
- `cut_editable_text`: the committed item/source assertion required by the
  design's Cut contract was claimed in the reason text but never asserted; it
  is now asserted, correlated through the cut's own change count so the
  pre-cut verification copy cannot satisfy it.
- `successive_ab_copies` timings were a constant (`abCommitSpan: 0`);
  measured commit latencies are recorded instead.
- `clipboard_live.sh run original-writer` did not hold the single-run lock;
  it now does (concurrent runs are rejected, verified exit 2).
- `clipboard_live.sh self-test` held the run lock itself, which made its own
  nested blocked-path fixtures fail; the wrapper no longer locks (self-test
  is fixtures, not a run).
- The driver selftest's burst-precondition check only verified verdict
  vocabulary; it now exercises the real gate against an expired burst.
- Docs now disclose that the self-test performs one synthetic pbcopy write to
  the real pasteboard; `script/verify/__pycache__/` is gitignored.

## What actually ran (unattended, on this machine)

Two retained full routine runs (identical repaired candidate):

- `.build/clipboard-live/reports/routine-postreview-1/report.json`
- `.build/clipboard-live/reports/routine-postreview-2/report.json`
- Both: 9 required scenarios **passed**, `real_permission_denial` blocked
  (by design), exit 2 (incomplete overall coverage, no failures).

Delivered live scenarios (evidence level `automated-real-desktop`, input
mechanism `osascript System Events keystroke`, recorded in provenance):

| Scenario | Verdict | Core evidence |
| --- | --- | --- |
| input_qualification (task 1.3) | passed | `copy_shortcut_observed` via the real `CGEvent.tapCreate`, pasteboard change, committed fixture digest, `source_resolved` slot=shortcut |
| successive_ab_copies (3.1) | passed | committed `[B, A]`, Chrome sources, copy B landed 0.43s after A's commit inside the 0.6s burst window (measured at B's copy, not earlier); measured `aCommitLatency`/`bCommitLatency`; missed-precondition path verified by a real fixture in the driver selftest |
| cut_editable_text (3.2) | passed | real Cmd+X through the tap, wake observed, committed item asserted with Code source (correlated to the cut's own change count), buffer emptied (pre-cut focus check) |
| clipboard_screenshot_region (3.2) | passed | `screencapture -R` region image committed, attributed to the frontmost app; no fabricated copy/cut event in the scenario window |
| copy_then_switch_keyboard (3.3) | passed | switch landed before resolution (write→switch→resolve ordering in events); Chrome source retained; shortcut evidence present |
| copy_then_switch_non_keyboard (3.3) | passed | single real Chrome menu Copy (locale-independent `AXMenuItemCmdChar`), write observed, then switch before resolution (run-1: observe→switch 147ms, resolve +21ms after switch; run-2: +147ms/+17ms); a late-switch trace now maps to not-covered via the at-switch-time check |
| restore_paste (3.4) | passed | store restore wrote the pasteboard, target equality verified, no recapture/duplicate movement across a ≥1.6 s window |
| restore_paste_negative (3.4) | passed | recaptured write handled by dedupe without unbounded growth |
| event_tap_failure_injection (3.5) | passed | injected `eventTapFactory = { nil }`; production idle fallback captured; no shortcut evidence; no permission attempt |

## Blocked, with precise prerequisites

1. **real_permission_denial (3.5b)** — the driver binary inherits
   Accessibility trust in this environment, so a confirmed OS denial cannot be
   produced here. The scenario is implemented and executable in a preconfigured
   session where the driver is untrusted: it confirms tap creation genuinely
   fails, idle capture continues, and no permission request is attempted.
   Reports distinguish injected failure vs confirmed OS denial vs unavailable
   environment.
2. **original_writer_replay (4.1/4.2)** — no established recipe exists for
   the archived Doubao→ChatGPT sequence. Installed writer candidates found on
   this machine: ChatGPT.app 26.915.31945, Doubao.app 2.24.10 (recorded as
   metadata in the blocked reason). The archived historical action sequence and
   the measured baseline remain the missing evidence; **original 5.2 stays
   pending**. The versioned recipe format, the driver's recipe executor
   (identity/version gating, multi-stage transition observation, commit
   verification — now live-verified with a throwaway Chrome recipe), and the
   deterministic replay driver are delivered and fixture-tested.
3. **replay comparison support (4.3)** — replay verified live
   (`transient+final within 120 ms → only final committed`, synthetic-replay
   labeled). Sequential baseline/candidate comparison is supported by the
   report contract but cannot produce a 5.2 acceptance claim without measured
   baseline evidence, which does not exist.

## Environment limitations recorded (not silently accepted)

- This machine is the user's daily desktop, not a disposable account. A
  resident Copythat.app captures scenario copies into the real user history;
  every retained report carries the interference note and the user-history/
  settings sentinel verification ran in each run (runner-written isolation
  verified; resident-app interference reported, not hidden).
- During the review session, minimized Chrome windows could not be activated
  (AX-invisible while minimized on this macOS build); unminimizing restored
  activation. Recorded as an environment observation, not a tooling defect.
- `screencapture -R` region capture succeeded in the retained runs; on hosts
  where it fails the scenario reports blocked with the exact cause and
  full-screen capture is refused to preserve the fixture-only boundary.
- Focus interference (other apps activating mid-run) is guarded: frontmost
  re-checks plus one bounded, reported retry per input delivery; unrelated
  clipboard writes during a scenario window invalidate the run as blocked.

## Build identities (both retained post-review runs)

- driver digest `b42b53fa67c43f1d…` (`provenance.driverDigest`), built by
  `clipboard_live.sh` from `script/verify/clipboard_live_driver.swift` plus
  production sources (ClipboardStore, CopySourceTracker, AppSettings,
  ClipboardDiagnostics, and their dependencies).
- source snapshot digest `43305f46e80fec0d…` over HEAD `e37d1cd…` plus the
  dirty working tree (digest only; no raw diffs).

## Gates run against the final implementation (post-review repairs)

- `swift build` — pass
- `./script/verify_all.sh` — pass (134 production tests in 26 suites,
  analyzers, icon/packaging/bundle checks)
- focused: `ClipboardLiveVerificationSeamTests` 3/3,
  `clipboard_live.sh self-test` (all fixture checks, including the real
  missed-precondition mapping)
- recipe executor live check — pass (throwaway recipe, blocked prerequisites
  still recorded for the historical sequence)
- `openspec validate automate-clipboard-live-verification --strict` — valid
- `git diff --check` — clean

## Residual obligations (unchanged by this work)

- **5.2**: measured original ChatGPT-writer reproduction + baseline/candidate
  comparison → pending; requires the historical recipe and baseline evidence.
- **5.3**: physical rapid Cmd+C copies → pending; never automatable here.
- **5.5**: clipboard screenshot System-source attribution via the physical
  Cmd+Shift+4 flow, physical multi-display behavior, and permission UI checks
  → remain manual per project context.
- Real-permission-denied environment execution of `real_permission_denial`.
