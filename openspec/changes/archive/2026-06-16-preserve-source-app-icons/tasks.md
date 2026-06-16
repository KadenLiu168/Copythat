## 1. Storage Behavior

- [x] 1.1 Update `ClipboardItem.storageOptimized` so `sourceAppIconData` is preserved exactly while `imageData` and `linkImageData` keep their existing size limits; verify by inspecting the focused model implementation.

## 2. Test Coverage

- [x] 2.1 Add a focused test proving `storageOptimized` preserves source icon bytes; verify the test fails against the old 64px downsampling behavior and passes after the model change.
- [x] 2.2 Add or retain assertions that storage optimization still bounds clipboard image data and link preview image data; verify source icon preservation does not remove media optimization.

## 3. Verification

- [x] 3.1 Run targeted SwiftPM tests for the storage optimization behavior.
- [x] 3.2 Run `swift build` and `./script/verify_all.sh` for project verification.
