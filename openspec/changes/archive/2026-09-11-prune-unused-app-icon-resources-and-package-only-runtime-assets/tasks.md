## 1. Inventory and establish the resource contract

- [x] 1.1 Enumerate all Resources consumers in SwiftPM, runtime loaders, generator scripts, packaging scripts, specs, and verification; verify every retained or removable file has an identified consumer or an explicit contract reason.
- [x] 1.2 Capture a pre-change file list and size for the processed resource bundle and staged `Copythat.app`; verify the baseline builds and the current icon/relocation checks pass.

## 2. Separate intermediates and prune unused outputs

- [x] 2.1 Update `script/generate_icons.py` to create the `iconutil` input set in a scoped temporary directory and leave generated `AppIcon.icns` unchanged; verify repeated generation leaves no `.iconset` directory under `Sources/Copythat/Resources` and produces a valid `.icns`.
- [x] 2.2 Remove `AppIcon-1024.png` and any additional file proven unused by task 1.1, while retaining the catalog, transparent logo, packaged `.icns`, and menu-bar template required by current contracts; verify no repository consumer references a removed file.
- [x] 2.3 Remove `NSScreenCaptureUsageDescription` from the generated app Info.plist and update verification to require `NSAppleEventsUsageDescription` while asserting the stale screen-capture declaration is absent; verify the panel geometry path still builds and runs.

## 3. Packaging and regression verification

- [x] 3.1 Run icon generation, `swift build`, and `./script/verify_all.sh`; verify required icon sizes, transparent corners, codesigning, resource-bundle relocation, portable launch, and panel launch all pass.
- [x] 3.2 Compare post-change resource and bundle sizes with the baseline, and review the final diff for unchanged logo pixels and menu-bar behavior; verify any reported reduction is measured rather than assumed.
