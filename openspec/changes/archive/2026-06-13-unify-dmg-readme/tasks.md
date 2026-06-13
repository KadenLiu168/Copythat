## 1. README Documentation

- [x] 1.1 Add Chinese installation steps, non-notarized build notes, Accessibility guidance, and current-version feature highlights near the top of `README.md`; verify by inspecting the README.

## 2. DMG Packaging

- [x] 2.1 Replace the generated `Install Copythat.txt` in `script/package_dmg.sh` with a copied root `README.md`; verify the script checks for `README.md` and absence of `Install Copythat.txt`.
- [x] 2.2 Run `./script/package_dmg.sh`; verify the generated DMG contains `Copythat.app`, `Applications`, and `README.md`, and does not contain `Install Copythat.txt`.

## 3. OpenSpec Completion

- [x] 3.1 Sync the new DMG README requirement into `openspec/specs/app-distribution-packaging/spec.md`; verify the main spec contains the README requirement.
- [x] 3.2 Archive `unify-dmg-readme`; verify the change is moved under `openspec/changes/archive/2026-06-13-unify-dmg-readme/`.
