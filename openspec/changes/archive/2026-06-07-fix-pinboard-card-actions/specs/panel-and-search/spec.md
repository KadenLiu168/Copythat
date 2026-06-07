## MODIFIED Requirements

### Requirement: Filter by pinboard
Copythat SHALL filter visible history by all items, pinned items, or configured custom pinboards.

#### Scenario: All pinboard is selected
- **WHEN** the user selects the Clipboard pinboard
- **THEN** Copythat shows all history items that match the current search query

#### Scenario: Pinned pinboard is selected
- **WHEN** the user selects the Pinned pinboard
- **THEN** Copythat shows pinned history items that match the current search query

#### Scenario: Custom pinboard is selected
- **WHEN** the user selects a custom pinboard
- **THEN** Copythat shows history items assigned to that custom pinboard and matching the current search query

#### Scenario: Pinned item is unpinned while viewing Pinned
- **WHEN** the user unpins a visible item while the Pinned filter is selected
- **THEN** Copythat removes that item from the visible timeline immediately
- **AND** the visible item count updates without requiring the user to switch filters

#### Scenario: Item is removed from current custom pinboard
- **WHEN** the user removes a visible item from the selected custom pinboard
- **THEN** Copythat removes that item from the visible timeline immediately
- **AND** the visible item count updates without requiring the user to switch filters

#### Scenario: Custom pinboard assignment does not pin an item
- **WHEN** the user assigns an unpinned item to a custom pinboard
- **THEN** Copythat keeps the item unpinned
- **AND** the item does not appear in the Pinned filter unless the user pins it

## ADDED Requirements

### Requirement: Present state-aware card actions
Copythat SHALL present card actions that match each card's current pinned and pinboard state.

#### Scenario: Unpinned card action
- **WHEN** the user opens the context menu for an unpinned card
- **THEN** Copythat shows a Pin action
- **AND** Copythat does not show an Unpin action

#### Scenario: Pinned card action
- **WHEN** the user opens the context menu for a pinned card
- **THEN** Copythat shows an Unpin action

#### Scenario: Card assigned to custom pinboard
- **WHEN** the user opens the context menu for a card assigned to a custom pinboard
- **THEN** Copythat offers an action to remove the card from its pinboard

#### Scenario: Card not assigned to custom pinboard
- **WHEN** the user opens the context menu for a card without a custom pinboard assignment
- **THEN** Copythat does not offer an action to remove the card from a pinboard
