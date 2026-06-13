## Why

The manual clear-cards confirmation currently asks users to parse a long default action label and a full explanatory sentence before choosing. This makes a destructive but simple Settings action feel heavier than it needs to be.

## What Changes

- Shorten the confirmation title from "Clear clipboard cards?" to "Clear cards?".
- Rename the default protected clear action to "Clear Regular Cards".
- Replace the long explanation with a concise definition: "Regular cards exclude pinned cards and cards in pinboards."
- Keep the existing "Clear All Cards" and "Cancel" choices.
- Keep all current clearing behavior unchanged.

## Non-goals

- Do not change which cards are removed by either clear action.
- Do not add automatic cleanup, scheduling, undo, export, or recovery.
- Do not change Settings layout outside the confirmation copy.
- Do not change store APIs, persistence, pinning, pinboard behavior, or history limits.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `settings-and-launch`: The manual clear-cards confirmation uses shorter decision copy while still defining the protected default clear mode.

## Impact

- Affects only `SettingsView` user-facing strings and the settings spec wording.
- Existing store tests continue to verify clear behavior.
- No new dependencies, migrations, or public API changes.
