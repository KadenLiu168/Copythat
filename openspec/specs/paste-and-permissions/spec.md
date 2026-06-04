# Paste and Permissions Specification

## Purpose
Copythat restores selected history items to the pasteboard and, when safe and permitted, pastes them into the target macOS application.

## Requirements

### Requirement: Restore selected items to the pasteboard
Copythat SHALL restore supported history items to the general pasteboard before attempting automatic paste.

#### Scenario: Restore text or URL
- **WHEN** the user pastes a text or URL history item
- **THEN** Copythat writes the stored string value to the pasteboard

#### Scenario: Restore image
- **WHEN** the user pastes an image history item with restorable image data
- **THEN** Copythat writes the image to the pasteboard

#### Scenario: Restore files
- **WHEN** the user pastes a file history item whose files still exist
- **THEN** Copythat writes the existing file URLs to the pasteboard

#### Scenario: Item cannot be restored
- **WHEN** the selected history item cannot be written back to the pasteboard
- **THEN** Copythat does not attempt automatic paste
- **AND** the panel reports that the clipboard item could not be restored

### Requirement: Preserve paste safety
Copythat SHALL avoid sending Command-V when there is no valid target application.

#### Scenario: No target app is available
- **WHEN** the selected item is restored to the pasteboard
- **AND** no valid target app is available
- **THEN** Copythat does not send Command-V
- **AND** the panel reports that the item was copied but no target app was available

#### Scenario: Copythat is the apparent target
- **WHEN** Copythat or another excluded system surface would be selected as the paste target
- **THEN** Copythat does not use it as the target for automatic paste

### Requirement: Respect Accessibility permission
Copythat SHALL require Accessibility permission before sending synthetic paste input.

#### Scenario: Accessibility is granted
- **WHEN** the selected item is restored to the pasteboard
- **AND** a valid target app is available
- **AND** Accessibility permission is granted
- **THEN** Copythat activates the target app
- **AND** sends Command-V to paste the restored item

#### Scenario: Accessibility is missing
- **WHEN** the selected item is restored to the pasteboard
- **AND** Accessibility permission is not granted
- **THEN** Copythat does not send Command-V
- **AND** the panel reports that the item was copied to the clipboard and Accessibility permission is off

### Requirement: Surface paste outcome feedback
Copythat SHALL show paste and permission failures in the panel without preventing manual use of the restored clipboard content.

#### Scenario: Automatic paste cannot continue
- **WHEN** Copythat restores the item but cannot complete automatic paste
- **THEN** the item remains copied to the pasteboard
- **AND** the footer message explains the reason automatic paste did not continue

#### Scenario: User retries after resolving permission
- **WHEN** the user resolves the reported permission or target issue
- **AND** retries paste with a selected item
- **THEN** Copythat clears the previous permission message before processing the new paste attempt
