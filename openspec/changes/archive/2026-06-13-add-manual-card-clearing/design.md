## Context

Copythat already keeps clipboard history in `ClipboardStore` and exposes history-related preferences through the native Settings surface. Settings currently receives only `AppSettings`, so it can configure future behavior but cannot act on the current in-memory and persisted card list.

Manual clearing is destructive and affects stored history, current filtered results, and selection state. The UI needs to stay small and native, while the deletion rules need to live in one store-level API so the same semantics can be reused later.

## Goals / Non-Goals

**Goals:**

- Add a Settings action for manually clearing clipboard cards.
- Default to preserving intentional saved cards: pinned cards and cards assigned to custom pinboards.
- Allow an explicit clear-all action from the same confirmation flow.
- Keep the visible timeline, selected item, and persisted history consistent after clearing.
- Keep the change limited to Settings UI wiring and clipboard history store behavior.

**Non-Goals:**

- No automatic cleanup cadence, age-based deletion, or background scheduling.
- No undo or recovery for cleared cards.
- No persistence schema migration.
- No changes to pasteboard capture, paste execution, source attribution, search, or pinboard management.

## Decisions

- Put clearing semantics in `ClipboardStore`.
  - Rationale: the store owns `items`, filtered results, selection, and persistence. Keeping the predicate there avoids duplicating destructive history logic in SwiftUI.
  - Alternative considered: make `SettingsView` filter and remove cards directly. That would couple presentation to store invariants and risk forgetting refresh or save steps.

- Inject the shared `ClipboardStore` into Settings.
  - Rationale: Settings needs to act on the same history used by the bottom panel. Passing the store through `CopythatApp` and `SettingsWindowController` keeps ownership unchanged in `AppModel`.
  - Alternative considered: expose clearing through `AppSettings`. That would mix durable preferences with mutable history operations.

- Use a confirmation dialog with two destructive choices.
  - Rationale: clearing is destructive, and the user needs to intentionally choose whether protected cards are included.
  - Alternative considered: add a persistent "include protected cards" toggle. That is unnecessary for a one-off manual action and would add state not requested for this change.

- Treat protected cards as `isPinned == true` or `pinboardName != nil`.
  - Rationale: users intentionally save cards either by pinning them or placing them in a custom pinboard. The default action should not remove either group.

## Risks / Trade-offs

- Settings now observes `ClipboardStore` as well as `AppSettings` -> keep the view limited to count display and action dispatch so it does not become a history management surface.
- Clear-all can permanently remove intentionally saved cards -> require a destructive confirmation choice with explicit wording.
- Existing main specs contain older pinboard/pinned wording -> this change scopes only the manual clearing behavior and does not alter pinboard assignment semantics.

## Migration Plan

No data migration is required. Existing persisted history remains unchanged until the user explicitly clears cards.

Rollback is straightforward: remove the Settings action and store clearing API; no stored preferences or schema changes need cleanup.

## Open Questions

None for manual clearing. Automatic cleanup intervals remain a future change.
