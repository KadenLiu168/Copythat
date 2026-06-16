## Why

Source app icons are captured at 160px, but `ClipboardItem.storageOptimized` currently decodes them, downsamples them to 64px, and re-encodes them whenever an item is optimized. This can make source icons softer than necessary in the card header and causes unrelated link preview updates to rewrite source icon bytes.

## What Changes

- Preserve captured `sourceAppIconData` exactly when creating a storage-optimized clipboard item.
- Continue capturing source app icons at the existing 160px size.
- Keep existing storage optimization for clipboard image data and link preview image data.
- Avoid UI changes; cards continue to display source icons in the existing fixed header area with proportional scaling.

## Non-goals

- Do not increase source app icon capture above 160px.
- Do not change clipboard image or link preview image size limits.
- Do not migrate older persisted 64px source icons.
- Do not redesign card headers or source icon presentation.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `clipboard-history`: Persisted clipboard items preserve captured source app icon data instead of downsampling it during storage optimization.

## Impact

- Affects `ClipboardItem.storageOptimized` and focused model tests.
- No persistence schema change.
- No new dependencies or public API changes.
