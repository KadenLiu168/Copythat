## Context

See `proposal.md` for motivation and scope. `ClipboardStore.startMonitoring()` currently schedules a 0.45-second repeating timer. `pollPasteboard()` records a new `changeCount` and `pendingFirstObservedSource` on one tick, then reads the payload only when the same count appears on the next tick. This preserves multi-step pasteboard-write safety but couples the stability requirement to the idle poll interval, produces roughly 0.45-0.9 seconds of capture latency, and can let a later copy replace an earlier value before the earlier value is observed.

`CopySourceTracker` already recognizes Cmd+C, Cmd+X, and clipboard screenshot shortcuts while retaining shortcut source evidence. `AppModel` owns both the tracker and the main-actor store. Source resolution is centralized in `CopySourceTracker` and `CopySourceResolution`, with priority `shortcut > firstObservedForeground > currentForeground > recentForeground > system > unknown`.

The archived `stabilize-pasteboard-capture-source` change requires Copythat not to commit transient content from multi-step writes. The archived `fix-source-attribution-timing` change requires the first-observed source to remain paired with the count that ultimately becomes stable. This design must preserve both guarantees.

## Goals / Non-Goals

**Goals:**

- Decouple the minimum stability interval from the idle polling cadence.
- Observe shortcut-driven pasteboard activity promptly while keeping idle monitoring near its current cost.
- Give non-keyboard writes faster stability confirmation and a short observation tail after idle polling discovers them.
- Keep scheduling and capture state serialized on `@MainActor ClipboardStore`.
- Make timing, replacement, and lifecycle behavior deterministically testable with narrow seams.

**Non-Goals:**

- Do not infer a pasteboard writer from a macOS event source that does not exist.
- Do not guarantee an earlier write that is overwritten before Copythat observes it or before it reaches the minimum stability interval.
- Do not change source resolution, duplicate handling, persistence, UI, permissions, or the asynchronous image-encoding cancellation policy.
- Do not introduce a general scheduler, event bus, protocol hierarchy, or user-configurable polling settings.

## Decisions

### D1: Retain the low-frequency idle timer

Keep the existing approximately 0.45-second timer as the always-on fallback. It remains necessary for context-menu Copy, web-page copy buttons, programmatic pasteboard writes, and other activity with no supported keyboard signal.

Alternative considered: reduce the permanent timer interval to 50-100 milliseconds. Rejected because it multiplies idle wake-ups while still leaving stability semantics coupled to polling frequency.

### D2: Send one narrow copy-intent wake signal from the tracker

Add a narrow internal callback on `CopySourceTracker` for recognized Cmd+C, Cmd+X, and clipboard screenshot shortcuts. Recognition sends the wake signal independently of whether a valid source snapshot is available. Existing shortcut-source queuing, diagnostics, freshness, and resolution behavior remain unchanged. Queue available shortcut evidence before invoking the wake callback so immediate polling cannot resolve ahead of its source evidence. A missing source still produces exactly one wake. If the existing event tap is unavailable (including denied permission), retain idle fallback without requesting a new permission.

`AppModel` wires the callback to the store with a weak store capture and a `MainActor` hop. The tracker reports only that clipboard activity is likely; it does not own polling, stability, or payload capture.

Alternative considered: move capture scheduling into `CopySourceTracker`. Rejected because source observation and pasteboard capture have separate ownership and lifecycle requirements.

### D3: Run at most one effective bounded burst loop

`ClipboardStore` owns a separate burst polling task, a monotonic deadline, an `isMonitoring` flag, and a small generation token. A wake signal starts or extends the deadline. If a current-generation loop already exists, the signal only extends its deadline. The loop polls immediately, then sleeps for the burst interval between later polls.

`isMonitoring` prevents a tracker callback from restarting burst polling before monitoring starts or after `stopMonitoring()`. Cancel/reset increments the generation; a canceled stale task may finish unwinding but cannot poll, clear, or replace state owned by a newer task. Only the current generation may clear the active task reference when it exits.

Alternative considered: cancel and replace the task for every signal. Rejected because rapid signals would create overlapping task cleanup and make an older canceled task capable of clobbering newer scheduling state.

### D4: Represent a pending observation as one value

Replace the parallel pending properties with one narrow value containing:

- `changeCount`
- `firstObservedSource`
- `firstObservedUptime`

When a new count appears, create a new value and replace the old value in one assignment. When the same count remains present, capture only after monotonic elapsed time reaches the minimum stability interval. Confirmation, an observed return to the processed count, self-write handling, and monitoring reset clear the whole value.

Alternative considered: keep three independent optionals. Rejected because the 2026-09-10 source-attribution guarantee depends on count, source, and timing belonging to the same observation on every branch.

### D5: Extend burst only for meaningful activity

Start or extend the burst deadline when:

1. a supported copy intent is observed;
2. a newly observed external change count replaces the pending observation; or
3. a stable count is processed, preserving a short tail for immediately following activity.

Do not extend the deadline merely because another burst tick sees the same still-pending count. This prevents the polling loop from sustaining itself indefinitely. Processing includes stable changes that are ignored, sensitive, empty, or unsupported so scheduler lifetime does not depend on whether payload insertion occurs.

The burst loop reads only `pasteboard.changeCount`. The existing payload-reading path runs once after stability is established.

