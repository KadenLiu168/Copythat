// preview_live_scenarios.swift - 8.2 live scenarios against the real
// production store + real LPMetadataProvider + real WebKit, using the local
// fixture server (see preview_fixture_server.py for the routes). Assertions
// carry item ids, outcome kinds and timing only - never URLs or payloads.

import Foundation

private func check(
    _ name: String,
    _ expected: String,
    _ observed: String,
    _ passed: Bool
) -> PreviewAssertion {
    PreviewAssertion(name: name, expected: expected, observed: observed, passed: passed)
}

@MainActor
enum PreviewScenarios {
    // MARK: P1 - og:image URL, closed panel, zero fallback

    static func metadataImageClosedPanel(port: Int) async -> PreviewScenarioResult {
        let host = PreviewHost(port: port)
        guard let itemID = host.capture(urlString: "http://127.0.0.1:\(port)/og/1") else {
            return blocked("P1-metadata-image-closed-panel", "capture failed")
        }
        let metadataSeen = previewWait(10) {
            host.log.count(.metadataImage, itemID: itemID) == 1
        }
        let snapshotEvents = snapshotEventCount(host, itemID: itemID)
        let imageStored = host.store.items.first?.id == itemID &&
            host.store.items.first?.linkImageData != nil
        let held = metadataSeen && snapshotEvents == 0 && imageStored
        return PreviewScenarioResult(
            scenario: "P1-metadata-image-closed-panel",
            verdict: held ? PreviewVerdict.passed : PreviewVerdict.failed,
            evidenceLevel: PreviewEvidence.automatedRealDesktop,
            reason: held
                ? "og fixture metadata applied its image with zero browser-fallback events while closed"
                : "metadata-image flow did not hold (see assertions)",
            assertions: [
                check("metadata-image-event", "1", "\(host.log.count(.metadataImage, itemID: itemID))", metadataSeen),
                check("zero-snapshot-events", "0", "\(snapshotEvents)", snapshotEvents == 0),
                check("og-image-stored", "true", "\(imageStored)", imageStored),
            ],
            timings: [:]
        )
    }

    // MARK: P2 - batch of title-only URLs, closed panel, zero fallback

    static func titleOnlyBatch(port: Int) async -> PreviewScenarioResult {
        let host = PreviewHost(port: port)
        var ids: [UUID] = []
        for index in 1...3 {
            guard let id = host.capture(urlString: "http://127.0.0.1:\(port)/title/\(index)") else {
                return blocked("P2-title-only-batch", "capture failed for case \(index)")
            }
            ids.append(id)
        }
        let batchSeen = previewWait(15) {
            ids.allSatisfy { host.log.count(.metadataTitleOnly, itemID: $0) == 1 }
        }
        let snapshotEvents = host.log.events.filter { $0.outcome.hasPrefix("snapshot") }.count
        let plainCards = host.store.items.count == 3 &&
            host.store.items.allSatisfy { $0.linkImageData == nil }
        let held = batchSeen && snapshotEvents == 0 && plainCards
        return result(
            scenario: "P2-title-only-batch",
            passed: held,
            reason: held
                ? "batch produced title-only outcomes with zero fallback while closed"
                : "title-only batch did not hold (see assertions)",
            assertions: [
                check("metadata-title-only-events", "3", "\(host.log.count(.metadataTitleOnly))", batchSeen),
                check("zero-snapshot-events", "0", "\(snapshotEvents)", snapshotEvents == 0),
                check("cards-stay-plain-while-closed", "true", "\(plainCards)", plainCards),
            ]
        )
    }

    // MARK: P3 - open panel: only the selected visible item snapshots

