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
