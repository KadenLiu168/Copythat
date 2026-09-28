## ADDED Requirements

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
