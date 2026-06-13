## MODIFIED Requirements

### Requirement: Display a clear panel command bar
Copythat SHALL present the bottom panel header as a compact command bar that visually separates search, pinboard filtering, and the add-pinboard action without changing search or filtering behavior. Non-Clipboard pinboard filters SHALL use vivid circular category markers that preserve their configured colors.

#### Scenario: Panel header displays default controls
- **WHEN** the bottom panel is visible and search is not expanded
- **THEN** the header shows a compact search control on the left
- **AND** shows the available pinboard filters as a grouped horizontal control in the center
- **AND** shows a compact add-pinboard control on the right

#### Scenario: Pinboard categories show vivid circular markers
- **WHEN** Pinned and custom pinboard filters are visible
- **THEN** each filter shows a compact circular category marker
- **AND** each custom pinboard marker uses its configured color
- **AND** the Clipboard filter continues to use its history icon

#### Scenario: Category markers remain vivid across filter states
- **WHEN** a non-Clipboard pinboard filter is selected or unselected
- **THEN** its circular category marker retains a strongly saturated appearance
- **AND** selection remains visually distinct without relying on muting the category marker

#### Scenario: Category markers adapt to appearance
- **WHEN** Copythat is displayed in Aqua or Dark Aqua
- **THEN** the category markers remain clear and visually consistent with macOS

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