    static func openSelectAppliesSelectedOnly(port: Int) async -> PreviewScenarioResult {
        let host = PreviewHost(port: port)
        guard let firstID = host.capture(urlString: "http://127.0.0.1:\(port)/title/4"),
              let secondID = host.capture(urlString: "http://127.0.0.1:\(port)/title/5") else {
            return blocked("P3-open-select-selected-only", "capture failed")
        }
        // items are newest-first, so openPanel auto-selects `secondID`.
        host.openPanel()
        let secondApplied = previewWait(8) { host.log.count(.snapshotApplied, itemID: secondID) == 1 }
        let firstAppliedWhileUnselected = host.log.count(.snapshotApplied, itemID: firstID)
        let firstIdle = firstAppliedWhileUnselected == 0
        selectItem(host, id: firstID)
        let firstApplied = previewWait(8) { host.log.count(.snapshotApplied, itemID: firstID) == 1 }
        let total = host.log.count(.snapshotApplied)
        let held = secondApplied && firstIdle && firstApplied && total == 2
        return result(
            scenario: "P3-open-select-selected-only",
            passed: held,
            reason: held
                ? "open+select drove exactly one fallback per selected visible item"
                : "selection-gated fallback did not hold (see assertions)",
            assertions: [
                check(
                    "selected-item-applied", "1",
                    "\(host.log.count(.snapshotApplied, itemID: firstID))", firstApplied
                ),
                check(
                    "unselected-item-idle", "0",
                    "\(firstAppliedWhileUnselected)", firstIdle
                ),
                check("total-applied", "2", "\(total)", total == 2),
            ]
        )
    }

    // MARK: P4 - rapid switching during slow navigation: no pile-up

    static func rapidSwitchOverlap(port: Int) async -> PreviewScenarioResult {
        let host = PreviewHost(port: port)
        guard let aID = host.capture(urlString: "http://127.0.0.1:\(port)/slowbody/1"),
              let bID = host.capture(urlString: "http://127.0.0.1:\(port)/slowbody/2") else {
            return blocked("P4-rapid-switch-overlap", "capture failed")
        }
        let metadataReady = previewWait(9.5) {
            host.log.count(.metadataTitleOnly, itemID: aID) == 1 &&
                host.log.count(.metadataTitleOnly, itemID: bID) == 1
        }
        guard metadataReady else {
            return blocked("P4-rapid-switch-overlap", "slowbody fixtures did not reach metadata success in time")
        }
        host.openPanel()
        for _ in 0..<3 {
            selectItem(host, id: bID)
            RunLoop.main.run(until: Date().addingTimeInterval(0.35))
            selectItem(host, id: aID)
            RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        }
        let appliedA = previewWait(10) { host.log.count(.snapshotApplied, itemID: aID) == 1 }
        let appliedACount = host.log.count(.snapshotApplied, itemID: aID)
        let appliedBCount = host.log.count(.snapshotApplied, itemID: bID)
        let cancelledTotal = host.log.count(.snapshotCancelled)
        let held = appliedA && appliedACount == 1 &&
            appliedBCount == 0 && cancelledTotal >= 2
        return result(
            scenario: "P4-rapid-switch-overlap",
            passed: held,
            reason: held
                ? "rapid switching cancelled superseded loads; only the final target applied once"
                : "rapid switching did not keep a single serialized fallback (see assertions)",
            assertions: [
                check("final-target-applied-once", "1", "\(appliedACount)", appliedACount == 1),
                check("superseded-target-never-applied", "0", "\(appliedBCount)", appliedBCount == 0),
                check("cancellations-observed", ">=2", "\(cancelledTotal)", cancelledTotal >= 2),
            ]
        )
    }

    // MARK: P5 - close cancels, reopen retries

    static func closeCancelReopenRetry(port: Int) async -> PreviewScenarioResult {
        let host = PreviewHost(port: port)
        guard let itemID = host.capture(urlString: "http://127.0.0.1:\(port)/slowbody/3") else {
            return blocked("P5-close-cancel-reopen-retry", "capture failed")
        }
        let metadataSeen = previewWait(9.5) {
            host.log.count(.metadataTitleOnly, itemID: itemID) == 1
        }
        guard metadataSeen else {
            return blocked("P5-close-cancel-reopen-retry", "slowbody metadata did not complete in time")
        }
        host.openPanel()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.closePanel()
        let cancelSeen = previewWait(6) { host.log.count(.snapshotCancelled, itemID: itemID) >= 1 }
        let appliedDuringClosed = host.log.count(.snapshotApplied, itemID: itemID)
        host.openPanel()
        let retried = previewWait(10) { host.log.count(.snapshotApplied, itemID: itemID) == 1 }
        let held = cancelSeen && appliedDuringClosed == 0 && retried
        return result(
            scenario: "P5-close-cancel-reopen-retry",
            passed: held,
            reason: held
                ? "close cancelled the in-flight fallback; reopen retried successfully (cancel is not a failure entry)"
                : "close/reopen cancellation did not hold (see assertions)",
            assertions: [
                check(
                    "cancel-observed", ">=1",
                    "\(host.log.count(.snapshotCancelled, itemID: itemID))", cancelSeen
                ),
                check(
                    "no-late-apply-while-closed", "0",
                    "\(appliedDuringClosed)", appliedDuringClosed == 0
                ),
                check(
                    "reopen-retried-and-applied", "1",
                    "\(host.log.count(.snapshotApplied, itemID: itemID))", retried
                ),
            ]
        )
    }

