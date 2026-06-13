# Local Development Signing Specification

## Purpose
Copythat supports stable local signing for the staged macOS app used during development and manual Accessibility testing.

## Requirements

### Requirement: Use configured local signing identity
Copythat's development build script SHALL sign the staged macOS app with a configured code-signing identity when one is provided.

#### Scenario: Local identity is configured
- **WHEN** the development build script creates `dist/Copythat.app`
- **AND** a local code-signing identity is configured
- **THEN** the staged app is signed with that identity
- **AND** the existing bundle identifier remains unchanged

#### Scenario: Local identity is unavailable
- **WHEN** the development build script creates `dist/Copythat.app`
- **AND** the configured code-signing identity cannot be used
- **THEN** the build fails with a clear signing error

### Requirement: Preserve ad hoc fallback
Copythat's development build script SHALL continue to support ad hoc signing when no local code-signing identity is configured.

#### Scenario: No local identity is configured
- **WHEN** the development build script creates `dist/Copythat.app`
- **AND** no local code-signing identity is configured
- **THEN** the staged app is signed with the existing ad hoc fallback

### Requirement: Support Accessibility trust verification
Copythat SHALL provide developer-facing guidance or verification steps for confirming the staged app's signing mode before manual Accessibility testing.

#### Scenario: Signing mode is inspected
- **WHEN** a developer verifies the staged app after a build
- **THEN** the verification output identifies whether the app is signed with the configured identity or with ad hoc signing

#### Scenario: Accessibility trust is retested after signing change
- **WHEN** a developer switches from ad hoc signing to a stable local signing identity
- **THEN** the documentation explains that the old Accessibility entry may need to be removed once before granting access to the newly signed staged app
