## Why

The DMG now includes `README.md`, but it copies the full repository README including developer-only sections. DMG users should receive concise installation and feature guidance without build, verification, and development notes.

## What Changes

- Generate the DMG `README.md` from the user-facing portion of the repository README.
- Exclude `Developer Notes` and all following developer-only sections from the DMG copy.
- Keep installation steps, temporary non-notarized build notes, Accessibility guidance, and current-version feature highlights in the DMG README.
- Extend DMG verification to fail if the packaged README includes `Developer Notes`.

## Non-goals

- Do not remove developer notes from the repository README.
- Do not add a second hand-maintained README source.
- Do not change app runtime behavior, signing, notarization, or DMG layout.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `app-distribution-packaging`: DMG README packaging now excludes developer-only notes while preserving user-facing install and feature guidance.

## Impact

- Affects `script/package_dmg.sh` and the app distribution packaging spec.
- No Swift runtime, public API, dependency, signing, or app UI changes.
