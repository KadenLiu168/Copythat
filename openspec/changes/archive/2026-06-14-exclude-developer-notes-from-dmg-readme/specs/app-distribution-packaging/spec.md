## MODIFIED Requirements

### Requirement: DMG includes unified README documentation
Copythat SHALL include a user-facing `README.md` in the root of the packaged DMG and SHALL NOT include the legacy generated `Install Copythat.txt` file. The DMG README SHALL preserve installation steps, temporary non-notarized build notes, Accessibility permission guidance, and current-version feature highlights, and SHALL exclude `Developer Notes` and following developer-only sections.

#### Scenario: DMG exposes README only
- **WHEN** the packaged DMG is mounted
- **THEN** the DMG root contains `README.md`
- **AND** the DMG root does not contain `Install Copythat.txt`

#### Scenario: README covers installation and version features
- **WHEN** a user opens the DMG-provided `README.md`
- **THEN** the README explains installation steps, temporary non-notarized build notes, Accessibility permission guidance, and current-version feature highlights

#### Scenario: README excludes developer notes
- **WHEN** a user opens the DMG-provided `README.md`
- **THEN** the README does not include `Developer Notes`
- **AND** the README does not include developer-only run, signing, development guideline, or verification sections
