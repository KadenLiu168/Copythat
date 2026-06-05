## Why

Distributed builds of Copythat can fail to launch when SwiftPM resources are only available through the developer machine's `.build` output instead of the staged `.app`. This blocks reliable installation on another Mac or from a copied `dist/Copythat.app`.

## What Changes

- Package the SwiftPM-generated `Copythat_Copythat.bundle` in the signed app's resources and load it from there at runtime.
- Add verification that the staged app contains the resource bundle in the expected location and does not rely on the repo-local `.build` path to start.
- Review packaging and runtime code for other hardcoded development-build paths, and fix any same-class install-location issues found.

## Non-goals

- No changes to clipboard capture, paste behavior, UI layout, or source attribution.
- No notarization workflow changes beyond preserving the existing signing validation.
- No broad resource-loading abstraction beyond the current bundled icon resources.

## Capabilities

### New Capabilities
- `app-distribution-packaging`: Defines requirements for staged Copythat app bundles to be self-contained and movable outside the development checkout.

### Modified Capabilities

## Impact

- Affects `script/build_and_run.sh`, package verification scripts, and any code paths that assume development-only resource locations.
- Verification includes SwiftPM build/test coverage plus staged app bundle structure and launch checks.
