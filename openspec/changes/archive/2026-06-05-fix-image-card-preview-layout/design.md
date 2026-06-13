## Context

`ClipboardCardView` fixes the whole card at `236 x 236` and fixes the header height at `52`, but the shared `contentSection` does not explicitly claim the remaining `184` points. Image previews also use fill scaling, which intentionally crops ultra-wide images. The attached analysis correctly identifies the missing content boundary as a layout risk, but incorrectly treats fill scaling, badge placement, and header text scaling as one root cause.

## Goals / Non-Goals

**Goals:**

- Make the content region's size explicit so previews cannot affect the header layout.
- Show the complete image preview proportionally inside the bounded content region.
- Keep the change local to the existing card view.

**Non-Goals:**

- Do not change the image-detail badge placement or styling.
- Do not duplicate the content-region frame inside `imagePreview`.
- Do not change header text, source icons, non-image preview implementations, card dimensions, or timeline behavior.

## Decisions

1. Constrain and clip the shared `contentSection`.

   Rationale: the shared content boundary is the single owner of the space below the fixed header. Applying the fixed width and remaining height there makes the layout contract explicit for every preview and avoids duplicate constraints inside `imagePreview`.

   Alternative considered: wrap only `imagePreview` in a fixed-size `Group`. That can contain the current image branch, but duplicates the shared content geometry and leaves the parent content boundary implicit.

2. Change the image content mode from fill to fit.

   Rationale: fill mode crops ultra-wide images by design. Fit mode preserves the full captured image while the shared content frame controls the available area.

   Alternative considered: keep fill mode and only add the shared boundary. That protects the header but retains the user-visible loss of image content.

3. Leave the image-detail badge and header unchanged.

   Rationale: moving or restyling the badge and scaling header text do not contribute to the layout boundary fix and would introduce unrelated visual changes.

## Risks / Trade-offs

- Ultra-wide images will have empty space above and below the fitted preview -> preserve the existing content background so the letterboxing remains visually contained.
- Automated tests do not directly inspect SwiftUI pixels -> verify the layout contract with build/test checks and a panel pass using an ultra-wide image.
