## Why

Copythat already exposes a Settings item from the menu bar right-click menu, but activating it currently does not open the native settings panel. This blocks users from changing launch, shortcut, history, pinboard, permission, and appearance settings from the app's primary menu bar entry point.

## What Changes

- Make the menu bar Settings action reliably open and foreground the native macOS settings window.
- Keep the existing settings surface and stored preferences unchanged.
- Add focused verification for the settings-opening path and existing settings controls where practical.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `settings-and-launch`: Clarify that the menu bar Settings action opens the native settings surface.

## Non-goals

- Redesigning the settings UI.
- Changing menu bar menu labels, shortcut choices, or stored preference semantics.
- Adding new settings.

## Impact

- Affected code: `Sources/Copythat/App/AppDelegate.swift` and focused tests or verification helpers as needed.
- No API, dependency, or data migration impact.
