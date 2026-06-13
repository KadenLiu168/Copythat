## 1. Empty State Presentation

- [x] 1.1 Update `EmptyTimelineView` so the prominent app logo is removed or replaced with a small low-contrast contextual symbol; verify the view no longer makes the logo the visual focus.
- [x] 1.2 Add concise empty-state title and description inputs to `EmptyTimelineView`; verify the view can render clipboard-empty, pinboard-empty, and search-empty messages without new model state.

## 2. Timeline Layout

- [x] 2.1 Update `BottomPanelView` so empty timeline content is centered in the available timeline area instead of inserted as the first item in the horizontal card stack; verify visible-item rendering still uses the existing horizontal card list.
- [x] 2.2 Derive empty-state copy from the current search text and selected pinboard context; verify selected custom pinboards and search-no-match states show distinct copy.

## 3. Verification

- [x] 3.1 Run `swift build`; verify the project builds successfully.
- [x] 3.2 Run `./script/verify_all.sh`; verify existing behavior remains covered.
- [x] 3.3 Manually inspect the panel with an empty clipboard, an empty custom pinboard, and a no-match search; verify the empty state is centered, visually quiet, and the footer item count remains readable.
