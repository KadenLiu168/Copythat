## MODIFIED Requirements

### Requirement: Track source context
Copythat SHALL show the source application name and the source icon captured for each clipboard history item when source metadata is available. When a pending pasteboard change count is first observed, Copythat SHALL capture the frontmost application at that moment as the first-observed source candidate. If a newer count arrives before the pending count is confirmed stable, Copythat SHALL replace the pending count and candidate together. Source attribution for captures without keyboard copy-shortcut evidence SHALL prefer the candidate paired with the final stable count over the application frontmost at capture confirmation.

#### Scenario: Source app is resolved
- **WHEN** Copythat captures an item and can resolve the source app
- **THEN** the history item displays the source app name
- **AND** the app icon captured for that item is available in the panel when icon data exists

#### Scenario: Source app is unknown
- **WHEN** Copythat cannot resolve the source app
- **THEN** the history item remains usable with an unknown source label

#### Scenario: Multiple visible items have distinct captured source icons
- **WHEN** the panel displays multiple history items with different captured source icons
- **THEN** each history card displays the icon captured for that specific item
- **AND** adding or displaying a later item MUST NOT replace the source icon shown on an earlier item

#### Scenario: Later capture does not rewrite earlier source context
- **WHEN** a later pasteboard capture is attributed to a different app
- **THEN** Copythat MUST NOT replace an earlier card's captured source app name or source icon with the later app's metadata

#### Scenario: Non-keyboard copy keeps the app that was frontmost when the pasteboard changed
- **WHEN** an application writes to the pasteboard without a keyboard copy shortcut (for example a context-menu Copy or a web-page copy button)
- **AND** that application remains frontmost when Copythat first observes the change count that ultimately stabilizes
- **AND** the user switches to a different application before Copythat confirms the pasteboard content is stable
- **THEN** the captured item is attributed to the application that was frontmost when the pasteboard change was first observed
- **AND** the item is not attributed to the application that became frontmost before capture confirmation

#### Scenario: A newer change count replaces the pending observation
- **WHEN** Copythat has recorded a pending change count and first-observed source candidate
- **AND** a newer pasteboard change count arrives before the pending count is confirmed stable
- **THEN** Copythat replaces the pending count and source candidate together
- **AND** the final captured content is not attributed using a candidate paired with an earlier count

#### Scenario: Keyboard copy shortcut evidence still wins
- **WHEN** a copy or cut keyboard shortcut precedes the pasteboard change
- **AND** the frontmost application changes between the shortcut and capture confirmation
- **THEN** the captured item is attributed to the app recorded at shortcut time

#### Scenario: First-observed snapshot is not a valid source candidate
- **WHEN** the application frontmost at first observation is not a valid source candidate (for example Copythat itself)
- **THEN** source resolution falls back to the existing candidates in order: capture-time frontmost app, recent foreground app, system, or unknown

### Requirement: Diagnose clipboard capture decisions
Copythat SHALL provide a default-off diagnostic mode that records safe runtime metadata for clipboard capture, source attribution, duplicate-content insertion decisions, and source-attribution timing.

#### Scenario: Diagnostics are disabled by default
- **WHEN** Copythat monitors pasteboard changes with no clipboard diagnostics flag enabled
- **THEN** Copythat does not emit clipboard diagnostics events
- **AND** clipboard history behavior remains unchanged

#### Scenario: Diagnostics record source and duplicate metadata
- **WHEN** clipboard diagnostics are enabled and a supported pasteboard item is captured
- **THEN** Copythat emits diagnostics that identify the captured item kind, resolved source app, pasteboard change-count context, content identity digest, duplicate-match status, and item counts before and after insertion
- **AND** Copythat does not change captured item content, source attribution, duplicate-content behavior, selection, or persistence as part of diagnostics

#### Scenario: Diagnostics expose source-attribution event ordering
- **WHEN** clipboard diagnostics are enabled and Copythat observes and resolves a pasteboard change
- **THEN** Copythat emits monotonic timing metadata for the first observation and final source-resolution decision
- **AND** applicable application-activation and copy-or-cut-shortcut events include monotonic timing and pasteboard change-count metadata
- **AND** the resolution event identifies the selected source-resolution slot and resolved source app

#### Scenario: Diagnostics avoid clipboard payloads
- **WHEN** clipboard diagnostics are enabled for text, URL, file, image, or sensitive-content pasteboard changes
- **THEN** Copythat MUST NOT log raw copied text, complete URLs, file paths, image data, unique acceptance markers, or other restorable clipboard payload values