### D6: Preserve source resolution and shortcut pairing exactly

The source snapshot stored in the pending observation is taken only when that count is first observed. A newer count replaces count, source, and uptime together. The stable observation passes its paired source into the unchanged resolution chain. Shortcut evidence remains higher priority than the first-observed source.

The existing change-count-aware shortcut queue is not replaced by the wake callback. The callback affects scheduling only.

### D7: Self-writes and stop invalidate burst state

`markPasteboardProcessed()` continues updating `lastChangeCount`, and additionally clears the complete pending observation and cancels/invalidates burst scheduling. `clearSystemPasteboardIfMatching()` inherits this behavior. `stopMonitoring()` stops the idle timer and idle poll task, cancels and invalidates burst polling, clears pending timing state, and preserves its existing image-task cancellation.

Stopping does not advance `lastChangeCount`; therefore a later explicit restart can still discover an external pasteboard change that occurred while monitoring was stopped. A wake received while stopped is ignored. Repeated start calls must not create another effective timer or burst loop. Preserve explicit one-shot `pollPasteboard()` calls, including `PanelWindowController.show()` and tests: they obey the same quiet-time check, but cannot start background scheduling while monitoring is stopped. Opening the panel must not bypass stability merely to populate it immediately.

### D8: Use narrow monotonic-time and timing seams

Use `ProcessInfo.processInfo.systemUptime` for production stability and deadline comparisons. Provide only the narrow internal injection needed for tests to control uptime and use shorter scheduler intervals; do not introduce a general Clock abstraction or public configuration.

Time-based state-machine tests advance uptime explicitly without real sleeps. Lifecycle tests exercise the real single-task start/extend/cancel behavior with bounded test timing. All mutating store tests inject no-op or in-memory `persistItems`. Migrate double-poll fixtures in `ClipboardStorePasteboardTests`, `ClipboardStoreSourceAttributionTests`, and `ClipboardStoreSelectionTests` to explicitly advance injected uptime before confirmation; preserve content, source, deletion, and persistence assertions. Rename the old second-poll timing test to reflect the new contract. Introduce minimal test seams before red assertions when necessary: a missing API/compiler error is not behavioral red evidence. Structural task 2.1 need not make elapsed-time tests green until task 2.2. For successive copies, explicitly run a confirmation tick for A before replacing it with B; elapsed time alone does not guarantee capture between ticks.

### D9: Tune private intervals from live evidence

The intended initial engineering ranges are approximately 50-75 milliseconds for burst polling, 150-200 milliseconds for minimum stability, and 500-800 milliseconds for the burst/tail window. These are not product requirements. For this Change, the user accepted automated real-desktop input and a 120 ms synthetic transient-to-final replay as the verification substitutes. The selected 0.06 s burst poll, 0.15 s stability interval, and 0.60 s window are accepted for the tested paths, while their behavior against the historical multi-step writer remains unverified.

Existing payload-free diagnostics provide `copy_shortcut_observed`, `pasteboard_observed`, and `source_resolved` monotonic events. Use them to validate source ordering without recording clipboard contents. Keep the burst window longer than the stability interval plus a burst tick so newly discovered content normally confirms within its burst. The historical report is in `openspec/changes/archive/2026-06-16-stabilize-pasteboard-capture-source/design.md` (ChatGPT intermediate old Doubao content); it has no measured writer gap or reproducible action sequence. The synthetic replay is regression coverage, not proof of that application's behavior. Record the available candidate timing and label the old baseline as estimated. If a future historical-writer replay exposes transient capture, lengthen the stability interval before claiming that writer is covered.

## Risks / Trade-offs

- [Two independent copies occur within the minimum stability interval] -> The earlier value remains intentionally indistinguishable from a multi-step intermediate write and may be omitted; document and test the narrower guarantee that the first copy must stabilize before the second replaces it.
- [The selected quiet interval is shorter than a real writer's multi-step gap] -> Replay the known writer with payload-safe timing evidence and lengthen the private interval until only final content is committed.
- [A copy intent is observed but its pasteboard write arrives after the burst deadline] -> Idle polling remains the fallback; keep the wake window long enough for verified normal and screenshot behavior without claiming an exact SLA.
- [Repeated signals create concurrent task cleanup] -> Use one current generation and allow only that generation to mutate active burst state.
- [A stop/self-write races with a wake signal] -> Serialize store transitions on the main actor, invalidate the old generation, and reject wake signals while stopped.
- [Fast polling accidentally reads payload repeatedly] -> Keep the fast loop limited to `changeCount`; cover payload capture count through focused tests and adversarial review.
- [Source attribution regresses while scheduling changes] -> Preserve the resolution API and priority, and retain all 2026-09-10 source pairing tests without weakened assertions.
- [Rapid image copies still lose the earlier encoding] -> Explicitly retain the existing `imageEncodingTask?.cancel()` behavior as an out-of-scope limitation and avoid claiming end-to-end rapid image preservation.

## Migration Plan

No persisted data, user setting, or permission changes. Ship the scheduler and stability-state changes in one app build after focused, full-gate, and live verification. Rollback is a code revert; existing history data remains compatible.

## Open Questions

- The historical multi-step-writer recipe and measured baseline remain unavailable. Revisit the private stability interval if that writer can be reproduced; the current accepted automated and synthetic tests do not establish its behavior.
