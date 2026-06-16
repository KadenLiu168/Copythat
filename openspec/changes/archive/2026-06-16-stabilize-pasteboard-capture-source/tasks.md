## 1. Pasteboard Capture Stability

- [x] 1.1 Add stable-change tracking to `ClipboardStore.pollPasteboard()` so the first observation of a new pasteboard change count is recorded as pending and only a repeated stable count is read. Verify with a focused store test.
- [x] 1.2 Ensure pending pasteboard state is reset when Copythat writes or clears the system pasteboard itself. Verify existing paste/write and deletion tests still pass.

## 2. Duplicate Source Preservation

- [x] 2.1 Change `ClipboardHistoryPolicy` to return a structured insertion result with updated items, selected item ID, and whether the new item was inserted. Verify unpinned duplicate content keeps the existing item's ID and source metadata.
- [x] 2.2 Update `ClipboardStore.add(_:)` to use the policy result for selection and link preview enrichment. Verify pinned duplicate behavior remains unchanged.

## 3. Verification and Archive Readiness

- [x] 3.1 Run `swift build` and `swift test`, fixing any regressions.
- [x] 3.2 Run `./script/verify_all.sh`, fixing any regressions.
- [x] 3.3 Sync the accepted `clipboard-history` delta into the main spec and archive the completed OpenSpec change.
