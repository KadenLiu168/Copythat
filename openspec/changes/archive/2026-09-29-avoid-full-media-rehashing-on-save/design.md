## Context

See proposal.md for motivation. `ClipboardHistoryPersistence` already separates V2 metadata from content-addressed blobs and saves reference-only heavy media without reading it. Resident bytes instead take precedence over references, trigger SHA256, and cause an existing blob read plus another SHA256. Source icons have no runtime address. `ClipboardItem.contentKey` also hashes resident images on every access.

Image capture already encodes bounded PNG in a utility detached task. Metadata previews and WebKit snapshots already produce bounded PNG, but Store merge paths subsequently call `storageOptimized`, which re-encodes resident media even for title-only updates. The existing positive snapshot cache stores Data alone. `ClipboardSource` snapshots can be copied independently of icon generation. These are identity propagation boundaries, not reasons to redesign their scheduling.

The main spec and `saveRepairsAnExistingBlobWhoseContentsDoNotMatchItsHash` explicitly require save-time repair. This change deliberately replaces that contract; treating removal as a behavior-neutral optimization would be incorrect.

## Goals / Non-Goals

**Goals:** Make media identity immutable alongside finalized bytes; ensure metadata changes require work proportional to metadata rather than media byte volume; retain read-time integrity and existing persistence transactions.

**Non-Goals:** See proposal.md. In particular, one finalization hash is not a global hash-once guarantee across independently generated copies of identical bytes, and it does not eliminate verification hashes on real blob reads. File existence checks and GC directory enumeration remain allowed; zero blob reads means zero payload reads, not zero filesystem operations.

## Decisions

### 1. One runtime identity, established before save

Rename `persistedImageBlobID`/`persistedLinkImageBlobID` to `imageBlobID`/`linkImageBlobID` and add `sourceAppIconBlobID`. The names identify content, not proof of a successful disk write. Keep these runtime fields outside legacy Codable keys; V2 manifest fields remain unchanged.

Use a small immutable Sendable `PreparedMedia` value containing Data and its SHA256 ID for media finalization and forwarding. Its creation from final bytes performs the identity hash once. Trusted forwarding and validated restore paths accept an already known identity without hashing. Do not introduce a second identity cache or a general media-management subsystem.

For every media slot: resident Data implies a matching ID; Data plus ID must satisfy ID == SHA256(Data); reference-only slots are valid; genuinely absent media has neither. Restrict pair creation/replacement to preparation and trusted forwarding paths rather than independently mutating bytes and IDs. Existing raw-data construction needed for compatibility/tests must establish identity at construction, never deferred to save; production finalized paths must pass their prepared identity to avoid a second hash. Tests verify pairing at creation/transformation boundaries without adding production revalidation.

`contentKey` uses the known image ID for both resident and lazy images. It retains `image:empty` for absent images. Update lazy display, paste, drag, deletion, and deduplication consumers mechanically for field renames, preserving their behavior. Paste materialization forwards the verified ID when making a temporary item.

Alternative: keep persisted-prefixed fields. Rejected because a new payload owns its address before its first write. Alternative: save-local hash caching. Rejected because identity lifetime belongs to the payload and cache invalidation would duplicate the model's responsibility.

### 2. Finalize once at actual byte boundaries

- Image capture: detached utility work produces the final 1200px-bounded PNG and PreparedMedia before returning to MainActor. Preserve cancellation, stale capture rejection, and source capture timing.
- Link metadata: prepare after final 640px-bounded PNG conversion, including provider-icon fallback. `LinkPreviewMetadata` carries prepared media.
- WebKit: keep snapshot lifecycle intact; prepare the final bounded PNG at the fetch boundary and forward it through Store callbacks and the existing positive cache. Cache values become prepared media; keys, capacity, eviction, cancellation, and eligibility do not change.
- Source icon: establish identity after PNG encoding, add `ClipboardSource.iconBlobID`, and preserve it in copied source snapshots and all four item creation paths, including system-generated sources. Reuse existing snapshot state; no new icon-cache subsystem. Small icon hashing may stay on its current source capture path.
- Merge: title-only changes preserve original bytes and ID without calling whole-item re-encoding. Already finalized previews are applied directly; do not re-run storage optimization merely to apply them.
- `storageOptimized`: when explicitly needed for raw/unbounded input, preserve ID if bytes are unchanged, establish a new ID once for changed output, and clear both if conversion yields no payload. Reference-only inputs keep their ID. A media address alone does not prove that bytes meet size bounds; normal prepared paths avoid redundant calls because their producer has already bounded the image.
- Legacy: decoder/migration preparation supplies missing identities once for resulting payloads before normal saves. Do not add a new eager optimization pass or disk migration merely to compute IDs. If a later explicit transformation changes bytes it creates a distinct finalized payload.

