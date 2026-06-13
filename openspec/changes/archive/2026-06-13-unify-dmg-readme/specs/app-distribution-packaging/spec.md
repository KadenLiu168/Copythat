## ADDED Requirements

### Requirement: DMG includes unified README documentation
Copythat SHALL include a user-facing `README.md` in the root of the packaged DMG and SHALL NOT include the legacy generated `Install Copythat.txt` file.

#### Scenario: DMG exposes README only
- **WHEN** the packaged DMG is mounted
- **THEN** the DMG root contains `README.md`
- **AND** the DMG root does not contain `Install Copythat.txt`

#### Scenario: README covers installation and version features
- **WHEN** a user opens the DMG-provided `README.md`
- **THEN** the README explains installation steps, temporary non-notarized build notes, Accessibility permission guidance, and current-version feature highlights
