## Context

Each `ClipboardItem` already stores its own `sourceApp` and `sourceAppIconData`, and persistence optimizes that icon data for later display. The panel currently also builds `sourceIconByApp`, a visible-item cache keyed only by `sourceApp`, and `BottomPanelView` passes that shared icon into each `ClipboardCardView`.

That shared cache can make multiple cards with the same resolved source name display the same logo, even when their captured `sourceAppIconData` differs. The observed failure is that copying text from app A, then text from app B, can make the earlier A card display B's logo.

## Goals / Non-Goals

**Goals:**

- Ensure each history card renders the source logo and derived accent from its own captured source icon.
- Keep source attribution resolution unchanged.
- Keep the change small and limited to the card display data path.
- Add regression coverage for distinct text items with distinct captured icons.

**Non-Goals:**

- Do not add new source metadata or alter the persisted `ClipboardItem` shape.
- Do not change pasteboard polling, source resolution, duplicate-content behavior, or ignored application handling.
- Do not redesign the card UI.

## Decisions

1. Use `ClipboardItem.sourceAppIcon` as the source of truth for card logo display.

   Rationale: source icon data is already captured per item and persisted with the item. Rendering from the item preserves historical context and avoids cross-card mutation caused by shared visible-state caches.

   Alternative considered: keep `sourceIconByApp`, but key it by item ID or source app plus icon digest. That recreates a second cache for data the item already owns, adding complexity without improving behavior.

2. Remove or bypass `sourceIconByApp` for card rendering.

   Rationale: a cache keyed by source application name cannot represent two visible items that share a source name but have different captured icons. The simplest fix is to stop feeding that cache into `ClipboardCardView`.

   Alternative considered: keep the cache for fallback when an item has no icon data. That risks preserving the same class of bug for unknown or missing metadata, and the existing fallback symbol already handles missing icon data.

3. Keep source resolution untouched.

   Rationale: the bug is in display ownership, not in deciding which app produced a pasteboard change. Changing `CopySourceTracker` or `CopySourceResolution` would widen the fix and make regression verification harder.

## Risks / Trade-offs

- Cached icon removal could reveal items with missing `sourceAppIconData` as fallback symbols instead of borrowing a logo from another visible item -> This is preferable because it avoids showing a misleading source logo.
- If a previously saved item lacks icon data, it will continue to use the existing symbolic fallback -> No migration is needed because old data already decodes with optional icon data.
- SwiftUI snapshot-style testing is limited in this package -> Prefer a small view/data-contract test if practical, and verify with `swift build`, `./script/verify_all.sh`, plus a manual panel check.
