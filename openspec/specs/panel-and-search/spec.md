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
Copythat SHALL display clipboard history in a bottom floating panel that fits the visible display area, remains anchored near the bottom of the active visible screen area while visible, cannot be repositioned by mouse dragging, and does not show rectangular shadow artifacts at its rounded corners.

#### Scenario: Panel opens
- **WHEN** the panel is shown
- **THEN** it appears as a native macOS floating panel near the bottom of the active visible screen area
- **AND** the first visible item is selected when available

#### Scenario: Panel cannot be dragged
- **WHEN** the bottom floating panel is visible
- **AND** the user drags the panel background or another non-control panel region with the mouse
- **THEN** the panel remains anchored near the bottom of the active visible screen area
- **AND** existing panel controls and card interactions remain available

#### Scenario: Panel corners are rendered
- **WHEN** the bottom floating panel is visible
- **THEN** its rounded corners do not show rectangular outer shadow artifacts

#### Scenario: Panel is closed
- **WHEN** the user presses Escape in the panel
- **THEN** Copythat closes the panel

### Requirement: Browse and select visible items
Copythat SHALL let users browse visible clipboard items horizontally, maintain a selected item, and show a balanced empty timeline state when restoration is complete and no items are visible. While startup history restoration is incomplete, the history content area SHALL instead show a minimal loading-history state, not an empty history or empty search result.

#### Scenario: History has visible items
- **WHEN** restoration is complete and the panel displays matching history items
- **THEN** each item is shown as a card with its title, preview, kind, source context, and available item actions

#### Scenario: User moves selection
- **WHEN** the user sends left or right movement commands in the panel
- **THEN** Copythat moves selection within the visible items without moving past the first or last item

#### Scenario: No items are visible
- **WHEN** restoration is complete and filters and search produce no visible items
- **THEN** Copythat shows an empty timeline state instead of item cards
- **AND** the empty state is visually centered within the timeline content area rather than aligned to the leading card position
- **AND** the empty state does not show the app logo as a prominent primary graphic

#### Scenario: Selected pinboard has no items
- **WHEN** restoration is complete and the user selects a pinboard with no matching visible items
- **THEN** Copythat shows empty-state copy that identifies the selected pinboard context

#### Scenario: Search has no matches
- **WHEN** restoration is complete and the user enters a search query that matches no visible items
- **THEN** Copythat shows empty-state copy that identifies the empty search result context

#### Scenario: Panel opens before history has loaded
- **WHEN** the user opens the panel while startup history is loading
- **THEN** the history content area shows “Loading clipboard history…” rather than reporting no history or no search matches
- **AND** menu and shortcut panel activation remain usable without waiting for restoration
- **AND** loading counts are not presented as an authoritative empty-history count

### Requirement: Preserve current browsing inputs across history restoration
Copythat SHALL keep search and pinboard selection usable during startup loading and apply their current values to the completed history without requiring another user input. Selection-driven preview enrichment SHALL reconcile against completed baseline-plus-replay history rather than transient baseline selections.

#### Scenario: Search entered while loading
- **WHEN** the user enters a query while persisted history is loading
- **THEN** completion immediately exposes matching retained restored and startup items using that query
- **AND** the user does not need to type it again

#### Scenario: Pinboard selected while loading
- **WHEN** the user selects a custom or Pinned filter and enters a query before restoration finishes
- **THEN** completed results use the current filter intersected with the current query
- **AND** selection is valid for those visible results or empty when no results survive

#### Scenario: Replay replaces the transient baseline selection
- **WHEN** the panel is visible and startup replay would replace the baseline's initially selected URL with a different final selection
- **THEN** merely installing that transient baseline selection does not start selection-driven metadata or browser fallback for it
- **AND** existing eager enrichment for newly inserted URLs remains available through ordinary insertion eligibility

### Requirement: Gate history organization actions while history is unavailable
Copythat SHALL disable pin/unpin, remove, move-to-pinboard, clear, and existing custom-pinboard edit/delete actions while startup history restoration is incomplete or accepted capture work is being drained for normal Quit. Rejected actions MUST NOT alter history, accepted capture eligibility, system pasteboard content, or pinboard settings, and MUST NOT be silently queued for later execution. Whole pinboard edit/delete confirmations MUST be guarded before either settings or history changes. Search, filtering, panel opening, preview privacy and safe new-pinboard creation remain available during history loading.

#### Scenario: Destructive history action is attempted while loading
- **WHEN** a history-destructive action is invoked before restoration completes
- **THEN** the action is unavailable and its handler makes no history, pasteboard, save or image-invalidation change
- **AND** the operation is not applied after loading finishes

