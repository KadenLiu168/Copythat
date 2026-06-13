# Clipboard History Specification

## Purpose
Copythat records recent clipboard content so users can review, search, pin, organize, and restore copied items without leaving the native macOS workflow.

## Requirements

### Requirement: Capture supported clipboard item kinds
Copythat SHALL capture non-empty text, HTTP/HTTPS URLs, images, and file references from the general pasteboard.

#### Scenario: Capture text
- **WHEN** the pasteboard changes to a non-empty text value
- **THEN** Copythat records a text history item with a title, preview, source app, timestamp, and restorable text value

#### Scenario: Capture URL
- **WHEN** the pasteboard changes to an HTTP or HTTPS URL string
- **THEN** Copythat records a URL history item using the URL host as its title when available
- **AND** the original URL string remains available for restoration

#### Scenario: Capture image
- **WHEN** the pasteboard changes to an image value
- **THEN** Copythat records an image history item with an image preview, source app, timestamp, and restorable image data

#### Scenario: Capture file
- **WHEN** the pasteboard changes to one or more file URLs
- **THEN** Copythat records a file history item with the file name or file count, source app, timestamp, and restorable file URLs

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

#### Scenario: Existing content is copied again
- **WHEN** a clipboard item has the same content key as an existing history item
- **THEN** Copythat keeps a single entry for that content
- **AND** the item is treated as the newest matching history item

#### Scenario: History exceeds the configured limit
- **WHEN** adding a clipboard item would exceed the configured history limit
- **THEN** Copythat removes older unpinned items before pinned items
- **AND** the visible history remains within the configured limit

### Requirement: Persist restorable history metadata
Copythat SHALL persist clipboard history with enough metadata to restore supported items and display their context after relaunch.

#### Scenario: App relaunches with prior history
- **WHEN** Copythat starts after previously saving history
- **THEN** previously saved items are loaded with kind, title, preview, source app, timestamp, pin state, pinboard assignment, and restorable content where available

#### Scenario: Stored media is optimized
- **WHEN** image or source icon data is saved
- **THEN** Copythat stores optimized image data suitable for history display and restoration

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
