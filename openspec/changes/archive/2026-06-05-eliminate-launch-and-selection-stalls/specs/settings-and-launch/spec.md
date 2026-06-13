## ADDED Requirements

### Requirement: Launch responsively with persisted history
Copythat SHALL avoid repeating expensive media transformation work when restoring clipboard items that are already stored in the current persistence format.

#### Scenario: Application launches with image-heavy history
- **WHEN** Copythat launches with persisted clipboard history containing images and source icons
- **THEN** Copythat restores the persisted items without re-encoding each item's stored media
- **AND** the menu bar application becomes usable without waiting for redundant media transformation

