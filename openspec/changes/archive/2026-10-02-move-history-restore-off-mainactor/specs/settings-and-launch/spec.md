## MODIFIED Requirements

### Requirement: Launch responsively with persisted history
Copythat SHALL avoid repeating expensive media transformation work when restoring clipboard items that are already stored in the current persistence format. Production startup SHALL construct usable in-memory application state and begin clipboard monitoring on its ordinary launch schedule without awaiting persisted-history restoration. History file reads, JSON decoding, V2 blob-reference validation, source-icon blob reads and SHA256 integrity verification, and restored item/search-corpus construction MUST execute outside MainActor. Final policy application, filtering, selection and observable state publication remain MainActor-owned.

#### Scenario: Application launches with image-heavy history
- **WHEN** Copythat launches with persisted clipboard history containing images and source icons
- **THEN** Copythat restores the persisted items without re-encoding each item's stored media
- **AND** the menu bar application becomes usable without waiting for redundant media transformation
- **AND** persisted-history file/decode/icon integrity/model construction work does not execute on MainActor

#### Scenario: Restore loader has not completed
- **WHEN** persisted-history loading is suspended during production-style startup
- **THEN** application and Store construction have already returned with an explicit loading-history state
- **AND** MainActor can continue processing events and normal clipboard monitoring can start without releasing that loader
- **AND** supported stable copies remain eligible for startup retention under existing capture rules

#### Scenario: V2 media remains lazy through production bootstrap
- **WHEN** production bootstrap restores 500 media-heavy V2 items with four shared source icons
- **THEN** restore reads the manifest once and each shared source-icon blob once
- **AND** restore reads zero heavy image or link-image blobs
- **AND** heavy Data remains absent, blob IDs and content keys remain intact, and retained metadata is searchable

#### Scenario: Explicit in-memory startup remains synchronous
- **WHEN** application construction receives explicit initial items, including an explicitly empty list used for isolated verification
- **THEN** their permitted retained history is immediately available without invoking a persisted-history loader
- **AND** startup does not enter a history-restoring state

### Requirement: Manually clear clipboard cards from Settings
Copythat SHALL let users manually clear clipboard cards from the native Settings surface when history restoration is complete and no normal-Quit admission pause is active. While history is loading, Settings SHALL identify the card count as loading rather than authoritative zero, and clear actions MUST be disabled and rejected without affecting stored history, startup captures or accepted image eligibility.

#### Scenario: Settings shows card clearing controls
- **WHEN** the user opens Settings after history is ready and no Quit admission pause is active
- **THEN** Copythat shows the current clipboard card count
- **AND** Copythat offers a clear-cards action when cards exist

#### Scenario: Clear action requires confirmation
- **WHEN** the user activates an available clear-cards action
- **THEN** Copythat asks the user to confirm a destructive clear operation with concise copy
- **AND** Copythat offers a "Clear Regular Cards" choice for the default protected clear mode
- **AND** Copythat explains that regular cards exclude pinned cards and cards in pinboards
- **AND** Copythat offers a separate "Clear All Cards" choice

#### Scenario: No cards are available to clear
- **WHEN** restoration is complete and no clipboard cards are stored
- **THEN** Copythat disables the clear-cards action

#### Scenario: Settings opens during restoration
- **WHEN** the user opens Settings while history is loading
- **THEN** the card-count area indicates loading and Clear Cards is unavailable
- **AND** changing the history limit and unrelated settings remains available

#### Scenario: Clear callback runs while mutation is unavailable
- **WHEN** a clear confirmation is invoked during restoration or a Quit admission pause
- **THEN** it performs no deletion, pasteboard clear, image invalidation or save request
- **AND** it is not deferred until mutation becomes available
