# Clipboard History Specification

## Purpose
Copythat records recent clipboard content so users can review, search, pin, organize, and restore copied items without leaving the native macOS workflow.

## Requirements

### Requirement: Capture supported clipboard item kinds
Copythat SHALL capture non-empty text, HTTP/HTTPS URLs, images, and file references from the general pasteboard after the observed pasteboard content state is stable.

#### Scenario: Capture text
- **WHEN** the pasteboard changes to a stable non-empty text value
- **THEN** Copythat records a text history item with a title, preview, source app, timestamp, and restorable text value

#### Scenario: Capture URL
- **WHEN** the pasteboard changes to a stable HTTP or HTTPS URL string
- **THEN** Copythat records a URL history item using the URL host as its title when available
- **AND** the original URL string remains available for restoration

#### Scenario: Capture image
- **WHEN** the pasteboard changes to a stable image value
- **THEN** Copythat records an image history item with an image preview, source app, timestamp, and restorable image data

#### Scenario: Capture file
- **WHEN** the pasteboard changes to one or more stable file URLs
- **THEN** Copythat records a file history item with the file name or file count, source app, timestamp, and restorable file URLs

#### Scenario: Multi-step pasteboard write settles before capture
- **WHEN** a single copy action causes multiple pasteboard change counts before the final copied value is stable
- **THEN** Copythat records the final stable clipboard value
- **AND** Copythat does not insert an earlier transient value as a history item

### Requirement: Responsive clipboard capture
Copythat SHALL react promptly to supported user-initiated clipboard writes without remaining in permanent high-frequency pasteboard polling, and SHALL commit pasteboard content only after the final observed change count has remained unchanged for a minimum stability interval.

#### Scenario: Shortcut-triggered copy wakes capture monitoring
- **WHEN** monitoring is active and Copythat observes a supported copy, cut, or clipboard-screenshot keyboard action
- **THEN** Copythat enters or extends a bounded fast-observation period
- **AND** Copythat does not rely solely on the next idle polling interval to observe the resulting pasteboard change

#### Scenario: Clipboard content is committed only after time-based stability
- **WHEN** one logical copy operation causes multiple pasteboard change counts
- **THEN** Copythat restarts the stability interval whenever it observes a newer count
- **AND** Copythat reads and commits content only after the final observed count remains unchanged for the minimum stability interval
- **AND** transient intermediate content is not inserted into history

#### Scenario: A newer pending count replaces its observation context atomically
- **WHEN** another change count arrives before a pending count reaches the minimum stability interval
- **THEN** Copythat replaces the pending count, its first-observed source candidate, and its stability start time together
- **AND** the captured content and source attribution belong to the count that actually becomes stable

#### Scenario: Successive stable shortcut-driven copies are retained
- **WHEN** a shortcut-driven copy reaches the minimum stability interval and is captured
- **AND** another shortcut-driven copy occurs while the bounded fast-observation period remains active
- **THEN** Copythat records both stable values in newest-first history order

#### Scenario: Non-keyboard pasteboard activity enters fast observation after discovery
- **WHEN** idle monitoring first observes a pasteboard change without a supported shortcut wake signal
- **THEN** Copythat enters or extends a bounded fast-observation period for stability confirmation
- **AND** a short fast-observation tail remains after the stable change is processed so immediately following activity can be observed promptly

#### Scenario: Fast observation ends after inactivity
- **WHEN** no new copy intent or pasteboard activity extends the bounded fast-observation period
- **THEN** Copythat exits fast observation after its deadline
- **AND** subsequent idle monitoring remains at its low-frequency cadence

#### Scenario: Copythat-generated pasteboard writes terminate pending external capture
- **WHEN** Copythat writes or clears the pasteboard while an external change is pending
- **THEN** Copythat discards the pending observation and ends its current fast-observation period
- **AND** Copythat does not insert either the stale pending value or its own pasteboard write into history

#### Scenario: Shortcut observation is unavailable
- **WHEN** the existing keyboard event tap is unavailable
- **THEN** Copythat continues discovering clipboard activity through low-frequency idle polling
- **AND** discovered changes receive the same time-based stability confirmation without requesting new permissions

#### Scenario: Monitoring stops and restarts
- **WHEN** clipboard monitoring stops
- **THEN** pending observation and scheduled fast polling are invalidated, and copy-intent wakes received while stopped do not restart polling
- **AND** an explicit later restart can discover an external change written while monitoring was stopped

