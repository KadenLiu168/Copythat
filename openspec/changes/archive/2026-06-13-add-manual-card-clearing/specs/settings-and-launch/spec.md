## ADDED Requirements

### Requirement: Manually clear clipboard cards from Settings
Copythat SHALL let users manually clear clipboard cards from the native Settings surface.

#### Scenario: Settings shows card clearing controls
- **WHEN** the user opens Settings
- **THEN** Copythat shows the current clipboard card count
- **AND** Copythat offers a clear-cards action when cards exist

#### Scenario: Clear action requires confirmation
- **WHEN** the user activates the clear-cards action
- **THEN** Copythat asks the user to confirm a destructive clear operation
- **AND** Copythat offers separate choices for clearing ordinary cards or clearing all cards

#### Scenario: No cards are available to clear
- **WHEN** no clipboard cards are stored
- **THEN** Copythat disables the clear-cards action
