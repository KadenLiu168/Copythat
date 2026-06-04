## Why

Selected clipboard cards can occasionally render with their top edge clipped in the bottom panel, making the header, rounded corner, and source icon look broken. This happens around the existing selected-card scale and upward offset, where the horizontal timeline leaves too little safe space for the selected card's expanded visual bounds.

## What Changes

- Allow selected cards in the horizontal timeline to render their raised, scaled, and stroked visual state without top-edge clipping.
- Add enough timeline safe space around visible cards so selected card headers remain intact across text, image, URL, and file cards.
- Preserve the existing selected-card animation, card dimensions, header layout, scrolling behavior, search behavior, and pinboard behavior.

## Non-goals

- Do not redesign card headers or move source icons.
- Do not change card size, panel size, selected-card scale, selected-card offset, paste behavior, or context menus.
- Do not change clipboard history storage, source attribution, pinning, or pinboard filtering.

## Capabilities

### New Capabilities

### Modified Capabilities
- `panel-and-search`: Ensure selected bottom-panel cards remain visually unclipped while browsing horizontally.

## Impact

- Affected code is expected to be limited to the bottom-panel timeline layout in `Sources/Copythat/Views/BottomPanelView.swift`.
- Automated verification should include `swift test`; implementation verification should also include a manual panel UI pass for selected text, image, URL, and file cards.
