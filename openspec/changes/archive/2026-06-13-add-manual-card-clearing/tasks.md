## 1. Store Behavior

- [x] 1.1 Add a store-level manual history clearing API; verify default mode removes only cards where `isPinned == false` and `pinboardName == nil`.
- [x] 1.2 Support explicit clear-all mode; verify pinned cards and custom-pinboard cards are removed only in clear-all mode.
- [x] 1.3 Refresh filtered items, selected item, and persisted history after clearing; verify selection clears when no visible cards remain.

## 2. Settings UI

- [x] 2.1 Inject the shared `ClipboardStore` into Settings surfaces; verify the app settings scene and settings window controller both build with the shared store.
- [x] 2.2 Add a Settings clear-cards control and current card count; verify the clear action is disabled when there are no cards.
- [x] 2.3 Add destructive confirmation choices for ordinary-card clearing and clear-all; verify pinned and custom-pinboard protection is communicated in the confirmation message.

## 3. Verification

- [x] 3.1 Add focused store tests for ordinary-card clearing and clear-all behavior.
- [x] 3.2 Update settings-window tests for the injected store dependency.
- [x] 3.3 Run `swift test`; verify all tests pass.
- [x] 3.4 Run `./script/verify_all.sh`; verify full project checks pass.
