## Context

Clipboard cards use a fixed `236 x 236` presentation with a colored header, content preview, and per-item source app icon. The current header uses a three-line-capable left stack: item kind, relative timestamp, and optional pinboard badge. The source icon is visually offset near the top-right corner, which can make the icon feel detached from the header and leave the left text competing with unused reserved space.

The requested direction is closer to a compact native card header: two lines of left text with modest top/left inset, and a right-side source icon that reaches the header edge and visually occupies the header height.

## Goals / Non-Goals

**Goals:**

- Make the header left text easier to scan by limiting it to item kind and relative timestamp.
- Preserve a small top and leading inset for the left text instead of placing it flush against the card edge.
- Treat the source app icon as a right-aligned header block that is sized from the header height and leaves no visible right gutter.
- Keep enough right-side reservation so left text does not overlap the icon.

**Non-Goals:**

- No changes to card size, timeline layout, selection animation, paste flow, or context menus.
- No changes to clipboard item data, source resolution, source icon ownership, pinning, or pinboard assignment.
- No new settings or alternate compact/dense header modes.

## Decisions

1. Keep the header as a presentation-only SwiftUI adjustment in `ClipboardCardView`.

   Rationale: the change affects only how existing card metadata is arranged. Moving logic into models or services would add unnecessary structure for a local visual refinement.

   Alternative considered: create a reusable card header component. This header is currently used only by `ClipboardCardView`, so extracting a component would add indirection without solving a real reuse problem.

2. Show only two text lines in the header: item kind and relative timestamp.

   Rationale: the user specifically wants the left side to contain only two lines. Removing the pinboard badge from the header prevents a third line from crowding the header and keeps the typography close to the provided reference.

   Alternative considered: keep the pinboard badge in a compressed third line. That preserves more metadata in the header but conflicts with the desired two-line layout and would force either a taller header or smaller text.

3. Size and align the source icon from the header height.

   Rationale: tying the icon frame to the header height makes it behave like an intentional right-side visual block. Removing the right gutter better matches the reference image and avoids the current floating-corner feel.

   Alternative considered: shrink the icon to reduce dominance. That would improve text hierarchy but does not match the requested reference, where the icon intentionally occupies the full header height.

## Risks / Trade-offs

- Pinboard assignment becomes less visible on the card face -> keep pinboard actions and filtering unchanged, and rely on the selected pinboard context or future body/metadata treatment if visible pinboard labels become important again.
- A header-height icon can crowd long localized kind labels -> reserve trailing space equal to the icon width plus a small gap, and keep the kind label single-line truncated.
- Increasing header height could reduce preview content area -> prefer the smallest header height that supports the desired icon treatment, and verify text cards still show readable previews.
