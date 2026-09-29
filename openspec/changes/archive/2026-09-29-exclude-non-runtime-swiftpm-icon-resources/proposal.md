## Why

SwiftPM currently processes the entire icon resource directory even though Copythat only loads `MenuBarIconTemplate.png` from its resource bundle at runtime. Narrowing that input reduces the distributed app's size while preserving its custom menu-bar icon, application icon, and existing branding and packaging verification contracts.

## What Changes

- Make `Package.swift` the only production file changed: declare `.process("Resources/MenuBarIconTemplate.png")` and target-level exclusions for `Resources/AppIcon.icns`, `Resources/AppIcon-transparent.png`, and `Resources/Assets.xcassets`.
- Keep all four source resources unchanged. Continue staging the outer `Contents/Resources/AppIcon.icns` directly from source through the existing packaging script.
- Verify that the SwiftPM bundle contains only the menu-bar image as runtime payload, allowing bundle metadata and signatures, in either flat or nested resource layouts.
- Measure comparable before/after app sizes and require a clear reduction, without treating an approximate expected size as a fixed threshold. Require both bundle inspection and visual confirmation of the custom menu-bar icon.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. Existing `app-branding` and `app-distribution-packaging` requirements remain unchanged. This change explicitly opts out of delta specs through `skip_specs: true`.

## Impact

- `Package.swift` narrows SwiftPM target inputs using paths relative to `Sources/Copythat`; no dependencies or runtime loading changes are needed.
- `CopythatIcon.swift` continues loading the menu-bar template from the staged bundle, with its existing `c.circle` fallback. Successful launch alone is therefore insufficient acceptance evidence.
- `script/build_and_run.sh` continues copying the outer app icon and the complete SwiftPM bundle. Existing flat/nested layout support remains intact.
- `script/verify_all.sh` continues checking the catalog and transparent PNG in the source tree. Existing packaging fixtures, portable launch, panel, and codesign checks remain mandatory.
- Incremental build outputs may retain obsolete resources; investigate any unexpected payload and verify fresh output without changing verification contracts or deleting source assets.

## Non-goals

- Do not delete or alter icon resources, artwork, generated pixels, or resource generation logic.
- Do not modify `script/generate_icons.py`, `script/build_and_run.sh`, `script/verify_all.sh`, `script/verify/packaging_test.sh`, `CopythatIcon.swift`, or `openspec/specs/app-branding/spec.md`.
- Do not use `.process("Resources", exclude: ...)`, absolute exclusion paths, or repository-root-relative exclusion paths.
- Do not refactor resource loading, change application functionality, or weaken a failing validation script. Any confirmed new problem requires diagnosis before reconsidering scope.
- No separate design artifact is needed for this single-target manifest adjustment; it introduces no cross-module changes or lifecycle, permission, or persistence decisions.

## Rollback

Restore only the manifest change, preserving unrelated edits, or revert its focused implementation commit. Resource files require no restoration because they remain unchanged.
