## ADDED Requirements

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
