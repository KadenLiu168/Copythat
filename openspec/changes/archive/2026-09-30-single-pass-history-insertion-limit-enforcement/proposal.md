## Why

Changing the history limit currently leaves existing clipboard cards visible until another copy occurs. Insertion and large limit reductions also repeatedly scan history, delaying a final bounded state on the main actor. This change makes limit changes take effect without another copy while preserving existing duplicate and pinned-card behavior.

## What Changes

- Apply a reduced history limit to existing history when the setting changes and on startup when restored history exceeds the configured bounds; persist the final retained state once when trimming occurs.
- Centralize duplicate classification, image and history retention, and removed-item identities in one linear-time history policy result for each insertion or enforcement operation.
- Preserve existing unpinned duplicate identity and source metadata, pinned duplicate coexistence, pinned-item protection, and removal cleanup; do not treat automatic eviction as an explicit user deletion.
- Ensure an incoming item discarded immediately by the limit is neither selected nor treated as a retained insertion.
- Clarify the documented limit exception when pinned cards alone exceed the configured limit.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `clipboard-history`: apply limit changes to existing history, preserve pinned items even when their count exceeds the limit, and keep final selection and removal behavior consistent across insertion and trimming.

## Impact

Changes are scoped to `ClipboardHistoryPolicy`, `ClipboardStore`, `ClipboardDiagnostics`, their existing tests, and the `clipboard-history` delta spec. History persistence continues to use the existing save path and V2 schema. No new dependencies or pasteboard, paste, source-attribution, or link-preview policies are introduced.

## Non-goals

No persistence-format migration, long-lived content index, image/blob/search-corpus redesign, pinboard retention-rule change, forced deletion of pinned cards, debounce of limit enforcement, or new clipboard/paste behavior.
