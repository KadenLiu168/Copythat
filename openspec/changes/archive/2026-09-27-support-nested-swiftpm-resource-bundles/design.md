## Context

See `proposal.md` for motivation and `specs/app-distribution-packaging/spec.md` for the behavior contract. `Package.swift` processes `Sources/Copythat/Resources` into `Copythat_Copythat.bundle`. `build_and_run.sh` copies that directory intact to the outer app's `Contents/Resources`, but its current check looks only at the bundle root. `CopythatIcon` loads the staged bundle through Foundation `Bundle` and asks it for `MenuBarIconTemplate.png`. `package_dmg.sh` repeats the root-only check. The current local build emits a flat bundle; nested layout is an unverified toolchain variation.

## Goals / Non-Goals

**Goals:** Preserve the generated SwiftPM bundle structure, accept flat and macOS nested resource locations, and fail packaging if the staged app lacks a readable icon declaration or referenced icon file.

**Non-Goals:** Change icon artwork, alter `CopythatIcon` resource lookup, or address Finder and Launch Services caches.

## Decisions

1. Copy the entire SwiftPM resource bundle unchanged. After staging, check `MenuBarIconTemplate.png` at the bundle root and `Contents/Resources`. Foundation `Bundle` can use the native structure of each layout. Repacking assets into a single layout would add a transformation and risk breaking runtime lookup.
2. Apply the same accepted locations to the DMG packaging check. Its input is the already staged app, so it must not reject a bundle that `build_and_run.sh` accepted. Keep the check within the existing scripts rather than introduce a new packaging abstraction for two callers.
3. Validate the outer `Info.plist` after writing it, including `CFBundleIconFile=AppIcon`, and require outer `Contents/Resources/AppIcon.icns` before signing succeeds. Missing source artwork must fail explicitly; the existing conditional copy must not permit a successful incomplete app.
4. Add isolated fixture checks for flat, nested, and missing assets and icon metadata. Run the existing build, full verification, and portable launch checks for integration. A local toolchain that only emits one layout cannot prove the other layout without fixtures.

## Risks / Trade-offs

- [A copied asset could exist but fail to load through Foundation `Bundle`] → Preserve bundle structure and retain the portable launch check; fixture checks establish path handling but cannot replace a runtime check on a nested-layout toolchain.
- [A packaging failure leaves a partial `dist/Copythat.app`] → Fail with a clear error and never report packaging success; cleanup of partial output can be considered during Apply without changing the contract.

## Migration Plan

No data migration. Apply the script and verification changes together; revert those changes to restore prior packaging behavior if needed.