#### Scenario: Rename or delete cannot split settings from assignments
- **WHEN** pinboard edit or deletion is attempted while history is loading
- **THEN** neither the pinboard settings nor restored item assignments change
- **AND** completing restoration does not reveal assignments referring to a name that was changed by that rejected action

#### Scenario: Confirmation is checked when executed
- **WHEN** a pinboard confirmation callback executes while history mutations are unavailable
- **THEN** it is rejected before updating pinboard name, color, deletion state or item assignments

#### Scenario: Mutation availability returns after loading or cancelled Quit
- **WHEN** restoration is complete and no Quit admission pause remains
- **THEN** existing history and pinboard mutation actions return to their ordinary behavior
- **AND** cancelling Quit does not discard in-memory history

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
Copythat SHALL display each custom pinboard using its persisted selected color from a fixed, vivid palette. Palette colors SHALL be anchored to the hues of the corresponding macOS system colors (orange, green, teal, blue, purple, pink) and SHALL use per-hue tuned saturation and brightness, rather than one numerically uniform saturation/brightness pair that renders perceptually uneven across hues.

Vividness SHALL be measured rather than asserted qualitatively: every palette color SHALL have an OKLab chroma of at least 0.11. Both that floor and the sRGB saturation and brightness floors SHALL be evaluated after converting the palette's calibrated color space to sRGB, the space that reaches the display.

#### Scenario: Color choices are displayed
- **WHEN** the pinboard creation form is visible
- **THEN** Copythat offers a small fixed set of distinct color choices
- **AND** every choice has an OKLab chroma of at least 0.11, measured after conversion to sRGB
- **AND** every choice has sRGB saturation of at least 0.55 and sRGB brightness of at least 0.75

#### Scenario: Custom pinboard is displayed
- **WHEN** a custom pinboard filter is visible
- **THEN** its category marker uses the color selected when the pinboard was created

#### Scenario: Existing pinboards adopt palette updates without migration
- **WHEN** the palette definition changes between app versions
- **THEN** every persisted custom pinboard renders with the updated palette color for its stored color token
- **AND** no persisted data is rewritten

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



#### Scenario: Browse lazy media with previews hidden
- **WHEN** Hide Previews is enabled and restored image or URL cards enter the displayed timeline
- **THEN** preview display initiates zero image/link-image blob reads
- **AND** enabling privacy cancels UI-owned loading and rejects its late results
- **AND** explicit paste or drag remains available and can load the payload required by that action

### Requirement: Edit custom pinboards from the panel
Copythat SHALL let users edit the name and color of custom pinboards from the bottom panel, preserving all clipboard history items and their organization.

#### Scenario: Custom pinboard edit action is available
- **WHEN** the user opens the context menu for a custom pinboard filter in the bottom panel
- **THEN** Copythat shows an action to edit that custom pinboard
- **AND** the edit action is presented as a normal, non-destructive action distinct from the delete action

#### Scenario: Built-in pinboards cannot be edited
- **WHEN** the user opens or uses the Clipboard or Pinned filter controls
- **THEN** Copythat does not offer an action to edit those built-in pinboards

#### Scenario: Edit form shows current values
- **WHEN** the user chooses to edit a custom pinboard
- **THEN** Copythat shows a compact edit form associated with that pinboard
- **AND** the form's name field contains the pinboard's current name
- **AND** the form's fixed set of color choices marks the pinboard's current color as selected
- **AND** the name field receives editing focus
- **AND** Copythat does not open Settings

#### Scenario: User renames a custom pinboard
- **WHEN** the user enters a valid new name for a custom pinboard and confirms the edit
- **THEN** Copythat displays the pinboard under its new name immediately
- **AND** every clip that was assigned to the pinboard remains assigned to it under the new name
- **AND** no clipboard item is deleted or moved out of the pinboard
- **AND** no clip's pinned state changes
- **AND** no clip's content changes

#### Scenario: User changes only the pinboard color
- **WHEN** the user selects a different color without changing the name and confirms the edit
- **THEN** the pinboard's category marker uses the new color immediately
- **AND** clip assignments to that pinboard are unchanged

#### Scenario: User renames and recolors together
- **WHEN** the user enters a valid new name and selects a different color, then confirms the edit
- **THEN** Copythat applies the new name and the new color in a single edit
- **AND** clip assignments follow the rename as with a name-only edit

