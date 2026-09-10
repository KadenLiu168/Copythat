## ADDED Requirements

### Requirement: Edit custom pinboards from the panel
Copythat SHALL let users edit the name and color of custom pinboards from the bottom panel, preserving all clipboard history items and their organization.

#### Scenario: Custom pinboard edit action is available
- **WHEN** the user opens the context menu for a custom pinboard filter in the bottom panel
- **THEN** Copythat shows an action to edit that custom pinboard
- **AND** the edit action is presented as a normal, non-destructive action distinct from the delete action

#### Scenario: Built-in pinboards cannot be edited
- **WHEN** the user opens or uses the Clipboard or Pinned filter controls
- **THEN** Copythat does not offer an action to edit those built-in pinboards

#### Scenario: Edit form shows current values
- **WHEN** the user chooses to edit a custom pinboard
- **THEN** Copythat shows a compact edit form associated with that pinboard
- **AND** the form's name field contains the pinboard's current name
- **AND** the form's fixed set of color choices marks the pinboard's current color as selected
- **AND** the name field receives editing focus
- **AND** Copythat does not open Settings

#### Scenario: User renames a custom pinboard
- **WHEN** the user enters a valid new name for a custom pinboard and confirms the edit
- **THEN** Copythat displays the pinboard under its new name immediately
- **AND** every clip that was assigned to the pinboard remains assigned to it under the new name
- **AND** no clipboard item is deleted or moved out of the pinboard
- **AND** no clip's pinned state changes
- **AND** no clip's content changes

#### Scenario: User changes only the pinboard color
- **WHEN** the user selects a different color without changing the name and confirms the edit
- **THEN** the pinboard's category marker uses the new color immediately
- **AND** clip assignments to that pinboard are unchanged

#### Scenario: User renames and recolors together
- **WHEN** the user enters a valid new name and selects a different color, then confirms the edit
- **THEN** Copythat applies the new name and the new color in a single edit
- **AND** clip assignments follow the rename as with a name-only edit

#### Scenario: User enters an invalid pinboard name
- **WHEN** the edited pinboard name is empty after trimming surrounding whitespace or exactly matches the trimmed name of a different custom pinboard
- **THEN** Copythat does not allow the edit to be saved
- **AND** keeping the pinboard's own current name is not treated as a duplicate

#### Scenario: User cancels the edit
- **WHEN** the user cancels the edit form or presses Escape while it is active
- **THEN** Copythat dismisses the edit form without changing the pinboard's name or color
- **AND** clip assignments remain unchanged

#### Scenario: Currently selected pinboard is renamed
- **WHEN** the user confirms renaming the custom pinboard that is the currently selected filter
- **THEN** Copythat keeps the renamed pinboard selected as the active filter
- **AND** Copythat does not fall back to the Clipboard filter
- **AND** Copythat preserves the current search query

#### Scenario: Non-selected pinboard is renamed
- **WHEN** the user confirms renaming a custom pinboard that is not the currently selected filter
- **THEN** Copythat keeps the current filter selected
- **AND** Copythat preserves the current search query

#### Scenario: User confirms with the keyboard
- **WHEN** the edit form contains a valid name and the user presses Return
- **THEN** Copythat saves the edit
- **AND** Copythat does not paste the selected clipboard item
