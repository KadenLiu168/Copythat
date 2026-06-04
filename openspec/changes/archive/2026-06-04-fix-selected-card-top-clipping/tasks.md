## 1. Timeline Layout

- [x] 1.1 Update the bottom-panel card timeline to provide enough top safe space for selected card scale, upward offset, stroke, and rounded-corner rendering; verify the selected-card scale and offset values remain unchanged.
- [x] 1.2 Disable horizontal card timeline scroll clipping if needed so selected-card stroke and shadow are not cut by the scroll view; verify the panel's rounded container still clips the overall panel cleanly.
- [x] 1.3 Keep the change local to `BottomPanelView` unless implementation proves another view owns the clipping boundary; verify `ClipboardCardView` header layout and card dimensions are unchanged.

## 2. Verification

- [x] 2.1 Run `swift build`; verify the app builds successfully.
- [x] 2.2 Run `swift test`; verify existing unit tests pass.
- [x] 2.3 Run `./script/verify_all.sh`; verify the project's scripted checks pass.
- [x] 2.4 Manually open the bottom panel and move selection across text, image, URL, and file cards; verify selected card top edges, headers, source icons, selected borders, and rounded corners remain fully visible during selection changes and horizontal scrolling.
