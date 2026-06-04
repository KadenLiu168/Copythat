## MODIFIED Requirements

### Requirement: Display a native bottom floating panel
Copythat SHALL display clipboard history in a bottom floating panel that fits the visible display area and does not show rectangular shadow artifacts at its rounded corners.

#### Scenario: Panel opens
- **WHEN** the panel is shown
- **THEN** it appears as a native macOS floating panel near the bottom of the active visible screen area
- **AND** the first visible item is selected when available

#### Scenario: Panel corners are rendered
- **WHEN** the bottom floating panel is visible
- **THEN** its rounded corners do not show rectangular outer shadow artifacts

#### Scenario: Panel is closed
- **WHEN** the user presses Escape in the panel
- **THEN** Copythat closes the panel
