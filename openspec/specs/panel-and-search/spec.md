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

#### Scenario: Pinned item is unpinned while viewing Pinned
- **WHEN** the user unpins a visible item while the Pinned filter is selected
- **THEN** Copythat removes that item from the visible timeline immediately
- **AND** the visible item count updates without requiring the user to switch filters

#### Scenario: Item is removed from current custom pinboard
- **WHEN** the user removes a visible item from the selected custom pinboard
- **THEN** Copythat removes that item from the visible timeline immediately
- **AND** the visible item count updates without requiring the user to switch filters

#### Scenario: Custom pinboard assignment does not pin an item
- **WHEN** the user assigns an unpinned item to a custom pinboard
- **THEN** Copythat keeps the item unpinned
- **AND** the item does not appear in the Pinned filter unless the user pins it

### Requirement: Present state-aware card actions
Copythat SHALL present card actions that match each card's current pinned and pinboard state.

#### Scenario: Unpinned card action
- **WHEN** the user opens the context menu for an unpinned card
- **THEN** Copythat shows a Pin action
- **AND** Copythat does not show an Unpin action

#### Scenario: Pinned card action
- **WHEN** the user opens the context menu for a pinned card
- **THEN** Copythat shows an Unpin action

#### Scenario: Card assigned to custom pinboard
- **WHEN** the user opens the context menu for a card assigned to a custom pinboard
- **THEN** Copythat offers an action to remove the card from its pinboard

#### Scenario: Card not assigned to custom pinboard
- **WHEN** the user opens the context menu for a card without a custom pinboard assignment
- **THEN** Copythat does not offer an action to remove the card from a pinboard

### Requirement: Show footer status and shortcuts
Copythat SHALL show useful status information at the bottom of the panel.

#### Scenario: No permission message is active
- **WHEN** the panel footer has no active permission message
- **THEN** Copythat shows keyboard hints and the current visible item count

#### Scenario: Permission message is active
- **WHEN** a paste or permission issue sets a message
- **THEN** Copythat shows that message in the panel footer
- **AND** offers an action to open Accessibility settings

### Requirement: Create custom pinboards from the panel
Copythat SHALL let users create a named, colored custom pinboard from the bottom-panel `+` control.

#### Scenario: User opens pinboard creation
- **WHEN** the user activates the bottom-panel `+` control
- **THEN** Copythat shows a compact creation form associated with that control
- **AND** the form provides a pinboard name field and a fixed set of color choices
- **AND** Copythat does not open Settings

#### Scenario: User creates a valid pinboard
- **WHEN** the user enters a non-empty trimmed name that is not already used by a custom pinboard, selects a color, and confirms creation
- **THEN** Copythat creates the custom pinboard with that name and color
- **AND** the new pinboard appears in the panel immediately
- **AND** the new pinboard becomes the selected filter
- **AND** no clipboard item is automatically moved into the new pinboard

#### Scenario: User enters an invalid pinboard name
- **WHEN** the entered pinboard name is empty after trimming or exactly matches an existing trimmed custom pinboard name
- **THEN** Copythat does not allow the pinboard to be created

#### Scenario: User cancels pinboard creation
- **WHEN** the user cancels the creation form or presses Escape while it is active
- **THEN** Copythat dismisses the creation form without creating a pinboard
- **AND** pressing Escape may close the bottom panel

#### Scenario: User confirms with the keyboard
- **WHEN** the creation form contains a valid name and the user presses Return
- **THEN** Copythat creates the pinboard
- **AND** Copythat does not paste the selected clipboard item

### Requirement: Delete custom pinboards from the panel
Copythat SHALL let users delete custom pinboards from the bottom panel while preserving all clipboard history items.

#### Scenario: Custom pinboard delete action is available
- **WHEN** the user opens the context menu for a custom pinboard filter in the bottom panel
- **THEN** Copythat shows an action to delete that custom pinboard

