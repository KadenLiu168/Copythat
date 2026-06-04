## ADDED Requirements

### Requirement: Render selected cards without top clipping
Copythat SHALL render selected bottom-panel history cards without clipping their top edge, header, source icon, selected border, or rounded corner.

#### Scenario: Selected card uses raised visual treatment
- **WHEN** the bottom panel displays visible history cards and one card is selected
- **THEN** the selected card's top edge, header text, source icon, selected border, and rounded corner remain fully visible
- **AND** the selected-card scale and raised positioning behavior remains unchanged

#### Scenario: User browses selected cards horizontally
- **WHEN** the user moves selection across visible text, image, URL, and file cards
- **THEN** each newly selected card remains visually unclipped at the top of the timeline
- **AND** horizontal scrolling continues to keep the selected card reachable without changing search, paste, or pinboard behavior
