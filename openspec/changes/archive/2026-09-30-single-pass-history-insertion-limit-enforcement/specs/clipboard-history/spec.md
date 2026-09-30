## MODIFIED Requirements

### Requirement: Maintain bounded and deduplicated history
Copythat SHALL reuse an existing unpinned entry when its content is copied again instead of adding another ordinary entry, and SHALL retain the newest eligible ordinary items within the configured history limit and the existing unpinned-image bound. Pinned items SHALL NOT be removed by either bound; when pinned items alone exceed the configured history limit, actual history SHALL be allowed to exceed that limit to retain pinned items.

#### Scenario: Existing unpinned content is copied again
- **WHEN** a clipboard item has the same content key as an existing unpinned history item
- **THEN** Copythat keeps the existing matching entry and moves it to the newest position
- **AND** the existing item's captured source app, source icon, ID, and creation time remain unchanged
- **AND** other previously present entries are subject only to the existing retention rules

#### Scenario: Existing pinned content is copied again
- **WHEN** a clipboard item has the same content key as an existing pinned history item and no unpinned match
- **THEN** Copythat keeps the pinned entry
- **AND** Copythat records the newly copied item as the newest ordinary history item if it survives the retention bounds

#### Scenario: History exceeds the configured limit
- **WHEN** adding a clipboard item would exceed the configured history limit
- **THEN** Copythat removes the oldest eligible unpinned items before any pinned items
- **AND** history remains within the configured limit unless pinned items alone exceed that limit

#### Scenario: Pinned items exhaust the limit
- **WHEN** pinned items already fill the configured history limit and a new unpinned item is copied
- **THEN** Copythat keeps the pinned items and discards the new item if no capacity remains
- **AND** selection does not point to the discarded item

#### Scenario: Pinned items exceed the limit
- **WHEN** the configured limit is lower than the number of pinned items
- **THEN** Copythat retains all pinned items even if history exceeds the configured limit
- **AND** unpinned items are removed before pinned items

#### Scenario: Unpinned image history reaches its bound
- **WHEN** a newly copied image would exceed the unpinned-image bound
- **THEN** Copythat retains the newest eligible unpinned images and removes the oldest excess unpinned images
- **AND** pinned images do not count against that bound

## ADDED Requirements

### Requirement: Apply history bounds to existing history
Copythat SHALL apply the configured history limit and existing unpinned-image bound to already stored history without requiring another copy. Automatic retention eviction SHALL NOT be treated as a user-requested deletion.

#### Scenario: History limit is reduced
- **WHEN** the user reduces the configured history limit below the size of existing removable history
- **THEN** Copythat trims eligible existing items without waiting for another copy
- **AND** the visible history and selection reflect the retained items
- **AND** Copythat requests persistence of the final retained history state once for that trim

#### Scenario: History limit increases or no trim is needed
- **WHEN** the user changes the configured history limit and no existing item needs to be removed
- **THEN** Copythat keeps history and selection unchanged
- **AND** the limit change alone does not request a history save

#### Scenario: Restore history above the configured bounds
- **WHEN** Copythat starts with saved history exceeding the configured history limit or unpinned-image bound
- **THEN** Copythat presents only the retained history according to the same bounds and pinned-item protection
- **AND** requests persistence of the final retained history state when items were trimmed

#### Scenario: Automatic eviction is not a manual deletion
- **WHEN** an item is removed because a history bound is enforced
- **THEN** Copythat does not clear matching content from the system pasteboard or suppress a future intentional copy of that content
- **AND** pending preview work for the removed item cannot later restore it or request a save
