## ADDED Requirements

### Requirement: Toggle panel preview privacy
Copythat SHALL let users hide and restore visible history card previews from a global privacy control in the bottom panel command bar.

#### Scenario: Privacy control is shown in the command bar
- **WHEN** the bottom panel displays its command bar
- **THEN** Copythat shows a privacy visibility control after the pinboard filters
- **AND** the privacy visibility control appears before the new-pinboard `+` control
- **AND** the privacy visibility control remains available when custom pinboard filters overflow into a horizontal scrolling region

#### Scenario: User hides previews
- **WHEN** the user activates the privacy visibility control while previews are visible
- **THEN** Copythat hides preview content for every visible history card
- **AND** each card still shows its item kind, relative timestamp, source context, selection state, and available item actions
- **AND** search, pinboard filtering, paste, drag, pin, move-to-pinboard, and delete behavior remain available

#### Scenario: User restores previews
- **WHEN** the user activates the privacy visibility control while previews are hidden
- **THEN** Copythat restores normal preview rendering for every visible history card

#### Scenario: Privacy mode does not change history data
- **WHEN** the user hides or restores previews
- **THEN** Copythat does not modify captured clipboard history, sensitive-content recording, pinboard assignments, persisted items, or restorable pasteboard content
