## Context

`ClipboardItem.contentKey` is implemented in the production model, while pasteboard classification and restore behavior live in the main-actor `ClipboardStore`. The current scripts under `script/verify/` compile reduced copies of these concepts, so they can pass without exercising the shipped code. The source-attribution timing harness is different: it validates a live, correlated physical-copy workflow and must remain an integration/evidence gate.

## Goals / Non-Goals

**Goals:**

- Make production tests the canonical deterministic regression coverage for content identity and pasteboard capture/restore behavior.
- Keep live source-attribution evidence separate from deterministic unit tests, while repairing only its stale evidence-path default.
- Preserve privacy by asserting metadata and item fields without logging or persisting raw clipboard payloads beyond test fixtures.

**Non-Goals:**

- Changing the production duplicate policy, source-resolution precedence, or paste timing semantics.
- Replacing physical Cmd+C evidence with synthetic events.
- Creating a general-purpose test abstraction for every AppKit boundary.

## Decisions

1. **Exercise the shipped model and store through narrow injected dependencies.**
   Existing `ClipboardStore` seams (`NSPasteboard`, `AppSettings`, `CopySourceTracker`, and persistence closure) are sufficient for deterministic tests. Add only the smallest internal access or fixture seam needed to observe a captured item; do not copy production structs into scripts.

   *Alternative considered:* expose all pasteboard parsing helpers publicly. Rejected because it expands the production API and weakens the service boundary.

2. **Use a unique `NSPasteboard` and the store's polling contract for pasteboard tests.**
   Text, URL, file, empty, and unsupported-content cases should write/read through the same change-count sequence the app uses. Image capture remains asynchronous; tests should use the existing pending-task observation or a focused seam and must verify the resulting item rather than duplicate PNG encoding code.

   *Alternative considered:* call a private parser directly or keep the reduced Swift script. Rejected because neither proves the public capture lifecycle or change-count ordering.

3. **Keep distinct trust-boundary checks.**
   `source_resolution.swift` remains a direct compile-and-run check for `CopySourceResolution`. The paste-target, paste-decision, pasteboard-write, history-performance, and content-key scripts are candidates for migration only where production tests can cover their actual shipped behavior; if a script covers a boundary not represented in the test target, the task must add focused production coverage before deletion.

4. **Preserve the live harness and make evidence-path resolution explicit.**
   The timing harness continues to require correlated physical Cmd+C evidence and schema-safe log validation. Its default evidence path should resolve from the current repository/script location or an explicit argument, never from a stale historical path.

## Risks / Trade-offs

- [AppKit pasteboard tests can be timing-sensitive] → use `NSPasteboard.withUniqueName()`, deterministic two-poll sequencing, and bounded waits only around the image encoder.
- [Migrating a script may accidentally drop a distinct safety assertion] → map every script assertion to a production test before deleting the script; retain `source_resolution.swift` and any check without an equivalent.
- [Test fixtures could expose copied content in logs] → use opaque fixture strings and assert fields in memory; do not add raw-payload diagnostics.

## Migration Plan

1. Add focused production tests and any minimal test-only seams.
2. Run the focused tests, `swift build`, and the existing full verification gate.
3. Update and validate the live harness evidence-path default.
4. Delete only scripts with equivalent passing coverage; retain the source-resolution check.
5. Roll back by restoring the deleted scripts and path-only harness change if the full gate or live evidence contract regresses.

## Open Questions

None. The exact test file split can be chosen during implementation without changing the scope or contract.
