## ADDED Requirements

### Requirement: Diagnose clipboard capture decisions
Copythat SHALL provide a default-off diagnostic mode that records safe runtime metadata for clipboard capture, source attribution, and duplicate-content insertion decisions.

#### Scenario: Diagnostics are disabled by default
- **WHEN** Copythat monitors pasteboard changes with no clipboard diagnostics flag enabled
- **THEN** Copythat does not emit clipboard diagnostics events
- **AND** clipboard history behavior remains unchanged

#### Scenario: Diagnostics record source and duplicate metadata
- **WHEN** clipboard diagnostics are enabled and a supported pasteboard item is captured
- **THEN** Copythat emits diagnostics that identify the captured item kind, resolved source app, pasteboard change-count context, content identity digest, duplicate-match status, and item counts before and after insertion
- **AND** Copythat does not change captured item content, source attribution, duplicate-content behavior, selection, or persistence as part of diagnostics

#### Scenario: Diagnostics avoid clipboard payloads
- **WHEN** clipboard diagnostics are enabled for text, URL, file, image, or sensitive-content pasteboard changes
- **THEN** Copythat MUST NOT log raw copied text, complete URLs, file paths, image data, or other restorable clipboard payload values
