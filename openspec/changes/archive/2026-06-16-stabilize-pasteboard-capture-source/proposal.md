## Why

Some apps can update the general pasteboard in multiple observable steps for a single copy action. Copythat currently reads immediately after the first pasteboard change, which can pair stale clipboard content with the newly resolved source app and make an existing card appear to change from its original source to the later app.

## What Changes

- Wait for a pasteboard change count to remain stable before reading and inserting clipboard content.
- Preserve an existing unpinned card's captured source app, source icon, ID, and creation time when duplicate content is seen again.
- Keep pinned duplicate behavior intact so intentionally saved cards remain protected.
- Keep clipboard diagnostics safe: continue logging metadata only, without raw copied text, URLs, file paths, or image data.

## Non-goals

- Do not redesign the bottom panel or clipboard cards.
- Do not change source resolution rules in `CopySourceTracker` or `CopySourceResolution`.
- Do not make same-content copies from different apps create multiple ordinary cards.
- Do not log raw clipboard payloads for diagnosis.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `clipboard-history`: Clipboard capture must ignore transient pasteboard write states and duplicate-content handling must not replace a card's captured source metadata.

## Impact

- Affects pasteboard monitoring in `ClipboardStore`.
- Affects duplicate insertion policy in `ClipboardHistoryPolicy` and the store selection/link-preview call path that consumes that policy.
- Adds focused tests for stable pasteboard capture and duplicate-source preservation.
- No new dependencies, persistence fields, UI controls, or public app settings.
