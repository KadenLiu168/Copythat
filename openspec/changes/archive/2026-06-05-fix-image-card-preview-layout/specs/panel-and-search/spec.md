## ADDED Requirements

### Requirement: Display bounded image card previews
Copythat SHALL display image history previews within the fixed card content region below the card header and SHALL preserve the complete image aspect ratio.

#### Scenario: Ultra-wide image card is displayed
- **WHEN** the panel displays an image history item with an ultra-wide aspect ratio
- **THEN** the image preview remains inside the content region below the header
- **AND** the card header, timestamp, and source icon remain fully visible
- **AND** the complete image is shown proportionally without cropping

#### Scenario: Other card kinds are displayed
- **WHEN** the panel displays text, URL, or file history items
- **THEN** their previews remain inside the same fixed content region
- **AND** their existing preview presentation remains unchanged
