## ADDED Requirements

### Requirement: Preserve consecutive observed image captures during bounded encoding

Copythat SHALL preserve eligible image captures read after the existing pasteboard stability gate without cancelling an earlier accepted encoding merely because a later image is observed. Image capture finalization SHALL remain outside MainActor, FIFO ordered among surviving image captures, and resource bounded to one physical capture encoder and at most four buffered captures, including active work that has been invalidated but has not actually finished. When the buffer is full, Copythat SHALL retain active work, discard the oldest waiting capture, and admit the newest image. Successful results SHALL remain subject to existing duplicate and history-retention rules, matching stale-deletion suppression and lifecycle invalidation.

This requirement SHALL NOT guarantee capture of a value overwritten before the existing polling/stability mechanism reads it, unlimited burst retention, or global ordering of delayed image insertion relative to synchronous text, URL or file insertion.

#### Scenario: Two consecutive images within capacity
- **WHEN** distinct eligible image A has been stably observed and is encoding
- **AND** distinct eligible image B is stably observed before A finishes, without overflow, deletion or lifecycle invalidation
- **THEN** B does not cancel A
- **AND** A finalizes before B and both are inserted through ordinary history rules
- **AND** with sufficient history capacity their final newest-first image order is B, A

#### Scenario: Three consecutive images within capacity
- **WHEN** eligible distinct images A, B and C are admitted in that order while A is still encoding
- **AND** no overflow or invalidation occurs and history capacity permits all three
- **THEN** finalization proceeds A, B, C with no simultaneous capture encoders
- **AND** history contains the images in order C, B, A

#### Scenario: Overflow retains active work and recent waiting images
- **WHEN** active image A and waiting images B, C and D fill the four-capture buffer
- **AND** eligible image E arrives
- **THEN** A remains active, B is discarded without encoding, and waiting order becomes C, D, E
- **AND** buffered captures never exceed four

#### Scenario: Source context and capture time survive queue delay
- **WHEN** images A and B are admitted with different resolved source names, icon bytes, icon identities and capture timestamps
- **AND** the foreground application changes while they wait or encode
- **THEN** newly created cards use each image's admission-time source context and timestamp rather than completion-time foreground context or time
- **AND** existing source-resolution precedence is unchanged

#### Scenario: Encoding failure allows subsequent work
- **WHEN** image A cannot produce a valid finalized PNG and image B is waiting
- **THEN** A is discarded without insertion or a result-triggered save
- **AND** B proceeds through finalization and ordinary insertion

#### Scenario: Finalization computes identity once
- **WHEN** N eligible image captures successfully finalize without invalidation or deletion and are inserted and saved
- **THEN** their bounded PNG encoding and N image identity hashes occur outside MainActor
- **AND** insertion, initial save and subsequent metadata saves reuse those identities without rehashing or re-encoding their image payloads
- **AND** prepared source-icon identities are forwarded without another source-icon identity hash

#### Scenario: Duplicate behavior remains unchanged
- **WHEN** consecutive finalized images have the same content key
- **THEN** the existing pinned and unpinned duplicate rules determine history entries, preserved metadata and selection
- **AND** the image pipeline does not create additional duplicate semantics

#### Scenario: Stop and restart wait for actual old encoding completion
- **WHEN** monitoring stops while image A is physically encoding and images are waiting
- **AND** monitoring restarts and image B is newly admitted before A actually finishes
- **THEN** previously admitted captures lose insertion eligibility and old waiting captures are discarded
- **AND** A continues occupying the sole physical encoding slot and one buffered-capture position until it finishes
- **AND** A's late result cannot insert, request a save or clear B's request state
- **AND** B can start only after A releases its own slot and can then insert normally

#### Scenario: New captures after clearing wait without encoder overlap
- **WHEN** Clear History invalidates active image A and its waiting captures
- **AND** new image B is admitted before A actually finishes
- **THEN** B waits while the invalidated A still occupies the sole physical slot
- **AND** A's result is rejected and B can proceed after A actually finishes
- **AND** repeated clearing or stop/restart does not create parallel capture encoders or bypass the four-capture buffer bound

#### Scenario: Overflow diagnostics are safe and default off
- **WHEN** an image is discarded by the bounded-overflow rule
- **THEN** exactly one overflow diagnostic event is emitted if clipboard diagnostics are enabled, and none is emitted if disabled
- **AND** image-pipeline events contain only sequence, pasteboard change-count, queue-depth, source-app, monotonic timing or reason metadata
- **AND** these events contain no clipboard text, URL, path, image bytes, payload bytes or content hash

## MODIFIED Requirements

### Requirement: Skip protected and ignored sources
Copythat SHALL avoid recording clipboard items that are configured or detected as unsuitable for history. An image resolved to an ignored source at capture admission SHALL NOT enter the image buffer or start capture encoding, insertion or persistence.

#### Scenario: Sensitive content is not recorded by default
- **WHEN** the pasteboard contains content marked as concealed or associated with password-manager data
- **AND** sensitive content recording is disabled
- **THEN** Copythat does not add the content to history

