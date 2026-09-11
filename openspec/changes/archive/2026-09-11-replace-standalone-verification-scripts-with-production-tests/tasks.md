## 1. Establish production coverage

- [x] 1.1 Add focused `ClipboardItem` tests for stable text/URL/file/image content keys, including empty image data and differing image bytes; verify with the focused test filter and confirm no raw payload is logged.
- [x] 1.2 Add deterministic `ClipboardStore` tests using a unique pasteboard for text, HTTP(S) URL, existing-file URL, file objects, empty/unsupported content, and invalid restore inputs; verify the two-poll change-count contract and failure paths with focused tests.
- [x] 1.3 Map each assertion in `pasteboard_write.swift`, `paste_target.swift`, `paste_decision.swift`, and `history_performance.swift` to production tests or a documented retained check; verify the mapping in the change diff and run the focused test filters.

## 2. Repair and simplify verification tooling

- [x] 2.1 Update `source_attribution_timing.sh` and its test invocation so the default evidence path is resolved from the current checkout or an explicit argument; verify fixture/schema validation still rejects wrong-order, wrong-source, and unsafe-extra-field evidence.
- [x] 2.2 Remove `content_keys.swift`, `pasteboard_write.swift`, `paste_target.swift`, `paste_decision.swift`, and `history_performance.swift` only after their mapped production tests pass; verify `source_resolution.swift` remains executable and no deleted script is referenced by the repository.
- [x] 2.3 Update `script/verify_all.sh` to run the retained source-resolution and live timing checks plus the production test suite without duplicate-script invocations; verify a clean run completes successfully.

## 3. Full regression verification

- [x] 3.1 Run `swift build`, `swift test`, `./script/verify_all.sh`, and `git diff --check`; verify all deterministic tests pass and the live timing harness continues to require correlated physical Cmd+C evidence.
- [x] 3.2 Review the final diff for unchanged duplicate policy, source attribution precedence, paste execution safety, persistence format, and diagnostics privacy; verify no raw clipboard content was added to logs or fixtures.
