# Verification record — paste-responsiveness

## Task 3.1 — repository gates (fresh Stage 3 pass, 2026-09-28)

- `swift build`: clean.
- `./script/verify_all.sh`: all gates pass — 177 tests in 32 suites (includes
  new `ClipboardPastePerformerTests`, 14 tests, and existing `PasteDecisionTests`),
  source resolution, source attribution timing, icons, portable app, panel
  geometry, bundle plist, code signature.
- `CopySourceTracker` and `PanelWindowController`: unchanged (git diff limited to
  `ClipboardPastePerformer.swift` + new test file).

Stage 3 independently reran the complete gate because the earlier record's
`2025-06` date and missing revision identity were insufficient for reuse.

- Base `HEAD`: `d2bd9741c0d3cab358be4ae56616b672a3bf1843`; reviewed working-tree
  implementation and untracked tests, not just the committed base.
- `swift build`: exit 0.
- `swift test -Xswiftc -F -Xswiftc /Applications/Xcode.app/Contents/Developer/Library/Frameworks`:
  exit 0, 177 tests in 32 suites.
- `PATH=/opt/homebrew/Caskroom/miniconda/base/bin:$PATH ./script/verify_all.sh`:
  exit 0, 177 tests in 32 suites and all remaining repository gates passed.
  Conda Python provides Pillow; the system Python lacks it. No gate was changed.
  Full local log: `/tmp/copythat-paste-stage3-verify.log` (temporary, not a
  durable archived artifact).
- `openspec validate paste-responsiveness --strict`: passed.
- `openspec validate --all --strict`: 8 passed, 0 failed; existing informational
  long-requirement notices only.
- `openspec doctor`: root ok, no declared references.
- `git diff --check`: passed. Installed CLI does not advertise `openspec verify`.
- SHA-256, verified unchanged before and after the complete gate:
  - `Sources/Copythat/Services/ClipboardPastePerformer.swift`:
    `ace7e5782806e5291dcc90d5dc9df495c7da18c116a1a41a6088ec044ec55824`
  - `Tests/CopythatTests/ClipboardPastePerformerTests.swift`:
    `c94f16604340a2e735d1b79f91f3617c5805e53c52704771a8fa769fdcd869dc`

Only this verification record was edited during Stage 3; no production code or
tests needed repairs. The existing implementation/test diff was preserved.

## Task 3.2 — real automatic-paste smoke test through the actual panel

Evidence boundary: the observations below are the earlier implementation-stage
report. Stage 3 checked the actual caller and implementation against this
procedure, but did not repeat the TextEdit paste or retain its raw automation
output. The reported polling interval is an observation, not a precise latency
measurement or a stable responsiveness guarantee. The fresh repository gate
above verifies launch/panel behavior but does not repeat this paste smoke test.

Environment: local user session, Copythat accessibility granted (CGEvent posting
worked), caller automation/keystroke permission granted. Target controlled by
file-driven TextEdit document; AX reads via System Events (TextEdit-targeted
Apple Events are NOT authorized in this environment — content verification used
System Events AXValue reads instead, which is why the live driver was not used:
it restores through the store and sends its own Command-V, bypassing the
performer).

- Target app: TextEdit (`/tmp/copythat-smoke-doc.txt`, initial text
  "copythat smoke marker").
- Permission state: Accessibility granted for both the caller (System Events
  keystrokes delivered) and Copythat (Command-V posted successfully).
- Procedure: TextEdit frontmost → global shortcut (Command-Shift-V) opens the
  real panel → Return triggers `PanelWindowController.pasteSelected` →
  `ClipboardPastePerformer.paste` (production path, no seams).
- Case 1 (normal activation): smoke string restored to pasteboard, TextEdit
  re-activated, Command-V delivered. Doc text changed within 1 poll iteration
  (~20–60 ms, well below the 350 ms fallback → activation-confirmed fast path).
  Content pasted exactly once (occurrences=1). Panel closed (no panel window;
  only an unrelated window present, see below). Focus returned to TextEdit.
- Case 2 (repeat paste): second full panel→paste cycle appended exactly one more
  occurrence (total 2 after two attempts; at-most-once per attempt). Both Return
  keystrokes were consumed by the panel (no stray newline inserted into the
  target document).
- Already-active case: not reachable through the actual panel path — `show()`
  captures the previous frontmost app and then activates Copythat, so the target
  is never already-active at paste time. That scenario is covered by the
  deterministic test `alreadyActiveTargetSendsWithoutActivationEvent`.
- Run-2 latency reading was lost (harness script error after the paste
  completed); run-2 content/count/focus outcomes are verified from the document
  text. Run-1 latency is the recorded responsiveness evidence.
- Unrelated observation: one launch restored a stale "Copythat Settings" saved
  window; a clean A/B relaunch (pre-change and post-change builds, both via
  `open dist/Copythat.app`, process presence verified) showed 0 windows on both,
  so this was stale saved app state, not a regression from this change.

