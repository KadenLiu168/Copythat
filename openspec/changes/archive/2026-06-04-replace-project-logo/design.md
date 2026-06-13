## Context

Copythat currently bundles app icon resources under `Sources/Copythat/Resources/`, including `Assets.xcassets/AppIcon.appiconset`, `AppIcon.iconset`, `AppIcon.icns`, `AppIcon-1024.png`, `AppIcon-transparent.png`, and `MenuBarIconTemplate.png`. The existing `script/generate_icons.py` draws the old red C mark procedurally, so simply replacing generated PNG outputs would be fragile because a later icon regeneration would restore the old mark.

The new logo source is `/Users/kaden/Copythat/script/assets/Copythat.png`, a 1254 x 1254 PNG. The implementation should treat that file as the source artwork for regenerated app branding assets.

## Goals / Non-Goals

**Goals:**

- Regenerate bundled Copythat app icon assets from the new logo source.
- Keep generated icon dimensions and resource filenames compatible with the current build and verification scripts.
- Preserve the transparent in-app logo asset with transparent corners.
- Keep verification focused on existing icon checks and application build health.

**Non-Goals:**

- No UI layout redesign.
- No changes to clipboard history, source attribution, paste, search, pinboards, permissions, shortcuts, or settings behavior.
- No new runtime dependency or user-facing setting for alternate branding.

## Decisions

1. Use the provided PNG as the generation source.

   Rationale: the user supplied finalized artwork, and using it directly avoids reinterpreting the logo in code. The generator should resize and compose from the source image instead of drawing a new mark.

   Alternative considered: manually overwrite only the checked-in PNG assets. That is faster once, but it leaves `script/generate_icons.py` producing stale branding on the next regeneration.

2. Preserve the existing resource contract.

   Rationale: `script/build_and_run.sh`, `script/verify_all.sh`, and bundled resources already expect the current filenames and icon sizes. Keeping those paths stable limits implementation to branding assets and generation logic.

   Alternative considered: introduce a new asset name for the new logo. That would require touching callers and packaging logic without changing user-visible behavior beyond the logo.

3. Treat the menu bar icon as a template asset unless visual review shows it is intentionally branded.

   Rationale: menu bar icons should remain compact and system-adaptable. If the current template icon is generated from the old mark, it should be refreshed from the new source in monochrome/template form; otherwise no unrelated menu bar behavior should change.

   Alternative considered: use the full-color new logo in the menu bar. That risks poor contrast in light/dark menu bar states and changes behavior beyond the requested logo replacement.

## Risks / Trade-offs

- New source image is 1254 x 1254 rather than an exact 1024 source -> Resize with high-quality sampling and verify all generated output dimensions.
- Source artwork includes a light rounded-square background -> `AppIcon-transparent.png` may need to derive only a transparent presentation of the full logo or preserve transparent corners according to the existing verification contract.
- Full-color artwork may be unsuitable for a menu bar template icon -> Generate or preserve a monochrome template asset and manually inspect menu bar readability if implementation touches it.
- `.icns` generation depends on `iconutil` on macOS -> Keep existing script behavior and verify `AppIcon.icns` is rebuilt successfully.

## Migration Plan

1. Update icon generation to load `script/assets/Copythat.png` and generate the existing output files from it.
2. Regenerate all app icon resources and `.icns`.
3. Run `swift build` and `./script/verify_all.sh`.
4. If the new resources fail verification, adjust only the generation logic and rerun the same checks.

Rollback is replacing the generated resources and generator logic with the previous committed versions.

## Open Questions

None.