#### Scenario: Opening the panel does not bypass stability
- **WHEN** opening the panel triggers an explicit pasteboard poll before the pending count reaches the minimum stability interval
- **THEN** Copythat does not capture that pending content prematurely

### Requirement: Skip protected and ignored sources
Copythat SHALL avoid recording clipboard items that are configured or detected as unsuitable for history.

#### Scenario: Sensitive content is not recorded by default
- **WHEN** the pasteboard contains content marked as concealed or associated with password-manager data
- **AND** sensitive content recording is disabled
- **THEN** Copythat does not add the content to history

#### Scenario: Ignored application is not recorded
- **WHEN** a new clipboard item resolves to a source app listed in ignored applications
- **THEN** Copythat does not add the item to history

### Requirement: Maintain bounded and deduplicated history
Copythat SHALL keep history within the configured limit and avoid duplicate entries for the same content.

#### Scenario: Existing unpinned content is copied again
- **WHEN** a clipboard item has the same content key as an existing unpinned history item
- **THEN** Copythat keeps a single entry for that content
- **AND** the existing item is treated as the newest matching history item
- **AND** the existing item's captured source app, source icon, ID, and creation time remain unchanged

#### Scenario: Existing pinned content is copied again
- **WHEN** a clipboard item has the same content key as an existing pinned history item
- **THEN** Copythat keeps the pinned entry
- **AND** Copythat may record the newly copied item as the newest ordinary history item

#### Scenario: History exceeds the configured limit
- **WHEN** adding a clipboard item would exceed the configured history limit
- **THEN** Copythat removes older unpinned items before pinned items
- **AND** the visible history remains within the configured limit

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

### Requirement: Keep history mutations responsive while saving
Copythat SHALL schedule history-save encoding and file writes outside the MainActor mutation path, so history actions do not wait for the complete save transaction.

#### Scenario: Pin a media-heavy history item
- **WHEN** the user pins or unpins a card in a media-heavy history
- **THEN** the visible history updates without waiting for full-history persistence work to finish

#### Scenario: Successive history changes
- **WHEN** multiple history changes arrive while a save is in progress
- **THEN** Copythat SHALL save the latest requested state after the in-progress save
- **AND** superseded intermediate states SHALL NOT overwrite a newer saved state

### Requirement: Resolve pending history saves on normal Quit
Copythat SHALL attempt to persist the latest requested history state before normal application termination completes. If that state remains unsaved, Copythat SHALL require an explicit user choice.

#### Scenario: Latest history state saves during Quit
- **WHEN** the user quits while a history save is pending
- **AND** the latest requested state is successfully saved
- **THEN** Copythat completes normal termination

#### Scenario: Latest history state remains unsaved during Quit
- **WHEN** the latest requested state remains unsaved after a flush attempt
- **THEN** Copythat offers Retry, Quit Anyway, and Cancel Quit
- **AND** Copythat does not silently terminate

#### Scenario: User retries an unsaved Quit
- **WHEN** the user selects Retry
- **THEN** Copythat retries saving the latest state before resolving termination

#### Scenario: User accepts an unsaved Quit
- **WHEN** the user selects Quit Anyway
- **THEN** Copythat terminates with the previously committed history intact

#### Scenario: User cancels an unsaved Quit
- **WHEN** the user selects Cancel Quit
- **THEN** Copythat remains open with its current in-memory history

### Requirement: Clear clipboard history manually
Copythat SHALL support manual clearing of stored clipboard history while protecting intentionally saved cards by default.

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

### Requirement: Removed current clipboard cards are not recaptured
Copythat SHALL prevent removed cards that match current or pending pasteboard content from returning to clipboard history unless the user copies that content again.

#### Scenario: Delete current image card
- **WHEN** the user deletes an image card that matches the current general pasteboard content
- **THEN** Copythat removes the card from history
- **AND** Copythat clears the matching general pasteboard content
- **AND** Copythat does not recapture that image from stale pasteboard state

#### Scenario: Pending image capture finishes after deletion
- **WHEN** image capture is still encoding a history item for content the user has removed
- **THEN** Copythat does not insert the encoded image into history

#### Scenario: Delete older history card
- **WHEN** the user deletes a history card that does not match the current general pasteboard content
- **THEN** Copythat removes the card from history
- **AND** Copythat keeps the current general pasteboard content available

