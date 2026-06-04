## 1. Build Script Signing

- [x] 1.1 Update `script/build_and_run.sh` to read an optional `CODESIGN_IDENTITY` value and sign `dist/Copythat.app` with that identity when configured; verify by building with a valid local identity and inspecting `codesign -dvvv dist/Copythat.app`.
- [x] 1.2 Preserve ad hoc signing when `CODESIGN_IDENTITY` is unset; verify by building without the variable and confirming `Signature=adhoc`.
- [x] 1.3 Ensure an unavailable configured identity fails clearly instead of silently falling back; verify by running the build with an invalid identity and confirming the script exits with a signing error.

## 2. Documentation

- [x] 2.1 Document how to create a local self-signed Code Signing certificate for development; verify the steps include certificate name, keychain location, and Code Signing certificate type.
- [x] 2.2 Document how to configure `CODESIGN_IDENTITY` for Copythat builds; verify the documented command matches the build script variable.
- [x] 2.3 Document the one-time Accessibility retest flow after switching from ad hoc signing; verify it tells developers to remove the old Copythat Accessibility entry, rebuild, grant access once, rebuild again, and retry automatic paste.

## 3. Verification

- [x] 3.1 Run `swift build`; verify the package still builds.
- [x] 3.2 Run `./script/verify_all.sh`; verify existing behavior checks still pass.
- [x] 3.3 Inspect the staged app signature in both configured-identity and ad hoc modes; verify each mode reports the expected signing state.
- [x] 3.4 Manually verify automatic paste on macOS after granting Accessibility to the locally signed `dist/Copythat.app`; verify double-click and Enter paste without repeated permission prompts after rebuilding.
