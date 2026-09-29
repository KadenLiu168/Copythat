## MODIFIED Requirements

### Requirement: Toggle panel preview privacy
Copythat SHALL let users hide and restore visible history card previews from a global privacy control in the bottom panel command bar.

#### Scenario: Privacy control is shown in the command bar
- **WHEN** the bottom panel displays its command bar
- **THEN** Copythat shows a privacy visibility control after the pinboard filters
- **AND** the privacy visibility control appears before the new-pinboard `+` control
- **AND** the privacy visibility control remains available when custom pinboard filters overflow into a horizontal scrolling region

#### Scenario: User hides previews
- **WHEN** the user activates the privacy visibility control while previews are visible
- **THEN** Copythat hides preview content for every visible history card
- **AND** each card still shows its item kind, relative timestamp, source context, selection state, and available item actions
- **AND** search, pinboard filtering, paste, drag, pin, move-to-pinboard, and delete behavior remain available

#### Scenario: User restores previews
- **WHEN** the user activates the privacy visibility control while previews are hidden
- **THEN** Copythat restores normal preview rendering for every visible history card

#### Scenario: Privacy mode does not change history data
- **WHEN** the user hides or restores previews
- **THEN** Copythat does not modify captured clipboard history, sensitive-content recording, pinboard assignments, persisted items, or restorable pasteboard content

#### Scenario: Browse lazy media with previews hidden
- **WHEN** Hide Previews is enabled and restored image or URL cards enter the displayed timeline
- **THEN** preview display initiates zero image/link-image blob reads
- **AND** enabling privacy cancels UI-owned loading and rejects its late results
- **AND** explicit paste or drag remains available and can load the payload required by that action

## ADDED Requirements

### Requirement: Display lazy media only while eligible
Copythat SHALL load persisted image/link-image previews only for cards entering the lazy display path while the panel is visible and previews are enabled. Closing the panel SHALL revoke eligibility even when its hosting view remains retained. Card disappearance, removal, changed media identity, panel close or preview concealment SHALL cancel UI-owned loading and prevent stale result application. Temporary card media SHALL be released when no longer needed instead of accumulating across retained cards.

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

### Requirement: Keep lazy preview layout stable
Copythat SHALL reserve the existing image card region and a URL preview's 105pt image region whenever the corresponding payload exists, including while loading or after access failure. Image presentation SHALL preserve the existing complete aspect ratio and bounded content region. URL typography and spacing SHALL use payload existence so completion does not switch from text-only layout.

#### Scenario: URL image arrives late
- **WHEN** a displayed URL references an unloaded preview image
- **THEN** its image region, title typography and spacing are established before completion
- **AND** loading or failure keeps that layout and uses a placeholder or fallback until successful display

#### Scenario: Image card is loading
- **WHEN** an image payload has not materialized yet
- **THEN** a fixed-region placeholder or progress indicator preserves the card and header geometry

### Requirement: Drag restored images as images
Copythat SHALL provide an image representation for restored image drag, materializing a persisted payload only when required by the drag consumer. An unloaded or failed image SHALL NOT be substituted with the item's textual preview. Existing text, URL and file drag behavior SHALL be preserved.

#### Scenario: Drag an unloaded image
- **WHEN** the user drags an unloaded restored image and the receiver requests its image representation
- **THEN** the provider asynchronously obtains verified image data and returns a supported image representation
- **AND** provider creation alone does not read the heavy blob

#### Scenario: Drag payload cannot be restored
- **WHEN** the requested persisted image is missing or corrupted
- **THEN** the provider reports image-load failure without supplying corrupt bytes or a text payload
