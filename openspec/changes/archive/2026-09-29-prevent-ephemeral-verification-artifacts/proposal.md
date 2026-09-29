## Why

One-off verification and review Markdown currently travels with OpenSpec changes into Git and archives, mixing local execution history with durable engineering knowledge. Keeping requirements, design tradeoffs, and genuine acceptance limitations authoritative helps future developers maintain Copythat's clipboard and paste guarantees without treating stale local results as current proof; this change does not alter application behavior.

## What Changes

- Add Artifact Hygiene guidance to `AGENTS.md` and project context in `openspec/config.yaml`: report conclusions in agent responses; keep detailed execution evidence in ignored `.build/` or `/tmp/`; incorporate durable findings into existing specs, designs, tasks, or long-lived docs.
- Add a deterministic, read-only, offline Markdown path allowlist gate for `openspec/changes/`, covering active and archived changes, including untracked files. Allow change-root `proposal.md`, `design.md`, `tasks.md`, and `specs/<capability-path>/spec.md`, including nested capability paths. This intentionally narrows the installed schema's discovery glob `specs/**/*.md` to its documented spec filename convention without changing the schema.
- Run the gate and isolated fixture tests early in `script/verify_all.sh`, before the existing packaging check; preserve all existing checks, their relative order, and failure propagation.
- Review and remove the three identified archived process documents only after preserving any unique durable knowledge. Include the additionally discovered active `lazy-load-history-media/stage1-review.md` in the same content-preserving cleanup; do not alter that change's implementation or acceptance status.
- Repair directly related historical instructions and references that still request evidence or handoffs inside changes. Preserve acceptance requirements and distinguish user-approved substitute coverage from still-unverified physical or historical behavior.

## Capabilities

### New Capabilities

None. This is repository tooling and documentation hygiene; `.openspec.yaml` declares `skip_specs: true`.

### Modified Capabilities

None. No Copythat product behavior or existing capability requirement changes.

## Impact

- Primary files: `AGENTS.md`, `openspec/config.yaml`, `script/verify/openspec_artifact_hygiene.sh`, its focused fixture test, and `script/verify_all.sh`.
- Migration: the three archived verification documents in `fix-source-attribution-timing`, `automate-clipboard-live-verification`, and `paste-responsiveness`; the active media change's `stage1-review.md`; only directly related durable artifacts or `docs/clipboard-live-verification.md` when needed to retain unique knowledge or repair stale instructions.
- No new dependencies or production changes. Reuse existing shell/Python verification capabilities and temporary fixture patterns. `.build/` is already ignored; no Markdown ignore rules are needed.
- The gate validates paths, not the meaning of prose inside allowed files. It runs through the existing verification entry point; it is not a Git hook or a server-side prohibition on commits. Explicitly required extra durable documents should normally live in `docs/`; any future exception inside changes needs a deliberate narrow policy/test update, never automatic exemption or a blanket notes allowance.
- Implementation must preserve the current unrelated dirty work. Verification evidence belongs in responses or temporary storage, including evidence for this change itself.

## Non-goals

- Change OpenSpec's official schema, introduce artifact types, redesign Agent workflows, or add a document management system.
- Scan all repository Markdown, prohibit durable operating procedures, ignore Markdown wholesale, or automatically delete/move files.
- Detect semantic process evidence inside legitimate artifact filenames, police non-Markdown formats, or introduce commit hooks/CI infrastructure.
- Rewrite Git history, retain every past review, rerun physical clipboard experiments for a tooling-only change, or claim synthetic checks prove physical behavior.

## Planning scope

The conditional design artifact is omitted under the project's design rule: this bounded tooling change does not cross application modules or alter platform behavior. Concrete acceptance checks and migration obligations are captured in `tasks.md`; no process report is introduced.