#### Scenario: Copy same content again after deletion
- **WHEN** the user copies the same image again after deleting its prior card
- **THEN** Copythat can record the new copy as a history item

### Requirement: Support pinning and pinboards
Copythat SHALL let users pin items and assign items to custom pinboards.

#### Scenario: Item is pinned
- **WHEN** the user pins a history item
- **THEN** the item remains marked as pinned and is eligible for the pinned pinboard

#### Scenario: Item is moved to custom pinboard
- **WHEN** the user moves a history item to a custom pinboard
- **THEN** Copythat assigns the item to that pinboard
- **AND** the item is pinned

### Requirement: Track source context
Copythat SHALL show the source application name and the source icon captured for each clipboard history item when source metadata is available. When a pending pasteboard change count is first observed, Copythat SHALL capture the frontmost application at that moment as the first-observed source candidate. If a newer count arrives before the pending count is confirmed stable, Copythat SHALL replace the pending count and candidate together. Source attribution for captures without keyboard copy-shortcut evidence SHALL prefer the candidate paired with the final stable count over the application frontmost at capture confirmation.

#### Scenario: Source app is resolved
- **WHEN** Copythat captures an item and can resolve the source app
- **THEN** the history item displays the source app name
- **AND** the app icon captured for that item is available in the panel when icon data exists

#### Scenario: Source app is unknown
- **WHEN** Copythat cannot resolve the source app
- **THEN** the history item remains usable with an unknown source label

#### Scenario: Multiple visible items have distinct captured source icons
- **WHEN** the panel displays multiple history items with different captured source icons
- **THEN** each history card displays the icon captured for that specific item
- **AND** adding or displaying a later item MUST NOT replace the source icon shown on an earlier item

#### Scenario: Later capture does not rewrite earlier source context
- **WHEN** a later pasteboard capture is attributed to a different app
- **THEN** Copythat MUST NOT replace an earlier card's captured source app name or source icon with the later app's metadata

#### Scenario: Non-keyboard copy keeps the app that was frontmost when the pasteboard changed
- **WHEN** an application writes to the pasteboard without a keyboard copy shortcut (for example a context-menu Copy or a web-page copy button)
- **AND** that application remains frontmost when Copythat first observes the change count that ultimately stabilizes
- **AND** the user switches to a different application before Copythat confirms the pasteboard content is stable
- **THEN** the captured item is attributed to the application that was frontmost when the pasteboard change was first observed
- **AND** the item is not attributed to the application that became frontmost before capture confirmation

#### Scenario: A newer change count replaces the pending observation
- **WHEN** Copythat has recorded a pending change count and first-observed source candidate
- **AND** a newer pasteboard change count arrives before the pending count is confirmed stable
- **THEN** Copythat replaces the pending count and source candidate together
- **AND** the final captured content is not attributed using a candidate paired with an earlier count

#### Scenario: Keyboard copy shortcut evidence still wins
- **WHEN** a copy or cut keyboard shortcut precedes the pasteboard change
- **AND** the frontmost application changes between the shortcut and capture confirmation
- **THEN** the captured item is attributed to the app recorded at shortcut time

#### Scenario: First-observed snapshot is not a valid source candidate
- **WHEN** the application frontmost at first observation is not a valid source candidate (for example Copythat itself)
- **THEN** source resolution falls back to the existing candidates in order: capture-time frontmost app, recent foreground app, system, or unknown

### Requirement: Diagnose clipboard capture decisions
Copythat SHALL provide a default-off diagnostic mode that records safe runtime metadata for clipboard capture, source attribution, duplicate-content insertion decisions, and source-attribution timing.

#### Scenario: Diagnostics are disabled by default
- **WHEN** Copythat monitors pasteboard changes with no clipboard diagnostics flag enabled
- **THEN** Copythat does not emit clipboard diagnostics events
- **AND** clipboard history behavior remains unchanged

#### Scenario: Diagnostics record source and duplicate metadata
- **WHEN** clipboard diagnostics are enabled and a supported pasteboard item is captured
- **THEN** Copythat emits diagnostics that identify the captured item kind, resolved source app, pasteboard change-count context, content identity digest, duplicate-match status, and item counts before and after insertion
- **AND** Copythat does not change captured item content, source attribution, duplicate-content behavior, selection, or persistence as part of diagnostics

