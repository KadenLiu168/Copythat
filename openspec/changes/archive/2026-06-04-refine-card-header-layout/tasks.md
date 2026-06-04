## 1. Header Layout

- [x] 1.1 Update `ClipboardCardView` header metrics so the left text stack has modest top and leading inset, remains two lines tall, and reserves only enough trailing space for the right-side source icon; verify by inspecting the card header code and checking text does not overlap the icon.
- [x] 1.2 Remove the pinboard badge from the card header left stack while preserving pinboard assignment, filtering, and context menu actions; verify pinned and custom-pinboard items still appear in the correct panel filters.
- [x] 1.3 Align the source app icon to the right header edge and size it relative to the header height so captured app icons visually fill the header area without a visible right gutter; verify text, URL, image, and file cards with source icons render consistently.

## 2. Verification

- [x] 2.1 Run `swift build`; verify the app target builds successfully.
- [x] 2.2 Run `./script/verify_all.sh`; verify existing behavior checks still pass.
- [x] 2.3 Manually open the bottom panel and inspect several card kinds, selected/unselected states, pinned items, and custom-pinboard items; verify each header shows only item kind and relative timestamp on the left, with source icon treatment matching the requested layout.
