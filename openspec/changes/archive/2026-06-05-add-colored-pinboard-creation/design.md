## Context

Custom pinboards are currently stored as newline-separated names in `AppSettings.pinboardsText`. Clipboard items refer to a custom pinboard by name, while `BottomPanelView` assigns display colors from each name's current list position. The panel `+` action opens Settings even though its placement and icon communicate creation.

This change crosses panel presentation, settings persistence, and pinboard model inputs. It must preserve existing custom pinboard names and clipboard-item assignments while introducing stable user-selected colors.

The active but unimplemented `vitalize-pinboard-category-dots` change includes an order-based color decision that conflicts with this requirement. Its independent marker-shape work can still be retained, but its color-assignment task must not be applied.

## Goals / Non-Goals

**Goals:**

- Create a custom pinboard directly from the panel with a required name and selected color.
- Keep the creation interaction compact, keyboard-usable, and visually attached to the `+` control.
- Persist a stable color with each custom pinboard and migrate existing names without losing assignments.
- Update the visible panel immediately and select the newly created pinboard.
- Use a small fixed palette whose options have consistent perceived saturation and brightness.

**Non-Goals:**

- Rename, delete, reorder, or recolor existing custom pinboards.
- Add pinboard management to Settings.
- Change the built-in Clipboard or Pinned identities and colors.
- Move an existing clipboard item when a pinboard is created.
- Replace name-based clipboard-item assignment with a new identifier system.

## Decisions

### Store structured custom pinboards with semantic color tokens

Introduce a small codable custom-pinboard value containing a trimmed `name` and a `color` token from a fixed enum. Persist the array as encoded data in `UserDefaults` and expose it as published settings state.

The color token is stored instead of raw RGB values so the supported palette remains controlled and can evolve without rewriting stored data. Clipboard items continue to store `pinboardName`; replacing that association with UUIDs would add a broad clipboard-history migration that is not required for creation and stable color.

Alternative considered: keep `pinboardsText` and store a separate name-to-color dictionary. Rejected because two independently editable stores can drift and would retain the obsolete text-editor configuration model.

### Migrate existing names once and preserve their order

When structured custom-pinboard data is absent, parse the existing newline-separated names using the current trimming and de-duplication behavior, assign palette colors deterministically in their existing order, persist the structured result, and keep clipboard-item name associations unchanged.

If structured data is unreadable, fall back to the legacy names rather than discarding visible pinboards. The legacy key can remain during the compatibility window, but structured data becomes the source of truth.

Alternative considered: reset to default Work and Ideas pinboards. Rejected because it would hide user-defined pinboards and strand assigned items.

### Present creation in a SwiftUI popover anchored to the plus control

The panel `+` opens a compact popover containing a focused name field, a row of selectable color swatches, and Cancel/Create actions. Create is disabled for an empty trimmed name or an existing exact trimmed name. Return creates when valid; Escape follows the panel's existing close behavior and may close the panel without creating a pinboard.

On successful creation, the settings model appends and persists the pinboard, the popover closes, and the store selects the new pinboard. The current clipboard item is not reassigned.

Alternative considered: open a separate window or Settings. Rejected because creation is a small contextual action and Settings remains available from the menu bar.

### Use a fixed perceptually balanced palette

Provide six named color tokens such as amber, green, cyan, blue, violet, and pink. Map them to precomputed display colors designed around shared perceptual lightness and chroma, changing primarily by hue. This keeps saturation and apparent brightness more consistent than unrelated system colors while preventing unrestricted colors that may be illegible on the panel.

Color tokens may repeat across different pinboards; limiting each color to one pinboard would impose an unnecessary category-count limit. Pinned retains its built-in red.

Alternative considered: use an unrestricted macOS color picker. Rejected because it cannot guarantee consistent vividness or contrast.

### Observe pinboard settings directly in the panel

`BottomPanelView` must observe the settings object that owns structured custom pinboards so creation updates the visible filters and card assignment menus immediately. Color lookup uses the pinboard's persisted token rather than its list index.

Alternative considered: recreate the panel after each creation. Rejected because it adds window lifecycle work and would disrupt the current panel interaction.

## Risks / Trade-offs

- [Name-based assignment prevents safe rename behavior] -> Keep rename out of scope and preserve the existing association model.
- [Existing custom pinboards have no chosen color] -> Assign deterministic palette colors during migration and preserve them afterward.
- [Popover keyboard events could reach the panel's paste/close handlers] -> Ensure Return creates without pasting; accept Escape closing the panel as consistent panel behavior.
- [The active category-dot change conflicts with persisted colors] -> Do not apply its order-based color-assignment task; reconcile or archive that change before implementation completion.
- [A fixed palette eventually repeats] -> Allow repeated colors and keep names as the primary category label.

## Migration Plan

1. On first load without structured pinboard data, parse and normalize the legacy pinboard-name text.
2. Assign each migrated name a deterministic palette token by existing order and persist the structured array.
3. Continue matching clipboard items by their existing `pinboardName`; no clipboard-history rewrite is required.
4. Treat the structured array as the source of truth for panel filters, assignment menus, and colors.

## Open Questions

None.
