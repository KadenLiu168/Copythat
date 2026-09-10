# Design: fix-source-attribution-timing

## Context

Current capture pipeline in `ClipboardStore`:

- `startMonitoring()` polls `NSPasteboard.general.changeCount` every 0.45s on the main actor.
- `pollPasteboard()` implements a double-tick stability gate: the first poll observing a new change count only records `pendingChangeCount`; capture happens on the *next* poll that sees the same count. So a copy is captured 0.45–0.9s after it happens.
- At capture, `readCurrentPasteboard` asks `sourceTracker.resolveSource(...)` which resolves in priority order: pending keyboard-shortcut snapshot (event-tap Cmd+C/X, max age 3s) → capture-time frontmost app (max age 8s via `recentExternalSource`) → system → unknown.

Verified failure mode: copies that produce no keyDown event (context menu, web copy buttons, programmatic writes) fall through to the capture-time frontmost app. If the user switches apps inside the 0.45–0.9s window, attribution goes to the wrong app. Keyboard-shortcut attribution is verified correct (TAPCHECK test, 2026-09-09).

## Goals / Non-Goals

**Goals:**

- Bind fallback attribution to the app frontmost when the change count that ultimately stabilizes was *first observed* (one poll interval earlier than capture confirmation), narrowing the misattribution window by ~half and covering the web-copy-then-switch case where the source app remains frontmost through that first observation.
- Keep shortcut attribution exactly as-is (verified working).
- Keep all resolution logic centralized in `CopySourceTracker` / `CopySourceResolution` per project architecture constraints.
- Make the real first-observation, app-switch, confirmation, and shortcut-resolution ordering auditable without recording clipboard payloads.

**Non-Goals:**

- Zero-latency attribution (would require pasteboard change notifications instead of polling — a larger architectural change; not needed to fix the observed bug class).
- Detecting *which* app wrote the pasteboard when it wasn't frontmost at any observed moment (macOS provides no such API for the general pasteboard).
- Any change to the stability gate itself.

## Decisions

### D1: Snapshot at first observation, inside the existing gate

`pollPasteboard()`, whenever it observes a change count different from `pendingChangeCount`, asks the tracker for a frontmost-app snapshot and stores the count and snapshot as one pending observation. If another count arrives before confirmation, both pending values are replaced together. On the confirming poll, the stored snapshot paired with that stable count is passed into `readCurrentPasteboard` → `resolveSource`.

- Alternative considered: preserve the snapshot from the first count in an unstable multi-step sequence — rejected, because the gate captures the final stable content and cannot distinguish a multi-step write from two rapid independent copies; pairing the snapshot with the count prevents an earlier source from being attached to later content.
- Alternative considered: snapshot on *every* poll unconditionally — rejected, unnecessary work; the gate branch is the single choke point where a pending change count transitions from unseen to seen.
- The snapshot is a plain `ClipboardSource` value (struct) created on the main actor — no new thread-safety surface.

### D2: Priority slot between shortcut and capture-time frontmost

`CopySourceResolution.resolveSlot` gains a `firstObservedForeground` candidate. Resolution order becomes:

1. shortcut (unchanged, still verified path)
2. first-observed foreground (new)
3. capture-time foreground (unchanged)
4. recent foreground (unchanged)
5. system / unknown (unchanged)

- Rationale for ranking 2 above 3: the first-observed moment is strictly closer in time to the actual copy than the confirmation moment; both are heuristics for "app that wrote the pasteboard", and the earlier sample wins.
- Alternative considered: replace candidate 3 with the snapshot entirely — rejected; when no snapshot exists (gate skipped via `markPasteboardProcessed`, or first-observed app was not a source candidate) the capture-time frontmost remains the best available heuristic.

### D3: Snapshot may be nil; nil falls through to existing chain

If the frontmost app at first observation fails `isSourceCandidate` (Copythat itself, SystemUIServer, missing localizedName), the snapshot is nil and resolution proceeds exactly as today. No special-casing.

### D4: New tracker method, no state added to resolution inputs

`CopySourceTracker` exposes `frontmostSourceSnapshot() -> ClipboardSource?` (reuse of the existing private `currentFrontmostSource`/`source(for:)` path, minus the `recentExternalSource` side effect). The store owns the pending observation's lifetime and clears its count and optional snapshot atomically. Resolution stays pure over its inputs.

- Alternative considered: tracker buffers the snapshot internally keyed by change count — rejected, duplicates gate state that the store already owns and makes the tracker stateful across concerns.

