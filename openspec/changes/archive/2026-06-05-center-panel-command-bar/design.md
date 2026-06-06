## Context

The bottom-panel header currently uses a full-width layered layout: search and Clipboard are anchored to the leading side, the add-pinboard control is anchored to the trailing side, and only Pinned plus custom pinboards are centered. This keeps controls visible but prevents them from reading as one compact command group and gives the groups no explicit spacing hierarchy.

The header presentation is contained in `BottomPanelView.swift`. Search expansion, pinboard filtering, horizontal overflow, and pinboard creation already work and must remain unchanged.

## Goals / Non-Goals

**Goals:**

- Center the complete top command group within the panel.
- Make search, the pinboard group, and add-pinboard read as three related groups with clear separation.
- Keep individual pinboard filters visually tighter than the surrounding group gaps.
- Slightly increase category marker size without changing configured colors.
- Preserve usable overflow and search-expanded states.

**Non-Goals:**

- Change search, filtering, selection, or pinboard creation behavior.
- Redesign the controls, panel surfaces, cards, or popover.
- Change pinboard color persistence or ordering.

## Decisions

### Compose one centered command group

The header uses one horizontally centered command group in this order:

`search | Clipboard and pinboard filters | add pinboard`

Clipboard moves into the same filter strip as Pinned and custom pinboards. This creates the requested continuous command bar and removes the current split between the leading Clipboard filter and centered secondary filters.

A full-width leading/center/trailing layout was considered, but it directly causes the current detached appearance.

### Use two spacing levels

The gap between search, the pinboard strip, and add-pinboard is larger than the gap between individual pinboard filters. The target visual rhythm is approximately 16 points between groups and 8 points between filters.

This spacing communicates structure without adding borders or container chrome. A uniform gap was considered, but it would make all controls read as peers and weaken the requested grouping.

### Keep only the pinboard strip flexible

Search and add-pinboard remain visible at fixed control widths. The pinboard strip receives the remaining available width and stays horizontally scrollable when its content exceeds that width.

When the search field expands, the complete command group remains centered within the panel while the pinboard strip yields width first. This avoids moving the add-pinboard action off-screen or returning to edge-anchored controls.

### Increase category markers to 10 points

Non-Clipboard marker circles increase from 8 by 8 points to 10 by 10 points. Their configured colors, opacity, and selected/unselected treatment remain unchanged. The increase is intentionally small so markers gain presence without competing with filter labels.

## Risks / Trade-offs

- [A long expanded search field leaves little room for filters] -> Keep the filter strip horizontally scrollable and give it the flexible width.
- [Many pinboards can make the centered group approach the panel edges] -> Constrain the complete group to the available header width while keeping search and add-pinboard visible.
- [Larger dots can make filters feel crowded] -> Reduce dot-to-label spacing slightly while keeping filter height unchanged.
