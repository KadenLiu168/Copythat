## Why

Machine-local paths in diagnostic test fixtures and raw verification evidence can expose developer or clipboard-related information through Git. Strengthening tests and the existing verification entry point protects Copythat's clipboard privacy guarantees without changing application behavior.

## What Changes

- Construct the diagnostic file-path fixture at runtime and replace vacuous serialization assertions with the exact current camelCase JSON key set, preserving existing digest privacy checks and meaningful value checks.
- Ignore `/openspec/changes/**/evidence/` as a fallback; require raw evidence to originate under `.build/verification/` or outside the repository.
- Extend the existing Artifact Hygiene section of `AGENTS.md` with repository-wide home-path and raw-evidence rules, and add corresponding `rules.tasks` guidance in `openspec/config.yaml`.
- Preserve the existing policy: single-run verification conclusions belong in agent responses. Durable requirements, limitations and procedures belong in their owning artifacts; repository-wide Agent obligations belong in `AGENTS.md`. Do not introduce exceptions for human-written verification reports.
- Add an early tracked-text home-path check to `script/verify_all.sh`, distinguishing matches, no matches, and Git execution failures.

## Capabilities

### New Capabilities

None. This change covers repository tooling, policy and tests; `.openspec.yaml` declares `skip_specs: true`.

### Modified Capabilities

None. Existing clipboard behavior and diagnostic production serialization remain unchanged.

## Impact

- Implementation allowlist: `Tests/CopythatTests/ClipboardDiagnosticsTests.swift`, `.gitignore`, `AGENTS.md`, `openspec/config.yaml`, and `script/verify_all.sh`.
- Preserve existing artifact hygiene rules and gates, including their ordering relative to packaging. Add the home-path check immediately after entering the repository root.
- Reuse Git, Bash, Foundation JSON parsing and Swift Testing; no dependencies or generic verification framework.
- The automated check covers tracked text in the working tree when full verification runs. It does not scan untracked outputs, binary payloads, Git history or arbitrary privacy-sensitive content, and is not a server-side commit prohibition.
- New planning artifacts must themselves avoid continuous home-root-plus-username literals. Use repository-relative paths, `$HOME`, `<repository-root>`, or split runtime construction.

## Non-goals

- Git history rewriting, force pushes, CI, hooks, or automatic publication.
- Changes to `Sources/`, `Package.swift`, or the intentional forbidden-prefix detector in `script/verify/clipboard_live_report.py`.
- Broad evidence migration, Markdown ignore rules, weakening the existing OpenSpec artifact allowlist, or unrelated refactoring.

## Planning scope

Keep detailed acceptance obligations in `tasks.md`. The conditional design artifact is omitted under the project's design rule: this bounded tooling/test change does not alter application modules, permissions, persistence, pasteboard behavior or source attribution.
