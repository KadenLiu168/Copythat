## Why

Several repository verification scripts duplicate behavior that belongs in the production test suite, while one live source-attribution harness still points at an obsolete evidence default. This makes the canonical regression gate harder to discover and allows script-only checks to drift from the actual `ClipboardItem` and `ClipboardStore` contracts.

## What Changes

- Add focused production tests for `ClipboardItem.contentKey` and the supported pasteboard capture branches (text, URL, file, image, and invalid/empty content).
- Add the smallest test seams needed to exercise those branches without storing raw clipboard payloads in diagnostics.
- Update the live source-attribution harness to use its current evidence location while preserving the harness and its physical-event requirement.
- Remove the five standalone verification scripts only after equivalent production tests and the live-harness path check pass.
- Keep `source_resolution.swift`, which remains a narrow compile-and-run check for the source-resolution boundary.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This is a test and verification-tooling consolidation; it does not change shipped clipboard behavior.

## Impact

- **Tests:** `Tests/CopythatTests/` gains focused coverage for content identity and pasteboard parsing behavior.
- **Tooling:** `script/verify/` loses redundant scripts and keeps the source-attribution timing harness and source-resolution check.
- **Production code:** only narrowly scoped testability seams may be added; no user-facing behavior or persistence format changes are intended.
- **Verification:** the focused tests, `swift build`, `swift test`, and `./script/verify_all.sh` must remain green.

## Non-goals

- Removing the live source-attribution timing harness.
- Replacing physical Cmd+C evidence with synthetic events.
- Changing duplicate policy, source attribution semantics, paste execution, or persistence.
- Removing `source_resolution.swift` or other checks that cover a distinct trust boundary.
- Introducing a generic verification framework or a new dependency.
