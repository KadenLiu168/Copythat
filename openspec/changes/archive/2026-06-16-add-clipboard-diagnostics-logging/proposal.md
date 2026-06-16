## Why

Users can observe a clipboard card's source appearing to change after copying from another app, but the current app has no focused runtime trace to distinguish a real source mutation from expected same-content deduplication or an old build.

## What Changes

- Add a hidden, default-off clipboard diagnostics mode for pasteboard capture and history insertion.
- Emit concise unified logging events for source resolution, content identity, duplicate detection, and item counts around clipboard item insertion.
- Keep diagnostics out of the Settings UI and avoid logging raw clipboard payloads.
- Do not change clipboard capture, source attribution, deduplication, persistence, or panel rendering behavior.

## Non-goals

- Do not redesign source tracking or change `CopySourceTracker` resolution rules.
- Do not change the duplicate-content policy or preserve same-content entries from different apps.
- Do not add a visible user-facing debug settings surface.
- Do not log full copied text, URLs, file paths, image contents, or other clipboard payloads.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `clipboard-history`: Add a diagnostic mode requirement for safely tracing clipboard capture/source/deduplication decisions without changing history behavior.

## Impact

- Affects clipboard monitoring and history insertion code around `ClipboardStore`.
- Adds lightweight `OSLog.Logger` usage behind a `UserDefaults` diagnostic flag.
- Adds focused tests for diagnostic metadata and duplicate-detection behavior.
