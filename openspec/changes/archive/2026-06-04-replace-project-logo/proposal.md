## Why

The project now has a newer Copythat logo, and the app should present that identity consistently wherever it uses the bundled application mark. Replacing the old logo keeps the app icon, transparent in-app logo asset, and packaged icon resource aligned with the latest design.

## What Changes

- Use `/Users/kaden/Copythat/script/assets/Copythat.png` as the source artwork for the Copythat application logo.
- Regenerate the bundled app icon PNG sizes, `.icns`, and transparent logo resource from the new artwork.
- Keep the existing menu bar template icon behavior unless it is directly generated from the old logo and must be refreshed to avoid stale branding.
- Verify generated icon assets meet the project icon size and transparency checks.

## Non-goals

- Do not redesign panel cards, empty states, settings screens, or clipboard history UI.
- Do not change pasteboard behavior, source app icon handling, shortcuts, launch-at-login behavior, or signing configuration.
- Do not introduce a user setting or alternate theme for the logo.

## Capabilities

### New Capabilities

- `app-branding`: Defines how Copythat presents its bundled application logo and icon resources.

### Modified Capabilities

None.

## Impact

- Affected resources are expected under `Sources/Copythat/Resources/`, including app icon image sets, the packaged `.icns`, and transparent logo assets.
- The icon generation script may need a narrow update so future regeneration uses the new source artwork instead of drawing the old mark.
- Verification should include the existing icon asset checks plus a Swift build after resources are updated.