### 3. Save consumes trusted identities, not media bytes for identification

For all three media kinds, validate every non-nil ID using existing canonical lowercase 64-hex rules before any writes. Resident Data without an ID is an internal contract violation: fail the save before writes rather than silently hash it. Do not recompute SHA to validate a syntactically valid trusted pair.

| State | Action |
| --- | --- |
| No bytes, no ID | No manifest media field |
| ID only | Preserve reference without accessing its file |
| Bytes + ID, blob exists | Reuse ID; no read/hash/write |
| Bytes + ID, blob absent | Queue bytes once per ID |
| Invalid ID or resident bytes without ID | Fail before blob/manifest writes and GC |

The pending dictionary deduplicates same-address writes within a transaction. No long-lived existence cache is necessary. Write missing blobs, atomically commit manifest, then allow best-effort GC. The worker continues using `garbageCollect: false` and the existing deferred GC flow. Failed writes leave the last committed manifest and its referenced blobs untouched; retry reuses identities. There is no callback that mutates the Store after a successful write merely to install IDs.

Alternative: read existing blobs only once per process. Rejected because it still adds payload reads to metadata saves and requires lifetime/invalidation state. Existing corrupt files are intentionally left unchanged by ordinary save, even when resident correct bytes exist. `ClipboardHistoryBlobStore.read` still validates syntax and SHA before returning any bytes. Missing files with available bytes can be written; unavailable lazy heavy media preserves its reference and fails only on access. Source-icon eager read failure behavior remains unchanged.

### 4. Restore existing addresses without recomputation

V2 `makeClipboardItem` forwards all three manifest addresses. Heavy media remains nil Data; source icons remain eager and use existing per-load duplicate icon reads. Reading an icon still performs integrity verification, but attaching its known ID performs no second hash. V1, raw arrays, and legacy preferences continue their existing decode/migration and deletion timing. Schema remains 2 with no new fields.

### 5. Measure operations at their real boundaries

Add a narrow test observation seam around actual media SHA operations, distinguishing identity creation from blob-read integrity verification. It must cover all production media hashing, including construction, content-key access, transformation, and save; do not count an expected event without observing the actual digest operation. Use concurrency-safe, test-isolated accounting that works across detached preparation and the save actor, with no raw payload logging or global counter leakage between parallel tests.

Reuse injectable readData/writeData for I/O counts, separating `.blob` reads/writes from manifest operations. Keep `mediaHashCount`, `blobReadCountDuringSave`, `blobWriteCount`, and `manifestWriteCount`; report identity and integrity hash categories separately when restore/read tests need them. Fixture digest computation and assertion-side SHA run outside measured production windows.

Use two scopes: direct persistence calls and real Store mutation through coordinator/worker flush. The latter detects hashing or encoding moved ahead of save. Build at least 100 mixed items including images, previews, and repeated icons within existing history limits. After initial save, isolate each pin/unpin, pinboard assignment/rename, other-item deletion, and title-only update; flush and assert 0/0/0/1 plus actual manifest content. Do not count coalesced bursts as one commit per user action. Deferred GC may read the manifest, but must not read blob payloads.

Capture and preview tests start measurement before finalization and establish exactly one identity hash for the target payload through insertion, initial save, content-key reuse, and later saves. Cache hits and source snapshot copies perform zero new identity hashes. Independently generated identical payloads may each hash once but still produce one physical blob. Verify observer sensitivity with positive controls for new media, blob reads, and writes.

## Risks / Trade-offs

- Removing automatic repair leaves preexisting corrupt blobs corrupt until some separately authorized recovery occurs. Mitigation: explicitly replace the old scenario and test, retain access-time rejection, and introduce no implicit repair promise.
- Missing ID forwarding can create duplicate hashes or incorrect references. Mitigation: immutable pairs, explicit trusted forwarding, focused transformation/restore/materialization tests, and measured Store-level acceptance.
- Counters can miss alternative digest calls or interfere across asynchronous tests. Mitigation: audit all media SHA call sites, test-isolated concurrent observation, and positive controls; diagnostics hashing of content-key strings is not media hashing.
- Moving work to preparation can affect capture lifecycle. Mitigation: keep image hashing in detached encoding and preserve cancellation/supersession regression coverage.
- Existence checks do not defend against external deletion or modification between checks and commit. This change retains lazy failure semantics and read verification; it does not claim protection from concurrent external blob-store mutation.

## Migration Plan

Implement runtime identity plumbing and producer preparation before removing save's hash fallback. Update fixtures to construct valid media pairs. Replace the corruption repair test with zero-read save plus failing verified-read coverage, then run focused and complete regression gates. No disk migration is needed; legacy media obtains identity in memory and migrates through the existing successful-save path. Older binaries still read schema V2 if the code change is rolled back. Do not rewrite existing history or touch real clipboard data during automated verification.
