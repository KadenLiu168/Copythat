## Purpose

Defines how Copythat presents its bundled application logo and app icon resources.

## Requirements

### Requirement: Application logo uses latest artwork
Copythat SHALL use the latest provided Copythat logo artwork as the source for bundled application logo and app icon resources.

#### Scenario: App branding resources are generated
- **WHEN** the project app icon resources are generated or inspected
- **THEN** the generated app icon images, packaged app icon, and transparent app logo resource reflect the latest provided Copythat logo artwork

#### Scenario: Branding update preserves app behavior
- **WHEN** Copythat launches with the updated branding resources
- **THEN** clipboard history, paste, search, pinboard, shortcut, permissions, launch-at-login, and panel behavior remain unchanged

### Requirement: Application icon resources remain build-compatible
Copythat SHALL keep the bundled application icon resources compatible with the existing macOS app packaging and verification flow.

#### Scenario: Required app icon sizes exist
- **WHEN** icon verification checks the bundled app icon image set
- **THEN** square PNG resources exist for 16, 32, 64, 128, 256, 512, and 1024 pixel sizes

#### Scenario: Transparent logo resource keeps transparent corners
- **WHEN** icon verification checks the transparent app logo resource
- **THEN** the transparent app logo resource is 1024 x 1024 pixels
- **AND** its corner pixels are transparent

#### Scenario: Packaged app uses updated icon
- **WHEN** Copythat is packaged as a macOS app bundle
- **THEN** the bundle uses the regenerated application icon resource for the Copythat app identity
