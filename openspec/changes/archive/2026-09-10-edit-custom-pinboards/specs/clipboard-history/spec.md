## ADDED Requirements

### Requirement: Preserve pinboard assignments across pinboard rename
Copythat SHALL keep clipboard history items attached to a custom pinboard when that pinboard is renamed, and SHALL persist the migrated assignments.

#### Scenario: Assigned items follow the rename
- **WHEN** a custom pinboard is renamed
- **THEN** every history item assigned to the pinboard's old name becomes assigned to the new name
- **AND** history items assigned to other pinboards or to no pinboard are unchanged
- **AND** no history item is deleted, unpinned, or otherwise modified

#### Scenario: Migrated assignments survive relaunch
- **WHEN** Copythat starts after a custom pinboard was renamed in a previous session
- **THEN** previously assigned history items are loaded with the pinboard's new name as their assignment
- **AND** the pinboard's edited color is restored
