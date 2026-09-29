## MODIFIED Requirements

### Requirement: Persist restorable history metadata
Copythat SHALL persist clipboard history with enough metadata to restore supported items and display their context after relaunch. History saves SHALL preserve the previous valid history if a newer save fails and SHALL not rewrite unchanged stored media for metadata-only changes.

#### Scenario: App relaunches with prior history
- **WHEN** Copythat starts after previously saving history
- **THEN** previously saved items are loaded with kind, title, preview, source app, timestamp, pin state, pinboard assignment, and restorable content where available

#### Scenario: Stored media is optimized while source icons are preserved
- **WHEN** clipboard history data is saved with image data, link preview image data, or source icon data
- **THEN** Copythat stores optimized image and link preview image data suitable for history display and restoration
- **AND** Copythat preserves the captured source icon data for each item without downsampling it during storage optimization

#### Scenario: Metadata-only history update
- **WHEN** the user pins, unpins, renames a pinboard assignment, or otherwise changes only history metadata
- **THEN** Copythat persists the changed metadata without rewriting unchanged stored image, link-preview image, or source-icon content

#### Scenario: New preview media
- **WHEN** an existing URL history item gains a link-preview image
- **THEN** Copythat persists that image and the updated item without rewriting unrelated stored media

#### Scenario: Existing history formats remain readable
- **WHEN** Copythat starts with a previously supported history format, including the prior versioned file, raw legacy item array, or legacy preferences history
- **THEN** its restorable items and available context remain accessible
- **AND** migration SHALL NOT discard the previous valid history before a replacement is successfully saved

#### Scenario: New history save fails
- **WHEN** a newer history save fails after media was prepared but before the replacement history is committed
- **THEN** the previous valid history and its referenced media remain available after relaunch

#### Scenario: Save unloaded media references
- **WHEN** V2 history is restored and the user changes pin state, pinboard assignment, pinboard name, or other metadata before media is loaded
- **THEN** saving preserves every unchanged heavy-media reference without reading or hashing that referenced payload
- **AND** garbage collection retains each blob still referenced by any committed item
- **AND** deleting the last referencing item permits removal only after the replacement manifest commits

#### Scenario: Existing materialized media repair remains available
- **WHEN** an item supplies media bytes and the stored blob at their content address is corrupted
- **THEN** saving verifies and repairs that blob using the supplied bytes before committing the manifest
- **AND** a failed save preserves the previous manifest and its referenced media

### Requirement: Generate browser previews only for the visible selected eligible URL
Copythat SHALL permit browser snapshot fallback only while the panel is visible and its currently selected visible item is a URL whose metadata enrichment has completed successfully in the current session without a usable image and whose stored preview image is still absent. Pending or failed metadata MUST NOT authorize fallback. Closing the panel SHALL revoke authorization regardless of whether the view hierarchy remains alive.

#### Scenario: Open panel on an eligible URL
- **WHEN** metadata has succeeded without an image and the panel opens with that URL selected
- **THEN** Copythat requests its browser preview, subject to session cache and retry limits

#### Scenario: Select URL while metadata is pending
- **WHEN** the visible panel selects a URL whose metadata is still pending
- **THEN** no browser fallback starts
- **AND** metadata returning an image prevents fallback
- **AND** metadata succeeding without an image permits fallback only if the visibility and selection conditions still hold

#### Scenario: Eligible item is not selected or filtered out
- **WHEN** an eligible URL is not the selected visible item, including after search or pinboard filtering
- **THEN** Copythat does not request its browser preview

#### Scenario: Restore history after relaunch
- **WHEN** a restored URL without a preview image becomes the visible selected item and lacks a current-session metadata outcome
- **THEN** Copythat completes metadata enrichment before allowing browser fallback
- **AND** a persisted title alone does not prove fallback eligibility
- **AND** loading history does not request metadata for all restored URLs

#### Scenario: Restored URL already references a preview image
- **WHEN** a restored URL has a persisted preview-image reference but its bytes have not been loaded
- **THEN** opening the panel, selecting it, or filtering it in and out does not request metadata or browser fallback for that item
- **AND** a missing or corrupt referenced image does not silently authorize network regeneration

### Requirement: Apply only current link preview results
Copythat SHALL validate preview results against the current request identity, surviving item ID and unchanged URL before changing history. Browser snapshot and cached results SHALL additionally require current panel visibility, matching visible selection, eligibility and an absent preview image. Cancelled or superseded results SHALL NOT update history, populate caches or request persistence. Valid snapshots SHALL preserve metadata title, restorable URL content, source context, pinning and pinboard state, using the existing history persistence format and save path.

#### Scenario: Selection returns to the original item
- **WHEN** selection changes A to B to A while an older A callback is pending
- **THEN** the older A callback cannot apply merely because A is selected again
- **AND** it cannot clear a newer request's active state

#### Scenario: Panel closes and reopens
- **WHEN** an old fallback callback arrives after the panel closes and reopens
- **THEN** current visibility alone does not make that old request valid
- **AND** it cannot update history, populate cache or request persistence