    // MARK: P6 - refused page: snapshot failure, negative cache, no recovery

    static func refusedPageFailure(port: Int) async -> PreviewScenarioResult {
        let host = PreviewHost(port: port)
        guard let itemID = host.capture(urlString: "http://127.0.0.1:9/refused") else {
            return blocked("P6-refused-no-recovery", "capture failed")
        }
        let metadataSeen = previewWait(10) {
            host.log.count(.metadataEmpty, itemID: itemID) == 1 ||
                host.log.count(.metadataFailure, itemID: itemID) == 1
        }
        host.openPanel()
        let metadataFailed = host.log.count(.metadataFailure, itemID: itemID) == 1
        let failedSeen = metadataFailed || previewWait(8) {
            host.log.count(.snapshotFailed, itemID: itemID) == 1
        }
        host.store.select(host.store.items.first ?? unreachableItem())
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        let failedAfterReselect = host.log.count(.snapshotFailed, itemID: itemID)
        let started = host.log.count(.snapshotStarted, itemID: itemID)
        let applied = host.log.count(.snapshotApplied, itemID: itemID)
        // Metadata failure cannot authorize browser recovery. Only empty
        // metadata success can exercise snapshot failure and its retry TTL.
        let expectedFailures = metadataFailed ? 0 : 1
        let held = metadataSeen && failedSeen && started == expectedFailures &&
            failedAfterReselect == expectedFailures && applied == 0
        return result(
            scenario: "P6-refused-no-recovery",
            passed: held,
            reason: held
                ? "refused page obeyed its metadata outcome and never retried or applied a snapshot"
                : "failure handling did not hold (see assertions)",
            assertions: [
                check(
                    "metadata-outcome-observed", "1",
                    "\(metadataEventCount(host, itemID: itemID))", metadataSeen
                ),
                check("snapshot-failures", "\(expectedFailures)", "\(failedAfterReselect)", failedSeen && failedAfterReselect == expectedFailures),
                check("snapshot-starts", "\(expectedFailures)", "\(started)", started == expectedFailures),
                check("no-snapshot-applied", "0", "\(applied)", applied == 0),
            ]
        )
    }

    // MARK: P7 - pinned duplicate reuses the session snapshot cache

