## ADDED Requirements

### Requirement: Removed current clipboard cards are not recaptured
Copythat SHALL prevent removed cards that match current or pending pasteboard content from returning to clipboard history unless the user copies that content again.

#### Scenario: Delete current image card
- **WHEN** the user deletes an image card that matches the current general pasteboard content
- **THEN** Copythat removes the card from history
- **AND** Copythat clears the matching general pasteboard content
- **AND** Copythat does not recapture that image from stale pasteboard state

#### Scenario: Pending image capture finishes after deletion
- **WHEN** image capture is still encoding a history item for content the user has removed
- **THEN** Copythat does not insert the encoded image into history

#### Scenario: Delete older history card
- **WHEN** the user deletes a history card that does not match the current general pasteboard content
- **THEN** Copythat removes the card from history
- **AND** Copythat keeps the current general pasteboard content available

#### Scenario: Copy same content again after deletion
- **WHEN** the user copies the same image again after deleting its prior card
- **THEN** Copythat can record the new copy as a history item
