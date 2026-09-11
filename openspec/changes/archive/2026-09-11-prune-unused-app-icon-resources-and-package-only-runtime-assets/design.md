## Context

SwiftPM processes the whole `Sources/Copythat/Resources` directory, while the app's runtime icon consumer is `CopythatIcon` and the app wrapper receives `AppIcon.icns` from `script/build_and_run.sh`. `script/generate_icons.py` currently writes an intermediate `.iconset` into the same processed directory, and `script/verify_all.sh` inspects the catalog and transparent logo. The panel uses `targetAppTouchesScreenBottom` for geometry; that function is unrelated to screen capture permission.

## Goals / Non-Goals

**Goals:**

- Separate build-time icon generation intermediates from resources that ship or are explicitly verified.
- Preserve the existing app-branding and distribution contracts while reducing accidental resource packaging.
- Keep Info.plist declarations aligned with actual API use and preserve all required automation/accessibility messaging.

**Non-Goals:**

- Redesigning the icon pipeline or changing generated pixels.
- Removing the spec-required catalog or transparent logo without first replacing the corresponding verification contract.
- Changing panel geometry, clipboard behavior, or paste permissions.

## Decisions

1. **Generate `.icns` from a temporary iconset.**
   The generator should create a temporary directory (with cleanup) for `iconutil` inputs instead of persisting `AppIcon.iconset` under SwiftPM's processed Resources. This preserves reproducibility and `AppIcon.icns` output while preventing intermediates from entering the resource bundle.

   *Alternative considered:* keep the checked-in iconset and exclude it in `Package.swift`. Rejected because the current target processes the directory as a whole and an exclusion would create a second, fragile resource rule.

2. **Prune only after an explicit consumer inventory.**
   `AppIcon.icns` remains because the app wrapper copies it; `MenuBarIconTemplate.png` remains because `CopythatIcon` loads it; the catalog and transparent logo remain because the current branding specification and verifier require them. `AppIcon-1024.png` is removed only if no runtime, package, or verification path consumes it.

   *Alternative considered:* delete every duplicate PNG and rewrite branding verification in the same change. Rejected because it would silently alter the existing `app-branding` contract and make the cleanup harder to review.

3. **Remove only the stale screen-capture usage declaration.**
   Keep `NSAppleEventsUsageDescription` and all actual permission checks. Update the plist verification assertion to encode the intended absence rather than weakening verification globally.

   *Alternative considered:* retain the declaration for compatibility. Rejected because it advertises access the implementation does not request and can confuse users about why a permission prompt appears.

4. **Measure packaging after pruning.**
   Compare the staged bundle/resource-bundle file list and sizes before and after. Size reduction is evidence, not a fixed acceptance number; launch and relocation checks remain authoritative.

## Risks / Trade-offs

- [A future generator invocation could leave temporary files] → use a scoped temporary directory and cleanup trap/context manager; verify the Resources tree has no generated `.iconset` after the run.
- [A supposedly unused asset may be consumed by an unindexed packaging path] → search all scripts/specs and run relocated-app, panel, and icon checks before deletion.
- [Changing Info.plist verification could hide a real permission regression] → assert required keys remain and explicitly assert only the screen-capture key is absent.

## Migration Plan

1. Record the pre-change resource inventory and bundle size.
2. Change generator output location and remove only confirmed-unused files.
3. Update packaging verification and measure the resulting bundle.
4. Run `swift build` and `./script/verify_all.sh`, including relocation and panel launch checks.
5. Roll back by restoring the removed intermediates and prior generator/plist verification if any required resource or launch behavior regresses.

## Open Questions

None. The inventory and measurement tasks resolve the only implementation-time uncertainty without changing the contract.
