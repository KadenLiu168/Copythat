## Context

`ClipboardStore` owns history mutation, pasteboard polling, manual clearing, and asynchronous image capture. The current image path reads an `NSImage` from `NSPasteboard.general`, starts background PNG encoding, returns no immediate item, and later inserts the encoded image on the main actor. Deleting a card only mutates stored history, so a pending image encode or matching current pasteboard content can reintroduce the deleted card.

This change affects pasteboard behavior and asynchronous capture, so the fix should stay inside `ClipboardStore` where the relevant state already lives.

## Goals / Non-Goals

**Goals:**

- Make deleting an image card final for any pending capture of that same image.
- Clear the system pasteboard only when a removed card matches the current pasteboard content.
- Apply the same deletion protection to manually cleared history items.
- Preserve intentional future copies of the same content.

**Non-Goals:**

- Add undo, trash, or card recovery.
- Redesign UI or change user-facing controls.
- Change persistence schema, history deduplication policy, pinning, pinboards, or paste execution.

## Decisions

1. Keep the fix local to `ClipboardStore`.

   Rationale: the store already owns `items`, selection refresh, persistence, pasteboard reads/writes, and image encoding tasks. Moving this into views or `ClipboardHistoryPolicy` would mix UI actions or generic deduplication with pasteboard side effects.

   Alternative considered: update `ClipboardHistoryPolicy` to reject deleted keys. That would risk blocking intentional re-copy because the policy does not know whether a content key came from a stale async task or a new pasteboard action.

2. Clear `NSPasteboard.general` only for matching removed items.

   Rationale: deleting the current clipboard card should remove the current clipboard value, but deleting older history should not disturb what the user can paste in other apps.

   Alternative considered: always clear the pasteboard on delete. That is simpler but creates avoidable side effects when deleting old history.

3. Add a bounded tombstone list for deleted content keys.

   Rationale: a pending image encoding task may complete after the card was deleted. A short-lived in-memory record lets the completion path reject that item without changing persistence or normal duplicate handling.

   Alternative considered: rely only on task cancellation. Cancellation is useful, but the detached PNG work can finish near the cancellation boundary; the completion guard is the final authority.

4. Cancel pending image encoding when cards are removed.

   Rationale: cancellation reduces wasted work and prevents most stale completions before the tombstone guard is needed.

   Alternative considered: only check tombstones after encoding. That is correct but spends CPU on work known to be obsolete.

## Risks / Trade-offs

- [Clearing pasteboard affects Cmd+V in other apps] -> Only clear when the current pasteboard content matches an item the user just removed.
- [Image matching can diverge if normalization differs] -> Reuse the same PNG normalization path used by captured image cards for pasteboard image comparisons.
- [Private deletion state needs tests] -> Expose narrow internal test hooks rather than making the tombstone list part of app behavior.
- [Tombstones could grow forever] -> Bound the list and evict oldest keys.

## Migration Plan

No data migration is required. The new deletion memory is in-memory only and resets on app restart. Rollback is limited to removing the store changes and the associated tests.

## Open Questions

None.
