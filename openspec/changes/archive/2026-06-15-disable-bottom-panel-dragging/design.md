## Context

The bottom panel is created by `PanelWindowController` as a borderless `NSPanel` and positioned through `PanelFrameCalculator` each time it is shown. The current panel setup enables background window movement, which lets users drag the transient bottom panel away from the bottom anchor even though the product model and existing frame calculation treat the panel as a fixed bottom surface.

This change affects AppKit window behavior only. SwiftUI panel content should continue to own presentation and user actions, while the AppKit service keeps ownership of panel movement and placement configuration.

## Goals / Non-Goals

**Goals:**

- Keep the bottom panel fixed near the bottom of the active visible screen while it is visible.
- Prevent mouse dragging from repositioning the panel through the panel background or non-control regions.
- Preserve current panel sizing, screen selection, visual treatment, keyboard handling, search, paste, card selection, horizontal scrolling, and pinboard behavior.

**Non-Goals:**

- Redesigning the bottom panel UI.
- Changing the `PanelFrameCalculator` placement policy.
- Adding user-configurable panel positioning.
- Changing card-level drag behavior or pasteboard data handling.

## Decisions

### Disable AppKit panel movement at the window boundary

Set the panel's movement configuration in `PanelWindowController` so the `NSPanel` cannot be repositioned by background dragging. The narrowest implementation is to stop enabling background movement and explicitly mark the panel itself as not movable.

Rationale: panel movement is an AppKit window concern, and `PanelWindowController` already owns panel creation, activation, positioning, and close/paste keyboard routing. Keeping the change there avoids spreading window behavior into `BottomPanelView`.

Alternative considered: add SwiftUI gestures that consume drag events in the panel content. Rejected because it would be broader, more fragile around controls and scroll views, and would treat a window-level behavior as view-level presentation logic.

### Preserve show-time positioning

Continue to call the existing `position(_:)` flow when showing the panel. This keeps the panel anchored on the screen containing the mouse and preserves the existing adjustment for full-height target apps.

Rationale: the issue is user-initiated repositioning after the panel appears, not the frame calculation itself.

Alternative considered: repeatedly re-anchor the panel during mouse movement or while visible. Rejected because disabling movement at the source is simpler and avoids unnecessary window frame churn.

## Risks / Trade-offs

- Panel movement could still be possible through another AppKit default path -> Verify by dragging or synthetic-dragging the visible panel and comparing window bounds.
- Disabling movement might interfere with legitimate SwiftUI interactions if applied too broadly -> Keep the implementation in panel window configuration and verify search, card clicks, horizontal scrolling, context menus, and Escape-to-close behavior.
- Automated tests cannot fully prove physical dragging behavior -> Pair `swift build` and `./script/verify_all.sh` with panel verification.

## Migration Plan

No data migration is required. The change is reversible by restoring the prior panel movement configuration if verification reveals unexpected interaction regressions.

## Open Questions

- None.
