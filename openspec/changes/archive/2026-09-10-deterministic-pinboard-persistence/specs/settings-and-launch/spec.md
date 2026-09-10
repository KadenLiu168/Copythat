## MODIFIED Requirements

### Requirement: Configure custom pinboards
Copythat SHALL persist each custom pinboard's trimmed name and selected color independently from Settings. The persisted representation SHALL be deterministic: for identical pinboard content, the stored bytes SHALL be identical across launches and processes.

#### Scenario: Custom pinboard is created
- **WHEN** the user creates a custom pinboard from the bottom panel
- **THEN** Copythat stores the pinboard's trimmed name and selected color

#### Scenario: Application relaunches
- **WHEN** Copythat launches with stored custom pinboards
- **THEN** each custom pinboard retains its name, order, and selected color

#### Scenario: Stored pinboard data is stable
- **WHEN** Copythat persists the same custom pinboard content in two separate launches
- **THEN** the stored representation is byte-identical
- **AND** the stored content decodes to the same pinboards, in the same order, with the same colors

#### Scenario: Existing custom pinboards are migrated
- **WHEN** Copythat launches with legacy custom pinboard names and no structured colored-pinboard data
- **THEN** Copythat preserves each non-empty unique trimmed name in its existing order
- **AND** assigns each migrated pinboard a stable color from the fixed palette
- **AND** preserves clipboard-item assignments that refer to those names

#### Scenario: No custom pinboards are configured
- **WHEN** the custom pinboard list is empty
- **THEN** Copythat still provides the Clipboard and Pinned pinboards
