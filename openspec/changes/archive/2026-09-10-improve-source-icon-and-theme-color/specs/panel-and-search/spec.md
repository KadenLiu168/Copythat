## ADDED Requirements

### Requirement: Store source app icons at display-sufficient resolution

Copythat SHALL store each captured source app icon at a bitmap resolution sufficient for sharp rendering at the card header's display size on Retina displays, using the best available high-resolution representation of the app icon rather than the image's logical point size. Stored icon resolution SHALL NOT exceed the bounded maximum needed for the header display slot.

#### Scenario: Captured icon is sharp on Retina displays
- **WHEN** Copythat captures the source app icon for a new history item from an app bundle that ships high-resolution icon representations
- **THEN** the stored icon bitmap has at least 104 pixels on its longest side (52pt header slot at 2× scale)
- **AND** the stored icon bitmap does not exceed 160 pixels on its longest side

#### Scenario: Low-resolution source does not get upscaled
- **WHEN** the source app's icon provides no representation larger than the display requirement
- **THEN** Copythat stores the largest available representation without inventing pixels through upscaling

### Requirement: Derive card header theme color from dominant brand color

Copythat SHALL derive each history card header's theme color from the source app icon's dominant vivid color, aggregated across the icon's pixels with coverage weighting, rather than selecting a single best-scoring pixel. The derivation SHALL exclude near-white, near-black, low-alpha, and low-saturation samples, and SHALL normalize saturation adaptively so muted brand colors gain mild vividness while already-saturated colors stay bounded below a neon threshold. When no icon or no usable color is available, Copythat SHALL fall back to a neutral accent color.

#### Scenario: Single-color icon preserves its color
- **WHEN** the source app icon is a single saturated color
- **THEN** the header theme color's hue closely matches that icon color

#### Scenario: Multi-color icon yields the dominant brand color
- **WHEN** the source app icon contains multiple brand colors with clearly different coverage areas
- **THEN** the header theme color's hue matches the most-covered vivid color rather than a highlight or gradient-edge pixel

#### Scenario: Neutral regions do not pollute the result
- **WHEN** the source app icon contains large white, black, or gray areas alongside a smaller vivid brand color region
- **THEN** the header theme color is derived from the vivid region and is not pulled toward gray

#### Scenario: Missing or unusable icon falls back to neutral accent
- **WHEN** a history item has no source icon data or the icon yields no usable color samples
- **THEN** the header uses the neutral fallback accent color

#### Scenario: Extracted color stays within bounded saturation
- **WHEN** the header theme color is derived from any source icon
- **THEN** its saturation is normalized within a bounded range that avoids both washed-out gray and fluorescent over-saturation
