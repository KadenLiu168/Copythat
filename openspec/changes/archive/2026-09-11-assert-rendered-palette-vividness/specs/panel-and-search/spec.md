## MODIFIED Requirements

### Requirement: Display stable custom pinboard colors
Copythat SHALL display each custom pinboard using its persisted selected color from a fixed, vivid palette. Palette colors SHALL be anchored to the hues of the corresponding macOS system colors (orange, green, teal, blue, purple, pink) and SHALL use per-hue tuned saturation and brightness, rather than one numerically uniform saturation/brightness pair that renders perceptually uneven across hues.

Vividness SHALL be measured rather than asserted qualitatively: every palette color SHALL have an OKLab chroma of at least 0.11. Both that floor and the sRGB saturation and brightness floors SHALL be evaluated after converting the palette's calibrated color space to sRGB, the space that reaches the display.

#### Scenario: Color choices are displayed
- **WHEN** the pinboard creation form is visible
- **THEN** Copythat offers a small fixed set of distinct color choices
- **AND** every choice has an OKLab chroma of at least 0.11, measured after conversion to sRGB
- **AND** every choice has sRGB saturation of at least 0.55 and sRGB brightness of at least 0.75

#### Scenario: Custom pinboard is displayed
- **WHEN** a custom pinboard filter is visible
- **THEN** its category marker uses the color selected when the pinboard was created

#### Scenario: Existing pinboards adopt palette updates without migration
- **WHEN** the palette definition changes between app versions
- **THEN** every persisted custom pinboard renders with the updated palette color for its stored color token
- **AND** no persisted data is rewritten

#### Scenario: Multiple pinboards use the same color
- **WHEN** a user selects a color already used by another custom pinboard
- **THEN** Copythat allows the new pinboard to use that color
