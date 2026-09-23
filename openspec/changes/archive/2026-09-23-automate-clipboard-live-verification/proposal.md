## Why

Clipboard responsiveness verification currently relies on a person coordinating copy actions with a short-lived log stream. This repeatedly loses evidence and makes regressions in capture order, source attribution, and paste behavior expensive to verify. A prepared macOS test session should execute routine regression scenarios without interactive prompts and return actionable, payload-safe results.

## What Changes

- Add one unattended clipboard verification entry point with preflight checks, bounded event-driven actions, automatic assertions, cleanup, and machine-readable plus human-readable reports.
- Reuse production Swift tests for stability and lifecycle boundaries; add real-application coverage for successive copies, cut, clipboard screenshot, app switching, and restore/paste.
- First qualify whether automated input reaches the candidate's real event tap. Record automated system-input evidence separately from direct handler tests and physical input.
- Support automatic replay of the historical ChatGPT writer once its actual application/version/action sequence is identified. Keep measured original-writer evidence separate from synthetic timing fixtures.
- Isolate test history/settings and require a prepared disposable desktop session for general-pasteboard scenarios. Report missing permissions or unavailable writers without waiting for human input during a run.
- Map results back to tasks 5.2, 5.3, and 5.5 of `improve-clipboard-capture-responsiveness`, preserving unmet acceptance requirements explicitly.

## Non-goals

- Change capture timing constants, source priority, duplicate policy, paste safety, or shipped permission behavior.
- Automatically accept or archive the responsiveness Change, redefine its physical-input requirement, or replace unrelated manual UI/multi-display acceptance.
- Build a general desktop automation framework, add hardware input equipment, reset macOS permissions, or require a person to execute routine test steps.
- Claim reproduction of an unavailable historical application/version or infer capture success from source-resolution logs alone.

## Capabilities

### New Capabilities

None. This is development verification tooling, not a new product capability.

### Modified Capabilities

None. Existing clipboard-history and paste-and-permissions behavior remains the acceptance target. This change declares `skip_specs: true`; tool contracts and acceptance scenarios are specified in design and tasks.

## Impact

- Primary implementation surface: `script/verify/`, existing Swift tests, and verification documentation.
- Narrow observation/injection seams may be needed in `ClipboardDiagnostics`, `CopySourceTracker`, `ClipboardStore`, and test bootstrap; they must reuse production paths and leave normal app startup unchanged.
- Live runs require macOS with an unlocked, prepared graphical test session and installed target applications. No new production dependency is planned.
- Builds on the current uncommitted responsiveness implementation. Each report must identify the exact candidate artifact and source snapshot; Git HEAD alone is insufficient.
- Existing `script/verify_all.sh` remains the canonical gate. Unattended live verification is a separate explicit entry point, not an unexpected desktop action inside ordinary unit tests.