#### Scenario: Diagnostics expose source-attribution event ordering
- **WHEN** clipboard diagnostics are enabled and Copythat observes and resolves a pasteboard change
- **THEN** Copythat emits monotonic timing metadata for the first observation and final source-resolution decision
- **AND** applicable application-activation and copy-or-cut-shortcut events include monotonic timing and pasteboard change-count metadata
- **AND** the resolution event identifies the selected source-resolution slot and resolved source app

#### Scenario: Diagnostics avoid clipboard payloads
- **WHEN** clipboard diagnostics are enabled for text, URL, file, image, or sensitive-content pasteboard changes
- **THEN** Copythat MUST NOT log raw copied text, complete URLs, file paths, image data, unique acceptance markers, or other restorable clipboard payload values

### Requirement: Preserve pinboard assignments across pinboard rename
Copythat SHALL keep clipboard history items attached to a custom pinboard when that pinboard is renamed, and SHALL persist the migrated assignments.

#### Scenario: Assigned items follow the rename
- **WHEN** a custom pinboard is renamed
- **THEN** every history item assigned to the pinboard's old name becomes assigned to the new name
- **AND** history items assigned to other pinboards or to no pinboard are unchanged
- **AND** no history item is deleted, unpinned, or otherwise modified

#### Scenario: Migrated assignments survive relaunch
- **WHEN** Copythat starts after a custom pinboard was renamed in a previous session
- **THEN** previously assigned history items are loaded with the pinboard's new name as their assignment
- **AND** the pinboard's edited color is restored

### Requirement: Preserve eager URL metadata enrichment
Copythat SHALL eagerly request link metadata for newly inserted URL history items that need enrichment, independently of panel visibility. Metadata completion SHALL distinguish request failure or cancellation from success with no usable image, including success with neither title nor image. Metadata enrichment MUST NOT invoke Copythat's browser snapshot fallback. Available metadata title and image SHALL remain usable by existing cards and search.

#### Scenario: Copy URL while panel is closed
- **WHEN** a new URL is inserted while the panel is closed and metadata succeeds with a title but no usable image
- **THEN** the title is saved and searchable
- **AND** Copythat does not create or invoke a browser snapshot fallback

#### Scenario: Metadata supplies an image or icon
- **WHEN** metadata enrichment supplies a usable preview image through the image or icon source
- **THEN** Copythat saves and displays that image through the existing preview path
- **AND** opening the panel and selecting the item does not start browser fallback

#### Scenario: Metadata fails
- **WHEN** the metadata request fails
- **THEN** the URL remains available with its existing card content
- **AND** no browser fallback is started as recovery for that failure

#### Scenario: Metadata succeeds without any preview fields
- **WHEN** metadata completes successfully with neither title nor usable image
- **THEN** the item can become eligible for on-demand browser fallback
- **AND** empty metadata does not clear existing title or image data

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

### Requirement: Keep browser fallback single and cancellable
Copythat SHALL run at most one active browser snapshot fallback, including resource cleanup during cancellation. The latest selected eligible URL SHALL replace any earlier desired target; a replacement MUST NOT start until the previous request has released its application-owned browser resources. Selection change and panel close SHALL cancel invalid fallback. Deletion, history eviction and Clear History SHALL cancel metadata and fallback work for the actual removed items.

#### Scenario: Rapid selection changes
- **WHEN** snapshot A is in flight and selection changes to B and then C before A has finished cleanup
- **THEN** A is cancelled and cleaned up
- **AND** only the latest still-valid target C is started after cleanup
- **AND** maximum simultaneous active browser fallback remains one

#### Scenario: Close panel during fallback
- **WHEN** the panel closes while a fallback is loading or taking a snapshot
- **THEN** the request stops loading, detaches navigation callbacks and releases application-owned browser resources
- **AND** a late result does not update history or request persistence

#### Scenario: Remove item with pending work
- **WHEN** an item with pending metadata or fallback is deleted, evicted by the history limit, or removed by Clear History
- **THEN** its work is cancelled and its transient item state is removed
- **AND** late results cannot restore the item, update another item, or request persistence

#### Scenario: Partially clear history
- **WHEN** Clear History removes ordinary items while retaining pinned or pinboard items
- **THEN** work for removed items is cancelled
- **AND** retained items remain governed by the current visibility and selection conditions

#### Scenario: Cancel before snapshot submission
- **WHEN** cancellation occurs before snapshot submission, including during navigation or deadline waiting
- **THEN** no subsequent takeSnapshot call occurs for that request
- **AND** cancellation is not swallowed by a wait operation

