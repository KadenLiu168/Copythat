# Proposal: increase-pinboard-color-saturation

## Why

Pinboard color choices look washed out: the fixed palette renders every token at uniform `saturation 0.72 / brightness 0.88`, which reads pastel on screen — especially amber (hue 0.10) and cyan (hue 0.52), whose perceived vividness is far lower than violet/pink at identical HSB values. The existing spec already demands "vivid circular category markers" with "consistent **perceived** saturation and brightness" — uniform numbers do not deliver uniform perception, so the current palette under-delivers on both counts.

## What Changes

- Raise and per-hue tune the `PinboardColorToken` palette for vivid, perceptually consistent markers, anchoring each token near its corresponding macOS system color (systemOrange / systemGreen / systemTeal / systemBlue / systemPurple / systemPink) instead of forcing one shared saturation/brightness pair.
- Update `AppSettingsPinboardTests.colorTokensRoundTripAndShareSaturationAndBrightness`, which hard-asserts sat 0.72 / brightness 0.88, to the new palette contract.
- No rendering changes: popover swatches and panel chip markers already fill directly with `token.color`.

Zero data migration: pinboards persist only the token name (`String, Codable`), never RGB values — every existing pinboard adopts the new palette automatically.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `panel-and-search`: the "Display stable custom pinboard colors" requirement changes — the fixed palette SHALL be vivid (bounded-high saturation) and perceptually consistent across hues, anchored to native macOS system color hues, rather than numerically uniform but perceptually uneven.

## Impact

- **Code**: `Sources/Copythat/Stores/AppSettings.swift` (`PinboardColorToken.color`), `Tests/CopythatTests/AppSettingsPinboardTests.swift` (palette assertions).
- **Data**: none — token names are persisted, colors are derived at runtime.
- **Dependencies**: none.
- **Behavior**: purely visual; all pinboard color markers (creation/edit popovers, panel filter chips) become more vivid. No layout, naming, or persistence changes.

## Non-goals

- Adding or removing palette tokens (still exactly 6 choices).
- Switching to dynamic `NSColor` system color objects (palette stays fixed and appearance-independent; the panel uses a custom warm theme).
- Any change to the pinned/all built-in filter colors.
- Free-form color picking.
