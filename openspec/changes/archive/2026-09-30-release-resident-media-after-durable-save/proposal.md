## Why

Newly captured images and link-preview images remain resident in history and filtered history after they have been saved, and the save coordinator retains its successful retry snapshot. Extending the existing reference-only media model to the current session reduces long-lived media ownership while preserving safe saves, responsive previews, and image paste/drag.

## What Changes

- Report resident heavy-media identities and bytes only after their snapshot successfully completes the existing blob-first, atomic-manifest save transaction.
- Seed committed bytes into the existing bounded media loader before releasing matching resident bytes from both history arrays; defer visible-panel ownership transitions until panel close.
- Release the coordinator's retry snapshot only when the successfully committed generation is still the latest requested generation; retain retry state after failure.
- Preserve stable media identities, item metadata, search, selection, payload presence, and existing reference-only display/paste/drag behavior without additional save requests or media hashing.
- Add deterministic coverage for failure, retry, coalescing, asynchronous lifecycle races, cache limits, and all three history snapshot owners.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `clipboard-history`: Require eventual release of durably committed resident heavy media without releasing uncommitted identities or regressing visible previews; allow trusted committed bytes to populate the existing bounded media cache.

## Non-goals

- No source-icon release or preparation cache, browser snapshot cache changes, or link-preview scheduler redesign.
- No disk schema/version changes, database, new cache, cache budget increase, permanent pinning, or new dependency.
- No redesign of persistence transactions, GC, latest-wins scheduling, Quit decisions, or read-time integrity verification.
- No save-time rehashing, disk warm-up reads, re-encoding, or stronger crash/disk-corruption guarantees than the existing persistence contract.
- No RSS reduction threshold as a correctness gate.

## Impact

Production changes are expected in `Sources/Copythat/Support/ClipboardHistorySaveCoordinator.swift`, `Sources/Copythat/Support/ClipboardHistoryMediaLoader.swift`, `Sources/Copythat/Models/ClipboardItem.swift`, `Sources/Copythat/Stores/ClipboardStore.swift`, and `Sources/Copythat/Stores/AppModel.swift`. The internal receipt can live alongside the coordinator. Focused tests extend coordinator, loader, model, Store, and existing lazy media coverage. Worker, persistence, Views, panel controller, and paste performer retain their existing responsibilities. No public API or storage migration is required.
