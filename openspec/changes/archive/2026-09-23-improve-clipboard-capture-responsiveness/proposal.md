## Why

Copythat currently discovers pasteboard activity only through a 0.45-second idle poll and confirms stability only on a second poll, so ordinary captures take about 0.45-0.9 seconds and a later copy can replace an earlier one before the earlier value is ever observed. Capture should become responsive while clipboard activity is occurring without turning the menu bar app into a permanent high-frequency poller or weakening the existing protection against transient multi-step pasteboard writes.

## What Changes

- Wake clipboard monitoring into a bounded fast-observation period when Copythat observes a supported copy, cut, or clipboard-screenshot shortcut.
- Enter or extend the same bounded fast-observation period when idle monitoring first discovers an external pasteboard change, and retain a short tail after processing activity.
- Define pasteboard stability by the elapsed monotonic quiet time for one change count rather than by seeing that count on two fixed timer ticks.
- Keep the pending change count, its first-observed source, and its first-observed uptime as one observation that is replaced or cleared together.
- Preserve the existing source-resolution priority and self-generated pasteboard-write suppression.
- Add focused regressions for stability timing, source pairing, successive shortcut-driven text copies, and monitoring lifecycle, followed by payload-safe live timing verification.

## Non-goals

- Do not guarantee capture of two writes when both occur before idle monitoring can observe either one and no supported shortcut wake signal exists.
- Do not guarantee capture of an earlier value that is replaced before it has remained stable for the minimum stability interval; that ambiguity is retained to protect against transient multi-step writes.
- Do not change clipboard-history persistence, duplicate semantics, `ClipboardHistoryPolicy`, link previews, paste delay, ignored-application UI, or permissions.
- Do not refactor the asynchronous image-encoding pipeline or claim that consecutive image captures survive its existing cancellation behavior.
- Do not change source-resolution priority, create a general event bus or scheduler framework, or poll the pasteboard permanently at high frequency.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `clipboard-history`: require bounded event-assisted observation, time-based pasteboard stability, atomic replacement of pending source/timing context, and termination of fast observation after inactivity.

## Impact

- `Sources/Copythat/Stores/ClipboardStore.swift`: time-based stability state plus bounded burst scheduling owned by the main-actor store.
- `Sources/Copythat/Services/CopySourceTracker.swift`: a narrow copy-intent wake callback without moving polling or source-resolution responsibility into the tracker.
- `Sources/Copythat/Stores/AppModel.swift`: weak wiring from the tracker callback to the store.
- Focused pasteboard, source-attribution, and tracker tests, plus live metadata-only capture timing verification.
- No new dependency, persistence field, user setting, permission, or UI change.
