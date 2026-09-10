# Design: increase-pinboard-color-saturation

## Context

See proposal.md → Why. Constraints that shape the approach:

- Palette lives in one place: `PinboardColorToken.color` in `Sources/Copythat/Stores/AppSettings.swift` — six hues, uniform `saturation 0.72 / brightness 0.88`.
- Only small markers consume the palette (20px popover swatches, panel chip dots) — no large fills, no overlaid text, so higher saturation carries no legibility risk.
- Persistence stores token names only, so palette edits are runtime-derived and migration-free.
- macOS system colors are the native reference point: their HSB values differ wildly per hue (systemOrange sat ≈ 1.0 vs systemTeal sat ≈ 0.56) yet read as equally vivid — evidence that perceived consistency requires per-hue tuning, not uniform HSB.

## Goals / Non-Goals

**Goals:**

- Vivid markers that satisfy the spec's "consistent perceived saturation and brightness".
- A defensible, testable rule for the new values (not eyeball-picked magic numbers).

**Non-Goals:**

- Token set changes, dynamic system-color objects, free-form picking (see proposal Non-goals).

## Decisions

### D1: Per-hue tuned HSB anchored to macOS system colors

Each token keeps its current hue family but adopts values near the corresponding system color's HSB, mildly softened where full system saturation would glare against the panel's warm cream theme:

| Token  | Current (H/S/B)      | System anchor  | New (H/S/B) target   |
|--------|----------------------|----------------|----------------------|
| amber  | 0.10 / 0.72 / 0.88   | systemOrange   | 0.08 / 0.90 / 0.95   |
| green  | 0.38 / 0.72 / 0.88   | systemGreen    | 0.36 / 0.80 / 0.78   |
| cyan   | 0.52 / 0.72 / 0.88   | systemTeal     | 0.52 / 0.60 / 0.82   |
| blue   | 0.60 / 0.72 / 0.88   | systemBlue     | 0.60 / 0.85 / 0.92   |
| violet | 0.73 / 0.72 / 0.88   | systemPurple   | 0.74 / 0.70 / 0.85   |
| pink   | 0.91 / 0.72 / 0.88   | systemPink     | 0.93 / 0.72 / 0.97   |

Alternatives considered:

- **Uniform bump (e.g. sat 0.9 / brightness 0.82 for all)**: one-line change, but keeps the core defect — amber/cyan would still read weaker than violet/pink. Rejected.
- **Adopt `NSColor.systemOrange` etc. directly**: native and adaptive, but the panel is a fixed warm light theme, dynamic colors can shift under system appearance/contrast settings, and tests currently pin exact HSB. Rejected; static HSB anchored to system hues gets the same perceptual calibration without the variability.

Target values are starting points for the visual pass (task 2.2), bounded by the spec floors (sat ≥ 0.55, brightness ≥ 0.75); final values within those bounds are acceptable.

### D2: Test contract changes from "shared S/B" to "bounded vividness + distinct hues"

`colorTokensRoundTripAndShareSaturationAndBrightness` currently asserts uniform sat/brightness — that assertion encodes the old design and must be rewritten: each token's saturation/brightness within its tuned target (exact values), all hues distinct, all tokens above the spec floors. TDD order: update the test to the new targets first, watch it fail, then update the palette.

### D3: Cyan re-tuned after task 2.2 — vividness measured as OKLab chroma, not HSB saturation

D1's visual pass was re-done objectively: **vividness was measured as OKLab chroma** (a perceptually uniform space) instead of HSB saturation. HSB saturation is not comparable across hues, which is what made D1 miss cyan.

Measured OKLab chroma (`NSColor(calibratedHue:)` → sRGB → OKLab):

| Token | Pre-change (0.72/0.88) | D1 | Final |
|-------|------------------------|-----|-------|
| amber | 0.1300 | 0.1652 | 0.1652 |
| green | 0.1895 | 0.2105 | 0.2105 |
| **cyan** | **0.1200** | **0.0994** | **0.1326** |
| blue | 0.1421 | 0.1743 | 0.1743 |
| violet | 0.2016 | 0.1917 | 0.1917 |
| pink | 0.1915 | 0.1964 | 0.1964 |

Findings:

- **D1 silently regressed cyan.** D1's cyan (`0.52 / 0.60 / 0.82`, sRGB `#62CCDA`) has chroma 0.0994 — *below* the pre-change uniform palette's 0.1200 — while the proposal's Why cites cyan as one of the two washed-out tokens. D1's real gains were amber and blue; violet also slipped slightly.
- **Equal chroma across hues is not attainable.** Cyan's sRGB-gamut chroma ceiling is only 0.102–0.146 across brightness 0.55–1.0 (0.146 even at B = 1.0 full saturation), versus 0.239 / 0.244 / 0.240 for green / violet / pink at their own brightness. Driving all six to one chroma would drag green, violet and pink back to ~0.15, undoing the change.
- **Darkening cyan does not help.** Cyan's chroma rises monotonically with brightness for this hue, so lowering B to buy chroma makes it paler, not more vivid. Hue shifts within 0.48–0.54 top out at 0.129–0.140.

Decision: keep D1 for the other five tokens; set cyan to **`0.52 / 0.89 / 0.85`** → sRGB `#00CCE0`, chroma **0.1326** (+33% over D1, above the pre-change 0.1200). This is cyan's practical ceiling at that brightness.

Consequence: the spec floors now hold **in the rendered sRGB space** as well as the calibrated space (cyan sRGB saturation 1.000, brightness 0.880), where D1's cyan sat at exactly 0.550 with zero margin. The spec's "consistent perceived vividness across hues" is read as *each token at its hue's achievable vividness, none left washed out*; numerically equal chroma remains a non-goal.

## Risks / Trade-offs

- [Full-saturation amber/blue could glare on the cream panel] → Mitigation: softened vs raw system values (amber sat 0.90 not 1.0, blue sat 0.85 not 1.0); visual pass in tasks against the real panel.
- [Users accustomed to pastel markers notice the shift] → Acceptable: this is the requested change; tokens/names/persistence are untouched so muscle memory for positions is preserved.
- [Perceived-consistency is judgment, not fully testable] → Mitigation: anchor rule (system hues) + numeric floors make the contract objective; final judgment call happens once, in the manual visual task.

## Migration Plan

None. Colors are derived from persisted token names at runtime; old installs render the new palette on next launch. Rollback = revert two files.
