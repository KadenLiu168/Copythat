## MODIFIED Requirements

### Requirement: Display lazy media only while eligible
Copythat SHALL load persisted image/link-image previews only for cards entering the lazy display path while the panel is visible and previews are enabled. Closing the panel SHALL revoke eligibility even when its hosting view remains retained. Card disappearance, removal, changed media identity, panel close or preview concealment SHALL cancel UI-owned loading and prevent stale result application. Temporary card media SHALL be released when no longer needed instead of accumulating across retained cards. A change between resident bytes and a persisted reference SHALL invalidate the card's display request even when the content address is unchanged, so the current payload remains displayable through the appropriate resident or on-demand path. This display contract SHALL NOT change when durable history release is permitted.

#### Scenario: Visible lazy card
- **WHEN** a restored card enters the display path with the panel visible and previews enabled
- **THEN** it uses existing in-memory bytes or requests its referenced media through on-demand loading
- **AND** cards not entering that display path do not start media reads

#### Scenario: Close retained panel during loading
- **WHEN** the panel closes while preview media is loading and its hosting view remains retained
- **THEN** no further visible-media loads start and UI-owned requests are cancelled
- **AND** late completion does not apply to the hidden panel or a later reopened card request

#### Scenario: Remove or replace loading card
- **WHEN** a loading card disappears, is evicted or deleted, or changes its media reference
- **THEN** its old completion cannot update a surviving or replacement card

#### Scenario: Replace inline media on the same card
- **WHEN** the same item ID changes from a persisted reference to inline media or replaces existing inline media
- **THEN** the card displays the current payload and rejects completion for the prior payload

#### Scenario: Close and reopen before an intermediate render
- **WHEN** panel close and reopen occur before the retained card renders the closed state
- **THEN** the previous display request remains invalid and cannot apply merely because visibility is true again

#### Scenario: Resident image becomes a reference with the same address
- **WHEN** an eligible visible card receives a replacement item whose image or link-image bytes have been released while its item ID, content address, metadata and panel authorization remain unchanged
- **THEN** the card requests the referenced payload through the existing on-demand path
- **AND** successful loading displays the same content and removes the loading indicator without changing card geometry
- **AND** an existing cache hit is permitted to satisfy the request without disk reads

#### Scenario: Reference becomes resident with the same address
- **WHEN** an eligible visible card receives resident bytes matching its existing image or link-image content address
- **THEN** the card displays those resident bytes and clears its prior temporary lazy-media state
- **AND** a pending completion from the superseded lazy request cannot repopulate that state
- **AND** displaying the resident payload does not start a new blob read

#### Scenario: Reopened card starts a current request
- **WHEN** a retained card renders the reopened panel under a newer authorization generation with an unloaded payload
- **THEN** it can start a new authorized display request and successfully show its payload
- **AND** a completion belonging to the older generation remains invalid

#### Scenario: Residency changes while media display is hidden
- **WHEN** an image or link-image card changes between resident bytes and a persisted reference while the panel is hidden or previews are concealed
- **THEN** that change does not initiate a preview blob read
- **AND** scrolling concealed cards continues to initiate zero preview blob reads

## ADDED Requirements

### Requirement: Reconcile cards using established media identities
At the boundary between persisted media references and native card display, Copythat SHALL reuse each payload's established content address and its residency in the history item to distinguish render changes, without comparing or hashing media bytes for card render equality or display-task identity. This SHALL apply to image, link-image and captured source-icon render identities; source-icon native image-view identity SHALL reuse the established icon content address without hashing icon bytes. Card reconciliation SHALL continue to reflect all metadata affecting displayed content, source appearance, item actions and drag content, together with selection, pinboards, preview privacy, panel visibility and authorization. It SHALL NOT change global history-item equality or the persistence format.

#### Scenario: Same payload and residency are rendered again
- **WHEN** card metadata, external display inputs, all media content addresses and all item residency states are unchanged
- **THEN** card render reconciliation treats the input as unchanged without a media-byte comparison or a new media identity hash

#### Scenario: Media identity or residency changes
- **WHEN** an image, link-image or source-icon content address changes, or its bytes become resident or nonresident with the same address
- **THEN** card render reconciliation treats the input as changed
- **AND** image and link-image residency or address changes invalidate their prior display-task identity

#### Scenario: Card metadata or actions change
- **WHEN** an item's title, preview, kind, source app, creation time, pin state, pinboard assignment, text value, file URLs or link title changes
- **THEN** the card updates the affected display or actions instead of retaining stale input

#### Scenario: Captured source icons keep their own content identities
- **WHEN** cards display captured source icons
- **THEN** equal icon content addresses have equal native source-icon content identities and different addresses have different identities
- **AND** each card displays its own captured icon rather than another card's icon

#### Scenario: Source icon residency changes
- **WHEN** a card's source-icon bytes become available or unavailable while the icon content address remains unchanged
- **THEN** the card updates between the real icon and its fallback source appearance without hashing icon bytes for view identity
