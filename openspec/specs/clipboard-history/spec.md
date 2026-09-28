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
