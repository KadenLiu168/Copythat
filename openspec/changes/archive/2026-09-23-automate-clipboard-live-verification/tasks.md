## 1. Establish the unattended runner and evidence contract

- [x] 1.1 Add the explicit `clipboard_live.sh` entry point and report schema for the three profiles in D1; verify stdin is never required, exit codes follow D7, and malformed/missing/stale evidence cannot pass using analyzer fixtures.
- [x] 1.2 Add prepared-session preflight and scoped candidate setup with isolated history/settings, owned-process tracking, and collector readiness; verify normal history/settings sentinels are unchanged and locked/missing-application/missing-permission conditions exit with actionable blocked reports without input or permission prompts.
- [x] 1.3 Qualify automated Chrome copy through the real event tap using the smallest native driver; verify shortcut observation, pasteboard change, and actual fixture capture correlate to the candidate. Record a reproducible passed or blocked qualification report; direct `handle` calls cannot satisfy live qualification, and a blocked result leaves dependent live acceptance incomplete.

## 2. Observe committed outcomes and protect evidence

- [x] 2.1 Reuse current insertion diagnostics and persistence seams, adding only missing verification observations for committed history, tap availability, and wake/burst state; verify no observation triggers capture, changes source order, bypasses permissions, or enables diagnostics in normal startup.
- [x] 2.2 Add bounded event-driven waits and process/count/scenario correlation; verify timeout, wrong process, unrelated clipboard changes, late app switching, and missed burst preconditions yield the correct failure or incomplete-coverage result.
- [x] 2.3 Add fixture-result comparison and payload-safe evidence extraction; verify text, URL, path, image bytes, unique copied markers, and UI dumps cannot enter persisted reports while wrong history order/source/target content fails assertions.
- [x] 2.4 Implement owned-resource cleanup and concurrent-run rejection; verify success, failure, timeout, and SIGINT release owned resources, preserve sanitized reports, leave unrelated processes intact, and permit a second clean run.

## 3. Implement routine application scenarios

- [x] 3.1 Implement real-application distinct A/B copies gated by A commit and active burst; verify `[B, A]`, source attribution, and recorded timing, plus a fixture proving a missed precondition cannot pass. Keep automated evidence separate from physical task 5.3.
- [x] 3.2 Implement editable-text Cmd+X and fixture-region system clipboard screenshot scenarios; verify actual cut removal, cut/wake correlation, completed image insertion and System source evidence without inventing copy/cut screenshot events.
- [x] 3.3 Implement keyboard and real Chrome non-keyboard copy followed by app switching; verify Chrome remains the source, with the non-keyboard case requiring observation before activation before resolution. Confirm a late-switch trace is reported as not covering that race.
- [x] 3.4 Implement actual Copythat restore/paste into a fixture target; verify equality and absence of recapture or duplicate history movement across the D3 observation window, including a negative fixture with a recaptured write.
- [x] 3.5 Add narrow tap-creation-failure injection and exercise the production idle fallback; verify capture continues without shortcut evidence or permission-request attempts. Add an executable real-denied-permission scenario for a preconfigured session and verify reports distinguish injected failure, confirmed OS denial, and unavailable environment.

## 4. Automate original-writer reproduction and replay

- [x] 4.1 Add a versioned recipe format and original-writer driver using application identity/version, fixture preparation, copy method, and exact actions; verify it executes a supported real-app recipe without interactive prompts and reports unavailable applications/recipes explicitly.
- [x] 4.2 Attempt the archived Doubao-to-ChatGPT reproduction using installed application metadata and available historical records; record sanitized measured transitions and insertion decisions, or the precise missing prerequisite. Verify a single observed final count is not accepted as historical multi-stage coverage; missing reproduction leaves original 5.2 pending.
- [x] 4.3 Add deterministic replay of measured timing fixtures and sequential baseline/candidate comparison support; verify transient insertion/movement fails, comparable artifact/timing metadata is reported, synthetic fixtures are labeled, and absent original-writer or baseline evidence cannot produce a 5.2 acceptance claim.

## 5. Verify delivery and document acceptance boundaries

- [x] 5.1 Document one-time desktop setup, each unattended command, required cases per profile, report interpretation, permission-denied setup, and original-task mapping; verify routine instructions contain no manual copy/confirmation step and preserve project manual checks outside this tooling scope.
- [x] 5.2 Run the routine profile twice unattended in a prepared session; verify all required live cases pass, repeated runs remain isolated, and retained reports identify exact candidate/source snapshots. Do not mark this task complete from mocked events or a blocked-only report.
- [x] 5.3 Run `swift build`, `./script/verify_all.sh`, focused runner/analyzer tests, target strict OpenSpec validation, and `git diff --check` against the final implementation; require successful exits and rerun affected/full required gates after subsequent repairs.
- [x] 5.4 Record delivered versus blocked original-writer and real-permission scenarios, evidence levels, build identities, residual physical-input obligations, and original 5.2/5.3/5.5 coverage in a handoff; verify no existing task is automatically checked, archived, or described as fully accepted from weaker evidence.
