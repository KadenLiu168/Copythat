# Design: deterministic-pinboard-persistence

## Context

See proposal.md — Why. Constraints that shape the approach:

- The payload is a single UserDefaults key (`customPinboards`) holding `Data`, produced by `JSONEncoder().encode([CustomPinboard])` in `persistCustomPinboards()` (`Sources/Copythat/Stores/AppSettings.swift`).
- `AppSettings.init` calls `persistCustomPinboards()` unconditionally, so the value is rewritten on every launch. That write also makes the legacy `pinboardsText` migration durable (see `loadCustomPinboards`), so it is not redundant and is out of scope.
- Measured behaviour of a default `JSONEncoder`: 4 independent processes encoding the same two-pinboard list produced 2 distinct byte strings (`name`-first vs `color`-first). 20 encodes inside a single process produced 1 distinct output. Key order is stable *within* a process and varies *across* processes.
- `loadCustomPinboards` decodes with `JSONDecoder`, which is order-insensitive, and no other reader of this key exists.

## Goals / Non-Goals

**Goals:**

- The persisted representation is a deterministic function of pinboard content.
- The deterministic form is pinned by a guard that cannot pass by luck.

**Non-Goals:**

- Removing the per-launch write (see proposal Non-goals).
- Human-readable output, schema or key changes, or extending determinism to other persisted keys.

## Decisions

### D1: `.sortedKeys` on a dedicated pinboard encoder

`persistCustomPinboards` gains an encoder configured with `.sortedKeys`, kept as a small static factory next to the persistence code so the test can assert its configuration.

Alternatives considered:

- **Leave the default encoder**: the defect. Rejected.
- **Hand-write `encode(to:)` emitting fields in a fixed order**: Foundation's keyed container is dictionary-backed, so declaration order does not survive. Rejected as unverifiable — it looks deterministic without being so.
- **Persist a plist or a sorted array of pairs**: changes the wire format and the migration surface for no functional gain. Rejected.

### D2: The guard is an encoder-configuration assertion plus a pinned payload, not a byte-equality test

**An in-process byte-equality test cannot detect this defect.** Verified: 20 encodes in one process produce identical bytes even *without* `.sortedKeys`, because ordering varies per process rather than per call. A test asserting exact bytes would fail on roughly half of process runs — a knowingly flaky guard, which is worse than no guard.

So determinism is guarded in two non-flaky ways:

- Assert the production encoder's `outputFormatting` contains `.sortedKeys`. Fails immediately and deterministically if the flag is dropped.
- Pin the canonical two-pinboard payload as a golden byte string, documenting the wire format and catching accidental format changes.

Cross-process determinism is confirmed empirically as change evidence — repeat the encode in separate processes and compare bytes — rather than as a permanent unit test.

## Risks / Trade-offs

- [Dropping `.sortedKeys` later silently reintroduces instability] → the configuration assertion fails deterministically; the golden payload also changes.
- [The stored bytes change for existing installs] → decoded content is identical, `JSONDecoder` is order-insensitive, and the payload is rewritten in canonical form on the next launch. No migration is needed.
- [A static encoder factory adds API surface for a one-line need] → keep it file-scoped and commented; the alternative (asserting raw bytes) is flaky.
- [Determinism holds only for the fields currently in `CustomPinboard`] → adding a field later changes the golden payload and fails the pin, forcing a deliberate update rather than a silent one.

## Migration Plan

None. Existing payloads keep decoding; the next launch rewrites them in canonical form. Rollback = revert one line in `persistCustomPinboards`.
