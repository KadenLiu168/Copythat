## Context

The bottom panel renders clipboard items as a horizontal SwiftUI card list. A selection change currently publishes even when the selected ID does not change, the timeline repeatedly resolves `selectedItem` while rendering, and every card can rebuild work tied to source icons, colors, shadows, and layout. The selected card's scale, border, shadow, raised position, and scroll-to-center behavior are part of the current interaction design and should remain unchanged.

## Goals / Non-Goals

**Goals:**

- Make left/right keyboard selection and single-click card selection feel immediate.
- Preserve the current selected-card appearance and center-scrolling behavior.
- Reduce unnecessary SwiftUI redraw and AppKit image update work during selection changes.
- Keep source icons scoped per card so existing icon correctness is preserved.

**Non-Goals:**

- No visual redesign or removal of the selected-card effects.
- No changes to search matching, pinboard filtering, pasteboard parsing, persistence, or settings.
- No new profiling framework or dependency.

## Decisions

- Use `selectedID` directly in the timeline instead of repeatedly resolving `selectedItem`.
  - Rationale: `selectedItem` scans filtered items; selection rendering only needs the stable ID.
  - Alternative considered: cache `selectedItem` in the store. That is broader than needed and can introduce more state to keep synchronized.
- Make store selection mutations no-op when the target selection is unchanged.
  - Rationale: repeated boundary key presses and clicking the selected card should not publish and trigger panel updates.
  - Alternative considered: suppress key events in the view. Store-level no-op behavior protects all callers, including panel key handling.
- Use SwiftUI equatable card rendering for unchanged cards.
  - Rationale: the card's visible output is determined by `item`, `pinboards`, and `isSelected`; closures do not affect rendering.
  - Alternative considered: split the selected overlay into a separate view. That is more invasive and risks drifting from current styling.
- Track AppKit image identity in `SourceLogoImageView`.
  - Rationale: repeatedly copying the same `NSImage` during unchanged updates adds unnecessary work.
  - Alternative considered: shared image caching. That risks cross-card source icon mistakes and is unnecessary for this narrow path.

## Risks / Trade-offs

- Equatable rendering could skip a render-affecting value if equality is incomplete -> include `item`, `pinboards`, and `isSelected`, which cover the card's visual state.
- Double-click selection may first run the single-click selection path -> acceptable because double-click still pastes and the first click makes the target item selected.
- Manual smoothness is still subjective -> verify with key repeat and mouse selection in the panel after automated checks.
