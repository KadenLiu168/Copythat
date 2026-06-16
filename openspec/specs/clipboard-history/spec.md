# Clipboard History Specification

## Purpose
Copythat records recent clipboard content so users can review, search, pin, organize, and restore copied items without leaving the native macOS workflow.

## Requirements

### Requirement: Capture supported clipboard item kinds
Copythat SHALL capture non-empty text, HTTP/HTTPS URLs, images, and file references from the general pasteboard after the observed pasteboard content state is stable.

#### Scenario: Capture text
- **WHEN** the pasteboard changes to a stable non-empty text value
- **THEN** Copythat records a text history item with a title, preview, source app, timestamp, and restorable text value

#### Scenario: Capture URL
- **WHEN** the pasteboard changes to a stable HTTP or HTTPS URL string
- **THEN** Copythat records a URL history item using the URL host as its title when available
- **AND** the original URL string remains available for restoration

#### Scenario: Capture image
- **WHEN** the pasteboard changes to a stable image value
- **THEN** Copythat records an image history item with an image preview, source app, timestamp, and restorable image data

#### Scenario: Capture file
- **WHEN** the pasteboard changes to one or more stable file URLs
- **THEN** Copythat records a file history item with the file name or file count, source app, timestamp, and restorable file URLs

#### Scenario: Multi-step pasteboard write settles before capture
- **WHEN** a single copy action causes multiple pasteboard change counts before the final copied value is stable
- **THEN** Copythat records the final stable clipboard value
- **AND** Copythat does not insert an earlier transient value as a history item

### Requirement: Skip protected and ignored sources
Copythat SHALL avoid recording clipboard items that are configured or detected as unsuitable for history.

#### Scenario: Sensitive content is not recorded by default
- **WHEN** the pasteboard contains content marked as concealed or associated with password-manager data
- **AND** sensitive content recording is disabled
- **THEN** Copythat does not add the content to history

#### Scenario: Ignored application is not recorded
- **WHEN** a new clipboard item resolves to a source app listed in ignored applications
- **THEN** Copythat does not add the item to history

### Requirement: Maintain bounded and deduplicated history
Copythat SHALL keep history within the configured limit and avoid duplicate entries for the same content.

#### Scenario: Existing unpinned content is copied again
- **WHEN** a clipboard item has the same content key as an existing unpinned history item
- **THEN** Copythat keeps a single entry for that content
- **AND** the existing item is treated as the newest matching history item
- **AND** the existing item's captured source app, source icon, ID, and creation time remain unchanged

#### Scenario: Existing pinned content is copied again
- **WHEN** a clipboard item has the same content key as an existing pinned history item
- **THEN** Copythat keeps the pinned entry
- **AND** Copythat may record the newly copied item as the newest ordinary history item

#### Scenario: History exceeds the configured limit
- **WHEN** adding a clipboard item would exceed the configured history limit
- **THEN** Copythat removes older unpinned items before pinned items
- **AND** the visible history remains within the configured limit

### Requirement: Persist restorable history metadata
Copythat SHALL persist clipboard history with enough metadata to restore supported items and display their context after relaunch.

#### Scenario: App relaunches with prior history
- **WHEN** Copythat starts after previously saving history
- **THEN** previously saved items are loaded with kind, title, preview, source app, timestamp, pin state, pinboard assignment, and restorable content where available

#### Scenario: Stored media is optimized while source icons are preserved
- **WHEN** clipboard history data is saved with image data, link preview image data, or source icon data
- **THEN** Copythat stores optimized image and link preview image data suitable for history display and restoration
- **AND** Copythat preserves the captured source icon data for each item without downsampling it during storage optimization

### Requirement: Clear clipboard history manually
Copythat SHALL support manual clearing of stored clipboard history while protecting intentionally saved cards by default.

#### Scenario: Clear ordinary cards
- **WHEN** the user confirms clearing ordinary cards
- **THEN** Copythat removes stored cards that are not pinned and are not assigned to a custom pinboard
- **AND** Copythat keeps pinned cards
- **AND** Copythat keeps cards assigned to custom pinboards

#### Scenario: Clear all cards
- **WHEN** the user confirms clearing all cards
- **THEN** Copythat removes stored cards regardless of pin state or custom pinboard assignment

#### Scenario: History state refreshes after clearing
- **WHEN** clipboard cards are cleared
- **THEN** Copythat updates the visible card list
- **AND** Copythat updates the current selection to a remaining visible card or clears selection when no visible cards remain
- **AND** Copythat persists the updated clipboard history

#### Scenario: Custom pinboards remain after clearing cards
- **WHEN** clipboard cards are cleared
- **THEN** Copythat keeps configured custom pinboards available

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

### Requirement: Support pinning and pinboards
Copythat SHALL let users pin items and assign items to custom pinboards.

#### Scenario: Item is pinned
- **WHEN** the user pins a history item
- **THEN** the item remains marked as pinned and is eligible for the pinned pinboard

#### Scenario: Item is moved to custom pinboard
- **WHEN** the user moves a history item to a custom pinboard
- **THEN** Copythat assigns the item to that pinboard
- **AND** the item is pinned

### Requirement: Track source context
Copythat SHALL show the source application name and the source icon captured for each clipboard history item when source metadata is available.

#### Scenario: Source app is resolved
- **WHEN** Copythat captures an item and can resolve the source app
- **THEN** the history item displays the source app name
- **AND** the app icon captured for that item is available in the panel when icon data exists

#### Scenario: Source app is unknown
- **WHEN** Copythat cannot resolve the source app
- **THEN** the history item remains usable with an unknown source label

#### Scenario: Multiple visible items have distinct captured source icons
- **WHEN** the panel displays multiple history items with different captured source icons
- **THEN** each history card displays the icon captured for that specific item
- **AND** adding or displaying a later item MUST NOT replace the source icon shown on an earlier item

#### Scenario: Later capture does not rewrite earlier source context
- **WHEN** a later pasteboard capture is attributed to a different app
- **THEN** Copythat MUST NOT replace an earlier card's captured source app name or source icon with the later app's metadata

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
