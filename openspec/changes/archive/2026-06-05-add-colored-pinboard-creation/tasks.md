## 1. Structured Pinboard Data

- [x] 1.1 Add codable custom-pinboard and fixed color-token models with a six-color perceptually balanced palette; verify token encoding, decoding, and color lookup with focused tests.
- [x] 1.2 Replace the newline-separated pinboard source of truth with published structured custom-pinboard data and a creation API that trims names and rejects empty or duplicate names; verify valid and invalid creation behavior with focused tests.
- [x] 1.3 Add one-time migration from legacy pinboard names to structured colored pinboards while preserving order and name-based clipboard-item assignments; verify legacy, empty, duplicate-name, and relaunch persistence cases with focused tests.
- [x] 1.4 Update pinboard filters and clipboard-card assignment inputs to consume structured pinboards and persisted colors instead of order-based color assignment; run `swift build` and the focused pinboard tests.

## 2. Panel Creation Flow

- [x] 2.1 Change the bottom-panel `+` action from opening Settings to presenting a compact anchored new-pinboard popover with a focused name field, fixed color choices, and Cancel/Create actions; verify the control no longer opens Settings.
- [x] 2.2 Wire valid creation to persist, dismiss, immediately display, and select the new pinboard without moving the current clipboard item; verify the full creation flow manually and with focused state tests where practical.
- [x] 2.3 Ensure empty and duplicate names cannot be created, Return creates only when valid, and Escape closes without creating a pinboard; verify each keyboard and validation scenario manually.
- [x] 2.4 Retire the legacy Settings pinboard text-editing path without adding a new Settings management surface; run `swift build` and verify menu-bar Settings continues to open the existing application settings.

## 3. Verification And Reconciliation

- [x] 3.1 Reconcile the overlapping `vitalize-pinboard-category-dots` change by preserving any desired marker-shape work while excluding its conflicting order-based color-assignment task; verify only persisted selected colors drive custom pinboard markers.
- [x] 3.2 Run `swift build` and `./script/verify_all.sh`; fix any regressions and confirm all automated checks pass.
- [x] 3.3 Manually verify creation, cancellation, empty and duplicate validation, repeated color choices, immediate selection, legacy migration, relaunch persistence, card assignment, pinboard filtering, horizontal scrolling, and unchanged Clipboard/Pinned behavior.
- [x] 3.4 Manually verify the fixed palette remains distinct with consistent perceived saturation and brightness in Aqua and Dark Aqua.
