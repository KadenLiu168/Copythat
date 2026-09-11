## Why

The pasteboard restore switch repeats the same processed-change bookkeeping in every supported branch, and `ClipboardCardView` exposes two computed properties solely to let tests inspect private presentation details. These duplications make small changes harder to audit while offering no additional user capability.

## What Changes

- Consolidate the successful-input path in `ClipboardStore.writeToPasteboard` so each supported branch preserves the current clear/write/mark ordering without repeating the final bookkeeping call.
- Replace card tests' use of `previewContentIsHidden` with the existing input state and remove that test-only projection.
- Inline the fixed concealed-preview label and remove the `concealedPreviewTitle` projection that exists only for tests.
- Re-check the `ClipboardItem` image content-key digest and storage optimization contracts without changing the stable digest format or detached PNG encoding path.
- Preserve `ClipboardItem`'s custom decoding keys because they provide defaults for older persisted history payloads; do not trade persistence compatibility for line-count reduction.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This is a model/view/testability cleanup with no intended user-visible or persisted-data behavior change.

## Impact

- **Pasteboard service:** `Sources/Copythat/Stores/ClipboardStore.swift` has less repeated restore bookkeeping while retaining invalid-item guards and mark-on-write-attempt semantics.
- **Card view/tests:** `Sources/Copythat/Views/ClipboardCardView.swift` and `Tests/CopythatTests/ClipboardCardViewTests.swift` stop exposing private presentation aliases.
- **Persistence/model:** `ClipboardItem.contentKey`, custom decoding defaults, image storage optimization, and source icon data remain unchanged.
- **Verification:** focused pasteboard/card/model tests, `swift build`, `swift test`, and `./script/verify_all.sh` must pass.

## Non-goals

- Removing or rewriting the custom `ClipboardItem.CodingKeys` decoder compatibility layer.
- Combining generic image PNG encoding with the detached `CGImage` encoder or the app-icon encoder.
- Changing pasteboard change-count ordering, duplicate handling, source attribution, or paste safety.
- Changing card identity, source-icon cache behavior, privacy-mode rendering, or user-facing copy.
