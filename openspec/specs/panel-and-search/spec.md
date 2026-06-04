# Panel and Search Specification

## Purpose
Copythat provides a compact bottom panel for browsing clipboard history, filtering by pinboard, searching content, and selecting items for paste.
## Requirements
### Requirement: Open from menu bar or global shortcut
Copythat SHALL remain available from the macOS menu bar and the registered global shortcut.

#### Scenario: User clicks the menu bar item
- **WHEN** the user activates the Copythat menu bar item with a primary click
- **THEN** Copythat shows the bottom floating panel

#### Scenario: User uses the global shortcut
- **WHEN** the registered global shortcut is pressed
- **THEN** Copythat toggles the bottom floating panel

#### Scenario: User opens menu actions
- **WHEN** the user opens the status item menu
- **THEN** Copythat offers actions to show the panel, open settings, or quit the app

### Requirement: Display a native bottom floating panel
Copythat SHALL display clipboard history in a bottom floating panel that fits the visible display area and does not show rectangular shadow artifacts at its rounded corners.

#### Scenario: Panel opens
- **WHEN** the panel is shown
- **THEN** it appears as a native macOS floating panel near the bottom of the active visible screen area
- **AND** the first visible item is selected when available

#### Scenario: Panel corners are rendered
- **WHEN** the bottom floating panel is visible
- **THEN** its rounded corners do not show rectangular outer shadow artifacts

#### Scenario: Panel is closed
- **WHEN** the user presses Escape in the panel
- **THEN** Copythat closes the panel

### Requirement: Browse and select visible items
Copythat SHALL let users browse visible clipboard items horizontally, maintain a selected item, and show a balanced empty timeline state when no items are visible.

#### Scenario: History has visible items
- **WHEN** the panel displays matching history items
- **THEN** each item is shown as a card with its title, preview, kind, source context, and available item actions

#### Scenario: User moves selection
- **WHEN** the user sends left or right movement commands in the panel
- **THEN** Copythat moves selection within the visible items without moving past the first or last item

#### Scenario: No items are visible
- **WHEN** filters and search produce no visible items
- **THEN** Copythat shows an empty timeline state instead of item cards
- **AND** the empty state is visually centered within the timeline content area rather than aligned to the leading card position
- **AND** the empty state does not show the app logo as a prominent primary graphic

#### Scenario: Selected pinboard has no items
- **WHEN** the user selects a pinboard with no matching visible items
- **THEN** Copythat shows empty-state copy that identifies the selected pinboard context

#### Scenario: Search has no matches
- **WHEN** the user enters a search query that matches no visible items
- **THEN** Copythat shows empty-state copy that identifies the empty search result context

### Requirement: Display compact card headers
Copythat SHALL display each visible history card with a compact header that separates the item kind, timestamp, and source icon without crowding the card edge.

#### Scenario: Card header shows two left text lines
- **WHEN** the panel displays a history item card
- **THEN** the card header's left side shows the item kind and relative timestamp as two text lines
- **AND** the left-side header text has visible top and leading inset from the card edge

#### Scenario: Source icon fills the right header edge
- **WHEN** the panel displays a history item card with a captured source app icon
- **THEN** the source icon is aligned to the right edge of the header
- **AND** the source icon visually occupies the header height without a visible right gutter
- **AND** the left-side header text does not overlap the source icon

#### Scenario: Pinboard assignment remains usable
- **WHEN** a history item is pinned or assigned to a custom pinboard
- **THEN** the card header still shows only the item kind and relative timestamp on the left side
- **AND** the item remains available through pinboard filtering and item actions

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

### Requirement: Search visible history
Copythat SHALL filter visible history by a case-insensitive search query.

#### Scenario: Search query is entered
- **WHEN** the user enters search text
- **THEN** Copythat shows items whose searchable text contains the query
- **AND** searchable text includes title, preview, link title, source app, kind label, and file paths

#### Scenario: Search query changes
- **WHEN** the search query changes
- **THEN** Copythat selects the first visible matching item when available

#### Scenario: Search query is cleared
- **WHEN** the user clears the search query
- **THEN** Copythat shows items matching the current pinboard filter without a search constraint

### Requirement: Filter by pinboard
Copythat SHALL filter visible history by all items, pinned items, or configured custom pinboards.

#### Scenario: All pinboard is selected
- **WHEN** the user selects the Clipboard pinboard
- **THEN** Copythat shows all history items that match the current search query

#### Scenario: Pinned pinboard is selected
- **WHEN** the user selects the Pinned pinboard
- **THEN** Copythat shows pinned history items that match the current search query

#### Scenario: Custom pinboard is selected
- **WHEN** the user selects a custom pinboard
- **THEN** Copythat shows history items assigned to that custom pinboard and matching the current search query

### Requirement: Show footer status and shortcuts
Copythat SHALL show useful status information at the bottom of the panel.

#### Scenario: No permission message is active
- **WHEN** the panel footer has no active permission message
- **THEN** Copythat shows keyboard hints and the current visible item count

#### Scenario: Permission message is active
- **WHEN** a paste or permission issue sets a message
- **THEN** Copythat shows that message in the panel footer
- **AND** offers an action to open Accessibility settings

### Requirement: Display a clear panel command bar
Copythat SHALL present the bottom panel header as a compact command bar that visually separates search, pinboard filtering, and the add/settings action without changing their behavior.

#### Scenario: Panel header displays default controls
- **WHEN** the bottom panel is visible and search is not expanded
- **THEN** the header shows a compact search control on the left
- **AND** shows the available pinboard filters as a grouped horizontal control in the center
- **AND** shows a compact add/settings control on the right

#### Scenario: Selected pinboard remains clear
- **WHEN** a pinboard filter is selected
- **THEN** the selected filter is visually distinct from unselected filters
- **AND** the selected state does not visually dominate the clipboard item cards

#### Scenario: Search expands without breaking header layout
- **WHEN** the user expands search or enters a search query
- **THEN** the search field remains in the left command bar area
- **AND** the pinboard filters remain horizontally scrollable when space is constrained
- **AND** the add/settings control remains available on the right

#### Scenario: Header controls provide interaction feedback
- **WHEN** the user hovers, presses, or focuses a top command bar control
- **THEN** Copythat provides visible feedback appropriate for a compact macOS utility panel

### Requirement: Select cards responsively
Copythat SHALL keep bottom-panel card selection responsive when users browse visible cards with keyboard movement or mouse clicks.

#### Scenario: User moves selection with keyboard
- **WHEN** the user repeatedly sends left or right movement commands in the bottom panel
- **THEN** Copythat updates the selected card without visible stutter
- **AND** the selected-card border, shadow, scale, raised position, and scroll-to-center behavior remain visually consistent with the existing panel design

#### Scenario: User clicks a card
- **WHEN** the user single-clicks a visible card in the bottom panel
- **THEN** Copythat selects that card promptly
- **AND** clicking the already selected card does not trigger unnecessary selection updates

#### Scenario: User double-clicks a card
- **WHEN** the user double-clicks a visible card in the bottom panel
- **THEN** Copythat still pastes the selected card

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
