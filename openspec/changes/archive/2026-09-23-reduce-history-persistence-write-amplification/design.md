## Context

See `proposal.md` for motivation and `specs/clipboard-history/spec.md` for the behavior contract. `ClipboardStore` is `@MainActor`; its mutation methods call `saveItems()`, whose default callback synchronously invokes `ClipboardHistoryPersistence.save`. The current version-1 wrapper directly encodes `ClipboardItem`, including three `Data` fields. `ClipboardStore` also synchronously loads history during initialization, which remains unchanged here. `AppDelegate` currently has no termination-flush hook.

## Goals / Non-Goals

**Goals:** Keep the runtime `ClipboardItem` API and exact stored media bytes unchanged; make normal mutations schedule rather than perform save work; reduce metadata-only writes to a small manifest; preserve last-good history through migration and write failures; make Quit explicitly resolve an unsaved latest state.

**Non-Goals:** Move startup decoding off the MainActor, change image optimization, change Link Preview fetching, add a database, or alter clipboard capture, UI cards, search, or paste behavior.

## Decisions

### Versioned manifest and immutable media

Introduce `ClipboardHistoryFileV2` and `PersistedClipboardItemV2`; do not change `ClipboardItem`'s runtime shape or use it as the v2 persistence DTO. Store metadata and media references in `clipboard-history.json` (`version: 2`) and exact `Data` bytes in `history-media/<sha256>.blob`, using CryptoKit. The same bytes across items and media roles share one blob. V2 JSON contains no embedded media `Data` or Base64 payload. This is preferable to a detached full-file save, which moves stalls but does not reduce encoding or disk amplification; SQLite/SwiftData add unnecessary migration and transaction surface for the current bounded in-memory history.

For each save, derive references from the snapshot, hash media off the MainActor, write only missing immutable blobs with atomic writes, encode the lightweight manifest, and atomically replace it. Commit is the successful manifest replacement; failure before then leaves the old manifest and its referenced blobs intact, although newly written orphan blobs may remain. Never delete old blobs before commit. After commit, best-effort GC may remove only blobs absent from the committed manifest; keep GC coordinated with the serial writer and defer it when newer saves are waiting. A GC failure does not fail a committed save. This ordering is preferable to manifest-first or pre-commit cleanup because those can create dangling references after a crash. Manifest-only updates still hash existing media in this first version, but do not Base64-encode or rewrite it; measure hashing separately from the eliminated write amplification.

V2 load decodes the manifest, resolves each blob reference into the existing runtime item fields, and caches loaded bytes by blob ID within the load. A missing referenced blob is a load failure, not a silently absent image. Keep the existing backup/decode-failure policy and avoid interpreting an unsupported or damaged versioned file as a legacy array.

### Save coordinator and ordering

Give a MainActor-owned coordinator the synchronous `requestSave(snapshot)` entry point. It assigns a strictly increasing generation and replaces its single pending snapshot; `ClipboardStore.saveItems()` only hands it the current array value and returns. The coordinator runs at most one drain task, submitting one transaction at a time to a dedicated worker actor. The worker performs conversion, hashing, JSON encoding, and all save/GC file IO off the MainActor. After each attempt, the coordinator takes the latest pending snapshot, not every intermediate one. This makes `1 -> 4` possible when requests 2–4 arrive during write 1 without a fixed debounce durability window.

Assigning generations before spawning work and using a single submitter avoids actor-message reordering from one Task per mutation. The worker additionally rejects any generation not newer than its last accepted/committed generation; successful commits advance monotonically. An attempt failure is recorded distinctly from success, and the latest unsaved snapshot stays available for retry. The store's current injectable `persistItems` test seam must remain safe: production uses the coordinator, while tests can inject a no-op or in-memory sink so they never touch the user's Application Support history. Reuse existing code paths rather than add save scheduling to individual mutations.

### Compatibility and migration

Load by explicit file shape/version: v2 manifest, version-1 wrapper, then raw `[ClipboardItem]`; when no history file exists, use the legacy UserDefaults array. A recognized version-2 file must not fall through to the permissive v1 `ClipboardItem` decoder. Keep current synchronous load behavior so previously saved items reach the UI as before. V1 or raw-array data is migrated on the first later save request, not rewritten synchronously during launch. If legacy UserDefaults is the source, retain its key until the v2 manifest has committed successfully; a failed write cannot erase the sole copy. Subsequent save attempts can retry migration.

### Termination flush and failure choice

Use `applicationShouldTerminate` with AppKit's `terminateLater`/`reply(toApplicationShouldTerminate:)` flow, not a MainActor wait. The coordinator's flush checks the latest requested generation, waits for its attempt, and reports whether that generation (or a newer one) actually committed. A failed latest attempt is not equivalent to a successful flush; Retry schedules another attempt of the latest in-memory snapshot, Quit Anyway explicitly accepts losing uncommitted changes, and Cancel Quit leaves the app running. Re-check the latest generation before replying to termination so a save completing for an older state cannot incorrectly approve Quit. Previously committed history remains untouched in either failure choice. The choice UI is only a save-failure boundary, not a redesign of normal clipboard UI.

## Risks / Trade-offs

- [Startup still synchronously reads and decodes large history] -> Explicitly document as remaining MainActor startup cost; do not claim all persistence IO is off-main.
- [Hashing all in-memory media on metadata-only saves can consume CPU] -> Run it only on the worker, avoid media Base64 and rewrites, and use deterministic instrumentation/tests before considering a safe reference cache.
- [Crash or atomic-write failure leaves unreferenced blobs] -> Preserve the last-good manifest and collect only after a later successful commit; storage cleanup is secondary to data safety.
- [A blob is missing or corrupted] -> Treat as a load failure rather than returning a seemingly healthy, unrestorable card; retain the existing failure-backup path.
- [Older Copythat binaries do not understand v2] -> In-place migration protects the old file until v2 commit, but downgrade compatibility after that commit is not provided by this Change.
- [Background saves make error and Quit ordering visible] -> Test failed commits, generation inversion, pending preview updates, rapid edits, retry, cancel, and explicit Quit Anyway with controlled worker barriers.

## Migration Plan

Deploy a dual-format reader with a v2-only writer. Initial launch reads v1, raw legacy, or legacy preferences without performing a migration write on the MainActor. The first save transaction writes blobs before replacing the old manifest; only successful replacement authorizes removal of legacy preferences. On failure, leave the previous on-disk representation and references available, retain the unsaved snapshot for retry, and present the normal-Quit decision if needed. Rollback of a failed migration is automatic because commit did not occur; binary downgrade after a successful v2 commit is outside scope.