#### Scenario: Navigation timeout and cancellation race
- **WHEN** navigation, timeout, cancellation or snapshot completion callbacks overlap
- **THEN** the request reaches its terminal state exactly once and releases its waiter exactly once
- **AND** callbacks arriving after the terminal state cannot submit another snapshot or change request state

### Requirement: Bound temporary browser rendering
Copythat SHALL attempt a browser snapshot promptly after navigation completes, without an unconditional three-second wait. If navigation has not completed within three seconds, it SHALL attempt a snapshot of the current page state unless the request has failed or been cancelled. Snapshot callback waiting SHALL be bounded by an additional two seconds. Browser fallback SHALL use non-persistent website data and SHALL NOT require persistent cookies, local storage, login state or a disk website cache.

#### Scenario: Page finishes early
- **WHEN** navigation finishes before the three-second deadline
- **THEN** snapshot submission proceeds without waiting for the unused navigation deadline

#### Scenario: Page has not finished at deadline
- **WHEN** the three-second navigation deadline expires while the request remains valid
- **THEN** Copythat attempts a snapshot of current page state at most once
- **AND** a missing snapshot callback becomes a failure after the additional two-second deadline rather than occupying the active slot indefinitely

#### Scenario: Navigation fails
- **WHEN** navigation fails or the browser content process terminates before snapshot submission
- **THEN** fallback ends as a failure and releases its resources
- **AND** existing URL content remains usable

#### Scenario: Late navigation failure after snapshot submission
- **WHEN** navigation reports failure after a snapshot has already been submitted
- **THEN** the snapshot callback or its deadline determines the result without another submission
- **AND** browser content process termination during snapshot waiting instead ends the request as a failure and releases its resources

#### Scenario: Temporary website state
- **WHEN** Copythat creates a browser fallback request
- **THEN** its website data is non-persistent
- **AND** no browser login-state reuse or disk preview cache is introduced

### Requirement: Reuse session browser previews and suppress repeated failures
Copythat SHALL reuse successful browser snapshots across eligible items with the same complete URL absoluteString within the application session, subject to a bounded memory cache of at most 64 entries. It SHALL NOT strip query parameters from cache identity. Actual browser fallback failure SHALL suppress another attempt for that URL for five minutes while its failure entry remains retained; cancellation SHALL NOT create a failure entry. Negative cache state SHALL also be bounded to at most 64 entries, with expired entries cleared and the earliest expiry evicted when capacity is exceeded. Cache and retry state SHALL NOT be persisted.

#### Scenario: Same URL is requested again
- **WHEN** an eligible selected URL has a successful snapshot still in the session cache
- **THEN** Copythat applies the cached image without starting another browser loader
- **AND** a different query string does not share that cache entry

#### Scenario: Immediate retry after failure
- **WHEN** a URL fallback fails and the user reselects it before five minutes have elapsed
- **THEN** Copythat does not start another browser fallback for that URL

#### Scenario: Retry TTL expires
- **WHEN** five minutes have elapsed since failure and the user reopens the panel or reselects the eligible URL
- **THEN** Copythat can request browser fallback again
- **AND** no background retry timer is required

#### Scenario: Explicitly select the current item after TTL expiry
- **WHEN** the user explicitly selects the already selected eligible URL after its failure TTL expires
- **THEN** Copythat reevaluates retry eligibility even though the selected item ID has not changed
- **AND** selecting the current item during an active request does not restart that request

#### Scenario: Reopen after cancellation
- **WHEN** closing the panel cancels a fallback and the user reopens it with that eligible URL selected
- **THEN** cancellation alone does not suppress a new attempt
- **AND** the new attempt still waits for any previous resource cleanup

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
Copythat SHALL use the same image content key for equal stored bytes whether eager or represented by their persisted SHA256 address, preserving duplicate detection, deletion suppression and current-pasteboard matching without loading the stored blob. Model transformations SHALL preserve unloaded references and SHALL establish the new payload's correct content address when they replace its bytes with a different payload. Resident image content-key access SHALL reuse the known address without hashing bytes again.

#### Scenario: Copy an existing lazy image
- **WHEN** a newly captured image has the same stored bytes as a restored unloaded image
- **THEN** their content keys are identical and existing pinned/unpinned duplicate rules apply

