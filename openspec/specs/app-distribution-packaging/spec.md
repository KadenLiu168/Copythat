## Purpose

Defines how Copythat stages distributable macOS app bundles so they remain self-contained after relocation.

## Requirements

### Requirement: Distributed app bundle is self-contained
Copythat SHALL stage a distributable app bundle that contains all runtime resources required for launch without reading resources from the development checkout.

#### Scenario: App launches after relocation
- **WHEN** the staged `Copythat.app` is copied outside the repository and launched
- **THEN** Copythat starts without requiring any resource under the repository `.build` directory

#### Scenario: SwiftPM resources are available in the staged app
- **WHEN** Copythat loads bundled images through its SwiftPM resource bundle
- **THEN** the staged app provides those resources from inside the copied `Copythat.app`

### Requirement: Packaging verification covers resource relocation
Copythat SHALL verify that packaged runtime resources are present at the location used by the app at launch.

#### Scenario: Verification catches misplaced SwiftPM resources
- **WHEN** the resource bundle is not present at the runtime lookup location inside the staged app
- **THEN** packaging verification fails before treating the app as distributable

### Requirement: DMG includes unified README documentation
Copythat SHALL include a user-facing `README.md` in the root of the packaged DMG and SHALL NOT include the legacy generated `Install Copythat.txt` file.

#### Scenario: DMG exposes README only
- **WHEN** the packaged DMG is mounted
- **THEN** the DMG root contains `README.md`
- **AND** the DMG root does not contain `Install Copythat.txt`

#### Scenario: README covers installation and version features
- **WHEN** a user opens the DMG-provided `README.md`
- **THEN** the README explains installation steps, temporary non-notarized build notes, Accessibility permission guidance, and current-version feature highlights
