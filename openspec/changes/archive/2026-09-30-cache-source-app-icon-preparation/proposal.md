## Why

Repeated observations of the same foreground application currently retrieve and render its source icon, encode a 160px PNG, and compute its media identity again. Reusing prepared icons reduces repeated work around clipboard capture while preserving the source name and icon captured for each history card.

## What Changes

- Add a CopySourceTracker-owned, session-only cache of successful PreparedMedia source icons, bounded to 32 entries with least-recently-used eviction.
- Identify entries by running application process generation and bundle location, never display name. Bypass caching when a reliable process generation cannot be established.
- Reuse both icon bytes and their established SHA256 identity while an entry remains retained; cache hits perform no icon retrieval, rendering, PNG encoding, or identity hashing.
- Construct a fresh ClipboardSource for every observation using its supplied timestamp and pasteboard change-count context; preserve existing activation/start preparation as natural warming.
- Retry unsuccessful preparation on later observations, and permit preparation again after eviction or application restart.
- Add deterministic cache and production-path regressions for operation counts, process isolation, observation context, failures, and eviction.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `clipboard-history`: Require bounded reuse of prepared source icons across observations of a running application without changing attribution precedence, observation context, or per-item icon correctness.

## Non-goals

- No source-attribution precedence, CopySourceResolution, polling, copy/cut timing, ignored-source behavior, or screenshot attribution changes.
- No ClipboardItem schema, V2 persistence format, media finalization model, read-time integrity checks, or source-icon residency changes.
- No UI changes, View-owned or global singleton caches, disk cache, app-name identity, or caching of entire ClipboardSource observations.
- No changes to the 160px icon specification, NSImage.appIconPNGData(maxPixel:) algorithm, SourceThemeColor, or ClipboardSource.system() preparation.
- No generic cache framework, new dependency, actor, detached task, background-thread redesign, termination observer, or adjacent tracker refactor.

## Impact

Production changes are confined to `Sources/Copythat/Services/CopySourceTracker.swift`, including small internal source-specific cache types and a narrow deterministic test seam where necessary. Tests extend `Tests/CopythatTests/CopySourceTrackerTests.swift` and `Tests/CopythatTests/ClipboardSourceIconIdentityTests.swift`; cache mechanics may live in `Tests/CopythatTests/SourceAppIconCacheTests.swift`. Existing Store attribution tests and source-attribution timing verification remain required. ClipboardItem, PreparedMedia, icon encoding, persistence, and Views already support the necessary identity forwarding and require no changes.