#### Scenario: User enters an invalid pinboard name
- **WHEN** the edited pinboard name is empty after trimming surrounding whitespace or exactly matches the trimmed name of a different custom pinboard
- **THEN** Copythat does not allow the edit to be saved
- **AND** keeping the pinboard's own current name is not treated as a duplicate

#### Scenario: User cancels the edit
- **WHEN** the user cancels the edit form or presses Escape while it is active
- **THEN** Copythat dismisses the edit form without changing the pinboard's name or color
- **AND** clip assignments remain unchanged

#### Scenario: Currently selected pinboard is renamed
- **WHEN** the user confirms renaming the custom pinboard that is the currently selected filter
- **THEN** Copythat keeps the renamed pinboard selected as the active filter
- **AND** Copythat does not fall back to the Clipboard filter
- **AND** Copythat preserves the current search query

#### Scenario: Non-selected pinboard is renamed
- **WHEN** the user confirms renaming a custom pinboard that is not the currently selected filter
- **THEN** Copythat keeps the current filter selected
- **AND** Copythat preserves the current search query

#### Scenario: User confirms with the keyboard
- **WHEN** the edit form contains a valid name and the user presses Return
- **THEN** Copythat saves the edit
- **AND** Copythat does not paste the selected clipboard item

### Requirement: Store source app icons at display-sufficient resolution
Copythat SHALL store each captured source app icon at a bitmap resolution sufficient for sharp rendering at the card header's display size on Retina displays, using the best available high-resolution representation of the app icon rather than the image's logical point size. Stored icon resolution SHALL NOT exceed the bounded maximum needed for the header display slot.

#### Scenario: Captured icon is sharp on Retina displays
- **WHEN** Copythat captures the source app icon for a new history item from an app bundle that ships high-resolution icon representations
- **THEN** the stored icon bitmap has at least 104 pixels on its longest side (52pt header slot at 2× scale)
- **AND** the stored icon bitmap does not exceed 160 pixels on its longest side

#### Scenario: Low-resolution source does not get upscaled
- **WHEN** the source app's icon provides no representation larger than the display requirement
- **THEN** Copythat stores the largest available representation without inventing pixels through upscaling

### Requirement: Derive card header theme color from dominant brand color
Copythat SHALL derive each history card header's theme color from the source app icon's dominant vivid color, aggregated across the icon's pixels with coverage weighting, rather than selecting a single best-scoring pixel. The derivation SHALL exclude near-white, near-black, low-alpha, and low-saturation samples, and SHALL normalize saturation adaptively so muted brand colors gain mild vividness while already-saturated colors stay bounded below a neon threshold. When no icon or no usable color is available, Copythat SHALL fall back to a neutral accent color.

#### Scenario: Single-color icon preserves its color
- **WHEN** the source app icon is a single saturated color
- **THEN** the header theme color's hue closely matches that icon color

#### Scenario: Multi-color icon yields the dominant brand color
- **WHEN** the source app icon contains multiple brand colors with clearly different coverage areas
- **THEN** the header theme color's hue matches the most-covered vivid color rather than a highlight or gradient-edge pixel

#### Scenario: Neutral regions do not pollute the result
- **WHEN** the source app icon contains large white, black, or gray areas alongside a smaller vivid brand color region
- **THEN** the header theme color is derived from the vivid region and is not pulled toward gray

#### Scenario: Missing or unusable icon falls back to neutral accent
- **WHEN** a history item has no source icon data or the icon yields no usable color samples
- **THEN** the header uses the neutral fallback accent color

#### Scenario: Extracted color stays within bounded saturation
- **WHEN** the header theme color is derived from any source icon
- **THEN** its saturation is normalized within a bounded range that avoids both washed-out gray and fluorescent over-saturation

### Requirement: Display lazy media only while eligible
Copythat SHALL load persisted image/link-image previews only for cards entering the lazy display path while the panel is visible and previews are enabled. Closing the panel SHALL revoke eligibility even when its hosting view remains retained. Card disappearance, removal, changed media identity, panel close or preview concealment SHALL cancel UI-owned loading and prevent stale result application. Temporary card media SHALL be released when no longer needed instead of accumulating across retained cards. A change between resident bytes and a persisted reference SHALL invalidate the card's display request even when the content address is unchanged, so the current payload remains displayable through the appropriate resident or on-demand path. This display contract SHALL NOT change when durable history release is permitted.

#### Scenario: Visible lazy card
- **WHEN** a restored card enters the display path with the panel visible and previews enabled
- **THEN** it uses existing in-memory bytes or requests its referenced media through on-demand loading
- **AND** cards not entering that display path do not start media reads

