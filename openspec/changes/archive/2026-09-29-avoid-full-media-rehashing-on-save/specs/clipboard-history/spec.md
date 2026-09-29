## MODIFIED Requirements

### Requirement: Persist restorable history metadata
Copythat SHALL persist clipboard history with enough metadata to restore supported items and display their context after relaunch. History saves SHALL preserve the previous valid history if a newer save fails and SHALL perform no media hashing, existing media blob reads, or unchanged media blob writes for metadata-only changes, including resident images, link previews, and source icons. Saves SHALL continue using schema version 2.

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

The scenario name is retained for spec continuity; its previous save-time repair guarantee is explicitly superseded by the following read-time integrity behavior.
- **WHEN** an item supplies media bytes and the existing stored blob at their content address is corrupted
- **THEN** an ordinary metadata save preserves its reference without reading, hashing, or repairing the blob
- **AND** an actual blob read detects the SHA256 mismatch and fails without releasing corrupt bytes
- **AND** unrelated history metadata remains usable

#### Scenario: Mixed resident history metadata update
- **WHEN** history containing at least 100 items with resident images, link previews, and repeated source icons has completed its initial save, all referenced blobs remain present, and one pin, unpin, pinboard assignment, pinboard rename, other-item deletion, or title-only mutation is flushed
- **THEN** the mutation through completed save performs zero media hashes, zero existing media blob reads, and zero media blob writes
- **AND** exactly one manifest commit records the changed metadata

#### Scenario: Missing blob with resident bytes
- **WHEN** a saved media reference has available resident bytes but its blob file is absent
- **THEN** saving writes those bytes at their known content address before committing the manifest without hashing them again
- **AND** equal media addresses share one physical blob

#### Scenario: Blob or manifest write fails
- **WHEN** writing a required new blob or committing the replacement manifest fails
- **THEN** the previous manifest remains valid and no blob referenced by it is removed before a successful replacement commit
- **AND** retry uses the same runtime content addresses without re-hashing media


### Requirement: Preserve image identity across media residency
Copythat SHALL use the same image content key for equal stored bytes whether eager or represented by their persisted SHA256 address, preserving duplicate detection, deletion suppression and current-pasteboard matching without loading the stored blob. Model transformations SHALL preserve unloaded references and SHALL establish the new payload's correct content address when they replace its bytes with a different payload. Resident image content-key access SHALL reuse the known address without hashing bytes again.

#### Scenario: Copy an existing lazy image
- **WHEN** a newly captured image has the same stored bytes as a restored unloaded image
- **THEN** their content keys are identical and existing pinned/unpinned duplicate rules apply

#### Scenario: Delete a current lazy image
- **WHEN** the user removes an unloaded restored image matching the current pasteboard
- **THEN** the matching pasteboard is cleared and stale capture cannot reinsert it
- **AND** this identity comparison does not read the history blob

## ADDED Requirements

### Requirement: Establish media content addresses at finalization
Copythat SHALL establish one SHA256 content address per newly finalized stored image, link-preview image, or source-icon payload and carry that identity through its runtime lifetime. Resident bytes and their address MUST agree. Unchanged metadata transformations and reuse of already prepared media SHALL preserve the address without hashing or re-encoding that media. Finalization hashes SHALL be distinguished from integrity verification performed on actual blob reads.

#### Scenario: New image is captured and saved repeatedly
- **WHEN** a captured image is encoded to its final bounded PNG, saved, and subsequently pinned or moved to a pinboard
- **THEN** its content address is computed once alongside background image encoding outside MainActor
- **AND** insertion identity checks, initial save, and subsequent metadata saves reuse that address

#### Scenario: Preview finalization and session reuse
- **WHEN** a metadata image or browser snapshot becomes final bounded PNG bytes
- **THEN** its address identifies those stored bytes rather than the original provider image
- **AND** applying it, saving it, changing only its title, or reusing the same prepared session-cache result does not re-encode or re-hash that payload

#### Scenario: Source icon is propagated
- **WHEN** a source icon is encoded and its source snapshot is reused to create text, URL, file, or image items
- **THEN** the icon address is computed once for that prepared payload and forwarded with its bytes
- **AND** metadata saves do not hash source icons even when many items share them

#### Scenario: Storage optimization changes bytes
- **WHEN** media optimization actually produces different stored bytes
- **THEN** the replacement receives its own matching address before save
- **AND** unchanged bytes retain their existing address and absent media does not acquire a stale address

#### Scenario: Restore V2 media identities
- **WHEN** V2 history is restored
- **THEN** all three media addresses are recovered from the manifest without recomputing their identity
- **AND** heavy image and preview bytes remain unloaded
- **AND** source icons retain eager read-time integrity verification and duplicate-read reuse

#### Scenario: Legacy inline media
- **WHEN** V1, raw legacy arrays, or legacy preferences provide inline media without addresses
- **THEN** each resulting finalized payload receives its address once during decoding or migration preparation before entering normal save operations
- **AND** subsequent metadata mutations and saves reuse the established identities

#### Scenario: Invalid save identity
- **WHEN** a save receives a media address other than exactly 64 lowercase ASCII hexadecimal characters
- **THEN** it fails before writing blobs, committing the manifest, or collecting garbage
