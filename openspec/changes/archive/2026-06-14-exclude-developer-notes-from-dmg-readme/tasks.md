## 1. DMG README Generation

- [x] 1.1 Update `script/package_dmg.sh` to write the DMG `README.md` from root README content before `## Developer Notes`; verify the script no longer copies the full README.
- [x] 1.2 Add packaging checks that the DMG README keeps user-facing sections and excludes `Developer Notes`; verify the checks are present in the script.

## 2. Verification

- [x] 2.1 Run `./script/package_dmg.sh`; verify the generated DMG contains `Copythat.app`, `Applications`, and `README.md`, does not contain `Install Copythat.txt`, and the README excludes developer notes.

## 3. OpenSpec Completion

- [x] 3.1 Sync the updated DMG README requirement into `openspec/specs/app-distribution-packaging/spec.md`; verify the main spec includes the developer-notes exclusion.
- [x] 3.2 Archive `exclude-developer-notes-from-dmg-readme`; verify the change is moved under `openspec/changes/archive/2026-06-14-exclude-developer-notes-from-dmg-readme/`.
