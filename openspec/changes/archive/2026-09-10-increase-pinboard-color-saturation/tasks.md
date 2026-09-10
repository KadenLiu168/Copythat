# Tasks: increase-pinboard-color-saturation

## 1. Palette Contract (TDD)

- [x] 1.1 Rewrite `colorTokensRoundTripAndShareSaturationAndBrightness` in `Tests/CopythatTests/AppSettingsPinboardTests.swift`: keep round-trip and distinct-hue assertions, replace the uniform sat 0.72 / brightness 0.88 assertions with per-token target HSB from design D1 (exact values ±0.01) plus floors (sat ≥ 0.55, brightness ≥ 0.75) for all tokens. Verify the test fails against the current palette.
- [x] 1.2 Update `PinboardColorToken.color` in `Sources/Copythat/Stores/AppSettings.swift` to the per-hue tuned values from design D1. Verify the rewritten test passes.

## 2. Verification

- [x] 2.1 Run `./script/verify_all.sh` and confirm full pass.
- [x] 2.2 Visual pass: open New Pinboard / Edit Pinboard popovers and the panel filter bar; verify all six swatches read vivid and perceptually even on the warm panel (no neon glare, amber/cyan no longer washed out). If a token glares or fades, tune its S/B within spec floors, update the test's target values to match, and re-run 2.1.
- [x] 2.3 Verify a pre-existing pinboard (created before the change) renders its marker in the new palette color with no data rewrite.
