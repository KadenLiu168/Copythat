## MODIFIED Requirements

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

#### Scenario: Paste an unloaded restored image
- **WHEN** the user pastes an image represented by a persisted blob reference
- **THEN** Copythat obtains and verifies its bytes outside MainActor before restoring the image through the existing pasteboard path
- **AND** only a temporary item holds those bytes, without mutation or save of history
- **AND** existing target and Accessibility prerequisites still govern automatic paste

#### Scenario: Lazy image restore fails
- **WHEN** materialization fails or the verified bytes cannot decode as an image
- **THEN** Copythat reports "This clipboard item could not be restored."
- **AND** it does not overwrite the pasteboard or send Command-V

## ADDED Requirements

### Requirement: Cancel and supersede pending paste materialization
Copythat SHALL capture the requested item and target at paste-request time, allow only the newest pending materialization to hand off to the existing paste performer, and invalidate pending materialization when the user closes the panel or the controller is released. Every new paste request SHALL supersede older materialization and any older pending or queued performer attempt immediately, including when the newer request later fails. Cancelled or stale completions SHALL NOT restore the pasteboard, send Command-V or overwrite current feedback. Successful handoff SHALL retain the existing synchronous panel-close and activation coordination behavior.

#### Scenario: Close before image load completes
- **WHEN** the user presses Escape or closes the panel while image materialization is pending
- **AND** that load later completes even though cancellation was requested
- **THEN** the old request causes zero pasteboard writes and zero Command-V

#### Scenario: Newer paste wins
- **WHEN** paste A is pending and the user requests paste B
- **THEN** A is invalidated before waiting for B's media
- **AND** an older performer fallback or queued send cannot execute
- **AND** only B can hand off if still current, even when A completes last or B fails

#### Scenario: Request-time target survives loading
- **WHEN** selection or target tracking changes while a current image request is loading
- **THEN** the request uses its captured item and target rather than substituting another selection or application

#### Scenario: Successful handoff closes the panel
- **WHEN** current materialization succeeds and the existing performer accepts automatic paste
- **THEN** the controller clears the pending materialization before closing the panel synchronously
- **AND** that internal close does not cancel the accepted performer attempt
- **AND** observer ordering, target PID checks, 350ms fallback and at-most-once send remain unchanged

#### Scenario: Release controller while materialization is suspended
- **WHEN** the controller owner releases it while media loading is still suspended
- **THEN** the pending task does not keep the controller alive until loading finishes
- **AND** subsequent completion causes zero pasteboard writes and zero Command-V
