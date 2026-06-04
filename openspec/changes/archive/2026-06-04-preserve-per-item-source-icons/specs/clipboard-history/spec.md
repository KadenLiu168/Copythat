## MODIFIED Requirements

### Requirement: Track source context
Copythat SHALL show the source application name and the source icon captured for each clipboard history item when source metadata is available.

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
