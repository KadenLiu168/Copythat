## 1. Durable commit boundary and retry ownership

- [x] 1.1 Add the scoped Sendable resident-media receipt and awaited MainActor handler to `ClipboardHistorySaveCoordinator`; verify focused tests receive only resident image/link-image roles from successful requests, preserve supplied IDs, exclude icons, and record zero new identity or integrity hashes.
- [x] 1.2 Clear `latestItems` only after the latest requested generation commits and expose a focused retained-retry-state accessor; verify latest success clears it with or without a handler, failure retains it, older success preserves newer state, and retry success clears it.
- [x] 1.3 Preserve drain ordering across the awaited handler; use controlled worker/handler continuations to verify flush does not return early, new requests arriving during handling are drained, coalesced generations never emit receipts, and GC is reconsidered after handler completion without changing failure/Retry semantics.

## 2. Bounded seeding and item transformation

- [x] 2.1 Add `seedCommitted` using the existing loader LRU; verify seed plus a retained cache hit performs zero blob reads, zero hashes, and no re-encoding, with returned bytes equal to the prepared payload.
- [x] 2.2 Cover duplicate IDs, hit recency, batch eviction, and oversized seeds with a small injected byte budget; verify byte accounting never exceeds budget, repeated IDs cost once, oversized seeds do not displace useful entries, and oversized/evicted accesses still use verified disk reads.
- [x] 2.3 Add the focused `ClipboardItem` release helper; verify independent image/link-image matches, nonmatching and absent IDs, reference-only no-ops, all metadata and icon fields, content key, search text, and payload-presence preservation with zero media hashes.

## 3. Store ownership and production wiring

- [x] 3.1 Add Store receipt handling that seeds oldest-to-newest before merging current matching UUID/role references; verify hidden-panel commits clear image and link-image bytes in both `items` and `filteredItems`, preserve references/title, favor newer media under cache pressure, and do not request a second save or trigger preview work.
- [x] 3.2 Add reference-only pending release state and consume it during `panelDidClose()` after visibility revocation; verify visible commits seed but retain inline bytes, close releases both arrays, repeated/no-match releases do not publish, and each changed array is assigned at most once without filter or selection reconciliation.
- [x] 3.3 Bound pending reference lifetime through existing removal/eviction handling and role matching; verify delete, Clear History, history-limit eviction, and media replacement discard obsolete pending state without storing Data or resurrecting removed items.
- [x] 3.4 Wire Coordinator to Store in `AppModel` with a weak capture and the injected Store loader; verify an isolated AppModel integration captures/saves/releases an image and obtains a zero-read cache hit using the matching blob store, with no retain cycle introduced by the callback.

## 4. Durability and asynchronous race acceptance

- [x] 4.1 Use isolated real persistence with injected blob-write and manifest-write failures; verify uncommitted image/link-image bytes remain in both arrays, no failed-commit seed or pending release appears, the previous manifest remains usable, and retry succeeds with the same IDs and no new hashes.
- [x] 4.2 Block G1 containing A, replace the same item's media with B in G2, then release G1; verify B remains resident until G2 success, including independent roles and unchanged-identity metadata updates. Extend to G1 active with G2/G3 coalesced and a failing latest generation; verify only successful receipts authorize release and the latest failure remains retryable.
- [x] 4.3 Suspend committed-media handling at the loader boundary and mutate current state; verify replacement, deletion, close, and close/reopen during the await use post-await identities and visibility, with no stale release or new persistence request. Use explicit synchronization rather than arbitrary sleeps.
- [x] 4.4 Verify successful flush waits for handling but completes while the panel stays visible; assert inline bytes remain until close, retry state is cleared after latest success, and one original mutation still produces exactly one persistence generation and manifest commit.
- [x] 4.5 Assert deterministic quiescent ownership metrics for hidden/closed panels: resident image and link-image byte totals are zero separately in `items` and `filteredItems`, successful latest retry snapshot is absent, pending release owns references only, and commit-to-seed-to-release adds zero hashes and zero release-triggered saves. Include oversized committed media to prove release is independent of cache admission.

## 5. Compatibility and full verification

- [x] 5.1 Extend metadata-save acceptance for post-release Pin, Move Pinboard, and Rename Pinboard; verify stable blob IDs, schema version 2, zero heavy-media reads/hashes and unchanged blob writes. Preserve existing resident and restored-reference-only acceptance coverage as separate cases.
- [x] 5.2 Exercise image paste and drag after actual durable release through existing lazy materialization, with both a seeded hit and an evicted miss; verify image payload delivery, no text fallback or preview refetch, and unchanged missing/corrupt-blob failure behavior. Keep tests on temporary storage, isolated defaults, and named pasteboards.
- [x] 5.3 Extend hosted card coverage and verify the actual panel close/reopen path: commit while visible does not switch inline ownership or show a placeholder, close releases history ownership, and reopening renders through existing lazy media identity/visibility gating. Perform isolated manual image/link-preview smoke checks for visual stability and paste permissions; report manual and automated evidence distinctly.
- [x] 5.4 Run `swift test`, `swift build`, `./script/verify_all.sh`, `git diff --check`, and `openspec validate release-resident-media-after-durable-save --strict`; resolve failures without weakening gates. Use the existing verify script's Testing.framework lookup when required by the toolchain and a Python environment with Pillow for its image checks. Keep execution evidence in `.build/verification/` or outside the repository and report results in the agent response.
