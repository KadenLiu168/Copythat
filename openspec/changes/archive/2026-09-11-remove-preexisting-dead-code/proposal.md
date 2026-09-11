## Why

Copythat retains several image-processing utilities, sample-model data, and icon-generation wrappers that are no longer used by the shipped application. Removing this code reduces maintenance and regression surface while preserving clipboard capture, source-icon display, card theming, and all other user-visible behavior.

## What Changes

- Remove the unused `foregroundLogoCutout` image-processing chain, including its private transparent-edge trimming, edge-background removal, color-distance, background-classification, and averaging helpers.
- Remove the unused `warmThemeColor` extractor and its private accent-normalization helper; keep `SourceThemeColor` as the sole production source-icon theme-color path.
- Remove the unused `ClipboardItem.sample` fixture.
- Remove the test-only production `representativeColor` helper while preserving the existing regression test's ability to verify that different cards display their own captured source icons.
- Remove the unused `CopythatIcon.transparentMark()` accessor.
- Inline the no-op `make_transparent_icon` alias in `script/generate_icons.py` without changing generated icon output.
- Add no dependencies and make no persisted-data or clipboard-behavior changes.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This cleanup does not change user-observable requirements.

## Impact

- **Code:** `Sources/Copythat/Support/NSImage+PasteData.swift`, `Sources/Copythat/Models/ClipboardItem.swift`, and `Sources/Copythat/Support/CopythatIcon.swift` lose unused implementation.
- **Tests:** `Tests/CopythatTests/ClipboardCardViewTests.swift` retains equivalent per-card source-icon assertions without relying on a production-only test helper.
- **Tooling:** `script/generate_icons.py` generates the same `AppIcon-transparent.png` output through `make_app_icon` directly.
- **Behavior and data:** no changes to pasteboard capture, source attribution, image storage, card theme-color extraction, settings, persistence formats, or generated assets.
- **Verification:** implementation must pass `swift build` and `./script/verify_all.sh`; generated icon output should also be confirmed unchanged.

## Design

No `design.md`, deliberately. The design artifact is conditional: it is written
only for a cross-cutting change, a new architectural pattern or dependency,
significant data-model change, or security, performance, or migration
complexity. This change is none of those. It does not cross Swift modules, adds
no dependency, and leaves permissions, persistence, pasteboard behavior, source
attribution, window management, and global shortcuts untouched; it only deletes
declarations that nothing references. The project design rule in
`openspec/config.yaml` and the schema's conditional design gate therefore both
resolve to "omit". The decisions worth recording already live in **What
Changes** and **Non-goals**.

## Non-goals

- Consolidating the semantically distinct generic-image, source-app-icon, and detached `CGImage` PNG encoding paths.
- Introducing a `ClipboardItem` capture factory or otherwise restructuring pasteboard parsing.
- Refactoring the new/edit pinboard popovers.
- Removing the SwiftUI Settings scene, the WebKit link-preview fallback, `RelativeTime`, or `CopythatPanel.keyDown(with:)`.
- Removing or changing packaged icon assets.
- Changing any user-visible clipboard, panel, settings, link-preview, relative-time, or icon-rendering behavior.
