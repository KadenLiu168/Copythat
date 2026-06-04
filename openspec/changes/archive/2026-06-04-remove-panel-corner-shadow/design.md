## Context

The bottom panel is an `NSPanel` hosting `BottomPanelView`. The panel window already disables the AppKit window shadow and uses a clear, non-opaque background. The remaining rectangular corner artifacts come from the SwiftUI outer shadows applied to the rounded panel container.

## Goals / Non-Goals

**Goals:**

- Remove the visible rectangular shadow artifacts at the four panel corners.
- Preserve the existing rounded panel clipping, material, tint, border, layout, and interactions.
- Keep the implementation local to the panel presentation layer.

**Non-Goals:**

- Introduce a replacement custom shadow system.
- Change panel sizing, positioning, cards, search, pinboard filtering, or paste behavior.
- Modify AppKit window setup beyond the existing clear, shadowless panel configuration.

## Decisions

- Remove the two outer `.shadow(...)` modifiers from `BottomPanelView.panelContainer`.
  - Rationale: these shadows are the source of the visible rectangular corner artifacts, while the window's own shadow is already disabled.
  - Alternative considered: attach a replacement shadow to the rounded shape. That would still need extra transparent window margin to avoid clipping at the rectangular `NSPanel` bounds, increasing scope for a visual-only fix.

## Risks / Trade-offs

- Removing the shadows reduces panel depth slightly -> keep the existing material, tint, and border treatments so the panel still reads as a distinct floating surface.
- Visual verification is partly manual -> run the automated build/test checks and inspect the panel after launch for the corner artifact.
