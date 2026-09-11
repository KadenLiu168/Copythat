## Context

`ClipboardStore.writeToPasteboard` has three valid branches (text/URL, file, image), each clearing the pasteboard, writing data, calling `markPasteboardProcessed`, and returning the write result. Invalid strings, missing files, or missing image data return before clearing. `ClipboardCardView` already stores `hidesPreview`; the `previewContentIsHidden` and `concealedPreviewTitle` accessors are only test projections, while the latter is used internally only to render a constant label. `ClipboardItem` uses a custom decoder and explicit `CodingKeys` to preserve defaults for legacy fields.

## Goals / Non-Goals

**Goals:**

- Remove duplicate bookkeeping and test-only surface area with behavior-preserving edits.
- Keep image identity, storage optimization, and persisted-history compatibility explicit and regression-tested.

**Non-Goals:**

- Redesigning pasteboard capture or image encoding.
- Simplifying away any code that protects older persisted history payloads.

## Decisions

1. **Compute the write result per branch, then mark once.**
   Keep each branch's validation and `pasteboard.clearContents()` placement, assign the branch result, call `markPasteboardProcessed()` once after the switch, and return it. Invalid guards remain before the switch result so an invalid item does not advance the monitor state.

   *Alternative considered:* add a generic pasteboard writer abstraction. Rejected because this is a single call site and a helper would obscure the existing type-specific checks.

2. **Test the stored input, not a private alias.**
   Card tests should assert `hidesPreview` and view inequality for privacy state. The concealed label is an internal constant; inline it and avoid exposing a computed property solely for tests.

   *Alternative considered:* keep the aliases for test convenience. Rejected because they expand the view's observable surface without representing domain behavior.

3. **Treat custom decoding keys as a persistence boundary.**
   Retain `ClipboardItem.CodingKeys` and its `decodeIfPresent` defaults. Add/retain round-trip and legacy-field tests rather than deleting the enum based on its apparent redundancy.

   *Alternative considered:* rely on synthesized Codable. Rejected because synthesized decoding would not preserve missing-field defaults for older history files.

4. **Keep PNG paths separate.**
   Validate that `contentKey` continues to use the stable SHA-256 digest and that storage optimization still bounds generic image/link previews. Do not merge the main-actor `NSImage` path with the detached `CGImage` path used for asynchronous capture.

## Risks / Trade-offs

- [Moving the mark call could change monitor state after a write failure] → preserve the current valid-item mark-on-attempt semantics and add tests for failed writes where possible.
- [Removing aliases could weaken privacy regression coverage] → assert the public `hidesPreview` input and card equality behavior, plus retain native/manual privacy checks.
- [Overzealous model cleanup could break legacy history] → keep `CodingKeys` and run decoding/storage tests against legacy payloads.

## Migration Plan

1. Add/update focused tests for restore bookkeeping, card privacy state, content keys, and legacy decoding.
2. Consolidate the switch bookkeeping and remove only the test-only projections.
3. Run the full build and verification gate.
4. Roll back by restoring the aliases or per-branch bookkeeping if any regression appears; no data migration is required.

## Open Questions

None. The compatibility-sensitive model boundary is intentionally resolved in this design.
