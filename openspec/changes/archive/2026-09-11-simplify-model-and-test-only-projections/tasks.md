## 1. Preserve model and pasteboard contracts

- [x] 1.1 Add or update focused tests for `ClipboardItem.contentKey`, stable image digest behavior, storage optimization bounds, source icon preservation, and legacy decoding defaults; verify with the focused model/storage test filters.
- [x] 1.2 Add focused restore tests for valid text/URL/file/image writes and invalid empty/missing inputs, including the monitor bookkeeping expectation; verify invalid items leave existing pasteboard content untouched.

## 2. Remove low-risk duplication

- [x] 2.1 Consolidate the valid-branch result and single `markPasteboardProcessed()` call in `ClipboardStore.writeToPasteboard` while preserving all guards and clear/write ordering; verify the focused restore tests and `swift build` pass.
- [x] 2.2 Replace card tests' private projections with `hidesPreview`, inline the concealed-preview label, and remove both test-only accessors; verify card privacy tests and repository search find no remaining projection references.
- [x] 2.3 Review `ClipboardItem.CodingKeys`, generic `NSImage.pngData`, detached `ClipboardStore.pngData`, and app-icon encoding paths; verify no compatibility-sensitive or semantically distinct path was merged or removed.

## 3. Full regression verification

- [x] 3.1 Run `swift build`, `swift test`, `./script/verify_all.sh`, and `git diff --check`; verify clipboard capture, restore/paste safety, card privacy, image deletion, source icons, and persistence tests remain green.
- [x] 3.2 Inspect the final diff for unchanged persisted JSON fields, content-key format, source attribution, duplicate policy, and diagnostics privacy; verify no raw clipboard data was added to logs or tests.
