## MODIFIED Requirements

### Requirement: Browse and select visible items
Copythat SHALL let users browse visible clipboard items horizontally, maintain a selected item, and show a balanced empty timeline state when no items are visible.

#### Scenario: History has visible items
- **WHEN** the panel displays matching history items
- **THEN** each item is shown as a card with its title, preview, kind, source context, and available item actions

#### Scenario: User moves selection
- **WHEN** the user sends left or right movement commands in the panel
- **THEN** Copythat moves selection within the visible items without moving past the first or last item

#### Scenario: No items are visible
- **WHEN** filters and search produce no visible items
- **THEN** Copythat shows an empty timeline state instead of item cards
- **AND** the empty state is visually centered within the timeline content area rather than aligned to the leading card position
- **AND** the empty state does not show the app logo as a prominent primary graphic

#### Scenario: Selected pinboard has no items
- **WHEN** the user selects a pinboard with no matching visible items
- **THEN** Copythat shows empty-state copy that identifies the selected pinboard context

#### Scenario: Search has no matches
- **WHEN** the user enters a search query that matches no visible items
- **THEN** Copythat shows empty-state copy that identifies the empty search result context
