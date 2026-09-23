## Context

See proposal.md for motivation. `source_attribution_timing.sh` currently supports shortcut/non-keyboard modes, reads interactive confirmation or waits for a fixed interval, and analyzes four source-timing event types. Its non-keyboard live branch uses `pbcopy`, which is not real application Copy evidence. Its shortcut analyzer accepts Code activation after resolution, which is sufficient for that trace but does not prove switching during pending capture.

Production Swift tests already cover quiet-time boundaries, transient replacement, successive stable copies, source pairing, wake callbacks, lifecycle cancellation, and restore. Tracker tests call `handle` directly; they do not establish that OS input traverses `CGEvent.tapCreate`. The screenshot branch queues a System source and wakes without emitting a copy/cut event. `source_resolved` occurs before a successful history insertion can be assumed, especially for asynchronous images.

The responsiveness Change remains unfinished. Its 5.2 requires measured original ChatGPT writer evidence and baseline/candidate comparison; 5.3 explicitly requires physical Cmd+C. Project context also retains manual permission, paste, and UI checks. This tooling change adds routine automation without silently rewriting those obligations.

## Goals / Non-Goals

Goals: unattended bounded execution in a prepared desktop session; production-path assertions; truthful evidence levels; reproducible reports; isolated persistent data.

Non-goals: general automation infrastructure, altered scheduler behavior, synthetic evidence represented as physical input, or production permission bypasses. See proposal.md for full scope.

## Decisions

### D1. One explicit runner, separate evidence levels

Add `script/verify/clipboard_live.sh` with `qualify-input`, `routine`, and `original-writer` profiles and an explicit output directory. Profiles execute without stdin prompts. Reuse existing analyzer/schema logic where semantics match; keep old manual harness compatibility. Prefer a small Swift/AppKit test driver and existing shell tooling over a new framework dependency.

Reports distinguish deterministic production tests, automated real-desktop integration, original-application replay, and physical-input evidence. A direct call to `handle`, `pbcopy`, or a synthetic writer never upgrades to real OS-input or original-writer evidence. Ordinary `verify_all.sh` remains a separate gate.

Alternative: automate the existing prompt sequence alone. Rejected because it would retain missing insertion assertions and conflate evidence levels.

### D2. Preflight and input qualification precede scenarios

Require an unlocked disposable macOS test account/session, target applications, an isolated candidate, existing runner permissions, and an available diagnostics sink. Verify actual frontmost application and collector readiness before sending input. A dedicated session may be configured once; each run must neither request new permissions nor reset TCC.

The first implementation slice tests automated input through the real tracker event tap and real source application. Require correlated shortcut observation, pasteboard change, and committed fixture result. Direct handler invocation cannot satisfy qualification. If delivery is unavailable, report blocked for dependent live scenarios and continue independent tests; do not silently fall back to fake input evidence. Record the input mechanism used. Hardware input is out of scope.

Alternative: promise that synthetic events behave identically on all hosts. Rejected because prior runs did not establish delivery and the current environment must be qualified.

### D3. Observe completed effects and enforce timing preconditions

Reuse `ClipboardDiagnostics` and existing insertion metadata first. Add only missing metadata-only test observations for committed results, event-tap availability, and wake/burst state if existing evidence cannot establish a scenario. Scope test hooks to the verification bootstrap; retain normal production scheduling and permission checks. Observation callbacks must not poll, wake, capture, or mutate history themselves.

Correlate candidate process, scenario boundaries, monotonic time, pasteboard count, source, insertion outcome, and fixture identity digest. Check committed history and the actual paste target in memory or isolated test storage; persist only verdicts and safe metadata. Do not record text, URLs, file paths, image bytes, UI dumps, screenshots, or unique copied markers in reports. Candidate artifact paths and application identifiers are execution metadata, not clipboard payload.

Use bounded event waits, not sleeps as success assertions. Stabilization, asynchronous image completion, and no-recapture observation windows need distinct deadlines. A no-recapture check spans at least the active burst tail plus two idle ticks after restore; record the actual duration. Detect unrelated clipboard writes and frontmost interference as an invalid/blocked run. Any repeat is bounded and reported; never retry away a genuine failed assertion.

Alternative: count `source_resolved` events. Rejected because parsing can precede filtering, insertion, or image completion.

### D4. Scenario contracts

