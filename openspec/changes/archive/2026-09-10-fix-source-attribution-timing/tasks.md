# Tasks: fix-source-attribution-timing

## 1. Guard tests for current resolution behavior (green before any change)

- [x] 1.1 Create `Tests/CopythatTests/CopySourceResolutionTests.swift` covering the CURRENT ordering: keyboard shortcut wins over all candidates; without shortcut, capture-time frontmost wins; without both, recent foreground (within 8s) wins; stale recent foreground (>8s) falls to system/unknown. Verify with `swift build && swift test --filter CopySourceResolutionTests` — all pass (baseline green).

## 2. Red tests for the new behavior

- [x] 2.1 Add red tests: `resolveSlot` with a `firstObservedForeground` candidate — ranked after shortcut but before capture-time frontmost; nil `firstObservedForeground` preserves today's ordering exactly (ties to 1.1 baseline). Verify with `swift test --filter CopySourceResolutionTests` — record the expected compile or assertion failure for the new behavior while retaining the separate green baseline evidence from 1.1.
- [x] 2.2 Add deterministic red store tests using ordered frontmost-source values: source A sampled on first observation beats source B at confirmation; nil first-observed source falls back to B; a newer change count replaces both the pending count and source; and `markPasteboardProcessed`/gate reset prevents a stale pending source from reaching a later capture. Verify with the focused store test filter — each new behavioral assertion fails for the expected missing behavior before implementation.

## 3. Implementation

- [x] 3.1 Extend `CopySourceResolution.resolveSlot` with the `firstObservedForeground` parameter and insert it between shortcut and capture-time foreground in the priority chain (design D2). Verify with `swift build && swift test --filter CopySourceResolutionTests` — all tests green.
- [x] 3.2 Add `CopySourceTracker.frontmostSourceSnapshot() -> ClipboardSource?` reusing the existing `currentFrontmostSource`/`source(for:)` path without touching `recentExternalSource`; add the narrow internal frontmost-source provider from design D5 so tests can supply deterministic sources while production still uses `NSWorkspace`. Verify with `swift build && swift test --filter CopySourceTracker`.
- [x] 3.3 Wire the store: whenever `ClipboardStore.pollPasteboard()` sees a change count different from the pending count, replace the pending count and `sourceTracker.frontmostSourceSnapshot()` together; on the confirming poll pass the paired snapshot through `readCurrentPasteboard` → `sourceMetadata` → `resolveSource` as the first-observed candidate; clear both pending values together in `markPasteboardProcessed`, the gate reset, and capture paths (design D1/D3). Verify with `swift build` and the focused resolution/store tests from 1.1, 2.1, and 2.2, then full `swift test` — all pass.

## 4. Auditable diagnostics and evidence tooling

- [x] 4.1 Add red diagnostics tests proving the four source-timing event schemas, the existing default-off gate, monotonic timestamps supplied by the caller, and absence of raw text/URL/file/marker payloads. Each test names the missing or unsafe production behavior and fails for that reason before implementation.
- [x] 4.2 Implement the default-off `pasteboard_observed`, `app_activated`, `copy_shortcut_observed`, and `source_resolved` metadata events at the owning store/tracker boundaries, including the selected `CopySourceResolutionSlot`, without changing source selection or history behavior. Verify with focused diagnostics, tracker, resolution, and store tests.
- [x] 4.3 Add `script/verify/source_attribution_timing.sh` with fixture-backed analyzer tests plus live non-keyboard and physical Cmd+C modes. The analyzer must fail wrong ordering/source/slot and must emit only sanitized evidence. Verify the analyzer against passing and deliberately invalid fixtures.

## 5. Final verification

- [x] 5.1 Run `swift build` and `./script/verify_all.sh` after the final relevant code/test/script change. Save the complete gate output and exact exit status under `openspec/changes/fix-source-attribution-timing/evidence/`, together with the command, toolchain, changed-file inventory, and SHA-256 identities of the relevant files.
- [x] 5.2 Run the live non-keyboard acceptance: Chrome remains frontmost through `pasteboard_observed`, Visual Studio Code activates before `source_resolved`, and the resolution event reports `firstObservedForeground` with `Google Chrome`. Preserve the sanitized correlated events and analyzer result; do not preserve the marker or clipboard payload.
- [x] 5.3 Run the physical Cmd+C regression: the event tap records a real Chrome copy shortcut before the app switch, and `source_resolved` reports `shortcut` with `Google Chrome`. Preserve the sanitized correlated events and analyzer result without clipboard payloads.
- [x] 5.4 Run target strict OpenSpec validation and `git diff --check`, confirm the evidence identities still match the final relevant files, and summarize exact results in `evidence/verification.md`.
