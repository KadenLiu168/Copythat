## MODIFIED Requirements

### Requirement: Browse and select visible items
Copythat SHALL let users browse visible clipboard items horizontally, maintain a selected item, and show a balanced empty timeline state when restoration is complete and no items are visible. While startup history restoration is incomplete, the history content area SHALL instead show a minimal loading-history state, not an empty history or empty search result.

#### Scenario: History has visible items
- **WHEN** restoration is complete and the panel displays matching history items
- **THEN** each item is shown as a card with its title, preview, kind, source context, and available item actions

#### Scenario: User moves selection
- **WHEN** the user sends left or right movement commands in the panel
- **THEN** Copythat moves selection within the visible items without moving past the first or last item

#### Scenario: No items are visible
- **WHEN** restoration is complete and filters and search produce no visible items
- **THEN** Copythat shows an empty timeline state instead of item cards
- **AND** the empty state is visually centered within the timeline content area rather than aligned to the leading card position
- **AND** the empty state does not show the app logo as a prominent primary graphic

#### Scenario: Selected pinboard has no items
- **WHEN** restoration is complete and the user selects a pinboard with no matching visible items
- **THEN** Copythat shows empty-state copy that identifies the selected pinboard context

#### Scenario: Search has no matches
- **WHEN** restoration is complete and the user enters a search query that matches no visible items
- **THEN** Copythat shows empty-state copy that identifies the empty search result context

#### Scenario: Panel opens before history has loaded
- **WHEN** the user opens the panel while startup history is loading
- **THEN** the history content area shows “Loading clipboard history…” rather than reporting no history or no search matches
- **AND** menu and shortcut panel activation remain usable without waiting for restoration
- **AND** loading counts are not presented as an authoritative empty-history count

## ADDED Requirements

### Requirement: Preserve current browsing inputs across history restoration
Copythat SHALL keep search and pinboard selection usable during startup loading and apply their current values to the completed history without requiring another user input. Selection-driven preview enrichment SHALL reconcile against completed baseline-plus-replay history rather than transient baseline selections.

#### Scenario: Search entered while loading
- **WHEN** the user enters a query while persisted history is loading
- **THEN** completion immediately exposes matching retained restored and startup items using that query
- **AND** the user does not need to type it again

#### Scenario: Pinboard selected while loading
- **WHEN** the user selects a custom or Pinned filter and enters a query before restoration finishes
- **THEN** completed results use the current filter intersected with the current query
- **AND** selection is valid for those visible results or empty when no results survive

#### Scenario: Replay replaces the transient baseline selection
- **WHEN** the panel is visible and startup replay would replace the baseline's initially selected URL with a different final selection
- **THEN** merely installing that transient baseline selection does not start selection-driven metadata or browser fallback for it
- **AND** existing eager enrichment for newly inserted URLs remains available through ordinary insertion eligibility

### Requirement: Gate history organization actions while history is unavailable
Copythat SHALL disable pin/unpin, remove, move-to-pinboard, clear, and existing custom-pinboard edit/delete actions while startup history restoration is incomplete or accepted capture work is being drained for normal Quit. Rejected actions MUST NOT alter history, accepted capture eligibility, system pasteboard content, or pinboard settings, and MUST NOT be silently queued for later execution. Whole pinboard edit/delete confirmations MUST be guarded before either settings or history changes. Search, filtering, panel opening, preview privacy and safe new-pinboard creation remain available during history loading.

#### Scenario: Destructive history action is attempted while loading
- **WHEN** a history-destructive action is invoked before restoration completes
- **THEN** the action is unavailable and its handler makes no history, pasteboard, save or image-invalidation change
- **AND** the operation is not applied after loading finishes

#### Scenario: Rename or delete cannot split settings from assignments
- **WHEN** pinboard edit or deletion is attempted while history is loading
- **THEN** neither the pinboard settings nor restored item assignments change
- **AND** completing restoration does not reveal assignments referring to a name that was changed by that rejected action

#### Scenario: Confirmation is checked when executed
- **WHEN** a pinboard confirmation callback executes while history mutations are unavailable
- **THEN** it is rejected before updating pinboard name, color, deletion state or item assignments

#### Scenario: Mutation availability returns after loading or cancelled Quit
- **WHEN** restoration is complete and no Quit admission pause remains
- **THEN** existing history and pinboard mutation actions return to their ordinary behavior
- **AND** cancelling Quit does not discard in-memory history
