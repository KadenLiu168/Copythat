## Context

`script/package_dmg.sh` builds `dist/Copythat.app`, creates a temporary DMG root, copies the app bundle, adds an `Applications` symlink, and writes `Install Copythat.txt` directly into the DMG. The repository `README.md` already contains development and temporary DMG notes, but DMG users currently receive installation instructions in a separate file.

## Goals / Non-Goals

**Goals:**
- Make `README.md` the single documentation file included in the DMG.
- Put Chinese user-facing installation steps and version feature highlights near the top of the README.
- Keep the DMG packaging verification explicit about expected documentation contents.

**Non-Goals:**
- Change signing, notarization, app runtime behavior, or permissions behavior.
- Add a second README source or generated documentation step.
- Change the DMG visual layout.

## Decisions

- Copy the root `README.md` into the DMG instead of generating DMG-specific text. This keeps documentation in one source and avoids stale install instructions.
- Verify both the new and removed documentation files in `package_dmg.sh`. Checking that `README.md` exists and `Install Copythat.txt` does not exist catches regressions in the generated DMG contents.
- Keep the README bilingual only where necessary by adding Chinese user-facing sections above the existing English development sections. This satisfies installer readability without rewriting unrelated developer documentation.

## Risks / Trade-offs

- Root README becomes longer for developers -> Mitigation: put user-facing sections first and preserve developer sections under clear headings.
- DMG includes development content below the user sections -> Mitigation: installation and feature guidance are placed at the top so DMG users do not need to read the developer sections.
