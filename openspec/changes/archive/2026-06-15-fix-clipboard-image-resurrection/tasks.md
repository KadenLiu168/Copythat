## 1. Store Deletion Behavior

- [x] 1.1 Add bounded deleted-content tracking in `ClipboardStore`; verify removed items can be recognized by content key without changing `ClipboardHistoryPolicy`.
- [x] 1.2 Update single-card deletion and manual history clearing to remember only actually removed items; verify preserved pinned or pinboard items are not marked deleted.
- [x] 1.3 Clear `NSPasteboard.general` only when the removed item matches current pasteboard content and update `lastChangeCount`; verify older deleted items do not clear unrelated pasteboard content.

## 2. Async Image Capture

- [x] 2.1 Cancel pending image encoding when cards are removed; verify the task reference is cleared.
- [x] 2.2 Guard image encoding completion with deleted-content tracking before calling `add`; verify deleted image content is not inserted after the delete.
- [x] 2.3 Preserve intentional re-copy behavior by keeping the normal add path independent from tombstones; verify the same image content can be added again through the normal path.

## 3. Verification

- [x] 3.1 Add focused `ClipboardStore` tests for tombstones, manual clear behavior, pasteboard matching, async insertion rejection, and re-copy behavior.
- [x] 3.2 Run `swift test` and fix any regressions.
- [x] 3.3 Run `swift build` or the project verification script if tests reveal build-level issues; document any manual clipboard checks that remain.
