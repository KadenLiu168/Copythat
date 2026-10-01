## Why

Consecutive observed image copies currently cancel the earlier capture's completion, so an image can disappear from history even though its detached PNG encoding still consumes CPU. A bounded encoding pipeline should preserve ordinary screenshot bursts while correcting overly broad deletion cancellation and the image path's bypass of ignored-source filtering.

## What Changes

- Replace latest-image-wins cancellation with a Store-owned bounded FIFO image pipeline: production capacity four captures including the active capture, with one background encoder.
- On overflow, retain active work, discard the oldest waiting capture, and admit the newest image; emit default-off, payload-free overflow diagnostics.
- Snapshot image capture time, display size, source name, icon bytes and prepared icon identity at admission. Preserve background bounded PNG finalization and one identity hash per finalized image.
- Limit single-card deletion suppression to matching stale content using an admission-sequence cutoff; permit an intentional new copy of that content after deletion.
- Invalidate all previously admitted image results on Clear History, even when no existing card is removable, and on monitoring stop. An invalidated encoder retains its physical slot until it actually finishes; new-generation images wait without parallel encoding.
- Filter ignored image sources before admission without changing source-resolution precedence or ignored-app configuration.
- Keep successful results on the standard `add()` path, preserving duplicate handling, retention, selection, persistence and durable-media behavior.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `clipboard-history`: Specify bounded preservation of consecutive observed images, deterministic overflow, safe lifecycle invalidation, matching-only stale deletion suppression, ignored-image admission and capture-time context.

## Non-goals

- Change polling, stability intervals, burst scheduling, or promise capture of values overwritten before the existing observation mechanism reads them.
- Provide unlimited burst buffering, a byte-based raw-image memory budget, multiple encoders, a generic scheduler, an event bus, or new dependencies.
- Change duplicate semantics, history limits, the 100-unpinned-image bound, persistence schema V2, blob layout, lazy media loading or durable-media release.
- Change link previews, paste flow, source-attribution priority, ignored-app UI or parsing, or introduce permissions.
- Add global mixed-content ordering: FIFO applies to image finalization, not ordering delayed images relative to synchronous text, URL or file insertions.
- Refactor deletion-time pasteboard image matching; background PNG/hash guarantees here apply to capture finalization, not every image operation in the application.

## Impact

- Primary implementation: `Sources/Copythat/Stores/ClipboardStore.swift` and its focused `Sources/Copythat/Stores/ClipboardStore+ImageCapture.swift` extension; safe pipeline diagnostics in `Sources/Copythat/Support/ClipboardDiagnostics.swift`.
- Focused coverage: `Tests/CopythatTests/ClipboardImageEncodingPipelineTests.swift` (new), existing image-deletion and media-hash suites, and related pasteboard, source-attribution, burst-lifecycle and history-performance tests.
- Existing `clipboard-history` requirements already promise ignored-source exclusion and intentional recopy after deletion; current image paths do not fully implement those promises. The change repairs those gaps and explicitly strengthens Clear History to invalidate pending images even when no stored card changes.
- No public API, persisted format, dependency or permission changes. Test-only/internal capacity and encoder controls remain narrow.
