## ADDED Requirements

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
