## ADDED Requirements

### Requirement: Display readable text card previews
Copythat SHALL prioritize readable text preview content within text history cards in the bottom panel.

#### Scenario: Text item contains multiple preview lines
- **WHEN** the panel displays a text history item with multiple lines or wrapped text
- **THEN** the text card shows the preview using compact readable typography
- **AND** the visible preview lines remain fully legible without an early fade reducing the readable content area

#### Scenario: Text item exceeds the card preview area
- **WHEN** the panel displays a text history item whose preview is longer than the card can show
- **THEN** the card limits the preview to the available text area
- **AND** the selected-card scale and raised positioning behavior remains unchanged
