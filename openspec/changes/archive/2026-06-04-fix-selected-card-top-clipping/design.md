## Context

Bottom-panel cards are fixed at `236 x 236` and the selected card intentionally scales up, moves upward, uses a thicker stroke, and casts a stronger shadow. The horizontal timeline currently gives cards only a small top inset inside a fixed-height scroll area, so the selected card's visual bounds can exceed the scroll area's clipped region.

The observed failure is intermittent because the layout is close to the clipping boundary. It is most visible on selected image or file cards, where a clipped header reveals bright preview content near the top edge.

## Goals / Non-Goals

**Goals:**

- Preserve the existing selected-card visual treatment while preventing top-edge clipping.
- Keep the fix local to the bottom-panel timeline layout.
- Maintain enough card breathing room for selected text, image, URL, and file cards.

**Non-Goals:**

- Do not change card dimensions, panel dimensions, card header structure, source icon layout, or selected-card animation values.
- Do not change pasteboard capture, paste execution, source attribution, search, pinboard filtering, or persistence.
- Do not add a new layout abstraction for the timeline.

## Decisions

1. Fix the timeline container rather than the card header.

   Rationale: the header layout is deterministic, while the failure appears when selected-card scale, upward offset, stroke, and scroll clipping leave insufficient visual space. Treating this as a container bounds issue keeps the change aligned with the cause.

   Alternative considered: reduce or remove selected-card scale and offset. That would avoid overflow but would change an existing interaction treatment that previous work explicitly preserved.

2. Add explicit selected-card safe space around the horizontal card row.

   Rationale: the selected card needs room for upward offset, scale expansion, and stroke width. Increasing the row's top inset is the smallest way to provide that room without changing card internals.

   Alternative considered: increase the whole panel height. That would solve the space shortage but would affect window sizing and screen fit more broadly than needed.

3. Disable scroll clipping for the card timeline if padding alone does not fully protect the selected visual bounds.

   Rationale: the selected card's shadow and stroke are presentation effects that can legitimately extend outside the scroll content's nominal bounds. The project already uses `scrollClipDisabled()` for a horizontal command-bar strip, so this stays within existing platform assumptions.

   Alternative considered: wrap each selected card in a larger invisible frame. That adds per-card layout complexity and risks affecting horizontal spacing or scroll centering.

## Risks / Trade-offs

- Extra top padding could make the timeline feel slightly lower or reduce bottom breathing room -> keep padding modest and adjust only the timeline row height if visual balance requires it.
- Disabling scroll clipping could allow card shadows to draw outside the timeline region -> verify the panel still looks contained within its rounded panel shape.
- Automated tests cannot fully catch this visual clipping bug -> pair `swift test` with a manual panel pass across selected text, image, URL, and file cards.
