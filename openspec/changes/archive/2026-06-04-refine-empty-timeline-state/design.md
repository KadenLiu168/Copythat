## Context

The bottom panel timeline is a horizontal card list. When `filteredItems` is empty, `BottomPanelView` currently inserts `EmptyTimelineView` into the same `LazyHStack` where cards normally appear. That makes the empty state behave like the first card in the row: it sits near the leading edge instead of representing the whole timeline area.

`EmptyTimelineView` also shows the app's transparent mark at a prominent size above the text. In an empty pinboard or search result, that mark is not task-relevant and draws more attention than the message.

## Goals / Non-Goals

**Goals:**

- Present no-visible-items states as panel-level timeline content, not as a leading card placeholder.
- Keep the empty state visually quiet by removing the prominent app mark or replacing it with a small contextual symbol.
- Use concise copy that distinguishes an empty clipboard, an empty selected pinboard, and search results with no matches.
- Preserve native macOS styling, compact typography, footer status, horizontal card browsing, and existing filtering behavior.

**Non-Goals:**

- Redesign the panel header, pinboard controls, footer, or card presentation.
- Change `ClipboardStore` filtering semantics, pinboard assignment, persistence, pasteboard capture, or paste behavior.
- Add new image assets, onboarding steps, or external UI dependencies.

## Decisions

1. Treat the empty timeline as a full-width timeline state.

   The timeline should branch before constructing the horizontal card stack: when no items are visible, show an empty-state view in the timeline's available area with centered alignment. This avoids making the empty state inherit card-list leading padding and spacing.

   Alternative considered: keep `EmptyTimelineView` inside `LazyHStack` and add a large leading spacer. That would be more fragile because spacing would depend on panel width and scrolling behavior.

2. Keep the empty-state graphic secondary to text.

   The empty state should not use the large pink app mark as its main visual. The simplest implementation is text-only. If an icon remains, it should be small, monochrome or semantic, and lower contrast than the title.

   Alternative considered: keep the app mark but reduce opacity. This is still less direct because the brand mark does not explain why the current filter is empty.

3. Derive empty copy from existing visible UI state.

   The text can be selected from `store.searchText`, `store.selectedBoardID`, and the selected `Pinboard` title already available in `BottomPanelView`. No new persistence or model state is required.

   Alternative considered: add empty-state text to `ClipboardStore`. That would mix presentation copy into filtering state and widen the change unnecessarily.

## Risks / Trade-offs

- Centering in the full timeline area could look slightly high or low across display sizes -> Verify the panel manually with the default panel size and ensure footer spacing remains balanced.
- Context-aware copy could become too wordy for the compact panel -> Keep titles and descriptions short, with single-line-friendly text.
- Text-only empty state could feel too sparse -> Allow a small, low-contrast contextual symbol if visual balance needs it after inspection.
