## Why

The temporary DMG currently includes a separate `Install Copythat.txt`, which splits installation guidance away from the main project documentation. Users should see one README in the DMG that explains installation, permission setup, and the main features included in the current version.

## What Changes

- Replace the DMG's generated `Install Copythat.txt` with a copied `README.md`.
- Update `README.md` with Chinese user-facing installation steps and current-version feature highlights.
- Keep temporary non-notarized build guidance and Accessibility permission guidance in the README.
- Update DMG verification so packaging fails if `README.md` is missing or the old install text file is present.

## Non-goals

- Do not change app runtime behavior, signing behavior, notarization status, or installer mechanics.
- Do not add a second DMG-specific README source.
- Do not redesign the DMG window layout or add background artwork.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `app-distribution-packaging`: DMG packaging now requires a user-facing README and no longer includes the generated install text file.

## Impact

- Affects `README.md`, `script/package_dmg.sh`, and the app distribution packaging spec.
- No public API, dependency, Swift runtime, or app UI changes.
