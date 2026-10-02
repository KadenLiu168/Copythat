## ADDED Requirements

### Requirement: Preserve captured content across asynchronous startup restoration
Copythat SHALL retain eligible content captured while persisted history is loading and apply it after the persisted baseline, in the order finalized captures reach history insertion. Duplicate handling, pinned protection, preserved duplicate metadata, pinboard assignment, selection, configured capacity, and the unpinned-image bound MUST match ordinary insertion into that baseline. Restoration MUST NOT overwrite startup captures. Existing stable-observation, image overflow, deletion/invalidation, and retention eligibility rules remain applicable; this contract does not promise capture of unread overwritten pasteboard values or global capture-time ordering across kinds.

#### Scenario: New copy survives delayed restore
- **WHEN** saved history contains A and the user copies eligible B while restoration is suspended
- **THEN** completed history contains the result of inserting B into restored A under ordinary history rules
- **AND** neither replacing history with the old snapshot nor replacing the old baseline with B alone is permitted

#### Scenario: Unpinned duplicate preserves original context
- **WHEN** startup capture matches an unpinned saved item with a pinboard assignment
- **THEN** replay moves the saved matching entry to the ordinary newest position
- **AND** its original ID, source app, source icon, creation time and pinboard assignment remain unchanged

#### Scenario: Pinned duplicate retains ordinary behavior
- **WHEN** startup capture matches a pinned saved entry and no unpinned match exists
- **THEN** the pinned entry survives
- **AND** a new ordinary entry is retained only if ordinary retention rules permit it

#### Scenario: Multiple captures retain insertion arrival order
- **WHEN** finalized startup items reach insertion in order A, B and C
- **THEN** the final history equals ordinary sequential insertion of A, B and C into the retained persisted baseline
- **AND** creation timestamps and content identities do not reorder replay

#### Scenario: Image finalizes while history is loading
- **WHEN** an eligible image is admitted and its encoding completes before persisted history finishes loading
- **THEN** its finalized bytes and established identity remain available for history replay without another encoding or identity hash
- **AND** its admission-time source context and creation time remain intact
- **AND** the existing single physical encoder, four-capture bound and FIFO among surviving images remain unchanged

#### Scenario: Current settings win at restore completion
- **WHEN** the history limit changes while restoration is suspended
- **THEN** baseline enforcement and replay use the normalized current limit at completion
- **AND** pinned protection and the existing image bound continue to apply

### Requirement: Save only complete startup history
Copythat MUST NOT start a history-save transaction, write capture blobs or a replacement history manifest, or collect history-media garbage before persisted baseline loading and synchronous baseline/replay application have finished. Existing corrupt-input backup writes remain permitted. Clean restoration SHALL request zero bootstrap saves; buffered capture, actual baseline trim, or another legitimate bootstrap save request SHALL produce exactly one final bootstrap save request. Saves caused by subsequent capture, preview enrichment or retry are independent of that bootstrap count. The V2 schema and lazy heavy-media references SHALL remain unchanged.

#### Scenario: Capturing during loading cannot replace the old manifest
- **WHEN** persisted history contains A and C and startup capture B arrives before loading finishes
- **THEN** no save request or history-save write occurs while loading remains suspended
- **AND** the old manifest and its referenced media remain intact
- **AND** the bootstrap save requests the final retained baseline-plus-replay snapshot, never a B-only intermediate snapshot

#### Scenario: Clean restore needs no save
- **WHEN** saved history already satisfies current bounds and no capture or other history mutation occurs during bootstrap
- **THEN** restoration itself requests no save

#### Scenario: Startup trim saves the final retained history once
- **WHEN** persisted history exceeds the current history limit or unpinned-image bound
- **THEN** ordinary bounds retain the permitted items
- **AND** bootstrap requests their final snapshot once

#### Scenario: Trim and multiple captures share one bootstrap request
- **WHEN** persisted history needs trimming and multiple finalized captures await replay
- **THEN** bootstrap requests persistence exactly once after all replay and final history reconciliation
- **AND** there is no intermediate trim snapshot or per-replayed-item save request

#### Scenario: A later image completion is an ordinary save
- **WHEN** an admitted image remains encoding when bootstrap finishes
- **AND** its eligible completion later inserts an item
- **THEN** it uses the normal insertion/save path
- **AND** this later save is not an extra baseline/replay bootstrap request

### Requirement: Complete failed startup restoration without losing new captures
Copythat SHALL complete loading with an empty baseline when restoration fails, preserving existing corrupt-input backup behavior and replaying eligible startup captures through ordinary history rules. Restore failure alone MUST NOT request an empty replacement save or leave history permanently loading.

#### Scenario: Loader failure with captured content
- **WHEN** history loading fails after startup items A and B have reached insertion
- **THEN** loading ends and A and B are replayed against an empty baseline under ordinary retention rules
- **AND** bootstrap requests one final save

#### Scenario: Loader failure without mutation
- **WHEN** history loading fails without startup capture or another legitimate save request
- **THEN** loading ends with empty in-memory history
- **AND** failure itself does not request a replacement manifest or overwrite the prior input

## MODIFIED Requirements

### Requirement: Resolve pending history saves on normal Quit
Copythat SHALL attempt to persist the latest requested history state before normal application termination completes. Normal Quit SHALL pause new capture admission without invalidating previously accepted eligible images, await persisted-history restoration and finalization/insertion of eligible images already admitted, then resolve saves through the existing flush and explicit failure-choice flow. This guarantee applies during startup and after restoration, subject to existing capture eligibility and retention rules. If the latest state remains unsaved, Copythat SHALL require an explicit user choice. Quit SHALL NOT require completion of all optional network preview enrichment.