### D5: Add a narrow source-provider seam for deterministic service/store tests

`CopySourceTracker` accepts an internal frontmost-source provider with a production default that uses the existing `NSWorkspace.shared.frontmostApplication` path. Tests can supply ordered `ClipboardSource?` values without activating real applications; production ownership and behavior remain in the tracker.

- Alternative considered: test against whichever application is frontmost during `swift test` — rejected, nondeterministic and unable to prove that first-observed source A beats confirmation-time source B.
- Alternative considered: introduce a general source-tracker protocol — rejected, broader abstraction than this single test boundary requires.

### D6: Emit default-off, payload-free source-timing events

Extend `ClipboardDiagnostics` with four metadata-only events while preserving the existing `clipboardDiagnosticsEnabled` gate:

1. `pasteboard_observed`: monotonic uptime, pending change count, first-observed source name or `none`.
2. `app_activated`: monotonic uptime, activated source name, current pasteboard change count.
3. `copy_shortcut_observed`: monotonic uptime, `copy` or `cut`, shortcut-time source name, baseline pasteboard change count.
4. `source_resolved`: monotonic uptime, captured change count, selected `CopySourceResolutionSlot`, resolved source name.

Use `ProcessInfo.processInfo.systemUptime` for ordering within one run; OSLog wall-clock timestamps remain supplemental. App names, change counts, resolution slots, and timing are permitted metadata. Clipboard text, URLs, file paths, image data, and other restorable payloads are never included.

`ClipboardStore` owns `pasteboard_observed`; `CopySourceTracker` owns activation, shortcut, and resolution events because those events originate at the centralized source-tracking boundary. A narrow injected event sink permits deterministic diagnostics tests while production continues to use `Logger`.

- Alternative considered: infer timing from the existing final `capture` message — rejected, because it contains neither first observation nor selected resolution slot.
- Alternative considered: enable diagnostics unconditionally — rejected, unnecessary runtime logging and inconsistent with the established default-off contract.

### D7: Verify live ordering and preserve evidence

Add `script/verify/source_attribution_timing.sh` with a non-keyboard mode and a physical-shortcut mode. The non-keyboard mode activates Chrome, writes a unique marker through background `pbcopy`, waits for the matching first-observation event, then activates Visual Studio Code before confirmation. The shortcut mode records a user-performed physical Cmd+C and subsequent app switch. Both modes analyze captured diagnostic events by change count and assert the required event order, selected slot, and final source without writing the marker or copied content to evidence.

Preserve the final full-gate output, sanitized timing events, toolchain/command results, and SHA-256 identities of every relevant implementation/test/script file under this Change's `evidence/` directory. Evidence files are verification artifacts, not runtime application state.

- Alternative considered: rely on screenshots and prose alone — rejected, they cannot establish event order or bind the result to the final diff.

## Risks / Trade-offs

- [Copy written by a *background* app (e.g. clipboard manager sync, ssh remote write) while user is in an unrelated app → first-observed snapshot now attributes to that unrelated app slightly more often than the capture-time fallback would] → Same heuristic class as today's behavior; the shortcut path already handles the dominant intentional-copy case; not a regression, just a different sample point.
- [Multi-step writes or rapid independent copies bump the change count several times before settling → an early source snapshot could be paired with later content] → Replace the pending count and snapshot together; only the snapshot taken when the final stable count was first observed is eligible for that capture.
- [The user switches apps before Copythat's first poll observes the new count → the real writer is no longer observable] → Explicitly outside the guarantee; the polling design narrows but cannot eliminate this attribution window without a different event source.
- [Snapshot taken while Copythat panel is frontmost (user copying via panel interaction) → nil snapshot, falls through] → Covered by D3; behavior identical to today.
- [Regression risk in resolution ordering] → Mitigated by TDD: red tests first for the new ordering (see tasks). There is no existing `CopySourceResolution` test file today; this change introduces one, including guard tests for the current behavior (shortcut wins, recent-foreground fallback, freshness windows) before any ordering change.
- [Diagnostics disclose clipboard data] → Emit only event type, monotonic timing, app name, change-count metadata, shortcut kind, and resolution slot; payload-safety tests reject copied text, URLs, file paths, and marker values.
- [OSLog delivery timing makes live automation flaky] → Correlate by pasteboard change count, use bounded waits, and keep a separate analyzer mode exercised against deterministic event fixtures.

## Migration Plan

Single app binary; no persistence or data migration. Rollback = revert commit.

## Open Questions

None — all decisions are settled by the verified reproduction evidence.
