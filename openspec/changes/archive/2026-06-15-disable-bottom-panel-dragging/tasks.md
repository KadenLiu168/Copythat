## 1. Panel Window Behavior

- [x] 1.1 Update `PanelWindowController` so the bottom `NSPanel` cannot be repositioned by mouse dragging; verify the existing show-time `position(_:)` call and `PanelFrameCalculator` usage remain unchanged.
- [x] 1.2 Add focused coverage for the panel movement configuration without showing a real foreground panel in CI.

## 2. Verification

- [x] 2.1 Run `swift test --filter CopythatPanelTests` and verify the focused panel movement test passes.
- [x] 2.2 Run `swift build` and fix any compile errors introduced by the panel configuration change.
- [x] 2.3 Run `./script/verify_all.sh` and verify existing clipboard, panel, packaging, and support checks still pass.
- [x] 2.4 Run `./script/build_and_run.sh --verify-panel` and verify the panel appears in the window server.
- [x] 2.5 Synthetic-drag the visible panel and verify its bounds remain unchanged.
