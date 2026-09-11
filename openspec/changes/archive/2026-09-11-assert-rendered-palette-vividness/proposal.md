# Proposal: assert-rendered-palette-vividness

## Why

The palette requirement claims "consistent perceived vividness across hues" but defines no way to measure it, and its only numeric guards (`saturation ≥ 0.55`, `brightness ≥ 0.75`) are read back from the calibrated color space the palette is *declared* in, not from the sRGB space that actually reaches the screen. The clause is therefore unfalsifiable and the floors cannot distinguish a vivid color from a washed-out one.

This is not hypothetical. The immediately preceding `increase-pinboard-color-saturation` change shipped a first-pass cyan whose perceived colorfulness was **lower than the palette it replaced** (OKLab chroma 0.0994 vs 0.1200), and it passed the entire suite — 86 tests, every script verifier, the full `verify_all.sh` gate — because both floors were satisfied (calibrated saturation 0.60 ≥ 0.55, brightness 0.82 ≥ 0.75). The defect was found by an out-of-band measurement, not by any assertion. The palette has now been re-tuned twice in recent history, so the next silent regression is a matter of when, not if.

## What Changes

- Redefine the vividness clause measurably: each palette color SHALL have an **OKLab chroma of at least 0.11**, measured after conversion from the palette's calibrated color space to sRGB, replacing "consistent perceived vividness across hues".
- Move the existing `saturation ≥ 0.55` / `brightness ≥ 0.75` floors into the **rendered sRGB space**, so the numbers asserted are the numbers displayed.
- Assert both in `Tests/CopythatTests/AppSettingsPinboardTests.swift`, via a test-local OKLab conversion helper. The existing exact per-token H/S/B assertions stay as change detectors.
- Rename `colorTokensRoundTripAndShareSaturationAndBrightness`, which still names the abolished "shared saturation and brightness" contract.
- **No palette values change.** All six current tokens already satisfy the new criteria.

No production code is touched: `PinboardColorToken.color` is unchanged, and the app gains no color-science code.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `panel-and-search`: "Display stable custom pinboard colors" — the vividness clause becomes a measurable OKLab chroma threshold, and the numeric floors are re-expressed in the rendered color space.

## Impact

- **Code**: `Tests/CopythatTests/AppSettingsPinboardTests.swift` only — rewritten palette assertions plus a test-local OKLab helper (~20 lines of matrix math).
- **Data**: none.
- **Dependencies**: none. The OKLab conversion uses the published matrix constants; no package is added.
- **Behavior**: none user-visible. Every current token already clears all three thresholds, so the palette renders identically before and after.
- **Contract strength**: strictly stronger. Rendered-space floors are tighter than calibrated-space floors for the same declared values (violet declares 0.70 and renders 0.582), and the chroma floor is the first criterion that expresses "vivid" rather than a proxy for it.

**Sequencing**: `increase-pinboard-color-saturation` is already archived and its MODIFIED requirement delta is already applied to the canonical spec. This change's MODIFIED requirement supersedes that text at archive time, so no ordering constraint remains between the two changes.

## Non-goals

- Changing any palette value. All six tokens already satisfy the new criteria; a value change would be a separate, visible decision.
- Requiring numerically equal chroma across all six hues. That is physically unattainable in sRGB — cyan's chroma ceiling is ~0.146 across the whole brightness range, against ~0.24 for green, violet and pink — so requiring it would only drag the other five back toward pastel. The floor is a *minimum-vividness* contract; evenness across hues remains a judgment call.
- Constraining the chroma spread between tokens (for example a max/min ratio). The achievable margin is too thin to be a stable assertion.
- Adding OKLab or any color-science code to the app target. The app has no need to compute chroma; the helper is test-only.
- Re-tuning the palette to gain chroma headroom. If the floor ever becomes binding, that is a separate decision with user-visible impact.