    static func pinnedDuplicateReusesCache(port: Int) async -> PreviewScenarioResult {
        let host = PreviewHost(port: port)
        guard let firstID = host.capture(urlString: "http://127.0.0.1:\(port)/title/6") else {
            return blocked("P7-pinned-duplicate-cache", "capture failed")
        }
        host.openPanel()
        let firstApplied = previewWait(8) { host.log.count(.snapshotApplied, itemID: firstID) == 1 }
        guard firstApplied else {
            return blocked("P7-pinned-duplicate-cache-reuse", "initial snapshot did not apply")
        }
        selectItem(host, id: firstID)
        let pinnedID = host.store.items.first { $0.id == firstID }
        if let pinnedID { host.store.togglePin(pinnedID) }
        let appliedBefore = host.log.count(.snapshotApplied)
        guard let secondID = host.capture(urlString: "http://127.0.0.1:\(port)/title/6") else {
            return blocked("P7-pinned-duplicate-cache-reuse", "re-capture failed")
        }
        let secondMetadata = previewWait(8) {
            host.log.count(.metadataTitleOnly, itemID: secondID) == 1
        }
        let cacheApplied = previewWait(4) {
            host.log.count(.snapshotCacheApplied, itemID: secondID) == 1
        }
        let secondIsFresh = secondID != firstID
        let held = secondMetadata && cacheApplied && secondIsFresh &&
            host.log.count(.snapshotApplied) == appliedBefore &&
            appliedBefore >= 1
        return result(
            scenario: "P7-pinned-duplicate-cache-reuse",
            passed: held,
            reason: held
                ? "same-URL pinned duplicate applied the cached snapshot without a browser loader"
                : "cache reuse did not hold (see assertions)",
            assertions: [
                check(
                    "distinct-item-for-pinned-duplicate", "true", "\(secondIsFresh)", secondIsFresh
                ),
                check(
                    "metadata-for-new-item", "1",
                    "\(host.log.count(.metadataTitleOnly, itemID: secondID))", secondMetadata
                ),
                check(
                    "cache-hit-applied", "1",
                    "\(host.log.count(.snapshotCacheApplied, itemID: secondID))", cacheApplied
                ),
                check(
                    "no-extra-live-loads", "\(appliedBefore)",
                    "\(host.log.count(.snapshotApplied))",
                    host.log.count(.snapshotApplied) == appliedBefore
                ),
            ]
        )
    }

    // MARK: P8 - event payload safety

    static func eventPayloadSafety() -> PreviewScenarioResult {
        let lines = ReportEventsStorage.all.map { (try? $0.jsonLine()) ?? "encoding-failure" }
        let unsafe = lines.filter { line in
            line == "encoding-failure" ||
                line.lowercased().contains("://") ||
                line.lowercased().contains("clipboard")
        }
        return result(
            scenario: "P8-event-payload-safety",
            passed: unsafe.isEmpty,
            reason: unsafe.isEmpty
                ? "every emitted event line carries item ids and outcome kinds only"
                : "unsafe tokens found in event stream",
            assertions: [
                check("no-url-tokens-in-events", "0", "\(unsafe.count)", unsafe.isEmpty),
            ]
        )
    }

    // MARK: shared helpers

    private static func result(
        scenario: String,
        passed: Bool,
        reason: String,
        assertions: [PreviewAssertion]
    ) -> PreviewScenarioResult {
        PreviewScenarioResult(
            scenario: scenario,
            verdict: passed ? PreviewVerdict.passed : PreviewVerdict.failed,
            evidenceLevel: PreviewEvidence.automatedRealDesktop,
            reason: reason,
            assertions: assertions,
            timings: [:]
        )
    }

    private static func blocked(_ scenario: String, _ reason: String) -> PreviewScenarioResult {
        PreviewScenarioResult(
            scenario: scenario,
            verdict: PreviewVerdict.blocked,
            evidenceLevel: PreviewEvidence.automatedRealDesktop,
            reason: reason,
            assertions: [],
            timings: [:]
        )
    }

    private static func snapshotEventCount(_ host: PreviewHost, itemID: UUID) -> Int {
        host.log.events.filter { $0.itemID == itemID.uuidString && $0.outcome.hasPrefix("snapshot") }.count
    }

    private static func metadataEventCount(_ host: PreviewHost, itemID: UUID) -> Int {
        host.log.events.filter {
            $0.itemID == itemID.uuidString && $0.outcome.hasPrefix("metadata")
        }.count
    }

    private static func selectItem(_ host: PreviewHost, id: UUID) {
        guard let item = host.store.items.first(where: { $0.id == id }) else { return }
        host.store.select(item)
    }

    private static func unreachableItem() -> ClipboardItem {
        ClipboardItem(
            id: UUID(), kind: .text, title: "unreachable", preview: "unreachable",
            sourceApp: "driver", sourceAppIconData: nil, createdAt: Date(),
            isPinned: false, pinboardName: nil, textValue: "unreachable",
            fileURLs: [], imageData: nil
        )
    }
}

/// Per-process storage for event lines, kept outside the scenarios so the
/// payload-safety scenario can inspect the full stream.
@MainActor
enum ReportEventsStorage {
    static var all: [ClipboardDiagnostics.LinkPreviewEvent] = []
}
