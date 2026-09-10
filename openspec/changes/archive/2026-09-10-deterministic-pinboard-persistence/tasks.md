# Tasks: deterministic-pinboard-persistence

## 1. Deterministic encoder

- [x] 1.1 Add a static encoder factory in `Sources/Copythat/Stores/AppSettings.swift` configured with `.sortedKeys`, and use it in `persistCustomPinboards()` in place of the inline default encoder. Verify `swift build` succeeds and the existing pinboard tests (create, relaunch, migrate, rename) still pass unchanged.
- [x] 1.2 Assert the factory's `outputFormatting` contains `.sortedKeys` in the test target. Verify the assertion fails when the flag is removed from the factory, then restore it.
- [x] 1.3 Pin the canonical payload: add a test that encodes `[CustomPinboard(name: "Github", color: .green), CustomPinboard(name: "SKILL.md 优化", color: .pink)]` and asserts the exact byte string. Generate the expected constant from the encoder and confirm it is alphabetical by key (`color` before `name`) before recording it — do not type the constant from memory. Verify the test fails if a field is added, removed, or reordered in `CustomPinboard`.
  - Golden (generated from the encoder via a failing-test capture, not typed from memory): `[{"color":"green","name":"Github"},{"color":"pink","name":"SKILL.md 优化"}]` — `color` precedes `name` in both objects (alphabetical, as `.sortedKeys` requires).
  - Failure-mode verification: field **added** → red ✓; field **removed** (via a temp manual `Codable` conformance omitting `color` from the payload) → red ✓; fields **reordered** (declaration order swapped) → still green — correct by design: under `.sortedKeys` the key order is canonical and declaration order never reaches the wire (design D1 notes the keyed container is dictionary-backed), so the bytes genuinely did not change. Reorder protection comes from the 1.2 configuration assertion plus the pin itself, not from byte mutation.

## 2. Cross-process determinism evidence

- [x] 2.1 Confirm determinism empirically: run the same encode in at least 4 separate processes and verify every run produces byte-identical output. Record the exact command and the observed digests in this task's notes. This is a manual evidence step, not a permanent unit test — see design D2 for why in-process repetition cannot detect this defect.
  - Command (each `swift test` invocation spawns a fresh test process with its own hash seed; the temp test `payloadDigestEvidence` printed the production encoder's output and was removed after collection):
    `for i in 1 2 3 4; do PATH=/tmp/wb-swift-shim:$PATH swift test --filter payloadDigestEvidence 2>/dev/null | grep EVIDENCE-PAYLOAD; done` then `shasum -a 256` per payload.
  - Observed: 4/4 runs produced `[{"color":"green","name":"Github"},{"color":"pink","name":"SKILL.md 优化"}]`, sha256[:16] all `85452c481c21e285`. Byte-identical across processes.

## 3. Verification

- [x] 3.1 Run `swift build` and `./script/verify_all.sh` and confirm the full suite passes. In this environment use the SwiftPM shim: `PATH=/tmp/wb-swift-shim:$PATH ./script/verify_all.sh`.
  - Result: exit 0. 88 tests / 17 suites passed (baseline 86 + 2 new), content keys / pasteboard write / paste target / paste decision / source resolution / history / icons / portable app / panel / bundle checks all ok. (First run hit a transient sandbox `safe-delete` block rebuilding `dist/Copythat.app`; clean rerun passed with no interception.)
- [x] 3.2 Confirm stability in the running app: read the `customPinboards` value from `local.copythat.clipboard`, relaunch Copythat, read it again, and verify the byte digest **and** the decoded content are both identical across the relaunch. Also verify the decoded content still lists the same pre-change pinboards with the same colors.
  - Pre-relaunch: len 77, sha256[:16] `85452c481c21e285`, payload `[{"color":"green","name":"Github"},{"color":"pink","name":"SKILL.md 优化"}]`.
  - Relaunched via `PATH=/tmp/wb-swift-shim:$PATH ./script/build_and_run.sh` (new build, signed, PID 62724).
  - Post-relaunch: identical digest `85452c481c21e285`, identical payload bytes; decoded content = same pinboards `Github`(green) + `SKILL.md 优化`(pink), same order, same colors. Note: the payload was already in canonical form before this relaunch (the `--verify-panel` step of verify_all.sh had briefly launched the new build), so this relaunch confirms write-idempotence across launches rather than the old→canonical migration itself.
