# Paste and Permissions Specification

## Purpose
Copythat restores selected history items to the pasteboard and, when safe and permitted, pastes them into the target macOS application.

## Requirements

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

### Requirement: Preserve paste safety
Copythat SHALL avoid sending Command-V when there is no valid target application.

#### Scenario: No target app is available
- **WHEN** the selected item is restored to the pasteboard
- **AND** no valid target app is available
- **THEN** Copythat does not send Command-V
- **AND** the panel reports that the item was copied but no target app was available

#### Scenario: Copythat is the apparent target
- **WHEN** Copythat or another excluded system surface would be selected as the paste target
- **THEN** Copythat does not use it as the target for automatic paste

### Requirement: Respect Accessibility permission
Copythat SHALL require Accessibility permission before sending synthetic paste input.

#### Scenario: Accessibility is granted
- **WHEN** the selected item is restored to the pasteboard
- **AND** a valid target app is available
- **AND** Accessibility permission is granted
- **THEN** Copythat activates the target app
- **AND** sends Command-V to paste the restored item

#### Scenario: Accessibility is missing
- **WHEN** the selected item is restored to the pasteboard
- **AND** Accessibility permission is not granted
- **THEN** Copythat does not send Command-V
- **AND** the panel reports that the item was copied to the clipboard and Accessibility permission is off

### Requirement: Surface paste outcome feedback
Copythat SHALL show paste and permission failures in the panel without preventing manual use of the restored clipboard content.

#### Scenario: Automatic paste cannot continue
- **WHEN** Copythat restores the item but cannot complete automatic paste
- **THEN** the item remains copied to the pasteboard
- **AND** the footer message explains the reason automatic paste did not continue

#### Scenario: User retries after resolving permission
- **WHEN** the user resolves the reported permission or target issue
- **AND** retries paste with a selected item
- **THEN** Copythat clears the previous permission message before processing the new paste attempt

### Requirement: Respond to target activation without duplicate paste
After successfully restoring a selected item to the pasteboard and satisfying the existing target and Accessibility prerequisites, Copythat SHALL send Command-V via the next asynchronous main-queue delivery after the intended target application is confirmed active, without imposing a fixed 350 ms wait on this normal path. If activation cannot be confirmed, Copythat SHALL retain the existing behavior of attempting Command-V after 350 ms. Copythat MUST send Command-V at most once per paste attempt and MUST NOT send a delayed Command-V from an attempt superseded by a later paste request.

#### Scenario: Target activates promptly
- **WHEN** the intended target app becomes active before the fallback deadline
- **THEN** Copythat sends Command-V via the next asynchronous main-queue delivery after that activation is confirmed
- **AND** it does not wait out the 350 ms fallback deadline

#### Scenario: Target is already active
- **WHEN** the intended target app is already active when automatic paste starts
- **THEN** Copythat sends Command-V via the next asynchronous main-queue delivery without waiting for an activation event or the fallback deadline

#### Scenario: Unrelated app activates
- **WHEN** an app other than the intended target becomes active before the deadline
- **THEN** that activation does not trigger Command-V
- **AND** a subsequent activation of the intended target can still trigger Command-V

#### Scenario: Activation confirmation is absent
- **WHEN** the intended target's activation has not been confirmed by 350 ms after activation is requested
- **THEN** Copythat attempts Command-V as it did before this change, even if the target is not confirmed active

#### Scenario: Activation and fallback compete
- **WHEN** activation confirmation and the fallback occur in either order for one attempt
- **THEN** Copythat sends Command-V at most once
- **AND** a later activation does not paste again

#### Scenario: A later paste request supersedes a pending attempt
- **WHEN** another paste request starts while an earlier attempt is pending
- **THEN** the earlier attempt cannot send Command-V, including after its target later activates or its fallback expires
- **AND** the later request follows the existing restore, target, and Accessibility prerequisites before it can paste

#### Scenario: Activation is confirmed synchronously
- **WHEN** the target activation notification arrives during the activation request, or the target is confirmed active immediately after it returns without a notification
- **THEN** Copythat schedules Command-V asynchronously on the main queue
- **AND** it does not send inline before the synchronous paste call returns or rearm a fallback that can paste again

#### Scenario: A failed newer request supersedes a queued paste
- **WHEN** an earlier attempt has a pending fallback or a queued Command-V
- **AND** a later paste request fails to restore its item or has no target after restore
- **THEN** the earlier attempt cannot send Command-V even when its already-enqueued callbacks run
- **AND** the later request retains the existing failure feedback and does not start automatic paste

#### Scenario: The paste performer is released
- **WHEN** the performer is released while awaiting activation or while Command-V delivery is queued
- **THEN** its observer and fallback are cleaned up
- **AND** no callback from that attempt sends Command-V

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
