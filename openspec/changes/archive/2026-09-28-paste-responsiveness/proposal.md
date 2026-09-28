## Why

Automatic paste currently waits a fixed 350 ms after requesting target-app activation, even when the target is ready sooner. This makes returning from the Copythat panel feel unnecessarily slow; we can remove the normal-path wait without changing the existing 350 ms compatibility fallback.

## What Changes

- Paste after the intended target app is confirmed active, on the next asynchronous main-queue delivery, instead of always waiting 350 ms.
- Preserve the existing 350 ms unconditional-paste fallback when activation confirmation is absent, including its current success/failure semantics.
- Ensure each paste attempt sends Command-V at most once, ignores unrelated activations, and invalidates a superseded attempt.
- Keep pasteboard restore, target selection, Accessibility checks, and immediate panel dismissal unchanged; add deterministic coordination tests.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `paste-and-permissions`: Specify activation-responsive automatic paste, the bounded compatibility fallback, and at-most-once behavior while retaining existing paste safety requirements.

## Impact

Primarily `Sources/Copythat/Services/ClipboardPastePerformer.swift` and new `Tests/CopythatTests/ClipboardPastePerformerTests.swift`; existing `PasteDecisionTests.swift` remain in place. No new dependency, public API, source attribution, or UI workflow is planned. The existing clipboard-live driver currently restores through the store and sends its own Command-V, bypassing `ClipboardPastePerformer`; its unchanged paste scenario is not acceptance evidence for this change. Extend it only if it can invoke the real performer without expanding scope; otherwise verify the actual panel paste flow against a controlled real target app manually.

## Non-goals

Clipboard capture responsiveness, persistence, Link Preview, source attribution, target selection, Accessibility redesign, panel/UI refactoring, global keyboard handling, or changing the 350 ms fallback duration or failure semantics.
