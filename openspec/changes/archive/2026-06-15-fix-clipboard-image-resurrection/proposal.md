## Why

Deleting an image card can be undone by Copythat's own clipboard monitoring when the same image is still present in the general pasteboard or when image encoding finishes after the delete. This makes a destructive panel action feel unreliable: a user removes a card, then sees it return during later clipboard activity.

## What Changes

- Prevent a deleted image card from being reinserted by a pending asynchronous image encoding result.
- Clear the system pasteboard when the deleted card matches the current pasteboard content, so later polling does not recapture the same deleted content.
- Apply the same protection to manual history clearing for the items that are actually removed.
- Preserve intentional re-copy behavior: if the user copies the same image again after deletion, Copythat can record it as a new clipboard action.

## Non-goals

- Do not add undo, trash, or recovery for deleted cards.
- Do not change panel UI, search, pinning, custom pinboards, persistence format, or paste behavior.
- Do not block normal duplicate handling or intentional future copies of the same content.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `clipboard-history`: Deleting or manually clearing cards must prevent removed current pasteboard content, especially images, from being recaptured by stale pasteboard state or delayed image encoding.

## Impact

- Affects `ClipboardStore` pasteboard deletion, manual history clearing, and asynchronous image capture behavior.
- Adds focused store tests for deletion, tombstone checks, pasteboard clearing, and re-copy behavior.
- No public API, dependency, storage schema, or UI changes are expected.
