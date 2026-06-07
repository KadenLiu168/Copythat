## Why

Cards do not leave the active Pinned or custom pinboard filter immediately after the user unpins them or removes their pinboard assignment. Custom pinboard assignment also currently makes a card pinned, which causes unpinned category items to show an unexpected Unpin action.

## What Changes

- Refresh the visible card list immediately after card actions that change pinned or pinboard membership.
- Make custom pinboard assignment independent from pinned state.
- Keep card context menu labels tied to the card's current pinned and pinboard state.
- Preserve existing clipboard history and existing pinned flags.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `panel-and-search`: Pin and pinboard card actions update the active filter immediately, and custom pinboard assignment no longer implies pinned state.

## Impact

- Affects clipboard item mutation and filtering behavior in the bottom panel.
- Adds focused store tests for pin, unpin, pinboard assignment, removal, and selection refresh.
- No persistence schema, dependency, pasteboard, source attribution, or UI redesign changes.

## Non-goals

- Do not migrate or rewrite existing clipboard history.
- Do not infer whether existing pinned items were pinned manually or by previous pinboard assignment behavior.
- Do not change the visual design, layout, or structure of the card context menu.
