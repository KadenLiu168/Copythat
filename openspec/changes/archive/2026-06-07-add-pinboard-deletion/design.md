## Context

Copythat already supports custom pinboard creation from the bottom-panel command bar. Custom pinboards are stored in `AppSettings.customPinboards`, while clipboard items keep their assignment as a name string on `ClipboardItem.pinboardName`.

There is no current way to delete a custom pinboard. This change crosses panel interaction, settings persistence, clipboard-history persistence, and filtered selection state, so the deletion behavior needs a small explicit design.

## Goals / Non-Goals

**Goals:**

- Let users delete obsolete custom pinboards from the bottom panel.
- Keep deletion discoverable as an object-specific action without adding permanent toolbar chrome.
- Confirm before deleting and show how many clips will be moved out of the pinboard.
- Preserve all clipboard history items and only clear matching pinboard assignments.
- Keep panel state predictable after deletion, including selection fallback and search preservation.

**Non-Goals:**

- Rename, reorder, recolor, or undo custom pinboard deletion.
- Add a separate pinboard management screen.
- Delete clipboard items when their pinboard is deleted.
- Change the built-in Clipboard or Pinned pinboards.
- Replace the existing name-based pinboard assignment model.

## Decisions

### Delete from a custom pinboard context menu

Attach a context menu to pinboard filter buttons and show `Delete Pinboard...` only when the button represents a custom pinboard. Clipboard and Pinned remain normal filter controls with no delete action.

This keeps the top command bar visually stable and fits macOS object-action patterns. A permanent delete button was rejected because deletion is low-frequency and destructive, while the command bar is optimized for search, filtering, and creation.

### Confirm deletion with affected clip count

Selecting the delete menu item records the pending custom pinboard name and presents a confirmation alert. The alert title names the pinboard, and the message includes the number of clips currently assigned to it.

This reduces accidental deletion and makes the consequence concrete. A direct delete action was rejected because right-click menus can still be opened accidentally and custom pinboards may represent meaningful organization work.

### Clear item assignments after deleting the pinboard

Deletion first removes the custom pinboard from settings, then clears `pinboardName` on all clipboard items whose assignment matches the deleted name. Clipboard items are not removed, and their `isPinned` values remain unchanged.

This preserves the current name-based association model and mirrors the existing card action that removes an item from a pinboard. A broader migration to stable pinboard IDs was rejected because deletion does not require changing the clipboard-history schema.

### Fall back only when the active filter disappears

If the deleted custom pinboard is the selected filter, set the selected filter to Clipboard after deletion. If another filter is active, keep it active. The current search query remains unchanged in both cases.

This avoids leaving the panel on an empty filter that no longer exists while preserving the user's search context. Clearing search was rejected because deleting a category is independent from the user's current query.

## Risks / Trade-offs

- [Context-menu action may be less discoverable] -> Keep it scoped for v1 because deletion is destructive and low-frequency; a future management surface can be added if users need bulk management.
- [Name-based assignments can collide with future rename behavior] -> Keep rename out of scope and preserve the current exact-name matching model.
- [Affected count can change before confirmation] -> Compute the count from current store state when opening the confirmation; deletion still clears all matching current assignments when confirmed.
- [Deleting an empty pinboard still asks for confirmation] -> Keep one consistent destructive flow for all pinboards, with a zero-count message for empty pinboards.

## Migration Plan

No stored data migration is required. Existing custom pinboards remain valid until a user deletes one, and existing clipboard items keep their current `pinboardName` values unless they match the deleted pinboard.

Rollback is straightforward: removing the UI action prevents new deletions. Pinboards already deleted by users are not automatically restored.

## Open Questions

None.
