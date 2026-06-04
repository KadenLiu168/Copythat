## 1. Regression Coverage

- [x] 1.1 Add focused coverage for two text `ClipboardItem` values that have distinct `sourceAppIconData` and remain visually/data-contract independent when rendered or passed into card views; verify the test fails before the implementation change when practical.
- [x] 1.2 Verify existing source icon persistence tests or decoding behavior still accept optional `sourceAppIconData` without migration changes.

## 2. Card Source Icon Rendering

- [x] 2.1 Update the card rendering data path so `ClipboardCardView` uses `item.sourceAppIcon` for `hasSourceLogo`, `sourceLogo`, and source accent calculation instead of a shared icon keyed by `sourceApp`; verify earlier cards cannot be affected by later visible items.
- [x] 2.2 Remove or stop using `ClipboardStore.sourceIconByApp` and related refresh logic if it becomes unused; verify no unrelated store behavior, search filtering, selection, pinboards, or paste actions change.

## 3. Verification

- [x] 3.1 Run `swift build` and verify the package builds successfully.
- [x] 3.2 Run `./script/verify_all.sh` and verify the existing scripted checks pass.
- [x] 3.3 Manually verify the panel by copying text from app A, then different text from app B, and confirming the older A card keeps its original source logo while the newer B card shows B's logo.
