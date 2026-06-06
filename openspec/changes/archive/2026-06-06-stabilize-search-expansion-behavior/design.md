## Context

`BottomPanelView` composes search, pinboard filters, and add-pinboard as one centered command group. The search control currently changes its layout width from its compact icon width to the expanded field width. Because that wider width participates in the command group's layout, expanding search moves the controls to its right.

The view already observes search focus and collapses an empty field when focus becomes false. On macOS, clicking another SwiftUI button does not reliably move focus away from the text field, so that focus-driven collapse does not cover the user's common command-bar interactions.

## Goals / Non-Goals

**Goals:**

- Expand the search field only into the space to its left.
- Keep pinboard filters and add-pinboard visually stationary across search expansion and collapse.
- Collapse an empty expanded search field when the user activates another command-bar control.
- Keep a non-empty search visible and active when focus moves elsewhere.

**Non-Goals:**

- Change search matching, filtering, submission, or clear-button behavior.
- Change the command group's default position, spacing, pinboard overflow, or control styling.
- Introduce a reusable focus-management abstraction outside `BottomPanelView`.

## Decisions

### Keep search's layout footprint compact

The search position in the command group keeps the compact control's layout width in both states. The expanded field is trailing-aligned to that position so its right edge stays fixed and its additional width extends left outside the compact footprint.

This keeps the pinboard strip, add-pinboard action, and centered command-group layout unchanged when search toggles. Reserving the full expanded width at all times was considered, but it would add unused space in the default state and move the currently visible controls.

### Explicitly end empty search interaction from other command-bar actions

Pinboard-filter and add-pinboard actions use one local helper that clears search focus and collapses search when the query is empty before continuing their existing actions. The existing focus-change observation remains useful for other genuine focus transitions.

Relying only on `@FocusState` changes was considered, but the current behavior demonstrates that another button can be activated without reliably clearing text-field focus on macOS.

### Let query content control persistent expansion

A non-empty query keeps the field expanded even after another command-bar control is activated. This preserves visibility of the active filter and keeps the existing clear-and-edit workflow intact.

Collapsing every time another control is activated was considered, but it would hide an active search and make the filtered state less understandable.

## Risks / Trade-offs

- [The expanded field can approach the panel's leading edge] -> Keep the existing bounded expanded width and verify it within the supported panel width.
- [A future command-bar action could omit empty-search dismissal] -> Route non-search command-bar actions through the same small local helper.
- [Changing focus before an action could interfere with that action] -> Perform only the search-state update and verify pinboard selection and add-pinboard presentation still complete normally.
