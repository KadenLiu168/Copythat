## Context

The current user history is 156 MB across 280 items, including 69 images. An 8-second launch sample showed 1,274 of 1,345 `AppDelegate` initialization samples inside `ClipboardItem.storageOptimized`; only 70 samples were spent decoding persisted JSON. The persisted items were already optimized when captured, so launch repeats expensive image decode, resize, and PNG encoding work without changing the required data.

A separate 5-second sample while sending 120 alternating arrow-key events showed 202 `ClipboardCardView.body` evaluations. Those evaluations repeatedly derived the same source accent by decoding source icon data, creating bitmap representations, and scanning pixels. The existing 180 ms selected-card and scroll animations also overlap during repeated movement.

## Goals / Non-Goals

**Goals:**

- Remove unnecessary main-thread image processing from application launch.
- Reuse source accent derivation across repeated card renders.
- Keep repeated keyboard and mouse selection visually responsive without changing the selected-card treatment or center-scrolling behavior.
- Preserve the existing persistence format and item content.

**Non-Goals:**

- No asynchronous history-loading state machine or history merge behavior.
- No persistence schema change, stored-image resize policy change, or asynchronous save pipeline.
- No card redesign, selection-style removal, gesture semantic change, or broad view decomposition.

## Decisions

- Load persisted items directly instead of mapping them through `storageOptimized`.
  - Persisted items already pass through storage optimization at capture and link-preview update boundaries. Repeating it on every launch is redundant.
  - An asynchronous load was considered, but profiling shows JSON decode is a small fraction of launch cost. It would add empty-loading UI and merge races without addressing the measured bottleneck.
- Add a bounded in-memory source-accent cache keyed by persisted icon bytes and have cards request accents from icon data.
  - The accent is deterministic for the icon bytes, and unchanged cards repeatedly request the same value.
  - Persisting accent values was rejected because it would change the storage schema for a derived presentation value.
- Keep selected-card styling animated with a shorter transition, but make scroll-to-selection immediate.
  - Immediate scrolling prevents animation work from accumulating during key repeat while preserving selected-card centering.
  - Removing all selected-card animation was rejected because it would unnecessarily change the established interaction design.
- Keep existing single-click and double-click handlers unchanged.
  - Both mouse and keyboard selection share the measured rendering and animation costs. There is not enough evidence that gesture arbitration is the common bottleneck.

## Risks / Trade-offs

- [The accent cache retains derived colors] → Bound it by entry count; values are small and can be recomputed after eviction.
- [Direct loading preserves older unoptimized persisted entries] → Existing migration and capture paths already optimize persisted data; changing old data during every launch is not required for correctness.
- [Immediate center scrolling is less animated] → Preserve the card selection transition so selection feedback remains visible while rapid navigation no longer queues scroll animations.
- [Performance remains dependent on very large JSON decode time] → Re-profile after removing repeated image encoding; only introduce asynchronous loading if decode remains a measured user-visible bottleneck.