Post-test cleanup: original clipboard content restored via pbcopy; TextEdit
document state reverted; test temp files removed. The freshly built app remains
running for the user.

## Task 3.3 — adversarial review

Findings checked against focused tests in `ClipboardPastePerformerTests`:

- Notification-before-activate ordering: observer + fallback installed before
  `activate()`; both cleanup handles exist when a notification arrives
  synchronously inside the activation request
  (`observerAndFallbackAreInstalledBeforeActivation`,
  `synchronousNotificationInsideActivationRequest`).
- Post-activation check cannot rearm a completed attempt (token-claimed
  completion is idempotent; `synchronousNotificationInsideActivationRequest`).
- Competing fallback/observer callbacks: single token-checked claim; both
  callback orders verified
  (`activationAndTimeoutCompeteSendsAtMostOnce`).
- Queued send supersession: request-entry invalidation bumps the attempt
  generation; queued delivery rechecks it before sending
  (`supersedingAttemptInvalidatesQueuedSend`); a failed newer restore or a
  missing-target newer request through the real `paste()` entry cancels pending
  and queued attempts
  (`failedNewerRestoreSupersedesQueuedSend`,
  `missingTargetFailureSupersedesPendingAttempt`).
- Deinit cleanup: observer removed, fallback cancelled, queued delivery
  neutralized after release, in both the awaiting-activation and queued-delivery
  states (`releasedPerformerCleansUpPendingAttempt`,
  `releasedPerformerCannotSendQueuedDelivery`). Deallocation of this
  main-actor-owned performer happens on the main thread in practice (owner is
  `PanelWindowController`; test fixtures are `@MainActor`), matching the
  existing `CopySourceTracker` deinit precedent.
- Target focus loss between confirmation and delivery: design-documented
  tradeoff — delivery goes to the then-foreground app with no new delivery-time
  gate; the real-app check observed correct focus restoration and correct
  content in the intended target. No change to target/fallback semantics in
  this change.
- Timer workItem cancel-after-start race: stale callback rechecks the token and
  is a no-op (covered by the post-claim fallback firing in
  `targetPIDActivationQueuesSendOnNextMainQueueTurn` and the compete test).
- Production observer threading: `NSWorkspace` notification observer registered
  with `queue: .main`; callback hops to the main actor via
  `MainActor.assumeIsolated` (same pattern as `ClipboardStore`'s timer).

Full suite re-run after review: `swift test` — 177 tests in 32 suites pass.

## Stage 3 — independent review and requirement evidence

A fresh reviewer inspected all Change artifacts, the complete implementation
diff, all 14 coordination tests, existing restore/decision tests, callers and
gate configuration. No Blocker/High or necessary behavioral Medium was found.
The necessary Medium concerning gate date/revision evidence was repaired by
the fresh gate and revision identity above.

| Requirement / scenarios | Design / tasks | Implementation | Test / validation evidence |
|---|---|---|---|
| Prompt activation, already-active, synchronous confirmation | Decisions 2–3; 1.2, 2.1–2.2 | `beginPasteAttempt`: observer/fallback before activation, pre/post active checks, exact PID; production `defaultScheduleSend` uses main-queue async | Target/wrong PID, already-active, post-activation, synchronous notification and installation-order tests; reported real panel smoke |
| Unrelated activation and absent confirmation | Decisions 2–3; 1.2, 2.2 | PID filter; `fallbackDelay = 0.35`; unconditional fallback completion | Wrong-PID and absent-confirmation tests; full gate |
| At most once with either callback ordering | Decisions 1, 3; 1.3, 2.2 | `completeAttempt` claims and clears pending state before cleanup/delivery | Both callback orders and stale callbacks tested |
| Superseded pending or queued delivery, including failed newer request | Decisions 1, 4; 1.3, 2.1–2.2 | `paste` invalidates at entry; `supersedePendingAttempt`; queued send rechecks generation | Pending/queued supersession tests; actual `paste` restore-failure and missing-target tests with exact messages |
| Release cleans up and never sends later | Decisions 1, 3–4; 1.3, 2.2 | Weak callbacks, deinit cleanup | Pending and queued release tests |
| Restore, target, Accessibility and immediate panel dismissal compatibility | Decisions 1, 4; 2.1, 3.1–3.2 | Existing gates/messages and `PanelWindowController.pasteSelected` synchronous close retained | Existing restore/decision tests, actual-entry failure tests, full gate and reported panel smoke |

The single-turn delivery can still send to a different foreground app if focus
changes after confirmation. This is the explicitly retained design tradeoff;
the 350 ms fallback likewise remains unconditional. Already-active behavior is
covered deterministically because the actual panel activates Copythat before
paste. These are evidence/behavior boundaries, not additional guarantees.

Stage 3 outcome: passed after repairing verification evidence. Archive is
recommended; archival, commit and push were not performed in this stage.