| Scenario | Action and required evidence | Acceptance boundary |
|---|---|---|
| Successive A/B | Prepare two distinct harmless values in a real application; copy A; observe actual A commit; copy B while the burst is still active; assert committed order `[B, A]` and correct sources | If the timing precondition is missed, report not-covered; automated input does not close existing physical 5.3 |
| Cut | Use an editable fixture; deliver Cmd+X; check text removal, cut observation, wake, and committed item/source | Command dispatch alone is insufficient |
| Clipboard screenshot | Capture only a fixture region through the system screenshot workflow; check wake/System shortcut evidence and completed image insertion | Do not require or fabricate a copy/cut event; slow region selection may exceed burst and must be reported accurately |
| Copy then switch | Separate keyboard and non-keyboard cases; for non-keyboard, invoke actual Chrome Copy, observe Chrome count, switch to Code before resolution; require retained Chrome source | Late switching is not pending-capture race coverage; fixed-delay switching is insufficient |
| Restore/paste | Invoke the actual app restore/paste path into a known target; assert target equality and no recapture during the observation window | A pasteboard write alone does not prove paste; a duplicate may be moved without increasing history count, so inspect mutations too |
| Event-tap failure | Inject tap creation failure through a narrow test seam; keep the real idle store path active and perform a non-keyboard write; assert capture and no permission-request attempt | Label injected failure separately from OS-denied permission |
| Real permission denial | In a separately prepared denied-permission session, confirm tap creation actually fails and capture still works through idle fallback | Missing shortcut events alone do not prove tap failure; routine runner never changes permissions |

The routine profile covers all automatable cases above, with real permission denial reported separately when its prepared environment is unavailable. Existing unit tests remain responsible for exact virtual-time boundaries and source precedence.

### D5. Original-writer replay is a separate, automatable profile

Record application identity/version, macOS version, copy method, fixture preparation, and exact actions. Start with the archived Doubao-then-ChatGPT sequence, treating desktop/browser/button/selection variants as candidate reproduction recipes, not established historical facts. Inspect installed versions and available records; request historical details only when those sources are insufficient. Once established, execute the recipe without human copy actions.

Use the actual writer to produce the pasteboard transitions. Require observed multi-stage count/timing evidence and committed-result checks that exclude transient insertion or duplicate movement; final history alone may conceal a transient mutation. A single final count can pass ordinary copying but leaves historical multi-stage coverage not-covered. Observation sampling can miss transitions, so lack of observations is not proof of atomic writer behavior.

Replay measured timings with harmless synthetic fixtures in deterministic tests for repeatable regression; label those separately. Compare baseline and candidate sequentially using the same recipe/environment, isolated history, identical observer configuration, and recorded artifact identities. Do not replace measured baseline latency with the design's estimated range. If actual writer/version or baseline is unavailable, record the exact missing evidence and leave original 5.2 pending. No physical-key requirement is imposed on this profile.

Alternative: accept a synthetic two-write script as historical reproduction. Rejected because it does not establish the original writer's behavior.

### D6. Data isolation and lifecycle ownership

Unit tests use named pasteboards and no-op/in-memory persistence. Real applications require the general pasteboard, so desktop runs require a disposable test account with test-only content. The runner must not read/export the normal user's history or attempt a lossy backup/restore of arbitrary clipboard types.

Create isolated candidate history/settings before startup; verify both loading and saving resolve to the test location. Reuse constructor injection and a verification-only bootstrap where needed; do not assume changing a shell HOME value isolates every macOS service. Validate isolation with sentinel tests. Keep normal app startup unchanged.

Track only owned PIDs, temporary paths, and settings. On success, timeout, SIGINT, or failure, stop owned collectors/apps and restore settings changed in the test scope. Never broad-kill Copythat or delete persistent user data. Validate repeated runs and parallel-run rejection. Preserve sanitized reports after cleanup.

### D7. Report and completion semantics

Each scenario has `passed`, `failed`, `blocked`, or `not-covered`, evidence level, expected/observed assertions, timing, and reason. Exit 0 only if all required cases in the selected profile pass; exit 1 for behavioral/evidence failures; exit 2 for incomplete prerequisites/coverage, with failures taking precedence. Missing, malformed, stale, cross-process, or out-of-order evidence cannot become passed.

Record source revision plus dirty-source snapshot digest, candidate binary digest, build configuration, OS/application versions, selected timing constants, and input mechanism. Do not store raw diffs or raw clipboard payloads as provenance. Provide a concise human report and schema-validated JSON.

Include a mapping to original 5.2/5.3/5.5, listing residual obligations; never edit original checkboxes automatically. Implementing a blocked reporting path is testable with fixtures, but does not count as successful live scenario delivery. This Change's handoff must state which unattended scenarios actually ran and which remain blocked.

## Risks / Trade-offs

- Desktop focus/lock interference → explicit preconditions, fixture-only session, bounded invalidation and reporting.
- Instrumentation changes timing → passive metadata observations, identical instrumentation for comparisons, no extra payload polling.
- Real writer updates invalidate reproduction → versioned recipe and provenance; preserve synthetic regression separately.
- Input qualification fails → deliver independent scenarios and report limitation; do not claim fully unattended physical acceptance or expand to hardware implicitly.
- Isolation and permission identity differ between test and release builds → record signatures/build identity and keep a separate real-permission environment check.
- Existing full gate has previously failed on missing Pillow → preflight/report dependency failure; do not suppress required gates or relabel them green.

## Migration Plan

Implement input qualification and report contracts first, then isolation/observability, then routine scenarios and original-writer replay. Add documentation for one-time desktop setup and unattended execution. Run final gates and a repeated unattended routine run before handoff. No persisted product schema migration is needed. Rollback removes the runner/test hooks; normal startup and saved history remain compatible.
