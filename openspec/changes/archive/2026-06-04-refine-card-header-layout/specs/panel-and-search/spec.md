## ADDED Requirements

### Requirement: Display compact card headers
Copythat SHALL display each visible history card with a compact header that separates the item kind, timestamp, and source icon without crowding the card edge.

#### Scenario: Card header shows two left text lines
- **WHEN** the panel displays a history item card
- **THEN** the card header's left side shows the item kind and relative timestamp as two text lines
- **AND** the left-side header text has visible top and leading inset from the card edge

#### Scenario: Source icon fills the right header edge
- **WHEN** the panel displays a history item card with a captured source app icon
- **THEN** the source icon is aligned to the right edge of the header
- **AND** the source icon visually occupies the header height without a visible right gutter
- **AND** the left-side header text does not overlap the source icon

#### Scenario: Pinboard assignment remains usable
- **WHEN** a history item is pinned or assigned to a custom pinboard
- **THEN** the card header still shows only the item kind and relative timestamp on the left side
- **AND** the item remains available through pinboard filtering and item actions
