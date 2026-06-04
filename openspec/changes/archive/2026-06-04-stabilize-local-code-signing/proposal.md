## Why

Copythat currently builds `dist/Copythat.app` with ad hoc signing, so macOS Accessibility trust can be tied to a changing code hash during local rebuilds. This makes automatic paste feel broken in development because users can grant Accessibility access and still be prompted again after the next build.

## What Changes

- Add a local development signing path that uses a configured stable code-signing identity when available.
- Keep ad hoc signing as the fallback when no local identity is configured.
- Document how to create and use a local self-signed Code Signing certificate for development.
- Add verification steps that confirm the staged app is signed with the expected identity and that ad hoc fallback still works.
- Do not change double-click or Enter paste behavior.
- Do not require Apple Development or Developer ID credentials for local development.

## Capabilities

### New Capabilities
- `local-development-signing`: Covers stable local signing for the staged macOS app used during development and manual Accessibility testing.

### Modified Capabilities

None.

## Non-goals

- No change to Copythat's automatic paste flow or Accessibility permission prompts at runtime.
- No support for production distribution, notarization, or Developer ID signing.
- No changes to SwiftUI panel interaction, pasteboard restore behavior, or TCC database management.

## Impact

- Affects `script/build_and_run.sh` and project documentation.
- May add a lightweight verification script or mode for signing inspection.
- Manual verification still requires granting Accessibility access on a real macOS session after switching signing identity.
