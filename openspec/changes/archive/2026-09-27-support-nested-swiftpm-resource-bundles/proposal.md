## Why

`build_and_run.sh` and `package_dmg.sh` assume SwiftPM resources are at the root of the generated resource bundle. If SwiftPM emits the macOS `Contents/Resources` layout, staging fails before the outer app `Info.plist` is written, potentially leaving an incomplete `.app` with no Finder icon. The current local build uses the flat layout; the nested-layout failure path still needs fixture-based verification.

## What Changes

- Stage and verify SwiftPM resources when the generated resource bundle uses the nested macOS layout, while preserving the bundle structure used by runtime lookup.
- Accept both resource layouts in the DMG packaging check.
- Verify the staged app has its outer `Info.plist` and `AppIcon.icns` before treating packaging as successful.

## Non-goals

- Changing the app icon artwork or menu bar icon rendering.
- Changing clipboard, panel, or paste behavior.
- Addressing Finder or Launch Services caches.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `app-distribution-packaging`: require support and verification for the nested SwiftPM resource bundle layout and the staged app icon metadata/resource.

## Impact

- `script/build_and_run.sh`, `script/package_dmg.sh`, and `script/verify_all.sh` packaging checks for the generated `Copythat.app`.
