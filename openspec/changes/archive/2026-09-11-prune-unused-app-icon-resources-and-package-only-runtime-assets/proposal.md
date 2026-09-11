## Why

The Resources directory contains both runtime assets and generator intermediates that SwiftPM processes into the application bundle even though the shipped app does not read them. Keeping duplicate full-size icon outputs and an obsolete permission declaration increases bundle size and makes packaging ownership unclear.

## What Changes

- Inventory every icon and permission resource against `Package.swift`, `CopythatIcon`, the icon generator, packaging scripts, and `verify_all.sh`.
- Remove only proven-unused shipped outputs, initially the standalone `AppIcon-1024.png` and checked-in `AppIcon.iconset`; make icon generation use a temporary iconset while continuing to produce the packaged `AppIcon.icns`.
- Preserve `Assets.xcassets/AppIcon.appiconset`, `AppIcon-transparent.png`, `AppIcon.icns`, and `MenuBarIconTemplate.png` where the existing branding or verification contract still requires them.
- Remove the unused `NSScreenCaptureUsageDescription` declaration and update packaging verification so it checks the permissions the app actually requests.
- Keep the staged app self-contained and preserve the current app branding, menu-bar icon, launch behavior, and relocation checks.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This is a packaging/resource ownership cleanup; required branding and launch behavior remain unchanged.

## Impact

- **Resources:** `Sources/Copythat/Resources/` loses only verified generator intermediates or unused outputs; required runtime and contract resources remain.
- **Tooling:** `script/generate_icons.py`, `script/verify_all.sh`, and packaging scripts are updated to use the reduced resource set.
- **Bundle:** SwiftPM no longer ships proven-unused duplicate icon data, while the staged app still receives `AppIcon.icns` and its resource bundle.
- **Permissions:** the generated Info.plist no longer advertises screen-capture access that the panel implementation does not use.
- **Verification:** icon dimensions, transparent corners, resource relocation, codesigning, `swift build`, and `./script/verify_all.sh` must remain valid.

## Non-goals

- Changing the Copythat logo artwork, icon appearance, or menu-bar template.
- Removing any asset still required by `app-branding` or packaging verification merely to reduce byte count.
- Removing `targetAppTouchesScreenBottom` or changing panel placement behavior.
- Changing clipboard capture, source attribution, paste behavior, persistence, or permissions actually required by AppKit APIs.
- Claiming a fixed size reduction before measuring the resulting bundle.
