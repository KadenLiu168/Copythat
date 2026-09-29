## 1. Establish a comparable baseline

- [x] 1.1 Before editing `Package.swift`, run `swift build` and `./script/build_and_run.sh --verify` with a recorded toolchain and debug configuration. Record the staged app and SwiftPM bundle inventories, `du -sh dist/Copythat.app`, and `du -sk dist/Copythat.app`; verify the baseline comes from this build rather than an older staged app. Keep logs, source-resource digests, environment details, and measurements in `.build/verification/` or outside the repository, preserving existing user data.

## 2. Narrow the manifest inputs

- [x] 2.1 Change only the `Copythat` executable target in `Package.swift`: add `exclude` before `resources` with `Resources/AppIcon.icns`, `Resources/AppIcon-transparent.png`, and `Resources/Assets.xcassets`; replace `.process("Resources")` with `.process("Resources/MenuBarIconTemplate.png")`. Verify exclusions are target-relative, no `.process(..., exclude: ...)` form is used, and source-resource digests are unchanged. The ordered checks below validate the resulting package.

## 3. Verify in the required order

Execute tasks 3.1 through 3.6 sequentially. If unexpected resources remain, diagnose build-cache residue before changing scope. If a fresh rebuild is needed, preserve evidence, remove only disposable generated outputs, and repeat the ordered checks; never manually prune the staged bundle to manufacture a passing result.

- [x] 3.1 Run `swift build`; capture its exit status and complete output, and require zero errors, zero warnings, and no `found N file(s) which are unhandled` warning. Diagnose any exclusion-path problem relative to `Sources/Copythat` without changing APIs or verification scripts.
- [x] 3.2 Run `./script/build_and_run.sh --verify`, then `find dist/Copythat.app/Contents/Resources/Copythat_Copythat.bundle -type f`. Require `MenuBarIconTemplate.png` at the bundle root or `Contents/Resources`, and require it to be the only runtime payload. Permit `Info.plist` and `_CodeSignature` metadata; reject `AppIcon.icns`, `AppIcon-transparent.png`, `Assets.xcassets` and its contents, or compiled catalog payload such as `Assets.car` anywhere in the bundle. Check directories as well as files so an empty excluded catalog does not escape detection.
- [x] 3.3 Run `test -f dist/Copythat.app/Contents/Resources/AppIcon.icns`; require success and verify its bytes match `Sources/Copythat/Resources/AppIcon.icns`. Verify the outer `Contents/Info.plist` still declares `CFBundleIconFile` as `AppIcon`.
- [x] 3.4 Run `du -sh dist/Copythat.app` and `du -sk dist/Copythat.app` using the same configuration and measurement method as task 1.1. Report actual before, after, and delta in KiB, plus human-readable sizes. Require a clear decrease attributable to the removed payload; approximate expectations of 8.9M to 5.8M are guidance, not fixed thresholds. Investigate a missing reduction instead of claiming success from resource exclusion alone.
- [x] 3.5 Run `./script/verify_all.sh` and require all checks to pass, including packaging fixtures, Swift build/tests, source-tree icon verification, portable app verification, panel verification, and codesign verification. Diagnose genuine failures before proposing any scope change; do not weaken or edit the verification scripts. Recheck the final staged bundle inventory and outer icon after the gate rebuilds the app.
- [x] 3.6 Launch the actual staged `dist/Copythat.app` and visually confirm that the menu bar shows Copythat's custom icon rather than the `c.circle` fallback; also confirm Finder/application icon appearance remains unchanged. Preserve user clipboard/history data during the check. Record the observation outside tracked artifacts and report it explicitly; launch success, bundle presence, or automated smoke tests alone do not satisfy this task. Leave it incomplete if visual inspection is unavailable.

## 4. Review the final scope

- [x] 4.1 Inspect the final diff and source-resource digests: require `Package.swift` to be the only production modification, with all four source resources unchanged and all prohibited scripts, loader code, and main specs untouched. Run `git diff --check` and strict validation of this Change. Report verification conclusions, before/after/delta, and any unresolved acceptance item in the response; do not commit execution reports or claim completion while a required check remains open.