#### Scenario: Close retained panel during loading
- **WHEN** the panel closes while preview media is loading and its hosting view remains retained
- **THEN** no further visible-media loads start and UI-owned requests are cancelled
- **AND** late completion does not apply to the hidden panel or a later reopened card request

#### Scenario: Remove or replace loading card
- **WHEN** a loading card disappears, is evicted or deleted, or changes its media reference
- **THEN** its old completion cannot update a surviving or replacement card

#### Scenario: Replace inline media on the same card
- **WHEN** the same item ID changes from a persisted reference to inline media or replaces existing inline media
- **THEN** the card displays the current payload and rejects completion for the prior payload

#### Scenario: Close and reopen before an intermediate render
- **WHEN** panel close and reopen occur before the retained card renders the closed state
- **THEN** the previous display request remains invalid and cannot apply merely because visibility is true again

#### Scenario: Resident image becomes a reference with the same address
- **WHEN** an eligible visible card receives a replacement item whose image or link-image bytes have been released while its item ID, content address, metadata and panel authorization remain unchanged
- **THEN** the card requests the referenced payload through the existing on-demand path
- **AND** successful loading displays the same content and removes the loading indicator without changing card geometry
- **AND** an existing cache hit is permitted to satisfy the request without disk reads

#### Scenario: Reference becomes resident with the same address
- **WHEN** an eligible visible card receives resident bytes matching its existing image or link-image content address
- **THEN** the card displays those resident bytes and clears its prior temporary lazy-media state
- **AND** a pending completion from the superseded lazy request cannot repopulate that state
- **AND** displaying the resident payload does not start a new blob read

#### Scenario: Reopened card starts a current request
- **WHEN** a retained card renders the reopened panel under a newer authorization generation with an unloaded payload
- **THEN** it can start a new authorized display request and successfully show its payload
- **AND** a completion belonging to the older generation remains invalid

#### Scenario: Residency changes while media display is hidden
- **WHEN** an image or link-image card changes between resident bytes and a persisted reference while the panel is hidden or previews are concealed
- **THEN** that change does not initiate a preview blob read
- **AND** scrolling concealed cards continues to initiate zero preview blob reads

### Requirement: Reconcile cards using established media identities
At the boundary between persisted media references and native card display, Copythat SHALL reuse each payload's established content address and its residency in the history item to distinguish render changes, without comparing or hashing media bytes for card render equality or display-task identity. This SHALL apply to image, link-image and captured source-icon render identities; source-icon native image-view identity SHALL reuse the established icon content address without hashing icon bytes. Card reconciliation SHALL continue to reflect all metadata affecting displayed content, source appearance, item actions and drag content, together with selection, pinboards, preview privacy, panel visibility and authorization. It SHALL NOT change global history-item equality or the persistence format.

#### Scenario: Same payload and residency are rendered again
- **WHEN** card metadata, external display inputs, all media content addresses and all item residency states are unchanged
- **THEN** card render reconciliation treats the input as unchanged without a media-byte comparison or a new media identity hash

#### Scenario: Media identity or residency changes
- **WHEN** an image, link-image or source-icon content address changes, or its bytes become resident or nonresident with the same address
- **THEN** card render reconciliation treats the input as changed
- **AND** image and link-image residency or address changes invalidate their prior display-task identity

#### Scenario: Card metadata or actions change
- **WHEN** an item's title, preview, kind, source app, creation time, pin state, pinboard assignment, text value, file URLs or link title changes
- **THEN** the card updates the affected display or actions instead of retaining stale input

#### Scenario: Captured source icons keep their own content identities
- **WHEN** cards display captured source icons
- **THEN** equal icon content addresses have equal native source-icon content identities and different addresses have different identities
- **AND** each card displays its own captured icon rather than another card's icon

#### Scenario: Source icon residency changes
- **WHEN** a card's source-icon bytes become available or unavailable while the icon content address remains unchanged
- **THEN** the card updates between the real icon and its fallback source appearance without hashing icon bytes for view identity

### Requirement: Keep lazy preview layout stable
Copythat SHALL reserve the existing image card region and a URL preview's 105pt image region whenever the corresponding payload exists, including while loading or after access failure. Image presentation SHALL preserve the existing complete aspect ratio and bounded content region. URL typography and spacing SHALL use payload existence so completion does not switch from text-only layout.