#### Scenario: Ignored application is not recorded
- **WHEN** a new clipboard item resolves to a source app listed in ignored applications
- **THEN** Copythat does not add the item to history

#### Scenario: Ignored image source is rejected before buffering
- **WHEN** a stable pasteboard image resolves to an app listed in ignored applications at admission
- **THEN** the image is not buffered or capture-encoded
- **AND** it does not enter history or request a save
- **AND** ignored-app configuration parsing and source-attribution precedence remain unchanged

### Requirement: Clear clipboard history manually
Copythat SHALL support manual clearing of stored clipboard history while protecting intentionally saved cards by default. Every confirmed Clear History operation SHALL invalidate all previously admitted image captures, including active and waiting captures, even when no stored card is removable. Invalidated image results SHALL NOT repopulate history or request persistence; images admitted after the clear SHALL remain eligible for ordinary capture. Clearing SHALL NOT request a history save when no stored card changes.

#### Scenario: Clear ordinary cards
- **WHEN** the user confirms clearing ordinary cards
- **THEN** Copythat removes stored cards that are not pinned and are not assigned to a custom pinboard
- **AND** Copythat keeps pinned cards
- **AND** Copythat keeps cards assigned to custom pinboards

#### Scenario: Clear all cards
- **WHEN** the user confirms clearing all cards
- **THEN** Copythat removes stored cards regardless of pin state or custom pinboard assignment

#### Scenario: History state refreshes after clearing
- **WHEN** clipboard cards are cleared
- **THEN** Copythat updates the visible card list
- **AND** Copythat updates the current selection to a remaining visible card or clears selection when no visible cards remain
- **AND** Copythat persists the updated clipboard history

#### Scenario: Custom pinboards remain after clearing cards
- **WHEN** clipboard cards are cleared
- **THEN** Copythat keeps configured custom pinboards available

#### Scenario: Clear invalidates active and waiting images
- **WHEN** the user confirms Clear History with image A active and images B and C waiting
- **THEN** none of those previously admitted captures can subsequently insert a card or trigger an additional save
- **AND** waiting captures are discarded without starting capture encoding
- **AND** the clear operation itself still persists any actual stored-card changes

#### Scenario: Clear an empty history with pending images
- **WHEN** the user confirms Clear History while history is empty and image captures are pending
- **THEN** those previously admitted captures are invalidated
- **AND** the clear and their late results request no history save

#### Scenario: Clear ordinary cards when only protected cards remain
- **WHEN** the user confirms clearing ordinary cards while only pinned or custom-pinboard cards remain and image captures are pending
- **THEN** protected cards and their organization remain unchanged
- **AND** all previously admitted image captures are invalidated
- **AND** no history save is requested solely for invalidation

### Requirement: Removed current clipboard cards are not recaptured
Copythat SHALL prevent removed cards that match current or pending pasteboard content from returning to clipboard history unless the user copies that content again. Single-card deletion SHALL suppress only matching image captures admitted before or at that deletion, without cancelling unrelated image captures. A matching image newly admitted from an intentional copy after deletion SHALL remain eligible under ordinary duplicate and retention rules, while any older matching completion SHALL remain suppressed until it finishes or is discarded.

#### Scenario: Delete current image card
- **WHEN** the user deletes an image card that matches the current general pasteboard content
- **THEN** Copythat removes the card from history
- **AND** Copythat clears the matching general pasteboard content
- **AND** Copythat does not recapture that image from stale pasteboard state

#### Scenario: Pending image capture finishes after deletion
- **WHEN** image capture admitted before or at deletion is still encoding a history item for content the user has removed
- **THEN** Copythat does not insert the encoded image into history or request a save for that completion

#### Scenario: Delete older history card
- **WHEN** the user deletes a history card that does not match the current general pasteboard content
- **THEN** Copythat removes the card from history
- **AND** Copythat keeps the current general pasteboard content available

#### Scenario: Copy same content again after deletion
- **WHEN** the user copies the same image again after deleting its prior card
- **THEN** Copythat can record the newly admitted copy as a history item under ordinary history rules

#### Scenario: Delete unrelated content during image encoding
- **WHEN** image A is encoding or waiting and the user deletes a card with different content
- **THEN** A retains its capture eligibility and is not cancelled by that deletion

#### Scenario: New same-content copy does not authorize an older completion
- **WHEN** old image A was admitted before its matching card was deleted
- **AND** the user intentionally copies A again and that new copy is admitted before the old completion is handled
- **THEN** the old completion remains rejected and does not request a save
- **AND** the new capture can insert through ordinary history rules

#### Scenario: Deletion protection survives unrelated tombstone churn
- **WHEN** a matching pre-deletion image completion remains outstanding while many unrelated cards are deleted
- **THEN** bounded deletion bookkeeping does not lose the protection required to reject that outstanding completion
- **AND** a later intentional copy remains eligible
