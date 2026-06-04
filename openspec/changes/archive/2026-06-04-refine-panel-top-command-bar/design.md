## Context

The bottom panel header currently combines three actions in one row: search, pinboard filtering, and settings access. The controls work, but the visual grouping is weak: the selected `Clipboard` pill is heavier than the surrounding controls, the pinboard labels read like loose status tags, and the trailing plus button appears detached from the command bar.

The implementation can stay in `BottomPanelView` because the change is presentational and does not require store, model, pasteboard, shortcut, or window-management changes.

## Goals / Non-Goals

**Goals:**

- Make the header read as a compact macOS command bar with search on the left, pinboard filters in the center, and settings/add on the right.
- Reduce visual noise in the selected pinboard state while keeping the active filter clear.
- Add consistent hover, pressed, and focus feedback for top controls.
- Preserve current search expansion, filtering, settings opening, keyboard, and timeline behavior.

**Non-Goals:**

- Do not change search matching, pinboard filtering, clipboard item data, paste behavior, or card layout.
- Do not add a new pinboard creation flow.
- Do not introduce new dependencies or move presentation logic out of `BottomPanelView`.

## Decisions

- Keep a single header row and refine grouping in place.
  - Rationale: the panel height is fixed and the current one-row command model is efficient for a bottom floating utility panel.
  - Alternative considered: split search and pinboards into two rows. Rejected because it would reduce timeline space and make the panel feel heavier.

- Add a light rounded container around the pinboard strip.
  - Rationale: a shared container makes the filters read as one control group without changing filtering behavior.
  - Alternative considered: keep standalone pills. Rejected because it leaves the same loose-label problem.

- Use reusable local button styling inside `BottomPanelView`.
  - Rationale: the search and add controls need matching hover/pressed/focus feedback, but this style is only used in this header.
  - Alternative considered: introduce a shared component or theme. Rejected as unnecessary for one scoped UI refinement.

## Risks / Trade-offs

- Header controls may crowd on narrow screens or with many custom pinboards -> keep the center strip horizontally scrollable and give search/add fixed widths.
- Search expansion may compete with the pinboard strip -> cap the expanded search width and preserve the trailing action width.
- More hover state code adds local complexity -> keep it as small private helpers scoped to `BottomPanelView`.
