## Context

Copythat's staged app is built by `script/build_and_run.sh` into `dist/Copythat.app`. The script currently signs the bundle with `codesign --sign -`, which produces an ad hoc signature. For Accessibility trust, macOS TCC can treat ad hoc rebuilds as a different trusted subject because the designated requirement is effectively tied to the current code hash.

The user wants double-click and Enter to keep performing automatic paste. The problem to solve is not paste behavior; it is local development identity stability after rebuilding the app.

## Goals / Non-Goals

**Goals:**

- Allow local development builds to use a stable signing identity when one is configured.
- Preserve ad hoc signing as the zero-setup fallback.
- Make the active signing mode visible enough to diagnose Accessibility trust issues.
- Document setup and reset steps for local Accessibility testing.

**Non-Goals:**

- No Apple Development, Developer ID, notarization, or distribution workflow.
- No runtime changes to Accessibility prompts, paste execution, or panel interaction.
- No automated edits to macOS TCC permission databases.
- No new Swift package dependency.

## Decisions

### Decision: Use an optional environment variable for signing identity

`script/build_and_run.sh` should read a local signing identity from an environment variable such as `CODESIGN_IDENTITY`. When set, the script signs `dist/Copythat.app` with that identity. When unset, it continues using ad hoc signing.

Alternative considered: hard-code a local certificate name. This is brittle across machines and would make the script fail for users who have not created the same certificate.

Alternative considered: require an Apple signing identity. This is unnecessary for the local development problem and contradicts the current constraint that no Apple Development or Developer ID certificate is available.

### Decision: Keep the staged app path and bundle identifier stable

The script should continue producing `/Users/kaden/Copythat/dist/Copythat.app` with the existing bundle identifier. A stable signing identity works best when paired with a stable app path and bundle ID during manual Accessibility testing.

Alternative considered: run the SwiftPM binary directly. That would avoid bundle rebuilds but would not match the menu bar app bundle and permission surface being tested.

### Decision: Verification uses signing inspection plus manual Accessibility check

Automated verification should inspect the resulting signature and confirm either the configured identity or ad hoc fallback. The final Accessibility behavior still requires a manual macOS session check because granting and observing TCC trust is outside reliable headless verification.

Alternative considered: script TCC database resets. This is intrusive, varies by macOS version, and is not necessary for the build script change.

## Risks / Trade-offs

- Local self-signed certificates may not exist on a fresh machine -> keep ad hoc fallback and document setup.
- macOS may retain stale Accessibility entries from prior ad hoc builds -> document removing the old Copythat entry and granting the newly signed app once.
- A configured identity could be misspelled or unavailable -> make signing fail clearly rather than silently falling back to a different identity.
- This improves local development trust stability but does not solve production update trust -> keep production signing out of scope until Developer ID or another distribution path exists.

## Migration Plan

1. Add optional identity-based signing to the build script.
2. Add documentation for creating a local Code Signing certificate and exporting `CODESIGN_IDENTITY`.
3. Add or update verification so the current signing mode can be inspected.
4. For manual testing, remove the old Accessibility entry for Copythat, rebuild with the local identity, grant Accessibility once, then rebuild and confirm automatic paste no longer prompts again.

Rollback is simple: unset `CODESIGN_IDENTITY` and the build script returns to ad hoc signing.

## Open Questions

- None for this change. The exact local certificate name remains user-configurable through the environment variable.
