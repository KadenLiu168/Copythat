## ADDED Requirements

### Requirement: Delete custom pinboards from the panel
Copythat SHALL let users delete custom pinboards from the bottom panel while preserving all clipboard history items.

#### Scenario: Custom pinboard delete action is available
- **WHEN** the user opens the context menu for a custom pinboard filter in the bottom panel
- **THEN** Copythat shows an action to delete that custom pinboard

#### Scenario: Built-in pinboards cannot be deleted
- **WHEN** the user opens or uses the Clipboard or Pinned filter controls
- **THEN** Copythat does not offer an action to delete those built-in pinboards

#### Scenario: User cancels custom pinboard deletion
- **WHEN** the user chooses to delete a custom pinboard and then cancels the confirmation
- **THEN** Copythat keeps the custom pinboard
- **AND** clips assigned to that pinboard remain assigned to it

#### Scenario: User confirms custom pinboard deletion
- **WHEN** the user confirms deletion of a custom pinboard
- **THEN** Copythat removes that custom pinboard from the panel
- **AND** Copythat does not delete any clipboard history items
- **AND** clips assigned to the deleted pinboard are moved out of that pinboard

#### Scenario: Deletion confirmation shows affected clips
- **WHEN** Copythat asks the user to confirm deletion of a custom pinboard
- **THEN** the confirmation identifies the pinboard by name
- **AND** the confirmation states how many clips will be moved out of that pinboard

#### Scenario: Current custom pinboard is deleted
- **WHEN** the user confirms deletion of the currently selected custom pinboard
- **THEN** Copythat selects the Clipboard filter
- **AND** Copythat preserves the current search query

#### Scenario: Non-selected custom pinboard is deleted
- **WHEN** the user confirms deletion of a custom pinboard that is not the currently selected filter
- **THEN** Copythat keeps the current filter selected
- **AND** Copythat preserves the current search query