#### Scenario: Built-in pinboards cannot be deleted
- **WHEN** the user opens or uses the Clipboard or Pinned filter controls
- **THEN** Copythat does not offer an action to delete those built-in pinboards

#### Scenario: User cancels custom pinboard deletion
- **WHEN** the user chooses to delete a custom pinboard and then cancels the confirmation
- **THEN** Copythat keeps the custom pinboard
- **AND** clips assigned to that pinboard remain assigned to it

#### Scenario: User confirms custom pinboard deletion
- **WHEN** the user confirms deletion of a custom pinboard
- **THEN** Copythat removes that custom pinboard from the panel
- **AND** Copythat does not delete any clipboard history items
- **AND** clips assigned to the deleted pinboard are moved out of that pinboard

#### Scenario: Deletion confirmation shows affected clips
- **WHEN** Copythat asks the user to confirm deletion of a custom pinboard
- **THEN** the confirmation identifies the pinboard by name
- **AND** the confirmation states how many clips will be moved out of that pinboard

#### Scenario: Current custom pinboard is deleted
- **WHEN** the user confirms deletion of the currently selected custom pinboard
- **THEN** Copythat selects the Clipboard filter
- **AND** Copythat preserves the current search query

#### Scenario: Non-selected custom pinboard is deleted
- **WHEN** the user confirms deletion of a custom pinboard that is not the currently selected filter
- **THEN** Copythat keeps the current filter selected
- **AND** Copythat preserves the current search query

### Requirement: Display stable custom pinboard colors
Copythat SHALL display each custom pinboard using its persisted selected color from a fixed, visually consistent palette.

#### Scenario: Color choices are displayed
- **WHEN** the pinboard creation form is visible
- **THEN** Copythat offers a small fixed set of distinct color choices
- **AND** the choices have consistent perceived saturation and brightness

#### Scenario: Custom pinboard is displayed
- **WHEN** a custom pinboard filter is visible
- **THEN** its category marker uses the color selected when the pinboard was created

#### Scenario: Multiple pinboards use the same color
- **WHEN** a user selects a color already used by another custom pinboard
- **THEN** Copythat allows the new pinboard to use that color

### Requirement: Display a clear panel command bar
Copythat SHALL present the bottom panel header as one compact centered command group containing search, pinboard filtering, and the add-pinboard action without changing search or filtering behavior. The search control, pinboard filters, and add-pinboard control SHALL share a consistent compact visible height. Non-Clipboard pinboard filters SHALL use vivid circular category markers that preserve their configured colors.

#### Scenario: Panel header displays default controls
- **WHEN** the bottom panel is visible and search is not expanded
- **THEN** the header shows search, Clipboard, the available pinboard filters, and add-pinboard together as one horizontally centered command group
- **AND** Clipboard appears within the pinboard filter group
- **AND** the gap between command groups is visibly larger than the gap between individual pinboard filters
- **AND** the visible height of search, pinboard filters, and add-pinboard appears consistent

#### Scenario: Pinboard categories show vivid circular markers
- **WHEN** Pinned and custom pinboard filters are visible
- **THEN** each filter shows a compact circular category marker
- **AND** the category markers have stronger visual presence than the previous compact marker size
- **AND** each custom pinboard marker uses its configured color
- **AND** the Clipboard filter continues to use its history icon

#### Scenario: Category markers remain vivid across filter states
- **WHEN** a non-Clipboard pinboard filter is selected or unselected
- **THEN** its circular category marker retains a strongly saturated appearance
- **AND** selection remains visually distinct without relying on muting the category marker

#### Scenario: Category markers adapt to appearance
- **WHEN** Copythat is displayed in Aqua or Dark Aqua
- **THEN** the category markers remain clear and visually consistent with macOS

#### Scenario: Selected pinboard remains clear
- **WHEN** a pinboard filter is selected
- **THEN** the selected filter is visually distinct from unselected filters
- **AND** the selected state does not visually dominate the clipboard item cards

