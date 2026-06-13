## MODIFIED Requirements

### Requirement: Display a clear panel command bar
Copythat SHALL present the bottom panel header as one compact centered command group containing search, pinboard filtering, and the add-pinboard action without changing search or filtering behavior. Non-Clipboard pinboard filters SHALL use vivid circular category markers that preserve their configured colors.

#### Scenario: Panel header displays default controls
- **WHEN** the bottom panel is visible and search is not expanded
- **THEN** the header shows search, Clipboard, the available pinboard filters, and add-pinboard together as one horizontally centered command group
- **AND** Clipboard appears within the pinboard filter group
- **AND** the gap between command groups is visibly larger than the gap between individual pinboard filters

#### Scenario: Pinboard categories show vivid circular markers
- **WHEN** Pinned and custom pinboard filters are visible
- **THEN** each filter shows a compact circular category marker
- **AND** the category markers have stronger visual presence than the previous compact marker size
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
- **THEN** the complete command group remains centered within the available header width
- **AND** the pinboard filter group remains horizontally scrollable when space is constrained
- **AND** search and the add-pinboard control remain available

#### Scenario: Header controls provide interaction feedback
- **WHEN** the user hovers, presses, or focuses a top command bar control
- **THEN** Copythat provides visible feedback appropriate for a compact macOS utility panel
