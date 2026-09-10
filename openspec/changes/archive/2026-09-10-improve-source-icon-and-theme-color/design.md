# Design: improve-source-icon-and-theme-color

## Context

See proposal.md → Why for the verified root causes. Key facts that shape the approach:

- `NSWorkspace.icon(forFile:)` returns an `NSImage` with `size = 32×32 pt` but representations up to 2048px (verified on Safari / Calendar / Chrome). Current export path reads `NSImage.size`, so output is capped at 32px.
- Header display slot is 52pt (`headerIconSize`), i.e. 104px @2×. 160px storage cap keeps headroom without unbounded growth.
- `SourceThemeColor.accent(iconData:)` extracts the header color from the **same stored icon data**. This coupling means fixing icon resolution improves color-extraction input quality for free — icon fix MUST land first.
- Three color extractors exist today: `logoThemeColor` (in use by `SourceThemeColor`), `warmThemeColor` (dead code, includes `normalizedCardAccent` forcing saturation ≥ 0.72), `representativeColor` (referenced only by `ClipboardCardViewTests`). This change consolidates on one algorithm, replacing `logoThemeColor`.

## Goals / Non-Goals

**Goals:**

- Store source icons at 104–160px longest side, chosen representation-aware.
- One dominant-vivid-color extraction path with coverage weighting and adaptive saturation normalization.
- Deterministic, fixture-based tests with concrete numeric assertions (hue ranges, coverage winner).

**Non-Goals:**

- Retroactive re-capture of icons for existing history items (they keep 32px icons until they age out of history).
- Card layout or view modifier changes in `ClipboardCardView` (the `.saturation(1.18)` / `.contrast(1.08)` icon boost stays; header color normalization happens in the extractor, keeping view code untouched). **Partially superseded by task 3.3:** storing 160px icons exposed a pre-existing sizing defect — `NSViewRepresentable` sized the header `NSImageView` by the image's intrinsic point size, so `.frame(52)` was not honored above 52pt; `SourceLogoImageView` therefore gained a `sizeThatFits`. Layout constants, icon modifiers, and the color path are unchanged.
- Deleting pre-existing dead code unrelated to the edited call sites.

## Decisions

### D1: Representation selection — use AppKit's `bestRepresentation(for:)`, not manual iteration

For a 160×160 pt target, ask AppKit for the best representation and draw it into a 160×160 bitmap:

- `NSWorkspace` icons carry representations at 16…2048px; AppKit picks the smallest rep ≥ target pixels (256px for a 160px target) and downsamples with high interpolation.
- Alternative considered: manually iterating `NSImage.representations` and ranking by `pixelsWide`. Rejected — it reimplements `bestRepresentation(for:)` poorly (must handle `NSISIconImageRep` quirks, @2× variants, non-bitmap reps) for zero gain.
- Add a dedicated `appIconPNGData(maxPixel:)` path in `NSImage+PasteData.swift` (or a sibling) so generic pasted-image handling keeps its existing `NSImage.size`-based behavior; only the app-icon call site in `CopySourceTracker.source(for:)` switches over.

### D2: One extractor, replacing `logoThemeColor`

Implement the new algorithm inside `SourceThemeColor`'s private `NSImage` extension, replacing `logoThemeColor` body. `warmThemeColor` / `representativeColor` stay untouched (pre-existing dead/test-only code; flagged in proposal Non-goals), but no new fourth extractor is introduced.

Algorithm:

1. Rasterize icon to a bounded bitmap (≤ 160px, reuse stored PNG).
2. Sample on a grid; drop samples with alpha < 0.35, saturation < 0.20, brightness outside (0.16, 0.99).
3. Quantize surviving samples into hue buckets (e.g. 12 buckets × sat/brightness sub-buckets); accumulate per-bucket coverage and mean color.
4. Score buckets: `coverage × (0.5 + saturation) × (0.5 + chroma)`; pick the winner's mean color.
5. Adaptive saturation normalization: sat < 0.35 → boost toward ~0.5; 0.35–0.7 → boost ~10–15%; sat > 0.7 → keep; final sat clamped ≤ 0.92, brightness clamped to (0.3, 0.95).

Rationale vs alternatives:

- Median-cut / k-means: more accurate but non-deterministic (k-means) or heavier (median-cut); hue bucketing is deterministic, ~50 lines, and adequate for 52pt headers.
- Keeping single-pixel scoring with better weights: rejected — coverage-blindness is the core defect for multi-color icons; no weight scheme fixes a sample of one pixel.

### D3: Fix order — icon first, then color

Because `SourceThemeColor` reads stored icon data, color tuning against 32px inputs would be thrown off when 160px inputs land (sharper edges = more pure-color samples). Tasks sequence icon work, visual verification, then color work.

### D4: Historical items — accept degraded icons, no migration

Stored 32px icons remain until items age out. Re-fetching icons at display time by app name was rejected: it adds a runtime `NSWorkspace` dependency to the view layer, breaks for uninstalled apps, and duplicates the capture-time source-attribution contract.

## Risks / Trade-offs

- [160px PNGs grow storage ~4KB → ~15–40KB per item] → Mitigation: verify actual PNG sizes across the common apps (Safari/Chrome/Finder/VS Code) during implementation; history is already count-bounded, so worst-case growth is linear in the existing limit. If measured sizes exceed ~40KB, drop cap to 128px (still > 104px requirement).
- [Hue bucketing picks an unexpected bucket on gradient-heavy icons] → Mitigation: fixture tests for Safari, Chrome, Finder-style icons with explicit hue-range assertions; tune bucket count/weights against fixtures, not vibes.
- [Normalization curve shifts colors of icons that already looked fine] → Mitigation: keep the curve conservative (cap 0.92, boost only low/mid saturation); visual pass on 5+ common apps before closing tasks.
- [`bestRepresentation(for:)` behavior varies for apps with unusual icon assets (e.g. `app.icon` fallback path without bundleURL)] → Mitigation: same code path for both `icon(forFile:)` and `app.icon`; test the fallback branch with a fixture `NSImage` carrying multiple reps.

## Migration Plan

No data or schema migration. Rollout = normal app update; old items keep low-res icons until they expire from history. Rollback = revert; no persisted format change (PNG bytes are opaque to storage).

## Open Questions

- Does the storage layer dedupe identical `iconData` across items from the same app? If not, per-item 160px icons multiply storage by history length. Quantify during implementation; only if growth is unacceptable, consider a per-app icon cache keyed by app name (would be a follow-up design decision, not part of this change's spec).
