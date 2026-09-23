## Why

History mutations currently encode and atomically rewrite the entire media-heavy history file on the MainActor. A small pin or pinboard change can therefore stall the UI and rewrite tens of megabytes, while URL insertion followed by link-preview enrichment repeats the work.

## What Changes

- Persist unchanged history media once and keep subsequent metadata-only saves small, without changing the runtime clipboard item or its restorable bytes.
- Schedule save transactions away from the MainActor, serialize writes, and coalesce superseded in-flight requests without allowing stale state to overwrite newer state.
- Keep existing history formats readable and migrate them without risking the previous valid history if a save fails.
- Flush the latest requested state on normal Quit. If it remains unsaved, offer Retry, Quit Anyway, and Cancel Quit instead of silently losing the change.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `clipboard-history`: Extend the persistence contract to cover unchanged-media write avoidance, nonblocking saves, latest-state ordering, backward-compatible loading, failure safety, and normal-Quit flush behavior.

## Impact

- Primary code: `ClipboardHistoryPersistence`, `ClipboardStore`, `AppModel`, and `AppDelegate`; a focused persistence coordinator/worker and persistence tests are expected.
- Storage: new history saves use a metadata manifest and deduplicated media files under Application Support; existing history remains readable. No new dependency is needed.
- User-visible behavior: history actions stay responsive; previously saved cards remain restorable; failed Quit saves require an explicit user decision.
- Startup history loading remains synchronous in this Change. Its existing MainActor startup cost is a known remaining limitation, not a claim of this optimization.

## Non-goals

- No SQLite, SwiftData, database dependency, image recompression, Link Preview fetch change, clipboard capture/source-attribution change, history-limit change, or UI/search/paste redesign.
- No asynchronous startup history loading in this Change.