#### Scenario: Search expands left without moving adjacent controls
- **WHEN** the user expands the compact search control
- **THEN** the search field's right edge remains anchored at the compact search position
- **AND** the additional search-field width extends to the left
- **AND** the pinboard filters and add-pinboard control remain in the same positions

#### Scenario: Search expands with natural motion
- **WHEN** the user expands or collapses search
- **THEN** the search control animates as a continuous pill rather than a hard replacement
- **AND** the animation is smooth and has no visible rebound
- **AND** search text and the clear button appear only after the field begins expanding

#### Scenario: Search expands without breaking header layout
- **WHEN** the user expands search or enters a search query
- **THEN** the complete command group remains within the available header width
- **AND** the pinboard filter group remains horizontally scrollable when space is constrained
- **AND** search and the add-pinboard control remain available

#### Scenario: Empty search collapses after another command-bar action
- **WHEN** search is expanded with an empty query and the user activates a pinboard filter or add-pinboard
- **THEN** the search field loses focus and returns to its compact state
- **AND** the activated command-bar action still completes

#### Scenario: Active query remains visible after another command-bar action
- **WHEN** search contains a query and the user activates another command-bar control
- **THEN** the search field remains expanded with the query visible
- **AND** the query continues to filter clipboard items

#### Scenario: Header controls provide interaction feedback
- **WHEN** the user hovers, presses, or focuses a top command bar control
- **THEN** Copythat provides visible feedback appropriate for a compact macOS utility panel

### Requirement: Select cards responsively
Copythat SHALL keep bottom-panel card selection responsive when users browse visible cards with keyboard movement or mouse clicks.

#### Scenario: User moves selection with keyboard
- **WHEN** the user repeatedly sends left or right movement commands in the bottom panel
- **THEN** Copythat updates the selected card without visible stutter or accumulating scroll delay
- **AND** the selected-card border, shadow, scale, raised position, and scroll-to-center behavior remain visually consistent with the existing panel design

#### Scenario: User clicks a card
- **WHEN** the user single-clicks a visible card in the bottom panel
- **THEN** Copythat selects that card promptly
- **AND** clicking the already selected card does not trigger unnecessary selection updates

#### Scenario: User double-clicks a card
- **WHEN** the user double-clicks a visible card in the bottom panel
- **THEN** Copythat still pastes the selected card

#### Scenario: User revisits cards with the same source icon
- **WHEN** selection changes repeatedly between visible cards whose source appearance has already been rendered
- **THEN** Copythat reuses the derived source appearance instead of repeatedly delaying selection feedback

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

### Requirement: Toggle panel preview privacy
Copythat SHALL let users hide and restore visible history card previews from a global privacy control in the bottom panel command bar.

#### Scenario: Privacy control is shown in the command bar
- **WHEN** the bottom panel displays its command bar
- **THEN** Copythat shows a privacy visibility control after the pinboard filters
- **AND** the privacy visibility control appears before the new-pinboard `+` control
- **AND** the privacy visibility control remains available when custom pinboard filters overflow into a horizontal scrolling region

#### Scenario: User hides previews
- **WHEN** the user activates the privacy visibility control while previews are visible
- **THEN** Copythat hides preview content for every visible history card
- **AND** each card still shows its item kind, relative timestamp, source context, selection state, and available item actions
- **AND** search, pinboard filtering, paste, drag, pin, move-to-pinboard, and delete behavior remain available

#### Scenario: User restores previews
- **WHEN** the user activates the privacy visibility control while previews are hidden
- **THEN** Copythat restores normal preview rendering for every visible history card

#### Scenario: Privacy mode does not change history data
- **WHEN** the user hides or restores previews
- **THEN** Copythat does not modify captured clipboard history, sensitive-content recording, pinboard assignments, persisted items, or restorable pasteboard content
