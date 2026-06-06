## 1. Card Preview Layout

- [x] 1.1 Constrain and clip `contentSection` to the existing card width and the height remaining below the header; verify the card and header dimensions remain unchanged.
- [x] 1.2 Change image previews from fill scaling to fit scaling; verify ultra-wide images can display completely and the existing image-detail badge remains unchanged.

## 2. Verification

- [x] 2.1 Run `swift build`; verify the app builds without errors.
- [x] 2.2 Run `swift test`; verify all existing tests pass.
- [x] 2.3 Run `./script/verify_all.sh`; verify the project's scripted checks pass.
- [x] 2.4 Launch the app and inspect the bottom panel with an ultra-wide image; verify its header remains visible, its image is not cropped, and non-image cards remain visually unchanged.
