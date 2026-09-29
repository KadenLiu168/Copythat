## Why

Pinning, organizing, or deleting history currently re-hashes resident images, previews, and source icons and reads existing blobs to verify them. Stable runtime content addresses should let these metadata operations commit a lightweight manifest without work proportional to stored media bytes, extending the existing V2 lazy-media design to newly captured media too.

## What Changes

- Establish one content address when each media payload is finalized; carry it with resident bytes and preserve it through metadata transformations, source snapshots, preview cache reuse, and lazy restoration.
- Complete runtime identity with `sourceAppIconBlobID`, `imageBlobID`, and `linkImageBlobID`; reuse image identity for content keys as well as persistence, without a second hash cache.
- Make save validate known ID syntax, write only missing blobs for available bytes, and commit the V2 manifest without computing media identities or reading existing blobs.
- **BREAKING behavioral contract**: replace save-time verification/repair of an existing corrupt blob with read-time integrity verification. Ordinary metadata saves no longer repair corruption even when resident bytes are available. Missing heavy-media references continue to survive saves and fail locally on access.
- Add deterministic hash/read/write instrumentation and mixed-history acceptance coverage proving zero media hashes, zero blob reads, zero blob writes, and one manifest commit per settled metadata mutation.
- Preserve schema version 2, legacy compatibility, deduplication, lazy media behavior, background serialized saves, generations, quit flushing, and post-commit garbage collection.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `clipboard-history`: establish reusable media content addresses across creation, transformation, restore, and save; extend metadata-only persistence guarantees to resident media and icons; replace save-time corruption repair with read-time rejection.

## Impact

Changes are bounded to `ClipboardItem`, `ClipboardSource`/`CopySourceTracker`, image preparation and identity forwarding in `ClipboardStore`, link preview finalization and existing snapshot cache values, `ClipboardHistoryPersistence`, and focused tests. Lazy media consumers need mechanical runtime-field renames. The save coordinator and worker retain their architecture and lifecycle. No new dependency, disk format, permission, or persistent cache is required.

## Non-goals

No schema V3, database adoption, history-limit change, lazy-cache policy change, search optimization, link-preview concurrency redesign, source-tracker rewrite, startup integrity scan, automatic repair subsystem, or save-coordinator/worker redesign. This does not remove integrity hashes on actual blob reads or promise globally one hash for independently generated identical payloads.
