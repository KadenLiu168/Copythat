## ADDED Requirements

### Requirement: Clear clipboard history manually
Copythat SHALL support manual clearing of stored clipboard history while protecting intentionally saved cards by default.

#### Scenario: Clear ordinary cards
- **WHEN** the user confirms clearing ordinary cards
- **THEN** Copythat removes stored cards that are not pinned and are not assigned to a custom pinboard
- **AND** Copythat keeps pinned cards
- **AND** Copythat keeps cards assigned to custom pinboards

#### Scenario: Clear all cards
- **WHEN** the user confirms clearing all cards
- **THEN** Copythat removes stored cards regardless of pin state or custom pinboard assignment

#### Scenario: History state refreshes after clearing
- **WHEN** clipboard cards are cleared
- **THEN** Copythat updates the visible card list
- **AND** Copythat updates the current selection to a remaining visible card or clears selection when no visible cards remain
- **AND** Copythat persists the updated clipboard history

#### Scenario: Custom pinboards remain after clearing cards
- **WHEN** clipboard cards are cleared
- **THEN** Copythat keeps configured custom pinboards available
