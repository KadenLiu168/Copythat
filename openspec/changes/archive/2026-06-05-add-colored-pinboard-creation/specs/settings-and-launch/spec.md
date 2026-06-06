## MODIFIED Requirements

### Requirement: Open settings from menu bar
Copythat SHALL open the native settings surface from the menu bar Settings action.

#### Scenario: Settings item is activated
- **WHEN** the user activates Settings from the menu bar right-click menu
- **THEN** Copythat opens the native settings window
- **AND** the window presents controls for launch at login, history behavior, global shortcut, permissions, ignored applications, and appearance

### Requirement: Configure custom pinboards
Copythat SHALL persist each custom pinboard's trimmed name and selected color independently from Settings.

#### Scenario: Custom pinboard is created
- **WHEN** the user creates a custom pinboard from the bottom panel
- **THEN** Copythat stores the pinboard's trimmed name and selected color

#### Scenario: Application relaunches
- **WHEN** Copythat launches with stored custom pinboards
- **THEN** each custom pinboard retains its name, order, and selected color

#### Scenario: Existing custom pinboards are migrated
- **WHEN** Copythat launches with legacy custom pinboard names and no structured colored-pinboard data
- **THEN** Copythat preserves each non-empty unique trimmed name in its existing order
- **AND** assigns each migrated pinboard a stable color from the fixed palette
- **AND** preserves clipboard-item assignments that refer to those names

#### Scenario: No custom pinboards are configured
- **WHEN** the custom pinboard list is empty
- **THEN** Copythat still provides the Clipboard and Pinned pinboards
