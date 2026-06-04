## 1. Source Artwork and Generator

- [x] 1.1 Confirm `/Users/kaden/Copythat/script/assets/Copythat.png` is present, square, and readable as the new source logo; verify image metadata reports a square PNG.
- [x] 1.2 Update `script/generate_icons.py` so app branding assets are generated from `script/assets/Copythat.png` instead of the old procedurally drawn red C mark; verify the script still writes the existing resource filenames.
- [x] 1.3 Preserve or regenerate `MenuBarIconTemplate.png` as a monochrome template asset suitable for the macOS menu bar; verify it remains readable as a template icon and does not use the full-color app icon directly.

## 2. Resource Regeneration

- [x] 2.1 Run the icon generation script to regenerate `Assets.xcassets/AppIcon.appiconset`, `AppIcon.iconset`, `AppIcon.icns`, `AppIcon-1024.png`, `AppIcon-transparent.png`, and `MenuBarIconTemplate.png`; verify generated files have updated modification times and expected paths.
- [x] 2.2 Inspect the generated app icon PNGs to confirm sizes 16, 32, 64, 128, 256, 512, and 1024 are square and visually derived from the new Copythat logo.
- [x] 2.3 Inspect `AppIcon-transparent.png` to confirm it is 1024 x 1024 with transparent corners while still representing the new logo.

## 3. Verification

- [x] 3.1 Run `swift build`; verify the app still builds with the updated resources.
- [x] 3.2 Run `./script/verify_all.sh`; verify existing tests, icon checks, packaging checks, and panel verification pass.
- [x] 3.3 Manually launch or inspect the packaged app and confirm the visible app icon uses the new logo; verify clipboard history, paste, search, pinboard, shortcut, permissions, launch-at-login, and panel behavior are not intentionally changed.