#### Scenario: Latest history state saves during Quit
- **WHEN** the user quits while a history save is pending
- **AND** the latest requested state is successfully saved
- **THEN** Copythat completes normal termination

#### Scenario: Latest history state remains unsaved during Quit
- **WHEN** the latest requested state remains unsaved after a flush attempt
- **THEN** Copythat offers Retry, Quit Anyway, and Cancel Quit
- **AND** Copythat does not silently terminate

#### Scenario: User retries an unsaved Quit
- **WHEN** the user selects Retry
- **THEN** Copythat retries saving the latest state before resolving termination

#### Scenario: User accepts an unsaved Quit
- **WHEN** the user selects Quit Anyway
- **THEN** Copythat terminates with the previously committed history intact

#### Scenario: User cancels an unsaved Quit
- **WHEN** the user selects Cancel Quit
- **THEN** Copythat remains open with its current in-memory history
- **AND** the Quit admission pause ends and previously active monitoring resumes

#### Scenario: Quit waits for restoration and startup capture
- **WHEN** the user quits while history loading is suspended and captured B awaits replay
- **THEN** termination waits for baseline installation, replay and save resolution
- **AND** successful termination includes B in the committed snapshot if ordinary retention permits it

#### Scenario: Restore finishes before an admitted image during Quit
- **WHEN** an eligible image has been admitted but its encoding is suspended when Quit begins
- **AND** history restoration completes first
- **THEN** termination still waits for that image's finalization and eligible insertion before resolving saves
- **AND** successful encoding is not discarded merely because the startup capture buffer was empty at restore completion

#### Scenario: Admitted images finish before restore during Quit
- **WHEN** active and waiting eligible images finish after Quit begins but before history restoration completes
- **THEN** they retain the existing FIFO encoder behavior and enter startup replay
- **AND** successful termination awaits their replay and save resolution

#### Scenario: Quit after restore protects outstanding image work
- **WHEN** restoration is ready, no save has been requested yet, and an eligible admitted image remains encoding or waiting
- **THEN** Copythat does not immediately terminate solely because there is no pending save
- **AND** termination waits for accepted image work and resulting saves

#### Scenario: New copies cannot indefinitely extend a Quit drain
- **WHEN** normal Quit has paused capture admission
- **THEN** new pasteboard observations do not admit more captures until Quit is cancelled
- **AND** already accepted images are neither generation-invalidated nor dropped by the pause
- **AND** destructive history and pinboard actions cannot invalidate the accepted-work drain

#### Scenario: Failed encoding does not strand termination
- **WHEN** an admitted image fails finalization while Quit waits for accepted image work
- **THEN** its ordinary terminal handling releases its physical slot and allows subsequent accepted work to finish
- **AND** termination proceeds to save resolution once accepted eligible work is resolved

#### Scenario: Repeated Quit requests share one resolution
- **WHEN** another normal Quit request arrives while restore, image work or save resolution is being awaited
- **THEN** Copythat continues the existing termination resolution rather than replying early or starting a second one

### Requirement: Clear clipboard history manually
Copythat SHALL support manual clearing of stored clipboard history while protecting intentionally saved cards by default, only when history restoration is complete and a normal-Quit admission pause is not active. Every allowed confirmed Clear History operation SHALL invalidate all previously admitted image captures, including active and waiting captures, even when no stored card is removable. Invalidated image results SHALL NOT repopulate history or request persistence; images admitted after the clear SHALL remain eligible for ordinary capture. Clearing SHALL NOT request a history save when no stored card changes. A clear rejected during loading or Quit pause MUST cause no history, pasteboard or image-eligibility side effect.

#### Scenario: Clear ordinary cards
- **WHEN** history mutations are available and the user confirms clearing ordinary cards
- **THEN** Copythat removes stored cards that are not pinned and are not assigned to a custom pinboard
- **AND** Copythat keeps pinned cards
- **AND** Copythat keeps cards assigned to custom pinboards

#### Scenario: Clear all cards
- **WHEN** history mutations are available and the user confirms clearing all cards
- **THEN** Copythat removes stored cards regardless of pin state or custom pinboard assignment

#### Scenario: History state refreshes after clearing
- **WHEN** clipboard cards are cleared
- **THEN** Copythat updates the visible card list
- **AND** Copythat updates the current selection to a remaining visible card or clears selection when no visible cards remain
- **AND** Copythat persists the updated clipboard history

#### Scenario: Custom pinboards remain after clearing cards
- **WHEN** clipboard cards are cleared
- **THEN** Copythat keeps configured custom pinboards available

#### Scenario: Clear invalidates active and waiting images
- **WHEN** history mutations are available and the user confirms Clear History with image A active and images B and C waiting
- **THEN** none of those previously admitted captures can subsequently insert a card or trigger an additional save
- **AND** waiting captures are discarded without starting capture encoding
- **AND** the clear operation itself still persists any actual stored-card changes

#### Scenario: Clear an empty history with pending images
- **WHEN** history mutations are available and the user confirms Clear History while history is empty and image captures are pending
- **THEN** those previously admitted captures are invalidated
- **AND** the clear and their late results request no history save

#### Scenario: Clear ordinary cards when only protected cards remain
- **WHEN** history mutations are available and the user confirms clearing ordinary cards while only pinned or custom-pinboard cards remain and image captures are pending
- **THEN** protected cards and their organization remain unchanged
- **AND** all previously admitted image captures are invalidated
- **AND** no history save is requested solely for invalidation

#### Scenario: Clear is rejected before invalidation while loading or quitting
- **WHEN** clear is invoked while history restoration is incomplete or a Quit admission pause is active
- **THEN** no stored or buffered history is removed, no matching pasteboard content is cleared, and no accepted image eligibility changes
- **AND** the rejected operation requests no save and is not queued for later execution
