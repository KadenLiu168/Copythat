## Context

Copythat stores each clipboard item with source app metadata so cards can show where content came from after relaunch. Source icons are captured by `CopySourceTracker` at 160px, but `ClipboardItem.storageOptimized` currently treats them like storage media and rewrites them to 64px whenever an item is optimized, including when a URL item later receives link preview metadata.

## Goals / Non-Goals

**Goals:**

- Preserve captured source app icon bytes through storage optimization.
- Keep existing image and link preview image optimization limits.
- Avoid card UI changes; the existing fixed source icon frame should display the preserved icon.
- Add focused test coverage for the source icon persistence behavior.

**Non-Goals:**

- Do not increase source icon capture above 160px.
- Do not migrate older persisted source icons that were already stored at 64px.
- Do not change link preview image or clipboard image size policy.
- Do not introduce a separate source icon store or app-level deduplication.

## Decisions

- Preserve `sourceAppIconData` directly in `ClipboardItem.storageOptimized`.
  - This keeps the captured 160px icon available for display and avoids unrelated byte changes when link preview metadata is applied.
  - Re-encoding to 160px was rejected because capture already normalizes source icons and re-encoding unchanged data still adds work and can alter bytes.
- Keep `imageData` and `linkImageData` resizing in `storageOptimized`.
  - Clipboard images and web preview images can be much larger and less predictable than source icons, so they still need bounded storage sizes.
- Leave rendering unchanged.
  - Cards already display source icons inside a fixed header frame with proportional scaling, so preserving larger source icon data does not require layout changes.

## Risks / Trade-offs

- [History files may be slightly larger for new source icons] -> Source icons remain bounded by the existing 160px capture limit, and this avoids introducing a new deduplication model.
- [Older 64px source icons remain unchanged] -> Existing persisted data stays valid; users will see preserved 160px icons for newly captured or newly rewritten items.
- [Source icon bytes may vary by capture source] -> Existing per-item source icon behavior already treats captured icon data as item-specific metadata.
