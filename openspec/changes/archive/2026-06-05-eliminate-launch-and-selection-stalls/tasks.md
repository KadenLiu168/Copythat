## 1. Launch Path

- [x] 1.1 Restore persisted clipboard items without re-running storage optimization; verify the launch profile no longer samples `ClipboardItem.storageOptimized`.

## 2. Selection Rendering

- [x] 2.1 Cache source accent derivation by persisted icon data and use it from card rendering; verify correctness and cache reuse with focused tests.
- [x] 2.2 Make selection scrolling immediate and shorten the selected-card transition; verify repeated left/right input no longer accumulates scroll-animation work.

## 3. Verification

- [x] 3.1 Run `swift build` and `swift test`.
- [x] 3.2 Repeat launch and selection sampling against the same image-heavy history and compare with the baseline.
- [x] 3.3 Run `./script/verify_all.sh` and confirm panel launch, packaging, and existing behavior remain valid.
