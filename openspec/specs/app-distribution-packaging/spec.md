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

### Requirement: Packaging verification accepts nested SwiftPM resource bundles
Copythat SHALL stage SwiftPM resource bundles so runtime resources remain available at their bundle resource URL, whether SwiftPM places them at the bundle root or under the standard macOS `Contents/Resources` directory.

#### Scenario: Nested SwiftPM resources are staged
- **WHEN** SwiftPM produces a resource bundle with runtime assets under `Contents/Resources`
- **THEN** packaging preserves the complete resource bundle structure
- **AND** packaging verification accepts `MenuBarIconTemplate.png` at that resource location

#### Scenario: Required runtime image is missing
- **WHEN** neither supported resource location contains `MenuBarIconTemplate.png`
- **THEN** packaging verification fails before treating the app bundle as complete

#### Scenario: DMG packaging accepts nested resources
- **WHEN** a staged app contains `MenuBarIconTemplate.png` under its SwiftPM resource bundle's `Contents/Resources` directory
- **THEN** DMG packaging accepts that resource layout without changing the staged bundle structure

### Requirement: Staged app icon metadata and resource are present
Copythat SHALL stage a readable outer app `Contents/Info.plist` that declares `AppIcon` and includes the referenced `AppIcon.icns` in the outer app's `Contents/Resources` before packaging succeeds.

#### Scenario: App bundle icon is available to Finder
- **WHEN** app bundle packaging succeeds
- **THEN** the outer app `Info.plist` declares `CFBundleIconFile` as `AppIcon`
- **AND** `Contents/Resources/AppIcon.icns` exists in the outer app bundle
