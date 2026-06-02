# Copythat

Native macOS clipboard history prototype with a menu bar app, global shortcut, bottom floating panel, search, pinned items, custom pinboards, and text, URL, image, and file capture.

## Run

Use the Codex Run action, or run:

```sh
./script/build_and_run.sh
```

The script builds the SwiftPM app, stages `dist/Copythat.app`, and opens it as a menu bar resident app.

## Development Guidelines

- Keep UI native to macOS: prefer system materials, semantic colors, system accent color, and compact controls over fixed custom palettes.
- Keep SwiftUI views focused on presentation and user actions. Put pasteboard parsing, source attribution, paste execution, window control, and other AppKit/CoreGraphics boundaries in `Services` or `Support`.
- Keep copy source tracking non-persistent. New items should continue to use `ClipboardItem.sourceApp` and `sourceAppIconData`; source resolution belongs in `CopySourceTracker` and `CopySourceResolution`.
- Preserve real domain terms such as paste, pasteboard, copy, cut, and source. Do not mechanically rename them away.
- Verify changes with `swift build`, `./script/verify_all.sh`, and targeted manual checks for panel UI, search, pinboards, horizontal scrolling, and paste flow.

## Verify

Run the full local check:

```sh
./script/verify_all.sh
```

This verifies:

- Swift build
- bottom panel frame calculation for compact, desktop, wide, and simulated multi-display visible areas
- bottom panel window creation in the staged menu bar app
- stable content keys for image history de-duplication
- pasteboard writes preserve existing contents when an item cannot be restored, including missing file items
- paste target filtering so Copythat and SystemUIServer are not selected as paste destinations
- paste decisions do not send Cmd+V without a valid target app
- 5,000 item history filtering performance
- generated app icon sizes
- staged menu bar app launch and bundle metadata

Manual checks still needed on a real Mac session:

- Grant Accessibility access to `dist/Copythat.app` from Copythat Settings > Permissions or System Settings to allow automatic paste after selecting an item. Without that permission, the app still copies the selected item and shows a permission message.
- Check the selected global shortcut on the target Mac. If macOS rejects the shortcut, Copythat Settings shows an inline warning and the menu bar icon remains available.
- Toggle Launch at login from Copythat Settings on the target Mac. If macOS rejects the change, the app restores the previous value and shows an inline warning.
- Check the panel on a physical multi-display setup. The frame calculator is covered with simulated left and right display bounds, but this machine only has one display attached.
