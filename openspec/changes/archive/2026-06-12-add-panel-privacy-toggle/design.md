## Context

The bottom panel command bar currently contains search, pinboard filters, and the new-pinboard `+` control. Visible history cards render their preview content directly by kind: text body, URL title and URL, image thumbnail, or file details.

Copythat already has capture-time protection for pasteboard contents marked as concealed or associated with password-manager data. This change addresses a different problem: temporary display privacy for history items that are already available in the panel.

## Goals / Non-Goals

**Goals:**

- Add a single panel-level privacy toggle in the command bar.
- Keep the requested command-bar order: search, pinboards, privacy toggle, new pinboard.
- Hide all card preview content when privacy mode is enabled.
- Preserve card identity and usability: kind, timestamp, source context, selection, paste, drag, pinboard actions, and deletion still work.
- Keep the change local to the panel UI and card presentation.

**Non-Goals:**

- Persist the privacy state across launches.
- Add per-card, per-kind, or per-pinboard privacy state.
- Change capture-time sensitive-content filtering.
- Change the stored clipboard history model.
- Add automatic classification for secrets, personal data, or password-manager content.

## Decisions

### Keep Privacy State Local to the Panel

Use local SwiftUI state in `BottomPanelView` to track whether previews are hidden, then pass that display state into each `ClipboardCardView`.

Rationale: the requested behavior is a quick panel-level visibility control. Keeping it local avoids migrations, defaults keys, and settings UI before there is evidence users need a persistent preference.

Alternative considered: store the privacy state in `AppSettings`. That would make the state survive relaunch, but it expands the feature into a preference and creates a risk that users forget previews are hidden.

### Place the Toggle Outside the Pinboard Scroll Region

The command bar should keep the privacy toggle after the pinboard filters and before `+`, while keeping it fixed outside the scrollable pinboard strip when the filters need horizontal scrolling.

Rationale: privacy is an emergency-access control. If the pinboard list overflows, users should still be able to hide or reveal previews without scrolling through filters first.

Alternative considered: include the toggle inside the pinboard strip. This preserves a simpler `HStack`, but it can move the control out of sight when custom pinboards overflow.

### Hide Preview Areas Without Changing Item Operations

When privacy mode is enabled, card bodies should render a neutral concealed state instead of text, URL details, image thumbnails, or file path details. Headers should remain visible because kind, timestamp, and source context help users navigate without exposing the copied payload.

Rationale: this provides useful orientation while preventing the panel from exposing content at a glance. It also keeps card size, selection, and timeline behavior stable.

Alternative considered: blur the existing previews. Blurring can still leak layout, colors, image shapes, and short text length. A neutral concealed state is clearer and more reliable.

### Reuse Command-Bar Icon Styling

Use the existing compact command-bar icon button styling with `eye` for visible previews and `eye.slash` for hidden previews.

Rationale: the control is a peer of search and new-pinboard actions, and reusing the existing button style keeps the command bar visually consistent.

Alternative considered: add a text label such as "Privacy". That makes the state explicit but consumes scarce command-bar width and competes with pinboard filters.

## Risks / Trade-offs

- Users may expect hidden previews to also disable search matching hidden content -> Keep search unchanged and document that privacy mode only affects display.
- Users may expect privacy mode to persist -> Keep the first version local; persistence can be added later if usage shows that expectation.
- Hiding image thumbnails may make image items harder to identify -> Preserve kind, source, timestamp, and selection; users can toggle visibility when they need visual confirmation.
- Adding one more fixed command-bar control reduces pinboard space -> Put only the pinboard strip in the constrained/scrolling region and keep the control compact.

## Migration Plan

No data migration is required. The feature can be removed by deleting the panel state, command-bar button, and card concealed rendering path because it does not alter stored history or settings.

## Open Questions

- None for the first version.