#### Scenario: URL image arrives late
- **WHEN** a displayed URL references an unloaded preview image
- **THEN** its image region, title typography and spacing are established before completion
- **AND** loading or failure keeps that layout and uses a placeholder or fallback until successful display

#### Scenario: Image card is loading
- **WHEN** an image payload has not materialized yet
- **THEN** a fixed-region placeholder or progress indicator preserves the card and header geometry

### Requirement: Drag restored images as images
Copythat SHALL provide an image representation for restored image drag, materializing a persisted payload only when required by the drag consumer. An unloaded or failed image SHALL NOT be substituted with the item's textual preview. Existing text, URL and file drag behavior SHALL be preserved.

#### Scenario: Drag an unloaded image
- **WHEN** the user drags an unloaded restored image and the receiver requests its image representation
- **THEN** the provider asynchronously obtains verified image data and returns a supported image representation
- **AND** provider creation alone does not read the heavy blob

#### Scenario: Drag payload cannot be restored
- **WHEN** the requested persisted image is missing or corrupted
- **THEN** the provider reports image-load failure without supplying corrupt bytes or a text payload

### Requirement: Reuse normalized searchable text for immediate search
Copythat SHALL reuse each item's already-normalized searchable text across repeated query changes while its searchable metadata is unchanged. Each item SHALL establish that text once when created or restored, and a link-preview enrichment SHALL replace the affected item's derived text before refreshed results are exposed. Search SHALL remain synchronous without introducing debounce or a background search delay, and SHALL preserve existing searchable fields, their order, space delimiter, localized case normalization, file-path matching, query trimming and Pinboard intersection behavior.

#### Scenario: Repeated queries over a full configured history
- **WHEN** 1000 items are created and at least five different search queries are applied without item enrichment
- **THEN** normalized searchable text is built exactly once per created item
- **AND** constructing the history view and changing queries cause zero additional corpus builds
- **AND** each query returns the matching items in their existing history order

#### Scenario: Every searchable field remains independently searchable
- **WHEN** a query matches a token unique to an item's title, preview, link title, source app, kind label or file path
- **THEN** that item matches through that field independently of the other searchable fields
- **AND** uppercase and lowercase queries, surrounding query whitespace and Chinese searchable text retain existing matching behavior

#### Scenario: Organization changes reuse normalized text
- **WHEN** items are pinned, unpinned, assigned to or removed from a Pinboard, or their Pinboard assignments are renamed or cleared
- **THEN** those changes produce zero additional corpus builds
- **AND** search results continue to intersect with the current Pinboard filter

#### Scenario: Media residency changes reuse normalized text
- **WHEN** an item's image or link-image bytes are storage-optimized, released after durable save or materialized for paste without link-preview enrichment
- **THEN** its normalized searchable text remains unchanged with zero additional corpus builds
- **AND** the item retains the same searchable metadata matches

#### Scenario: Link-preview enrichment replaces stale searchable text
- **WHEN** a link-preview enrichment replaces an item's displayed title and link title
- **THEN** exactly that item rebuilds its corpus once before search results refresh
- **AND** the new title immediately matches search
- **AND** a token present only in the replaced titles no longer matches that item
- **AND** unrelated items reuse their existing corpora

#### Scenario: Link-preview enrichment retains existing nil-title semantics
- **WHEN** an enrichment provides no title for an item with an existing link title
- **THEN** the displayed title remains and the link title is cleared
- **AND** the affected corpus is rebuilt once and reflects those resulting fields
- **AND** enrichment with unchanged titles or only a preview image also rebuilds the affected corpus once

### Requirement: Keep normalized searchable text out of persisted history
Normalized searchable text SHALL remain runtime-derived. Copythat MUST rebuild it from decoded metadata rather than read a persisted corpus. Legacy encoded items and V2 history manifests MUST NOT acquire `searchText` or `searchCorpus` fields or corpus blobs, and the V2 schema version SHALL remain 2 without migration.

#### Scenario: Legacy item round-trip
- **WHEN** an item is encoded in the legacy payload format and decoded again
- **THEN** the encoded item contains no search corpus fields
- **AND** decoding builds its corpus exactly once and retains correct metadata search matches
- **AND** unexpected input corpus fields do not override metadata-derived search

#### Scenario: V2 history is saved and restored into a new session
- **WHEN** items are saved as V2 history and restored into a new Store
- **THEN** the manifest version is 2 and neither manifest nor item records contain search corpus fields
- **AND** restoring each item builds its corpus once from metadata without corpus blob storage or migration
- **AND** subsequent Store initialization and queries cause zero additional corpus builds and retained metadata is searchable
