# Settings and Launch Specification

## Purpose
Copythat lets users configure clipboard history behavior, pinboards, appearance, global shortcut, launch-at-login behavior, and permission recovery from a native macOS settings surface.

## Requirements

### Requirement: Open settings from menu bar
Copythat SHALL open the native settings surface from the menu bar Settings action.

#### Scenario: Settings item is activated
- **WHEN** the user activates Settings from the menu bar right-click menu
- **THEN** Copythat opens the native settings window
- **AND** the window presents controls for launch at login, history behavior, global shortcut, permissions, ignored applications, and appearance

### Requirement: Configure history behavior
Copythat SHALL let users configure the bounds and sources of recorded clipboard history.

#### Scenario: History limit is changed
- **WHEN** the user changes the history limit
- **THEN** Copythat stores a normalized value between 100 and 1,000 items

#### Scenario: Sensitive content setting is changed
- **WHEN** the user enables or disables sensitive content recording
- **THEN** Copythat stores the setting for future pasteboard monitoring

#### Scenario: Ignored applications are changed
- **WHEN** the user edits the ignored applications list
- **THEN** Copythat stores the newline-separated list for future source filtering

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

### Requirement: Configure custom pinboards
Copythat SHALL persist each custom pinboard's trimmed name and selected color independently from Settings. The persisted representation SHALL be deterministic: for identical pinboard content, the stored bytes SHALL be identical across launches and processes.

#### Scenario: Custom pinboard is created
- **WHEN** the user creates a custom pinboard from the bottom panel
- **THEN** Copythat stores the pinboard's trimmed name and selected color

#### Scenario: Application relaunches
- **WHEN** Copythat launches with stored custom pinboards
- **THEN** each custom pinboard retains its name, order, and selected color

#### Scenario: Stored pinboard data is stable
- **WHEN** Copythat persists the same custom pinboard content in two separate launches
- **THEN** the stored representation is byte-identical
- **AND** the stored content decodes to the same pinboards, in the same order, with the same colors

#### Scenario: Existing custom pinboards are migrated
- **WHEN** Copythat launches with legacy custom pinboard names and no structured colored-pinboard data
- **THEN** Copythat preserves each non-empty unique trimmed name in its existing order
- **AND** assigns each migrated pinboard a stable color from the fixed palette
- **AND** preserves clipboard-item assignments that refer to those names

#### Scenario: No custom pinboards are configured
- **WHEN** the custom pinboard list is empty
- **THEN** Copythat still provides the Clipboard and Pinned pinboards

### Requirement: Configure global shortcut
Copythat SHALL let users choose from supported global shortcuts and report registration failures.

#### Scenario: Supported shortcut is selected
- **WHEN** the user selects a supported shortcut
- **THEN** Copythat stores it
- **AND** attempts to register it as the global shortcut

#### Scenario: Unsupported shortcut value is encountered
- **WHEN** the stored shortcut value is not supported
- **THEN** Copythat restores the default Command-Shift-V shortcut

#### Scenario: Shortcut registration fails
- **WHEN** macOS rejects registration of the selected shortcut
- **THEN** Copythat shows an inline shortcut registration warning
- **AND** the menu bar item remains available

### Requirement: Configure launch at login
Copythat SHALL let users enable or disable Launch at login and recover if macOS rejects the change.

#### Scenario: Launch at login is enabled
- **WHEN** the user enables Launch at login
- **THEN** Copythat asks macOS to register the app for launch at login

#### Scenario: Launch at login is disabled
- **WHEN** the user disables Launch at login
- **THEN** Copythat asks macOS to unregister the app from launch at login

#### Scenario: Launch at login change fails
- **WHEN** macOS rejects a Launch at login change
- **THEN** Copythat restores the previous setting value
- **AND** shows an inline warning that Launch at login could not be changed

### Requirement: Configure appearance
Copythat SHALL let users choose whether the app follows the system appearance or uses light or dark appearance.

#### Scenario: System appearance is selected
- **WHEN** the user selects system appearance
- **THEN** Copythat follows the macOS system appearance

#### Scenario: Light or dark appearance is selected
- **WHEN** the user selects light or dark appearance
- **THEN** Copythat applies the selected app appearance

### Requirement: Recover Accessibility permission
Copythat SHALL guide users to macOS Accessibility settings when automatic paste cannot run because permission is missing.

#### Scenario: Accessibility message is shown in panel
- **WHEN** Copythat reports that Accessibility permission is off
- **THEN** the panel offers an Open Settings action

#### Scenario: User opens Accessibility settings
- **WHEN** the user activates the Open Settings action for Accessibility
- **THEN** Copythat opens the macOS Accessibility privacy settings pane

### Requirement: Launch responsively with persisted history
Copythat SHALL avoid repeating expensive media transformation work when restoring clipboard items that are already stored in the current persistence format.

#### Scenario: Application launches with image-heavy history
- **WHEN** Copythat launches with persisted clipboard history containing images and source icons
- **THEN** Copythat restores the persisted items without re-encoding each item's stored media
- **AND** the menu bar application becomes usable without waiting for redundant media transformation
