## Why

The bottom-panel `+` control looks like a pinboard creation action but currently opens Settings, leaving users without a direct way to create a category from the panel. Custom pinboards also receive colors from their list position rather than a user-selected, stable category color.

## What Changes

- Make the bottom-panel `+` control open a compact new-pinboard form instead of Settings.
- Require a pinboard name and one color selected from a small, visually consistent fixed palette.
- Persist each custom pinboard's selected color so it remains stable across launches and ordering changes.
- Show and select the new pinboard immediately after creation.
- Preserve existing custom pinboards by migrating their names to the new colored-pinboard representation.
- Remove the obsolete specification that custom pinboards are configured from Settings; this change does not add pinboard management to Settings.
- Supersede the order-based, non-configurable color assignment proposed by the unimplemented `vitalize-pinboard-category-dots` change.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `panel-and-search`: define direct creation of a named, colored custom pinboard from the panel `+` control and stable display of its selected color.
- `settings-and-launch`: replace the obsolete Settings-based custom-pinboard configuration requirement with persisted named and colored custom-pinboard data.

## Impact

- Affects the bottom-panel command bar and a compact SwiftUI creation surface.
- Replaces the existing newline-separated custom-pinboard setting with persisted structured pinboard data and a compatibility migration.
- Updates pinboard presentation and assignment inputs while preserving the existing clipboard-item-to-pinboard name association.
- Requires focused model/persistence tests, panel interaction verification, `swift build`, and `./script/verify_all.sh`.

## Non-goals

- Renaming, deleting, reordering, or recoloring existing custom pinboards.
- Adding pinboard creation or management controls to Settings.
- Moving the current clipboard item into a newly created pinboard automatically.
- Introducing free-form color picking or changing the built-in Clipboard and Pinned identities.
