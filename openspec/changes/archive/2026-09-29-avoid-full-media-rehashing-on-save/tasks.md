## 1. Runtime identities and operation observation

- [x] 1.1 Introduce immutable prepared media and complete `ClipboardItem` runtime addresses, replacing persisted-prefixed names without changing Codable payload keys; verify matching Data/ID pairs, reference-only and empty states, and legacy encoding compatibility in model tests.
- [x] 1.2 Make image content keys reuse the address and forward it through model copies, temporary paste materialization, and renamed lazy consumers; verify eager/lazy equality, pinned/unpinned deduplication, deletion suppression, paste, drag, and display regression tests.
- [x] 1.3 Add test-isolated, concurrency-safe observation of actual identity and integrity SHA operations, reusing read/write injection for blob and manifest counts; verify positive controls and detached-task/actor propagation, and audit all production media SHA call sites for unobserved paths.

## 2. Finalization and restore boundaries

- [x] 2.1 Add source icon identity after PNG creation and forward it through copied ClipboardSource snapshots and text/URL/file/image creation, including system sources; verify one identity hash per prepared icon and zero on snapshot/item reuse without a new icon cache.
- [x] 2.2 Return prepared image bytes and ID from detached capture encoding; verify one image identity hash through capture, content-key checks, initial save, and later metadata saves, with preparation outside MainActor and existing capture cancellation/stale-result tests preserved.
- [x] 2.3 Carry prepared bounded preview media through metadata extraction, WebKit fetch results, Store merges, and the existing positive snapshot cache; verify one identity hash per final PNG, zero on cache reuse, preserved 640px bounds, and unchanged fallback eligibility/cancellation/cache-capacity behavior.
- [x] 2.4 Remove redundant whole-item optimization from already-finalized and title-only preview updates; make explicit storage optimization preserve unchanged IDs, compute changed-output IDs, and clear failed/absent payload pairs correctly; verify changed bytes never retain old IDs, title-only updates do not encode/hash, and source icon bytes remain unchanged.
- [x] 2.5 Restore all three V2 identities while retaining lazy heavy media and eager verified/deduplicated icon reads; establish missing legacy identities during decode/preparation. Verify V2 performs zero identity hashes, no heavy reads, and no extra icon hash beyond verification; cover V1, raw arrays, preferences, and failed migration retention.

## 3. Persistence hot path and integrity contract

- [x] 3.1 Replace save-time identity derivation and existing-blob verification with known-ID syntax validation and missing-blob staging; verify resident and reference-only paths perform zero SHA/read, invalid IDs fail before writes/GC, and no normal producer reaches save with resident data lacking identity.
- [x] 3.2 Preserve deduplicated blob-first writes, atomic V2 manifest commit, and deferred post-commit GC; verify identical media produces one physical blob, missing resident blobs are written using known IDs, missing lazy references survive, and injected blob/manifest write failures plus retry preserve last-good history without re-hashing.
- [x] 3.3 Replace the existing save-repairs-corruption test with explicit no-read/no-repair metadata save followed by failing verified blob access; verify SHA mismatch never releases corrupt bytes and existing missing/corrupt heavy-media metadata restoration behavior remains intact.

## 4. Acceptance and regression

- [x] 4.1 Add a direct persistence fixture of at least 100 mixed items with resident images, previews, and repeated icons; after initial save verify each metadata-only save has mediaHashCount=0, blobReadCountDuringSave=0, blobWriteCount=0, manifestWriteCount=1, and correct manifest fields.
- [x] 4.2 Exercise real Store pin/unpin, pinboard assignment/rename, other-item deletion, and title-only update through coordinator/worker flush, measuring from before mutation; verify the same 0/0/0/1 acceptance for each isolated mutation and repeat with V2 lazy-restored media. Keep fixture preparation, actual media access, and assertion-side digest computation outside measurement windows.
- [x] 4.3 Run focused suites for model optimization, capture, source propagation, previews/cache reuse, persistence/legacy, lazy media, and Store integration; verify exactly-once new/changed-media hashing and all seven requested media scenarios with isolated temporary directories/defaults and mocked pasteboards.
- [x] 4.4 Run existing worker/coordinator tests proving background disk I/O, save coalescing, generation ordering/stale rejection, serialized writes, quit flush/retry/cancel, and deferred GC; verify no lifecycle redesign or user-data mutation was introduced.
- [x] 4.5 Run `swift build`, `./script/verify_all.sh`, `openspec validate avoid-full-media-rehashing-on-save --strict`, and scoped diff review. Report results and any manual verification limits in the response; keep ephemeral output only under `.build/` or `/tmp/` and preserve unrelated workspace changes.