#### Scenario: Delete a current lazy image
- **WHEN** the user removes an unloaded restored image matching the current pasteboard
- **THEN** the matching pasteboard is cleared and stale capture cannot reinsert it
- **AND** this identity comparison does not read the history blob

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
Copythat SHALL read and verify persisted heavy media outside MainActor and reuse successful loads through a byte-cost LRU cache keyed by blob ID with an internal 32 MiB budget. The same cache SHALL accept trusted finalized resident media after successful durable commit and before history releases those bytes, without disk reads, hashing, or re-encoding. Each hit SHALL refresh recency; insertion and eviction SHALL keep retained byte cost within budget, including repeated identities. A single blob exceeding the budget SHALL be returned by a load without caching and SHALL be skipped by committed-media seeding without preventing history release. Loading and seeding SHALL NOT populate the history array with media bytes, request persistence, change selection or start link enrichment. Actual disk reads SHALL retain existing integrity verification.

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

#### Scenario: Reuse freshly committed media
- **WHEN** committed resident media is seeded and requested while still retained in the cache
- **THEN** seeding and the subsequent cache hit perform zero disk reads and zero media hashes
- **AND** the returned bytes match the finalized payload without re-encoding

#### Scenario: Batch seeding respects the budget
- **WHEN** committed-media seeding includes repeated identities or combined media larger than the budget
- **THEN** each retained identity is accounted for once and LRU eviction preserves the byte budget
- **AND** an evicted media identity can be released from history and subsequently loaded from disk

#### Scenario: Oversized committed media
- **WHEN** successfully committed resident media individually exceeds the cache budget
- **THEN** seeding does not retain it or increase the budget
- **AND** matching history ownership can still be released
- **AND** subsequent access reads and verifies the durable blob

### Requirement: Release resident heavy media after durable commit
Copythat SHALL eventually release resident image and link-preview image bytes from history and its filtered copies after the corresponding item and media identity have successfully completed the existing blob-first, atomic-manifest persistence transaction and release no longer disrupts visible previews. Release MUST preserve stable blob references, all item metadata, source icons, content identity, payload presence, and search and organization behavior. Copythat MUST NOT release an identity that has not successfully committed, infer commitment from a requested save or elapsed time, or request persistence solely because residency changed.

#### Scenario: Image commits while history is not visible
- **WHEN** a snapshot containing resident image bytes successfully commits and history is not visible
- **THEN** matching image bytes are released from both history and filtered history after committed-media cache seeding
- **AND** the image reference, metadata, content key, and image payload presence remain unchanged
- **AND** release requests no additional save generation or manifest write

#### Scenario: Link-preview image commits
- **WHEN** a snapshot containing a resident link-preview image successfully commits and release will not disrupt a visible preview
- **THEN** matching preview bytes are released from history and filtered history after committed-media cache seeding
- **AND** its image reference, link title, restorable URL, source context, and pinboard state remain unchanged
- **AND** the image remains present for enrichment eligibility without another metadata or browser request

#### Scenario: Save fails and is retried
- **WHEN** a required blob write or manifest commit fails for resident heavy media
- **THEN** that failed transaction does not authorize release or committed-media seeding
- **AND** uncommitted resident bytes and the latest retry snapshot remain available
- **WHEN** retry successfully commits the matching media identity
- **THEN** the bytes become eligible for release under the same visibility and identity rules
- **AND** normal Quit retains its Retry, Quit Anyway, and Cancel Quit behavior

#### Scenario: Older commit meets a newer payload
- **WHEN** an older generation commits media A for an item whose current resident media of that role is B with a different blob identity
- **THEN** the older commit does not release B
- **AND** B remains resident until its own identity successfully commits
- **AND** image and link-preview image eligibility are evaluated independently

#### Scenario: Intermediate snapshots are coalesced
- **WHEN** pending generations are superseded while another generation is saving
- **THEN** only snapshots that actually commit authorize media release
- **AND** an older successful generation does not discard the latest pending or failed retry snapshot

#### Scenario: Latest retry snapshot is no longer needed
- **WHEN** the latest requested generation successfully commits
- **THEN** the save coordinator stops retaining that snapshot for retry
- **AND** callback completion leaves no durable-release queue retaining its media bytes

#### Scenario: Media commits while previews are visible
- **WHEN** resident media commits while its preview is visible
- **THEN** committed bytes are offered to the bounded cache without a resident-to-placeholder display regression
- **AND** history ownership is released when the visibility boundary permits it
- **AND** reopening uses the existing on-demand media path

