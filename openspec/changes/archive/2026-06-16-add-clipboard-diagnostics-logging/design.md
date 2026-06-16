## Context

Copythat already records per-item `sourceApp`, `sourceAppIconData`, and a `contentKey` used for duplicate-content handling. When a user sees a source appear to change after copying from another app, the current runtime offers no narrow trace that shows whether the app inserted a new duplicate replacement, resolved the wrong source for a new item, or is running an older build.

## Goals / Non-Goals

**Goals:**

- Add focused diagnostics for pasteboard capture, source resolution, and history insertion.
- Keep diagnostics default-off and controlled by a hidden `UserDefaults` flag.
- Make logs useful from Console.app, `log stream`, and the existing build script log paths.
- Avoid raw clipboard payload logging.

**Non-Goals:**

- Do not change source resolution, duplicate-content handling, storage, or card rendering.
- Do not add a visible Settings control or permanent user-facing debugging feature.
- Do not introduce a new telemetry dependency or remote reporting.

## Decisions

1. Use Apple's unified logging through `OSLog.Logger`.

   Rationale: `Logger` is native, filterable by subsystem/category, and matches macOS diagnostics workflows. `print` is less useful for a menu bar app once launched outside a terminal.

   Alternative considered: write a local debug file. That adds file lifecycle, privacy, and cleanup concerns without improving this investigation.

2. Gate all clipboard diagnostics behind `UserDefaults.standard.bool(forKey: "clipboardDiagnosticsEnabled")`.

   Rationale: the logging is intentionally temporary/noisy and should be easy to enable with `defaults write local.copythat.clipboard clipboardDiagnosticsEnabled -bool true` without changing the app UI.

   Alternative considered: add a Settings toggle. That would make an internal diagnostic affordance look like a supported product feature.

3. Log bounded metadata only.

   Rationale: the needed signal is item identity and state transitions, not clipboard contents. Logs should include item ID, kind, source app, content length, a short stable digest of the content key, duplicate match counts/IDs, and before/after item counts. They should not include copied text, full URLs, file paths, or image data.

   Alternative considered: log the full `contentKey`. For text, URLs, and files, the content key can contain sensitive user payloads.

4. Keep the diagnostic implementation near `ClipboardStore`.

   Rationale: `ClipboardStore` is where pasteboard reads become `ClipboardItem` values and where deduplication policy is applied. This keeps the instrumentation close to the state transition being investigated.

   Alternative considered: instrument `CopySourceTracker` broadly. That can help source-resolution bugs, but it does not show whether the history policy replaced an existing card.

## Risks / Trade-offs

- [Diagnostics are off unless explicitly enabled] -> Document the `defaults` commands and `log stream` predicate in the implementation notes and final verification.
- [Unified logging can still retain metadata] -> Keep all payload-derived data hashed/truncated and avoid raw clipboard values.
- [Hash collisions are theoretically possible] -> Use the hash only as a diagnostic correlation hint, not as product logic.
- [Logging could become stale after the investigation] -> Keep the instrumentation small and default-off so it can be removed or retained without changing user behavior.
