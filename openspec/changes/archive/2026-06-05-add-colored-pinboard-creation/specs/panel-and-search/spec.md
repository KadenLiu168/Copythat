## ADDED Requirements

### Requirement: Create custom pinboards from the panel
Copythat SHALL let users create a named, colored custom pinboard from the bottom-panel `+` control.

#### Scenario: User opens pinboard creation
- **WHEN** the user activates the bottom-panel `+` control
- **THEN** Copythat shows a compact creation form associated with that control
- **AND** the form provides a pinboard name field and a fixed set of color choices
- **AND** Copythat does not open Settings

#### Scenario: User creates a valid pinboard
- **WHEN** the user enters a non-empty trimmed name that is not already used by a custom pinboard, selects a color, and confirms creation
- **THEN** Copythat creates the custom pinboard with that name and color
- **AND** the new pinboard appears in the panel immediately
- **AND** the new pinboard becomes the selected filter
- **AND** no clipboard item is automatically moved into the new pinboard

#### Scenario: User enters an invalid pinboard name
- **WHEN** the entered pinboard name is empty after trimming or exactly matches an existing trimmed custom pinboard name
- **THEN** Copythat does not allow the pinboard to be created

#### Scenario: User cancels pinboard creation
- **WHEN** the user cancels the creation form or presses Escape while it is active
- **THEN** Copythat dismisses the creation form without creating a pinboard
- **AND** pressing Escape may close the bottom panel

#### Scenario: User confirms with the keyboard
- **WHEN** the creation form contains a valid name and the user presses Return
- **THEN** Copythat creates the pinboard
- **AND** Copythat does not paste the selected clipboard item

### Requirement: Display stable custom pinboard colors
Copythat SHALL display each custom pinboard using its persisted selected color from a fixed, visually consistent palette.

#### Scenario: Color choices are displayed
- **WHEN** the pinboard creation form is visible
- **THEN** Copythat offers a small fixed set of distinct color choices
- **AND** the choices have consistent perceived saturation and brightness

#### Scenario: Custom pinboard is displayed
- **WHEN** a custom pinboard filter is visible
- **THEN** its category marker uses the color selected when the pinboard was created

#### Scenario: Multiple pinboards use the same color
- **WHEN** a user selects a color already used by another custom pinboard
- **THEN** Copythat allows the new pinboard to use that color

## MODIFIED Requirements

### Requirement: Display a clear panel command bar
Copythat SHALL present the bottom panel header as a compact command bar that visually separates search, pinboard filtering, and the add-pinboard action without changing search or filtering behavior.

#### Scenario: Panel header displays default controls
- **WHEN** the bottom panel is visible and search is not expanded
- **THEN** the header shows a compact search control on the left
- **AND** shows the available pinboard filters as a grouped horizontal control in the center
- **AND** shows a compact add-pinboard control on the right

#### Scenario: Selected pinboard remains clear
- **WHEN** a pinboard filter is selected
- **THEN** the selected filter is visually distinct from unselected filters
- **AND** the selected state does not visually dominate the clipboard item cards

#### Scenario: Search expands without breaking header layout
- **WHEN** the user expands search or enters a search query
- **THEN** the search field remains in the left command bar area
- **AND** the pinboard filters remain horizontally scrollable when space is constrained
- **AND** the add-pinboard control remains available on the right

#### Scenario: Header controls provide interaction feedback
- **WHEN** the user hovers, presses, or focuses a top command bar control
- **THEN** Copythat provides visible feedback appropriate for a compact macOS utility panel