#### Scenario: Item URL or preview changes before completion
- **WHEN** a pending result returns after its item URL has changed or an image has already been supplied
- **THEN** the mismatched result cannot overwrite the current URL or preview image

#### Scenario: Save a valid snapshot
- **WHEN** the current eligible selected URL receives a valid snapshot
- **THEN** its existing metadata title remains displayed and searchable
- **AND** its image is saved through the existing history and media persistence path
- **AND** no new persistence schema, database or disk cache is needed

#### Scenario: Title-only completion preserves unloaded image
- **WHEN** a valid title-only metadata completion meets an item that already references an unloaded preview image
- **THEN** the existing image reference survives the merge and subsequent save
- **AND** it is treated as an existing image for metadata outcome and fallback eligibility

#### Scenario: Explicit new preview image replaces its prior identity
- **WHEN** a valid update actually replaces an item's preview image with new bytes
- **THEN** the prior persisted reference no longer represents the current image
- **AND** saving records the new bytes' content address without changing unrelated media

## ADDED Requirements

### Requirement: Restore V2 heavy media on demand
Copythat SHALL restore V2 history metadata and eagerly restore source icons while retaining image and link-image blob references without reading or hashing those heavy payloads at startup. The on-disk schema SHALL remain version 2. Media existence SHALL remain distinct from whether its bytes are resident. V1, raw legacy arrays and legacy UserDefaults SHALL retain inline-data compatibility.

#### Scenario: Restore media-heavy history
- **WHEN** V2 history containing 500 image and URL items is restored
- **THEN** restore reads the manifest and required source-icon blobs, reusing duplicate icon reads
- **AND** heavy image/link-image blob reads are zero and their runtime Data fields remain empty with references retained
- **AND** metadata is searchable and pinboard organization is available before media access

#### Scenario: Legacy history is decoded
- **WHEN** a supported inline-media legacy history is restored
- **THEN** available inline media remains usable
- **AND** a subsequent successful V2 save uses the existing blob layout without extra migration or premature legacy deletion

### Requirement: Preserve image identity across media residency
Copythat SHALL use the same image content key for equal stored bytes whether eager or represented by their persisted SHA256 address, preserving duplicate detection, deletion suppression and current-pasteboard matching without loading the stored blob. Model transformations SHALL preserve unloaded references and SHALL invalidate a reference when they replace its bytes with a different payload.

#### Scenario: Copy an existing lazy image
- **WHEN** a newly captured image has the same stored bytes as a restored unloaded image
- **THEN** their content keys are identical and existing pinned/unpinned duplicate rules apply

#### Scenario: Delete a current lazy image
- **WHEN** the user removes an unloaded restored image matching the current pasteboard
- **THEN** the matching pasteboard is cleared and stale capture cannot reinsert it
- **AND** this identity comparison does not read the history blob

### Requirement: Validate media without losing unrelated history
Copythat SHALL validate every manifest blob ID as exactly 64 lowercase ASCII hexadecimal characters. Invalid syntax SHALL reject the damaged manifest through existing decode-failure handling. A syntactically valid missing or corrupt heavy blob SHALL NOT fail startup history restoration. On-demand reads SHALL verify SHA256 before releasing bytes to image, drag or paste consumers; access failure SHALL preserve metadata and references without deleting items or exposing corrupt bytes.

#### Scenario: Invalid blob ID
- **WHEN** a manifest includes an invalid source-icon, image or link-image ID, including path traversal, uppercase or non-ASCII characters
- **THEN** decoding rejects the manifest before using that ID as a file path

#### Scenario: Missing or corrupt heavy media
- **WHEN** a valid heavy-media reference names a missing file or bytes with a mismatching SHA256
- **THEN** startup retains the item and unrelated history
- **AND** actual media access fails locally, display uses a fallback, and paste reports the existing restore failure
- **AND** metadata saves keep that reference rather than silently removing it

### Requirement: Bound on-demand media retention
Copythat SHALL read and verify persisted heavy media outside MainActor and reuse successful loads through a byte-cost LRU cache keyed by blob ID with an internal 32 MiB budget. Each hit SHALL refresh recency; eviction SHALL keep retained byte cost within budget. A single blob exceeding the budget SHALL be returned without caching. Loading SHALL NOT populate the history array with media bytes, request persistence, change selection or start link enrichment.

#### Scenario: Reuse and evict cached media
- **WHEN** a blob is loaded twice while retained
- **THEN** only the first access reads disk and the second refreshes recency
- **WHEN** subsequent insertion exceeds the byte budget
- **THEN** least recently used entries are evicted until retained byte cost is within budget

#### Scenario: Oversized blob
- **WHEN** a verified blob exceeds the cache byte budget
- **THEN** it is returned to the caller without being retained by the cache
- **AND** the next access reads disk again

#### Scenario: Load completes without history mutation
- **WHEN** display, paste or drag loads a restored payload
- **THEN** its history item retains references and empty heavy Data fields
- **AND** no save, selection update or link enrichment is caused by that load
