## MODIFIED Requirements

### Requirement: Display stable custom pinboard colors
Copythat SHALL display each custom pinboard using its persisted selected color from a fixed, vivid, perceptually consistent palette. Palette colors SHALL be anchored to the hues of the corresponding macOS system colors (orange, green, teal, blue, purple, pink) and SHALL use per-hue tuned saturation and brightness high enough to read as vivid category markers, rather than one numerically uniform saturation/brightness pair that renders perceptually uneven across hues.

#### Scenario: Color choices are displayed
- **WHEN** the pinboard creation form is visible
- **THEN** Copythat offers a small fixed set of distinct color choices
- **AND** every choice has saturation of at least 0.55 and brightness of at least 0.75
- **AND** the choices have consistent perceived vividness across hues

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
