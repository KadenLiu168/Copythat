## Context

Copythat is an LSUIElement menu bar app with a SwiftUI `Settings` scene. The right-click status menu already includes `Settings...`, and `SettingsView` already contains the settings controls. The failing behavior is the AppKit action path from the status menu to the SwiftUI settings scene.

## Goals / Non-Goals

**Goals:**

- Provide one reliable menu action path for opening the native settings window.
- Keep the existing `SettingsView` and stored setting semantics intact.
- Make the action path small enough to verify without broad UI rewrites.

**Non-Goals:**

- Redesign the settings view.
- Add a separate custom settings window.
- Change launch-at-login, shortcut, history, pinboard, permission, or appearance behavior.

## Decisions

- Use the existing SwiftUI `Settings` scene as the settings surface.
  - Rationale: the app already owns a native settings scene and view; duplicating it in a custom window would create two window ownership paths.
  - Alternative considered: create an `NSWindowController` for `SettingsView`. This is unnecessary unless the SwiftUI settings command cannot be made reliable.
- Isolate the settings-open action behind a tiny AppKit-facing helper.
  - Rationale: menu item behavior can be unit-tested by injecting the action, while the helper keeps the platform selector and activation behavior in one place.
  - Alternative considered: keep calling `NSApp.sendAction` inline from each view/menu. That makes the behavior harder to verify and easier to drift.
- Foreground Copythat when opening settings.
  - Rationale: as an LSUIElement app, a settings window can be created without an obvious foreground transition. Activating the app after dispatching the settings command makes the result visible.

## Risks / Trade-offs

- SwiftUI's private settings selector could remain platform-sensitive -> Keep the call centralized so a future replacement can be made in one location.
- Full visual verification of a menu bar click is environment-dependent -> Add focused automated verification for the action path and run the app-level build/launch checks.
