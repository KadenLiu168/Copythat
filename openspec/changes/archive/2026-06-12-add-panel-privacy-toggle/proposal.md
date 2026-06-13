## Why

Copythat's bottom panel can expose clipboard history previews immediately when opened, which is risky during screen sharing, recording, remote support, or working near other people. A global privacy toggle gives users a quick way to browse and act on history without showing every card's content at once.

## What Changes

- Add a global privacy visibility control to the bottom panel command bar using an eye icon.
- Place the control after the pinboard filters and before the new-pinboard `+` control:
  `[Search] [Clipboard] [Pinned] [Custom...] [Privacy Toggle] [+]`.
- When privacy mode is enabled, hide card preview content across all visible history cards while preserving card structure, item kind, timestamp, source context, selection, pinboard actions, delete, paste, drag, search, and filtering behavior.
- When privacy mode is disabled, show card previews normally.
- Keep the toggle as a panel display state; it does not change captured history, persistence, sensitive-content recording, or pasteboard restoration.

## Non-goals

- Do not add per-card visibility toggles.
- Do not add automatic sensitive-content detection beyond the existing capture policy.
- Do not change whether sensitive clipboard contents are recorded.
- Do not introduce private pinboards or per-pinboard privacy rules.
- Do not alter paste, search, pinboard assignment, deletion, or history persistence semantics.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `panel-and-search`: Add a panel-level privacy toggle that hides and restores visible card previews from the bottom panel command bar.

## Impact

- Affects the bottom panel command bar layout in `BottomPanelView`.
- Affects card preview rendering in `ClipboardCardView`.
- May require focused view tests or rendering tests for privacy-on versus privacy-off card states.
- No new runtime dependencies, storage migrations, pasteboard APIs, or app permissions are expected.
