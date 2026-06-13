## MODIFIED Requirements

### Requirement: Manually clear clipboard cards from Settings
Copythat SHALL let users manually clear clipboard cards from the native Settings surface.

#### Scenario: Settings shows card clearing controls
- **WHEN** the user opens Settings
- **THEN** Copythat shows the current clipboard card count
- **AND** Copythat offers a clear-cards action when cards exist

#### Scenario: Clear action requires confirmation
- **WHEN** the user activates the clear-cards action
- **THEN** Copythat asks the user to confirm a destructive clear operation with concise copy
- **AND** Copythat offers a "Clear Regular Cards" choice for the default protected clear mode
- **AND** Copythat explains that regular cards exclude pinned cards and cards in pinboards
- **AND** Copythat offers a separate "Clear All Cards" choice

#### Scenario: No cards are available to clear
- **WHEN** no clipboard cards are stored
- **THEN** Copythat disables the clear-cards action
