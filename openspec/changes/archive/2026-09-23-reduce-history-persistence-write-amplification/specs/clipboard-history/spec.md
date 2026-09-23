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

## ADDED Requirements

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
