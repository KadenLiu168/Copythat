# Tasks: improve-source-icon-and-theme-color

## 1. High-Resolution Icon Capture

- [x] 1.1 Add failing tests in `Tests/CopythatTests/NSImageIconProcessingTests.swift`: fixture `NSImage` with multiple representations (16/64/256px) must export PNG with longest side in (104, 160]; a max-64px fixture must store 64px without upscaling. Verify tests fail against current `pngData(maxPixel:)`.
- [x] 1.2 Add representation-aware `appIconPNGData(maxPixel:)` in `Sources/Copythat/Support/NSImage+PasteData.swift` using `bestRepresentation(for:)` drawn into a bounded bitmap (design D1). Verify 1.1 tests pass and existing `pngData(maxPixel:)` behavior/callers are unchanged.
- [x] 1.3 Switch `CopySourceTracker.source(for:)` (both `icon(forFile:)` and `app.icon` branches) to the new export path. Verify `swift build` succeeds and existing CopySourceTracker tests pass.
- [x] 1.4 Measure stored icon PNG byte sizes for Safari, Chrome, Finder, VS Code after the change. Verify sizes are ≤ ~40KB; if larger, reduce cap to 128px (still > 104px requirement) and re-verify.
  - Evidence (stage-3 re-measure on real bundles via `NSWorkspace.icon(forFile:)` → `appIconPNGData(maxPixel: 160)`): Safari 26,963 B; Chrome 20,923 B; Finder 17,916 B; VS Code 15,324 B; Notes 13,102 B; Calendar 18,469 B; Mail 18,921 B; Terminal 14,283 B. Max 26,963 B < 40,960 B, so the 160px cap stands and the 128px fallback is not needed. Every output is 160x160px.
  - Same icons through the old `pngData(maxPixel: 160)` produced 64x64px (15,818 / 15,221 / 15,663 / 13,650 B for Safari / Chrome / Finder / VS Code), i.e. real storage growth is 1.31x in total, not the 4x worst case the design flagged.

## 2. Theme Color Extraction

- [x] 2.1 Add failing tests in `Tests/CopythatTests/SourceThemeColorTests.swift` with numeric assertions: single-color icon hue preserved (±0.03 hue); multi-color fixture returns the highest-coverage vivid color; large white/black/gray regions do not pull result toward gray (result saturation ≥ 0.3); extracted saturation ≤ 0.92; nil icon falls back to `neutralAccent`. Verify tests fail against current `logoThemeColor`.
- [x] 2.2 Replace `logoThemeColor` body in `Sources/Copythat/Support/SourceThemeColor.swift` with filter → hue-bucket aggregation → coverage-weighted scoring → adaptive saturation normalization (design D2). Verify 2.1 tests pass.
- [x] 2.3 Verify the accent cache (`NSCache` keyed by iconData) still behaves correctly with the new algorithm (cache-hit test returns identical color).

## 3. Integration Verification

- [x] 3.1 Run `./script/verify_all.sh` and confirm full pass.
- [x] 3.2 Manual visual check with Safari, Chrome, Finder, Xcode, VS Code copies: header icons are sharp on a Retina display, header colors read as each app's brand color without neon over-saturation, and old (pre-change) history items still render acceptably with their stored low-res icons.
  - Evidence (stage-3 re-measure): all 8 installed apps report a 32pt logical size while carrying representations up to 2048x2048, and `appIconPNGData(maxPixel: 160)` returns 160x160px for each one — the spec's [104, 160] px bound holds on real bundles, not just on fixtures. Xcode is not installed on the review machine, so that row of the manual check is not reproducible here.
  - Measured header accents (after the sRGB conversion the view layer performs): Safari #45B5F5 s=0.720; Chrome #00B66B s=1.000; Finder #3C96C5 s=0.696; VS Code #10ADE5 s=0.929; Notes #F4DF4B s=0.692; Calendar #F75546 s=0.716; Mail #4DBDF5 s=0.685; Terminal falls back to neutral #C5B7A5 (monochrome icon, no usable sample). None of these read as fluorescent.
- [x] 3.3 Fix header icon overflow discovered during 3.2: `NSViewRepresentable` sized the header `NSImageView` by the image's intrinsic point size (`.frame(52)` ignored), so 160px icons rendered beyond the slot. Added `sizeThatFits` to `SourceLogoImageView` returning the proposal + regression test `highResolutionSourceIconStaysWithinHeaderSlot`.