#### Scenario: State changes during committed-media handling
- **WHEN** an item is removed or replaced, or the panel closes or reopens, while committed-media seeding is pending
- **THEN** release uses the current item identity and visibility when seeding completes
- **AND** removed items are not recreated, newer unmatched media remain resident, and visible previews remain stable

#### Scenario: Flush waits for committed-media handling
- **WHEN** a normal save flush is waiting on a successful commit whose media handling is still in progress
- **THEN** successful flush completion waits for cache seeding and the release-or-defer decision
- **AND** a visible panel does not make flush wait for the user to close it

#### Scenario: Metadata changes after release
- **WHEN** a released image or preview item is pinned, moved to a pinboard, or affected by pinboard rename
- **THEN** its blob references and content identity survive the mutation and subsequent save
- **AND** the metadata operation performs zero heavy-media reads and zero media hashes

#### Scenario: Paste and drag after release
- **WHEN** a user pastes or drags an image whose resident history bytes have been released
- **THEN** the existing on-demand media path supplies its image payload
- **AND** residency alone does not cause a missing payload, text fallback, or link-preview refetch
- **AND** actual blob-read failures retain the existing local failure behavior

### Requirement: Reuse prepared source application icons
Copythat SHALL reuse a successfully prepared source application icon's bytes and established SHA256 content address across observations of the same reliably identified running application while its cache entry remains retained. A cache hit MUST perform zero application-icon retrievals, rasterizations, PNG encodings, and media identity hashes. Each miss or uncached observation SHALL attempt the existing bounded 160px PNG preparation at most once and establish at most one identity hash, only when preparation succeeds. Source-icon cache state SHALL be session-only, owned by source tracking, and bounded to at most 32 successful entries with least-recently-used eviction. Reuse MUST preserve existing source-attribution precedence, per-observation capture timestamp and pasteboard change-count context, and per-item captured icon correctness.

#### Scenario: Repeated observations while the entry is retained
- **WHEN** Copythat successfully prepares an icon for a reliably identified running source application and observes that same identity multiple times while its entry remains retained
- **THEN** only the first observation retrieves and prepares the icon and establishes its content address
- **AND** subsequent observations reuse identical icon bytes and content address without retrieval, rendering, encoding, or identity hashing
- **AND** each observation receives its own supplied capture timestamp and pasteboard change-count context, including absent change counts

#### Scenario: Different process generations or installation locations
- **WHEN** a source application has a different process identifier, launch date, or bundle location from a retained application identity
- **THEN** Copythat resolves and prepares its icon independently of that entry
- **AND** restarting an application or reusing a PID with a different launch date does not reuse the prior process generation's entry
- **AND** sharing a display name or bundle identifier does not cause distinct running identities to share an entry

#### Scenario: Reliable process generation is unavailable
- **WHEN** a source candidate has no valid positive process identifier or its launch date is unavailable
- **THEN** Copythat performs normal source attribution and attempts icon preparation for that observation without consulting or populating the source-icon cache
- **AND** unavailable identity metadata does not cause rejection of an otherwise valid source candidate
- **AND** a later observation with a reliable identity can establish a cache entry

#### Scenario: Icon preparation is unavailable
- **WHEN** source icon preparation fails to produce PNG bytes
- **THEN** Copythat continues source attribution with the resolved application name and no icon
- **AND** that failure creates no cache entry and does not evict a successful entry
- **AND** a later observation can retry and cache a successful preparation

#### Scenario: Least recently used entry is evicted
- **WHEN** a successful insertion exceeds the cache capacity
- **THEN** Copythat evicts the least recently used successful entry and retains no more than the capacity
- **AND** each cache hit refreshes that entry's recency
- **AND** observing an evicted identity can prepare its icon again even if the application is still running

#### Scenario: Eviction preserves captured history
- **WHEN** a source-icon entry is evicted or a later application observation supplies a different icon
- **THEN** already created source observations and history items retain their captured icon bytes and content address
- **AND** earlier cards do not change source name or icon because of cache mutation

#### Scenario: Prepared identity is forwarded through capture and save
- **WHEN** a retained prepared source icon is used to capture a text, URL, file, or image item and persist that item
- **THEN** the source icon's established content address is forwarded with its bytes without another source-icon identity hash or encoding
- **AND** history uses the existing persistence schema and keeps its existing integrity verification on actual blob reads
