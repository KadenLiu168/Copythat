## 1. Diagnostic Metadata

- [x] 1.1 Add a small clipboard diagnostics helper near the store layer that checks `UserDefaults.standard.bool(forKey: "clipboardDiagnosticsEnabled")`; verify diagnostics are disabled by default.
- [x] 1.2 Add a safe content identity summary that reports kind, content length, and a short digest of `contentKey` without returning raw copied text, URLs, file paths, or image data; verify with focused tests.
- [x] 1.3 Add duplicate-match metadata for pending insertion, including matching item IDs/counts and pinned status; verify same-content/different-source items are detected before insertion.

## 2. Runtime Logging

- [x] 2.1 Add an `OSLog.Logger` category named `ClipboardDiagnostics` using the app bundle identifier fallback `local.copythat.clipboard`; verify the app builds.
- [x] 2.2 Emit a diagnostics event after source metadata is resolved for a supported pasteboard item, including item kind, source app, pasteboard change count, and change-count delta; verify no event is emitted when the flag is off.
- [x] 2.3 Emit a diagnostics event around history insertion with before/after counts, item ID, source app, content identity summary, and duplicate-match metadata; verify insertion behavior and selected item behavior are unchanged.

## 3. Tests and Verification

- [x] 3.1 Add unit coverage for default-off diagnostics, safe content identity summaries, and duplicate metadata; verify tests would fail if raw payload values are exposed.
- [x] 3.2 Run targeted tests for clipboard history policy, card source icons, and the new diagnostics helper; verify all pass.
- [x] 3.3 Run `swift build` and `./script/verify_all.sh`; verify no unrelated clipboard, source attribution, search, pinboard, or paste behavior regresses.
- [x] 3.4 Manually enable diagnostics with `defaults write local.copythat.clipboard clipboardDiagnosticsEnabled -bool true`, reproduce the Doubao-to-ChatGPT copy sequence, and inspect logs with `log stream --style compact --predicate 'process == "Copythat" && category == "ClipboardDiagnostics"'`; verify logs distinguish duplicate replacement from source mutation.
