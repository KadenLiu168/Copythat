## Why

Copythat currently restores persisted history synchronously inside its MainActor-owned Store initializer, delaying clipboard monitoring and menu-bar availability while reading the manifest, decoding metadata, verifying source icons, and constructing searchable items. Moving this work off MainActor must preserve startup copies and previously saved history rather than exchange launch latency for lost updates or partial-manifest writes.

## What Changes

- Restore persisted history through a narrow background actor while constructing an empty in-memory Store immediately and starting monitoring on the existing application-launch schedule.
- Buffer complete startup captures in Store arrival order, install the persisted baseline, and replay captures through the existing `ClipboardHistoryPolicy` insertion path on MainActor.
- Block all history saves until baseline installation and replay finish. Clean restoration requests no save; capture, trim, or another legitimate bootstrap save request produces at most one final bootstrap save request.
- Preserve V2 persistence, eager deduplicated source-icon verification, lazy heavy media, runtime search-corpus construction, duplicate/pin/pinboard semantics, and the bounded image pipeline.
- Show a minimal loading-history state and prohibit history-destructive operations, including pinboard rename/delete transactions, until restoration finishes.
- Extend normal Quit to pause new admission without invalidating accepted images, await restore and the existing image pipeline's accepted work, then use the existing save flush and Retry / Quit Anyway / Cancel Quit flow. Cancel Quit resumes monitoring.
- Preserve synchronous explicitly injected `initialItems` and isolated verification startup; add deterministic gated restore, capture, persistence, lifecycle, and production-worker tests.

## Capabilities

### New Capabilities

None; this extends existing clipboard, panel, settings, and launch contracts.

### Modified Capabilities

- `clipboard-history`: Safe asynchronous bootstrap, policy replay, persistence barrier, restore failure handling, and Quit protection for restore and admitted image captures.
- `panel-and-search`: Distinguish loading from empty results, preserve current search/filter after restore, and gate history/pinboard mutations while loading.
- `settings-and-launch`: Restore file/decode/icon integrity/model construction outside MainActor, begin monitoring without awaiting restoration, and protect Settings clear actions during loading.

## Impact

- Production wiring: `Sources/Copythat/Stores/AppModel.swift` and `Sources/Copythat/App/AppDelegate.swift`.
- State and capture ownership: `Sources/Copythat/Stores/ClipboardStore.swift`, `ClipboardStore+ImageCapture.swift`, and focused link-preview mutation/reconcile integration where necessary.
- New support boundary: `Sources/Copythat/Support/ClipboardHistoryRestoreWorker.swift`; structural Sendable conformances in `Sources/Copythat/Models/ClipboardItem.swift`.
- Presentation/actions: `Sources/Copythat/Views/BottomPanelView.swift` and `Sources/Copythat/Views/SettingsView.swift`. Pinboard rename/delete currently update AppSettings before Store assignments, so gating must protect the entire action.
- Tests: focused restore tests, existing image-capture and termination suites, and production-worker/performance integration. No new package dependency, permission, persistent schema, or settings migration.

## Non-goals

- No background ObservableObject mutation, background search/filtering, cross-kind capture ordering scheduler, duplicate-policy rewrite, or generic persistence/bootstrap manager.
- No heavy-media eager reload, image re-encoding during replay, new image queue, changed four-capture capacity, or forced cancellation of physical encoding.
- No general startup mutation journal or arbitrary startup-buffer eviction rule. Slow restore can retain accumulated finalized captures; this resource risk is explicit and does not authorize weakening capture guarantees.
- No guarantee for pasteboard values overwritten before stable observation, captures excluded by existing overflow/retention/invalidation rules, forced process termination, or waiting for all optional network enrichment before Quit.
