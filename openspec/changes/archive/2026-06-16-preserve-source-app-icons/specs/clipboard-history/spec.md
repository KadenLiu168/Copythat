## MODIFIED Requirements

### Requirement: Persist restorable history metadata
Copythat SHALL persist clipboard history with enough metadata to restore supported items and display their context after relaunch.

#### Scenario: App relaunches with prior history
- **WHEN** Copythat starts after previously saving history
- **THEN** previously saved items are loaded with kind, title, preview, source app, timestamp, pin state, pinboard assignment, and restorable content where available

#### Scenario: Stored media is optimized while source icons are preserved
- **WHEN** clipboard history data is saved with image data, link preview image data, or source icon data
- **THEN** Copythat stores optimized image and link preview image data suitable for history display and restoration
- **AND** Copythat preserves the captured source icon data for each item without downsampling it during storage optimization
