# Proposal: fix-source-attribution-timing

## Why

Copythat attributes clipboard items captured without a keyboard copy shortcut (context-menu Copy, web-page copy buttons, programmatic pasteboard writes) to whichever app is frontmost at capture time — which happens 0.45–0.9s after the copy, after the double-tick stability gate. When the user switches apps within that window, the new card is misattributed to the *next* app (e.g. content copied via a Chrome page button shows as `Code` after a quick switch to VSCode). This was reproduced and confirmed against real app data (history JSON shows `sourceApp=Code` for content written while Chrome was verified frontmost).

## What Changes

- Snapshot the frontmost app **when the change count that ultimately stabilizes is first observed** (inside the stability gate's first tick), instead of resolving the source only at capture confirmation.
- Pass that first-observed snapshot into source resolution with priority between the keyboard-shortcut evidence and the capture-time frontmost app.
- Keyboard-shortcut attribution (Cmd+C/Cmd+X via the event tap) keeps its existing, higher priority — that path is verified correct and stays untouched.
- Existing fallback behavior (recent foreground, system, unknown) remains for cases where no first-observed snapshot exists (e.g. the frontmost app at first observation is Copythat itself or otherwise not a source candidate).
- When the existing default-off clipboard diagnostics mode is enabled, emit payload-free timing events for first observation, application activation, copy-shortcut observation, and source resolution so the real ordering and selected resolution slot can be audited.
- Provide a focused verification script and preserve sanitized evidence tied to the final relevant file identities.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `clipboard-history`: the "Track source context" requirement gains a scenario pinning source attribution for non-keyboard copies to the app that was frontmost when the pasteboard change was first observed, rather than at capture confirmation; the existing diagnostics requirement gains payload-free source-timing evidence.

## Impact

- `Sources/Copythat/Stores/ClipboardStore.swift` — `pollPasteboard()` stability gate: pair each pending change count with the source snapshot from its first observation, replacing both together if a newer count arrives; pass the stable pair through `readCurrentPasteboard`.
- `Sources/Copythat/Services/CopySourceTracker.swift` — expose a frontmost-app snapshot method for the store to call at first observation.
- `Sources/Copythat/Support/CopySourceResolution.swift` — resolution slot priority: shortcut > first-observed foreground > capture-time foreground > recent foreground > system > unknown.
- `Sources/Copythat/Support/ClipboardDiagnostics.swift` — default-off structured metadata events for source timing and resolution decisions.
- `Tests/CopythatTests/` — regression tests for the resolution ordering and the stability-gate snapshot hand-off.
- `script/verify/source_attribution_timing.sh` and this Change's `evidence/` directory — deterministic live acceptance and sanitized evidence capture.
- No persistence format change; no UI change; no new permissions.

## Non-goals

- **Pinned duplicate handling** — earlier analysis flagged `ClipboardHistoryPolicy.adding` replacing pinned duplicates as a spec violation; re-reading the spec shows current behavior (keep the pinned entry, optionally record the new copy as an ordinary item) is explicitly allowed ("Existing pinned content is copied again" scenario). No change.
- **Surfacing event-tap creation failure** (`CGEvent.tapCreate` returning nil is silently ignored) — a real observability gap, but independent of attribution timing; separate change if wanted.
- **Shortening the poll interval / stability gate** — the gate dropping intermediate rapid copies (<0.9s apart) is a separate behavior with its own trade-offs (the gate exists to skip transient multi-step writes).
- **History persistence size** (44.8MB full-rewrite JSON) — unrelated performance concern.
