## 1. Lock Regression Behavior First

Introduce only the minimal compiling test seams needed for behavioral red tests; missing symbols are not red evidence. Migrate existing double-poll fixtures to explicit virtual-time advancement without weakening their content/source assertions. All store mutation tests use isolated pasteboards and no-op or in-memory persistence.

- [x] 1.1 Add deterministic failing pasteboard-store tests for a pending count below the minimum quiet duration, the same count at or beyond the duration, a newer count restarting the duration, and a transient count being excluded; verify the new assertions fail against the old double-poll behavior for the expected reason without using real sleeps.
- [x] 1.2 Add a failing successive-text-copy regression in which copy A reaches the minimum stability duration, is confirmed by a burst tick, and copy B replaces it before the old 0.45-second double-tick path could preserve both; verify the expected newest-first result `[B, A]` fails against the old scheduler behavior.
- [x] 1.3 Add failing source-pairing tests proving that count, first-observed source, and stability uptime are replaced together and that the source paired with the final stable count wins; verify existing source-attribution assertions remain unchanged and the new timing assertion fails before implementation.
- [x] 1.4 Add failing lifecycle tests for copy-intent start/extension, inactivity expiry, single effective burst generation, repeated start, stop/restart with an external write while stopped, explicit panel-style polling below threshold, wake rejection while stopped, `stopMonitoring()` cancellation, and self-write cancellation; verify each failure identifies missing burst lifecycle behavior rather than unrelated persistence or timing flakiness.

## 2. Introduce Time-Based Stability State

- [x] 2.1 Replace the parallel pending count/source properties with one narrow pending observation containing change count, first-observed source, and monotonic first-observed uptime; verify the observation representation compiles and preserves count/source pairing; elapsed-time assertions become green in 2.2.
- [x] 2.2 Change stable confirmation from repeated-poll count equality to elapsed monotonic quiet time, resetting the whole observation on every newer count and reading payload only after the minimum duration; verify the below-threshold, threshold, reset, and historical transient-state regressions pass.
- [x] 2.3 Update processed-count, self-write, clear, and reset branches to clear the complete pending observation without changing duplicate or source-resolution behavior; verify `writingToPasteboardClearsPendingExternalCapture`, `processedPasteboardClearsPendingSourceBeforeLaterCapture`, and focused pasteboard tests pass. Adapt double-poll fixtures in `ClipboardStorePasteboardTests`, `ClipboardStoreSourceAttributionTests`, and `ClipboardStoreSelectionTests` to injected uptime while retaining all non-timing assertions.

## 3. Add Bounded Burst Polling

- [x] 3.1 Add main-actor monitoring state, a monotonic burst deadline, one burst task, and generation-safe start/extend/cancel behavior while retaining the approximately 0.45-second idle timer; verify copy intent creates one effective loop and repeated signals extend it without creating another current generation.
- [x] 3.2 Poll immediately and then at the private burst interval while the current deadline remains active, reading only `pasteboard.changeCount` on unstable ticks; verify focused tests show payload capture occurs once only after stability.
- [x] 3.3 Enter or extend burst polling when a newly observed external count replaces the pending observation and after a stable count is processed, but not for every unchanged pending tick; verify non-keyboard discovery receives fast confirmation/tail coverage and inactivity still ends the loop.
- [x] 3.4 Make `stopMonitoring()` and `markPasteboardProcessed()` cancel and invalidate burst scheduling, clear pending timing state, and prevent a later stale task from clearing newer state; verify stopped/self-write lifecycle tests pass and existing image-task cancellation remains intact.

## 4. Wake Burst Polling from Copy Intent

- [x] 4.1 Add a narrow `CopySourceTracker` wake callback for recognized Cmd+C, Cmd+X, and clipboard screenshot shortcuts, independent of whether a foreground source snapshot is available; verify focused tracker tests receive exactly one wake for each supported intent and none for unrelated key events, including a nil source provider. Verify available source evidence is queued before wake delivery and no event-tap availability is required for idle fallback.
- [x] 4.2 Wire the tracker callback to the store in `AppModel` using a weak store capture and a main-actor hop, without moving polling into the tracker; verify focused wiring/lifecycle tests show wake starts or extends the single store-owned burst and does not form a retain cycle.
- [x] 4.3 Run all `CopySourceTracker`, `CopySourceResolution`, and `ClipboardStoreSourceAttributionTests` focused tests; verify the priority `shortcut > firstObservedForeground > currentForeground > recentForeground > system > unknown` and all existing count/source replacement assertions remain unchanged.

## 5. Tune with Payload-Safe Live Evidence

- [x] 5.1 Build and run a diagnostics-enabled candidate, capture sanitized `copy_shortcut_observed -> pasteboard_observed -> source_resolved` timing for ordinary physical Cmd+C, and select provisional private burst/stability/tail values only from observed behavior; verify no raw clipboard text, URL, file path, image data, or unique marker is preserved.
- [x] 5.2 Attempt the original-writer profile and record installed ChatGPT/Doubao versions plus missing historical recipe/baseline evidence; run a payload-safe 120 ms transient-to-final synthetic replay and verify only the final value is committed. Per the user's 2026-09-23 direction, accept this replay as the Apply test substitute while explicitly keeping historical ChatGPT behavior and baseline latency unverified. Record the available candidate latency and keep timing constants provisional.
- [x] 5.3 Use the qualified automated OS-input routine to perform successive Cmd+C copies after A reaches stability; verify newest-first `[B, A]` history order and Chrome source attribution. Per the user's 2026-09-23 direction, automated-real-desktop evidence substitutes for physical HID evidence.
- [x] 5.4 Verify context-menu Copy and a web Copy button without shortcut evidence are discovered by idle polling, enter burst confirmation, and capture normally; verify the sanitized trace contains no fabricated shortcut event.
- [x] 5.5 Use the automated routine profile to verify Cmd+X, region screenshot capture, keyboard and non-keyboard app switching, restore/paste, and injected event-tap-failure idle fallback; confirm capture/source behavior and no recapture. Per the user's 2026-09-23 direction, accept this automated coverage in place of physical actions, recording that region capture does not prove the physical screenshot shortcut/System-source path or OS permission denial.

## 6. Full Verification and Adversarial Review

- [x] 6.1 Perform a correctness adversarial review of transient writes, rapid-copy boundaries, stable payload read count, unsupported/sensitive content, and self-write suppression; fix any defect found and rerun the affected focused tests.
- [x] 6.2 Perform a source-attribution adversarial review of every resolution slot and every pending-observation establish/replace/clear path; fix any count/source/time mismatch and rerun all source-attribution tests.
- [x] 6.3 Perform a lifecycle/performance adversarial review for overlapping task generations, unbounded deadlines, wake-after-stop, permanent fast polling, and payload reads inside the fast loop; fix any defect found and rerun lifecycle plus full verification.
- [x] 6.4 Run `swift build`, `swift test`, `./script/verify_all.sh`, target strict OpenSpec validation, and `git diff --check` after all review repairs; verify every command exits successfully against the final implementation and artifacts. Any later code/test/dependency/tooling change invalidates this complete-gate evidence and requires another complete run.
- [x] 6.5 Record final results, live-evidence limitations, and the still-existing rapid-image encoding cancellation limitation in the Change verification handoff; verify the handoff makes no claim that unobservable pre-idle writes or consecutive image encodings are guaranteed.
