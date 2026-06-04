## Context

Text clipboard cards share a fixed `236 x 236` card with a header and a body preview. The current text body uses relatively large type, extra line spacing, and a fade mask that begins before the final third of the preview, which reduces how much copied text is readable in the panel.

## Goals / Non-Goals

**Goals:**

- Improve text card readability and density within the existing card size.
- Preserve the current card header, source icon treatment, and selected-card scale/offset behavior.
- Keep the change local to text card presentation.

**Non-Goals:**

- No changes to card sizing, timeline layout, or panel window behavior.
- No changes to image, URL, or file card previews.
- No new user preference for dense previews.

## Decisions

- Remove the text body fade mask instead of delaying it to 80% or 90%.
  - Rationale: the card already has a line limit, and copied text identification depends on fully legible lines. A late fade is less harmful than the current fade, but it still makes the last visible line less useful.
  - Alternative considered: move the fade start to 90%. This keeps the visual hint of overflow but preserves less readability than removing the mask.
- Reduce text body type size and line spacing modestly.
  - Rationale: the panel is a compact browsing surface, so text cards should prioritize scan density without making the body feel cramped.
  - Alternative considered: only raise the line limit. This would not help if the current type metrics still consume too much vertical space.
- Keep selected-card motion unchanged.
  - Rationale: the raised selected-card effect is accepted behavior and not the reported readability problem.

## Risks / Trade-offs

- Smaller body text may feel slightly less prominent -> use a modest reduction rather than a dense micro-text treatment.
- Removing the fade removes a visual overflow cue -> rely on the existing line limit and character count to communicate that longer content exists.
