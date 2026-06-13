## MODIFIED Requirements

### Requirement: Select cards responsively
Copythat SHALL keep bottom-panel card selection responsive when users browse visible cards with keyboard movement or mouse clicks.

#### Scenario: User moves selection with keyboard
- **WHEN** the user repeatedly sends left or right movement commands in the bottom panel
- **THEN** Copythat updates the selected card without visible stutter or accumulating scroll delay
- **AND** the selected-card border, shadow, scale, raised position, and scroll-to-center behavior remain visually consistent with the existing panel design

#### Scenario: User clicks a card
- **WHEN** the user single-clicks a visible card in the bottom panel
- **THEN** Copythat selects that card promptly
- **AND** clicking the already selected card does not trigger unnecessary selection updates

#### Scenario: User double-clicks a card
- **WHEN** the user double-clicks a visible card in the bottom panel
- **THEN** Copythat still pastes the selected card

#### Scenario: User revisits cards with the same source icon
- **WHEN** selection changes repeatedly between visible cards whose source appearance has already been rendered
- **THEN** Copythat reuses the derived source appearance instead of repeatedly delaying selection feedback
