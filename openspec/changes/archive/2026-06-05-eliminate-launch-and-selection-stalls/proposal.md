## Why

Copythat currently takes several seconds to become usable with a large image-heavy history, and card selection can lag during mouse or repeated left/right input. Profiling shows the launch path needlessly re-encodes every persisted image on the main thread, while selection repeatedly decodes source icons, scans their pixels for theme colors, and overlaps scroll animations.

## What Changes

- Load already-persisted clipboard items without re-running storage optimization during every application launch.
- Reuse decoded clipboard images and derived source theme colors across repeated card renders.
- Make selection scrolling follow the selected card immediately and shorten the selected-card transition so repeated movement does not accumulate animation work.
- Add focused regression tests and repeat the launch and selection performance probes against the same history fixture.

## Capabilities

### New Capabilities

### Modified Capabilities
- `settings-and-launch`: application launch must remain responsive when persisted history contains image data.
- `panel-and-search`: mouse and keyboard card selection must avoid repeated image/theme derivation and overlapping scroll-animation stalls.

## Non-goals

- No changes to clipboard history limits, stored image dimensions, persistence format, paste behavior, or source attribution.
- No asynchronous history-loading state, new dependency, profiling framework, or broad SwiftUI architecture rewrite.
- No removal of selected-card styling, center scrolling, context menus, dragging, or double-click paste.

## Impact

- Affects `ClipboardStore`, `ClipboardItem`, `SourceThemeColor`, `BottomPanelView`, `ClipboardCardView`, and focused tests.
- Keeps the existing persisted history schema and public behavior unchanged.
