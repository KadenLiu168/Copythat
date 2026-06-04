## ADDED Requirements

### Requirement: Display a clear panel command bar
Copythat SHALL present the bottom panel header as a compact command bar that visually separates search, pinboard filtering, and the add/settings action without changing their behavior.

#### Scenario: Panel header displays default controls
- **WHEN** the bottom panel is visible and search is not expanded
- **THEN** the header shows a compact search control on the left
- **AND** shows the available pinboard filters as a grouped horizontal control in the center
- **AND** shows a compact add/settings control on the right

#### Scenario: Selected pinboard remains clear
- **WHEN** a pinboard filter is selected
- **THEN** the selected filter is visually distinct from unselected filters
- **AND** the selected state does not visually dominate the clipboard item cards

#### Scenario: Search expands without breaking header layout
- **WHEN** the user expands search or enters a search query
- **THEN** the search field remains in the left command bar area
- **AND** the pinboard filters remain horizontally scrollable when space is constrained
- **AND** the add/settings control remains available on the right

#### Scenario: Header controls provide interaction feedback
- **WHEN** the user hovers, presses, or focuses a top command bar control
- **THEN** Copythat provides visible feedback appropriate for a compact macOS utility panel
