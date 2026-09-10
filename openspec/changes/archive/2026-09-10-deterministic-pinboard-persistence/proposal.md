# Proposal: deterministic-pinboard-persistence

## Why

Copythat rewrites the stored custom-pinboard payload on every launch, but encodes it with a default `JSONEncoder`, whose key ordering comes from per-process hash seeding. The stored bytes therefore differ between launches for identical content: four independent processes encoding the same two-pinboard list produced two distinct byte strings, while twenty encodes inside one process produced one. Nothing is lost or corrupted and decoding is unaffected — but the persisted representation is not reproducible, so any byte-level comparison of the stored data reports a change when no content changed.

This has already cost a verification cycle. A "did this version rewrite my pinboard data?" check based on the payload's digest produced a false alarm during the preceding palette change, and the digest check had to be replaced with a semantic comparison.

## What Changes

- Configure the custom-pinboard encoder with `.sortedKeys`, so the persisted representation becomes a deterministic function of pinboard content.
- Guard it with a test that asserts the production encoder is configured for sorted-key output and pins the canonical two-pinboard payload as a golden value.
- Nothing else changes: the persisted fields (trimmed name, color token), the key, decoding, and the legacy migration path all stay as they are.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `settings-and-launch`: "Configure custom pinboards" — adds a determinism constraint on the persisted representation.

## Impact

- **Code**: `Sources/Copythat/Stores/AppSettings.swift` (`persistCustomPinboards`), `Tests/CopythatTests/AppSettingsPinboardTests.swift`.
- **Data**: none. Decoded content is unchanged and existing payloads keep decoding; the next launch rewrites them in canonical form.
- **Dependencies**: none.
- **Behavior**: no user-visible change. One 77-byte UserDefaults value becomes byte-stable across launches, so backup, sync, audit, and diff tooling stops reporting spurious changes to it.

## Non-goals

- Removing the unconditional `persistCustomPinboards()` call in `AppSettings.init`. That call is what makes the legacy `pinboardsText` migration durable on the launch that performs it, and once the writes are deterministic the repeated write is harmless. Removing it is a separate behavioral decision.
- Changing the stored schema, the key name, or the legacy migration path.
- Extending determinism to any other persisted key (clipboard history, settings). This change covers custom pinboards only, where the instability was observed.
- Making the stored payload human-readable, pretty-printed, or self-describing.
