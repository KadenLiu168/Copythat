## Why

The current card header lets the source icon dominate the top-right corner while the left-side text can feel tight against the top edge. The header should read more like a compact macOS card label: two clear text lines with modest inset, paired with a source app icon that occupies the right edge intentionally.

## What Changes

- Refine clipboard card header layout so the left side shows only the item kind and relative timestamp.
- Give the left-side header text small top and leading inset so it does not feel pinned to the card edge.
- Align the source app icon to the right edge and size it relative to the header height so it visually fills the header area.
- Reserve only enough right-side text space to avoid overlap with the icon.
- Remove the pinboard badge from the header text stack; item organization actions and data remain unchanged.

## Non-goals

- Do not change card size, horizontal scrolling, selection motion, paste behavior, or context menu actions.
- Do not change clipboard capture, source attribution, pinboard data, or persistence.
- Do not redesign card body previews beyond any spacing needed to preserve the existing header/content split.
- Do not introduce a user setting for header density or icon size.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `panel-and-search`: Clarify how visible history card headers present item kind, timestamp, and source icon context.

## Impact

- Affected code is expected to be limited to `Sources/Copythat/Views/ClipboardCardView.swift`.
- Existing tests should continue to cover source icon ownership and card construction.
- Implementation verification should include `swift build`, `./script/verify_all.sh`, and a manual panel check for text, URL, image, file, pinned, and custom-pinboard items.
