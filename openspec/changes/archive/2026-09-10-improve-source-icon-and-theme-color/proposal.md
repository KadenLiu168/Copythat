# Proposal: improve-source-icon-and-theme-color

## Why

Clipboard cards show a blurry source app icon and a header theme color that does not match the app's brand color.

Verified root causes:

1. **Icon resolution is deterministically capped at 32px.** `NSWorkspace.icon(forFile:)` returns an `NSImage` whose `size` is always 32×32 pt (representations up to 2048px exist but are ignored). `pngData(maxPixel: 160)` computes `scale = min(1, 160 / size.width) = 1`, so it never upscales and stores a 32px PNG (at best 64px on Retina via `lockFocus`). The card header slot is 52pt → 104px on Retina, so every icon is displayed at 2–3× its stored resolution. The 160px design target has never been reached.
2. **Header theme color is a single pixel pick.** `SourceThemeColor.accent` samples the stored low-res icon on a ~20×20 grid and returns the single highest-scoring pixel (`saturation × 0.52 + brightness × 0.24 + chroma × 0.24`). It is coverage-blind: for multi-color icons (Chrome, Arc, VS Code) it picks whichever single pixel scores highest — often a highlight or gradient edge — with no aggregation, no coverage weighting, and no saturation normalization. Because it reads the same degraded 32px icon data, many sampled pixels are antialiased edge blends rather than pure brand colors.

## What Changes

- Store source app icons at up to 160px by selecting the best available `NSImage` representation instead of relying on `NSImage.size`.
- Replace the single-pixel theme color pick with dominant-vivid-color extraction: filter near-white/near-black/low-alpha/gray samples, aggregate by color proximity, weight by coverage × saturation × chroma, then apply adaptive saturation normalization (mild boost for low-saturation colors, cap below neon).
- Replace `logoThemeColor` as the single extraction path. The codebase currently has three extractors — `logoThemeColor` (in use), `warmThemeColor` (dead code), `representativeColor` (test-only) — this change consolidates on one algorithm rather than adding a fourth.
- No changes to `ClipboardCardView` layout: `headerIconSize = 52` is correct; the defect is upstream data quality.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `panel-and-search`: the history card header requirement changes — the source icon SHALL be stored and rendered at a resolution sufficient for sharp Retina display, and the header theme color SHALL derive from the icon's dominant vivid brand color with bounded saturation, rather than a single best-scoring pixel.

## Impact

- **Code**: `Sources/Copythat/Support/NSImage+PasteData.swift` (representation-aware icon export), `Sources/Copythat/Services/CopySourceTracker.swift` (icon fetch path), `Sources/Copythat/Support/SourceThemeColor.swift` (new extraction algorithm replacing `logoThemeColor`), `Tests/CopythatTests/` (new/updated tests).
- **Storage**: stored icon PNG grows from ~4KB (32px) to ~15–40KB (160px) per history item. History size impact must be quantified in design; existing stored items keep their low-res icons (no retroactive migration).
- **Dependencies**: none added. AppKit-only.
- **Behavior**: purely visual quality improvement; no public API, paste flow, or permission changes.

## Non-goals

- Retroactive re-capture of icons for already-stored history items.
- Changing card layout, header size, or icon display modifiers in `ClipboardCardView`.
- Removing pre-existing dead code (`warmThemeColor`, `foregroundLogoCutout`) beyond what this change's edits orphan — noted for a separate cleanup.
- Third-party color-extraction libraries.
