## Why

Text clipboard cards currently show too little useful content in the bottom panel. The body type size, generous line spacing, and early fade mask make short multi-line snippets feel truncated even when the card has room to identify more of the copied text.

## What Changes

- Increase the readable density of text clipboard cards so more copied text is visible at the existing card size.
- Remove or substantially reduce the body fade treatment that starts too early in the text preview.
- Keep the existing selected-card scale and raised hover-style treatment unchanged.
- Keep image, URL, and file card layouts unchanged.

## Non-goals

- Do not change clipboard capture, persistence, search, pinning, or paste behavior.
- Do not resize cards or restructure the horizontal timeline.
- Do not redesign source icons, header colors, or selected-card motion.
- Do not add user settings for preview density.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `panel-and-search`: Text history cards should display more readable preview content within the existing bottom panel card layout.

## Impact

- Affected code: `Sources/Copythat/Views/ClipboardCardView.swift`.
- Affected specs: `openspec/specs/panel-and-search/spec.md`.
- No API, dependency, storage, or permission changes.
