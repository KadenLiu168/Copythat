## Context

Copythat is a SwiftPM executable that uses `.process("Resources")` and reads images through `Bundle.module`. SwiftPM generates a resource accessor that first looks for `Copythat_Copythat.bundle` next to `Bundle.main.bundleURL`, then falls back to the absolute `.build` resource bundle path. For a macOS app wrapper, `Bundle.main.bundleURL` resolves to `Copythat.app`, which would put the generated lookup at the app wrapper root.

The current packaging script copies the resource bundle to `Copythat.app/Contents/Resources/`. That location is conventional and code-signable for app resources, but it does not match the generated SwiftPM accessor. Copying the bundle to the app wrapper root would match the accessor but fails macOS code signing as unsealed root contents, so the runtime loader for Copythat's icon resources must prefer the code-signable app resource location before falling back to `Bundle.module` for development and tests.

## Goals / Non-Goals

**Goals:**
- Make `dist/Copythat.app` self-contained for bundled icon resources.
- Verify staged app resources without relying on the repo-local `.build` directory.
- Review the codebase for similar development-build path assumptions and fix any found in scope.

**Non-Goals:**
- Do not replace SwiftPM's resource accessor with a custom app-wide resource loading layer.
- Do not change app behavior, UI, signing policy, or notarization flow.
- Do not alter generated `.build` files.

## Decisions

1. Keep `Copythat_Copythat.bundle` in `Contents/Resources` and load it explicitly for app launches.

   Rationale: The app wrapper root matches SwiftPM's generated lookup, but macOS code signing rejects unsealed root contents. `Contents/Resources` is the valid signed app location, and `CopythatIcon` is the only current runtime consumer of SwiftPM image resources.

2. Keep `AppIcon.icns` in `Contents/Resources`.

   Rationale: `CFBundleIconFile` is app metadata handled by Launch Services, not SwiftPM `Bundle.module` resource loading. The existing location is correct for the icon.

3. Add a portable app verification mode to the build script and call it from the full verification script.

   Rationale: A structure check alone can miss the generated `.build` fallback. A portable verification copies the staged app to a temporary location, temporarily hides the local resource bundle, launches the copy, and asserts the process starts.

## Risks / Trade-offs

- Future direct `Bundle.module` uses could reintroduce the development fallback -> Mitigation: the path review covers current code, and portable verification will fail if launch-critical resources rely on `.build`.
- Temporarily hiding the local `.build` resource bundle during verification could disrupt a concurrent local launch -> Mitigation: the script already terminates running Copythat before builds, and the hide/restore operation is scoped with a shell trap.
