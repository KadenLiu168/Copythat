## MODIFIED Requirements

### Requirement: Display readable text card previews
Copythat SHALL prioritize readable text preview content within text history cards in the bottom panel, using compact macOS-native body typography for the preview text.

#### Scenario: Text item contains multiple preview lines
- **WHEN** the panel displays a text history item with multiple lines or wrapped text
- **THEN** the text card shows the preview using compact readable typography
- **AND** the visible preview lines remain fully legible without an early fade reducing the readable content area

#### Scenario: Text item uses mixed Chinese and English content
- **WHEN** the panel displays a text history item containing mixed Chinese and English text
- **THEN** the text card body uses a macOS-native text font suitable for reading mixed-language preview content
- **AND** the body preview remains visually distinct from the card header and metadata

#### Scenario: Text item exceeds the card preview area
- **WHEN** the panel displays a text history item whose preview is longer than the card can show
- **THEN** the card limits the preview to the available text area
- **AND** the selected-card scale and raised positioning behavior remains unchanged
