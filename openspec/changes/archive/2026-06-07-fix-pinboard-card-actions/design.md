## Context

The bottom panel renders cards from `ClipboardStore.filteredItems`. The store refreshes that list when search text or the selected pinboard changes, but card actions that mutate `isPinned` or `pinboardName` can leave the current filtered list stale until another filter change forces a refresh.

Custom pinboard assignment also currently sets `isPinned = true`. That couples two user concepts: keeping an item in Pinned and organizing an item into a named custom pinboard.

## Goals / Non-Goals

**Goals:**

- Recompute visible items immediately after pin and pinboard membership changes.
- Treat custom pinboard assignment independently from pinned state.
- Preserve selection behavior by using the existing filtered-list refresh path.
- Keep card menu presentation state-driven without redesigning it.

**Non-Goals:**

- No clipboard-history migration.
- No new stored fields or pinboard identifiers.
- No changes to pasteboard capture, paste behavior, source attribution, panel layout, or custom pinboard deletion.

## Decisions

1. Refresh inside `ClipboardStore` mutation methods.

   Rationale: `ClipboardStore` owns `items`, `filteredItems`, `searchText`, and `selectedBoardID`, so it is the narrowest place that can keep visible state correct after mutations. Updating `BottomPanelView` after each action would spread filtering policy into the view layer.

   Alternative considered: add view-level `.onChange` hooks for item mutations. Rejected because item mutations are already encapsulated in store APIs and this would duplicate refresh responsibility.

2. Do not pin items when assigning a custom pinboard.

   Rationale: Pinned and custom pinboards are separate filters in the command bar. Assigning to Work, Ideas, or another custom pinboard should not make the item appear in Pinned unless the user explicitly pins it.

   Alternative considered: keep custom pinboard assignment as implicit pinning and only hide Unpin in custom filters. Rejected because it preserves surprising state and would make the menu label inconsistent with the stored item state.

3. Preserve existing pinned data.

   Rationale: Existing history only stores a boolean `isPinned`; it does not distinguish manual pins from pins caused by prior pinboard assignment. Changing old records would risk unpinning items the user intentionally pinned.

## Risks / Trade-offs

- Existing custom-pinboard items may remain pinned if they were assigned before this change -> Leave stored data unchanged and make future actions independent.
- Refreshing after each pin or pinboard action may reset selection when the current item disappears -> Use the existing `refreshFilteredItems()` selection fallback so behavior stays consistent with search and filter changes.
- `add-pinboard-deletion` is active in the same workspace -> Keep this change scoped to card actions and avoid editing deletion flow artifacts.
