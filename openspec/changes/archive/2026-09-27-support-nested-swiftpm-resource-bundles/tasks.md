## 1. Support SwiftPM resource bundle layouts

- [x] 1.1 Update `script/build_and_run.sh` to locate `MenuBarIconTemplate.png` at either the resource bundle root or `Contents/Resources` while preserving the generated bundle structure; verify both layouts and a missing image with isolated packaging fixtures.
- [x] 1.2 Update `script/package_dmg.sh` to accept the same two staged resource locations; verify its resource check accepts both layouts and rejects a missing image with isolated fixtures.

## 2. Verify the staged app icon

- [x] 2.1 Validate the outer app `Contents/Info.plist` and its `CFBundleIconFile` value after writing the plist, and require the referenced outer `Contents/Resources/AppIcon.icns` before packaging succeeds; verify missing or invalid icon metadata fails packaging with isolated fixtures.
- [x] 2.2 Extend `script/verify_all.sh` to check the staged app plist, icon resource, and supported resource layouts; verify with `swift build`, `./script/verify_all.sh`, and `./script/build_and_run.sh --verify-portable` on the available toolchain, plus deterministic flat and nested layout fixtures independent of toolchain output.
