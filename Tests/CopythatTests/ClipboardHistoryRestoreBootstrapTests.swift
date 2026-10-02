@testable import Copythat
import AppKit
import Foundation
import Testing

/// Startup bootstrap: buffering, baseline installation, policy replay and the
/// persistence barrier. Every scenario gates the loader explicitly, so none of
/// them waits for a wall-clock delay or a guessed scheduling threshold.
@MainActor
@Suite(.serialized)
struct ClipboardHistoryRestoreBootstrapTests {

    // MARK: - 2.2 One-shot restore state

    @Test func loadingIsPublishedBeforeBeginReturnsAndFinishIsAwaitable() async {
        let harness = HistoryRestoreHarness(outcomes: [.success([HistoryRestoreFixture.textItem("A")])])
        defer { harness.cleanUp() }

        #expect(harness.store.restoreState == .ready)
        #expect(harness.store.isRestoringHistory == false)

        harness.store.beginHistoryRestore(with: harness.loader)

        #expect(harness.store.isRestoringHistory, "loading is published before begin returns")
        #expect(harness.store.restoreState == .restoring)

        await harness.loader.release()
        await harness.store.finishHistoryRestore()

        #expect(harness.store.isRestoringHistory == false)
        #expect(harness.store.restoreState == .ready)
        #expect(harness.store.items.map(\.textValue) == ["A"])
    }

    @Test func duplicateBeginCannotInvokeTheLoaderTwice() async {
        let harness = HistoryRestoreHarness(outcomes: [.success([])])
        defer { harness.cleanUp() }

        await harness.beginRestoring()
        harness.store.beginHistoryRestore(with: harness.loader)
        harness.store.beginHistoryRestore(with: harness.loader)
        await harness.finishRestoring()
        // The one-shot guard outlives the cleared completion handle.
        harness.store.beginHistoryRestore(with: harness.loader)
        await harness.finishRestoring()

        #expect(await harness.loader.loadCount == 1)
    }

    @Test func aReadyStoreFinishReturnsImmediatelyWithoutALoader() async {
        let harness = HistoryRestoreHarness(outcomes: [])
        defer { harness.cleanUp() }

        await harness.store.finishHistoryRestore()

        #expect(await harness.loader.loadCount == 0)
        #expect(harness.store.restoreState == .ready)
        #expect(harness.store.canMutateHistory)
    }

    @Test func loadFailureAlwaysReachesReady() async {
        let harness = HistoryRestoreHarness(outcomes: [.failure])
        defer { harness.cleanUp() }

        await harness.beginRestoring()
        await harness.finishRestoring()

        #expect(harness.store.restoreState == .ready)
        #expect(harness.store.isRestoringHistory == false)
        #expect(harness.store.items.isEmpty)
    }

    // MARK: - 3.1 Arrival buffering

    @Test func gatedAddsAreBufferedCompleteAndPersistNothing() async {
        let harness = HistoryRestoreHarness(outcomes: [.success([])])
        defer { harness.cleanUp() }
        let capturedAt = Date(timeIntervalSince1970: 1_700_555_000)
        let captured = HistoryRestoreFixture.textItem(
            "B",
            createdAt: capturedAt,
            sourceApp: "Safari"
        )

        await harness.beginRestoring()
        harness.store.add(captured)

        #expect(harness.store.items.isEmpty, "a buffered capture is not a formal insertion")
        #expect(harness.saves.count == 0, "a blocked restore records zero persistence calls")

        await harness.finishRestoring()

        #expect(harness.store.items.map(\.textValue) == ["B"])
        let replayed = harness.store.items.first
        #expect(replayed?.id == captured.id, "identity survives buffering")
        #expect(replayed?.sourceApp == "Safari", "admission source context survives buffering")
        #expect(replayed?.createdAt == capturedAt, "admission time survives buffering")
    }

    @Test func imageMediaIdentitySurvivesBufferingWithoutReHashing() async throws {
        let media = PreparedMedia(hashing: Data(repeating: 0x5a, count: 512))
        let captured = HistoryRestoreFixture.imageItem(media: media)
        let harness = HistoryRestoreHarness(outcomes: [.success([])])
        defer { harness.cleanUp() }

        await harness.beginRestoring()
        harness.store.add(captured)
        await harness.finishRestoring()

        let replayed = try #require(harness.store.items.first)
        #expect(replayed.imageBlobID == media.id, "prepared media identity is forwarded, never recomputed")
        #expect(replayed.contentKey == captured.contentKey)
    }

    // MARK: - 3.4 Bootstrap save counts

    @Test func cleanRestorationRequestsZeroSaves() async {
        let harness = HistoryRestoreHarness(outcomes: [.success([HistoryRestoreFixture.textItem("A")])])
        defer { harness.cleanUp() }

        await harness.beginRestoring()
        await harness.finishRestoring()

        #expect(harness.saves.count == 0)
    }

    @Test func baselineTrimRequestsExactlyOneSave() async {
        let harness = HistoryRestoreHarness(outcomes: [.success(newestFirstBaseline(count: 101))], limit: 100)
        defer { harness.cleanUp() }

        await harness.beginRestoring()
        await harness.finishRestoring()

        #expect(harness.store.items.count == 100)
        #expect(harness.saves.count == 1, "an actual trim is a legitimate bootstrap save")
        #expect(harness.saves.latestTextValues.first == "item-100", "the newest entries survive")
        #expect(harness.saves.latestTextValues.contains("item-0") == false, "the oldest entry is trimmed")
    }

    @Test func aSingleCaptureRequestsExactlyOneSave() async {
        let harness = HistoryRestoreHarness(outcomes: [.success([HistoryRestoreFixture.textItem("A")])])
        defer { harness.cleanUp() }

        await harness.beginRestoring()
        harness.store.add(HistoryRestoreFixture.textItem("B"))
        await harness.finishRestoring()

        #expect(harness.store.items.map(\.textValue) == ["B", "A"])
        #expect(harness.saves.count == 1)
        #expect(harness.saves.latestTextValues == ["B", "A"])
    }

    @Test func trimPlusMultipleCapturesShareExactlyOneBootstrapSave() async {
        let harness = HistoryRestoreHarness(outcomes: [.success(newestFirstBaseline(count: 101))], limit: 100)
        defer { harness.cleanUp() }

        await harness.beginRestoring()
        harness.store.add(HistoryRestoreFixture.textItem("newest"))
        harness.store.add(HistoryRestoreFixture.textItem("middle"))
        harness.store.add(HistoryRestoreFixture.textItem("last-arrival"))
        #expect(harness.saves.count == 0, "no intermediate snapshot is requested")

        await harness.finishRestoring()

        #expect(harness.saves.count == 1, "trim plus several captures still commit exactly once")
        #expect(
            Array(harness.saves.latestTextValues.prefix(4)) == ["last-arrival", "middle", "newest", "item-100"],
            "the last arrival ends up at the head, ahead of the retained baseline"
        )
        #expect(harness.store.items == harness.saves.snapshots.last)
    }

    @Test func aDiscardedDuplicateStillCommitsTheBufferedCaptureOnce() async {
        let harness = HistoryRestoreHarness(
            outcomes: [.success(newestFirstBaseline(count: 100, pinned: true))],
            limit: 100
        )
        defer { harness.cleanUp() }

        await harness.beginRestoring()
        // Ordinary capacity is fully reserved by pinned items, so policy
        // discards this arrival — yet the buffered add is still a legitimate
        // dirty reason and commits exactly once.
        harness.store.add(HistoryRestoreFixture.textItem("arrival"))
        await harness.finishRestoring()

        #expect(harness.store.items.allSatisfy { $0.isPinned })
        #expect(harness.store.items.count == 100)
        #expect(harness.saves.count == 1)
        #expect(harness.saves.snapshots.last == harness.store.items)
    }

    // MARK: - 3.6 Duplicate replay follows the existing policy

    @Test func replayMatchesPolicyForUnpinnedPinnedAndAssignedDuplicates() async {
        let scenarios: [(String, ClipboardItem, ClipboardItem)] = [
            (
                "unpinned duplicate with a pinboard assignment",
                HistoryRestoreFixture.textItem("dup", isPinned: false, pinboardName: "Work"),
                HistoryRestoreFixture.textItem("dup")
            ),
            (
                "pinned duplicate",
                HistoryRestoreFixture.textItem("dup", isPinned: true),
                HistoryRestoreFixture.textItem("dup")
            ),
            (
                "unpinned duplicate without an assignment",
                HistoryRestoreFixture.textItem("dup"),
                HistoryRestoreFixture.textItem("dup")
            )
        ]

        for (name, saved, captured) in scenarios {
            let harness = HistoryRestoreHarness(outcomes: [.success([saved])])
            defer { harness.cleanUp() }

            await harness.beginRestoring()
            harness.store.add(captured)
            await harness.finishRestoring()

            let expected = ClipboardHistoryPolicy.adding(captured, to: [saved], limit: harness.settings.historyLimit)
            #expect(harness.store.items == expected.items, "\(name): items must match policy exactly")
            #expect(harness.store.selectedID == expected.selectedItemID, "\(name): selection must match policy")

            // The saved entry is identified by its own identity, not by
            // content: a replayed duplicate may legitimately add a second
            // entry with the same content key.
            let savedSurvivor = harness.store.items.first { $0.id == saved.id }
            #expect(savedSurvivor != nil, "\(name): the saved entry is preserved")
            #expect(savedSurvivor?.createdAt == saved.createdAt, "\(name): creation time is preserved")
            #expect(savedSurvivor?.sourceApp == saved.sourceApp, "\(name): source app is preserved")
            #expect(savedSurvivor?.pinboardName == saved.pinboardName, "\(name): assignment is preserved")
            #expect(savedSurvivor?.isPinned == saved.isPinned, "\(name): pin state is preserved")
        }
    }

    @Test func pinnedCapacityExhaustionReplaysThroughTheSamePolicy() async {
        // The effective limit is reserved for pinned items first, so an unpinned
        // arrival into a fully pinned history is discarded by the ordinary rule.
        let limit = 100
        let pinned = (0..<limit).map { HistoryRestoreFixture.textItem("pinned-\($0)", isPinned: true) }
        let captured = HistoryRestoreFixture.textItem("newcomer")
        let harness = HistoryRestoreHarness(outcomes: [.success(pinned)], limit: limit)
        defer { harness.cleanUp() }

        await harness.beginRestoring()
        harness.store.add(captured)
        await harness.finishRestoring()

        let expected = ClipboardHistoryPolicy.adding(captured, to: pinned, limit: limit)
        #expect(harness.store.items == expected.items)
        #expect(harness.store.items.contains { $0.contentKey == "text:newcomer" } == false)
    }

    @Test func configuredLimitIsAppliedAcrossBaselineAndReplay() async {
        let limit = 100
        let baseline = (0..<(limit + 5)).map { HistoryRestoreFixture.textItem("item-\($0)") }
        let captured = (0..<3).map { HistoryRestoreFixture.textItem("new-\($0)") }
        let harness = HistoryRestoreHarness(outcomes: [.success(baseline)], limit: limit)
        defer { harness.cleanUp() }

        await harness.beginRestoring()
        for item in captured {
            harness.store.add(item)
        }
        await harness.finishRestoring()

        // Replay against the already-enforced baseline, item by item, is the
        // definition of "ordinary sequential insertion".
        var expected = ClipboardHistoryPolicy
            .enforcingLimits(on: baseline, limit: limit)
            .items
        for item in captured {
            expected = ClipboardHistoryPolicy.adding(item, to: expected, limit: limit).items
        }
        #expect(harness.store.items == expected)
        #expect(harness.store.items.count == limit)
    }

    @Test func unpinnedImageBoundIsAppliedDuringBaselineAndReplay() async {
        // The policy evaluates an insertion's head first, so an arriving image
        // is never itself rejected by the image bound — the bound trims later
        // candidates. The baseline is therefore where it bites, and replay
        // must reproduce exactly that.
        let baseline = (0..<101).map { imageReference(id: $0) }
        let arrival = imageReference(id: 101)
        let harness = HistoryRestoreHarness(outcomes: [.success(baseline)])
        defer { harness.cleanUp() }

        await harness.beginRestoring()
        harness.store.add(arrival)
        await harness.finishRestoring()

        let enforced = ClipboardHistoryPolicy
            .enforcingLimits(on: baseline, limit: harness.settings.historyLimit)
        #expect(enforced.items.count == 100, "the image bound trims the baseline itself")
        let expected = ClipboardHistoryPolicy
            .adding(arrival, to: enforced.items, limit: harness.settings.historyLimit)
            .items
        #expect(harness.store.items == expected, "replay matches the policy exactly")
        #expect(harness.store.items.first?.contentKey == arrival.contentKey)
        #expect(
            harness.store.items.contains { $0.contentKey == baseline[baseline.count - 1].contentKey } == false,
            "the oldest baseline image is what the bound gives up"
        )
    }

    // MARK: - 3.7 Arrival order, not timestamps

    @Test func contradictoryTimestampsAndMixedKindsStillReplayInArrivalOrder() async throws {
        let harness = HistoryRestoreHarness(outcomes: [.success([])])
        defer { harness.cleanUp() }
        // A is newest by time but arrives first; C is oldest by time but last.
        // First is newest by time but arrives first; Last is oldest by time
        // but arrives last.
        let first = HistoryRestoreFixture.textItem("A", createdAt: Date(timeIntervalSince1970: 3_000))
        let media = PreparedMedia(hashing: Data(repeating: 0x77, count: 64))
        let middle = HistoryRestoreFixture.imageItem(media: media, createdAt: Date(timeIntervalSince1970: 1_000))
        let last = HistoryRestoreFixture.textItem("C", createdAt: Date(timeIntervalSince1970: 2_000))

        await harness.beginRestoring()
        harness.store.add(first)
        harness.store.add(middle)
        harness.store.add(last)
        await harness.finishRestoring()

        #expect(harness.store.items.map(\.id) == [last.id, middle.id, first.id], "Store arrival order decides replay")
        let timestamps = harness.store.items.map(\.createdAt)
        #expect(timestamps != timestamps.sorted(by: >), "the fixture is deliberately contradictory")
        #expect(harness.store.items.map(\.kind) == [.text, .image, .text])
    }

    // MARK: - 3.8 Failure is an empty baseline

    @Test func failureReplaysBufferedCapturesAndSavesOnce() async {
        let harness = HistoryRestoreHarness(outcomes: [.failure])
        defer { harness.cleanUp() }

        await harness.beginRestoring()
        harness.store.add(HistoryRestoreFixture.textItem("A"))
        harness.store.add(HistoryRestoreFixture.textItem("B"))
        await harness.finishRestoring()

        #expect(harness.store.items.map(\.textValue) == ["B", "A"])
        #expect(harness.saves.count == 1, "buffered captures still commit once against an empty baseline")
        #expect(harness.store.restoreState == .ready, "failure never leaves an infinite loading state")
    }

    @Test func failureWithoutMutationWritesNoReplacementManifest() async {
        let harness = HistoryRestoreHarness(outcomes: [.failure])
        defer { harness.cleanUp() }

        await harness.beginRestoring()
        await harness.finishRestoring()

        #expect(harness.store.items.isEmpty)
        #expect(harness.saves.count == 0, "the failure itself requests no save")
        #expect(harness.store.restoreState == .ready)
    }

    // MARK: - 3.9 Settings and query changes during suspension

    @Test func currentNormalizedLimitWinsOverTheSuspendedOne() async {
        let harness = HistoryRestoreHarness(outcomes: [.success(newestFirstBaseline(count: 150))], limit: 500)
        defer { harness.cleanUp() }

        await harness.beginRestoring()
        // 250 normalizes down to 100; completion must use the normalized value.
        harness.settings.historyLimit = 250
        harness.settings.historyLimit = 100
        await harness.finishRestoring()

        #expect(harness.settings.historyLimit == 100)
        #expect(harness.store.items.count == 100)
        #expect(harness.saves.count == 1)
    }

    @Test func queuedLimitEnforcementCausesNoRedundantTrimSave() async {
        let harness = HistoryRestoreHarness(outcomes: [.success(newestFirstBaseline(count: 101))], limit: 100)
        defer { harness.cleanUp() }

        await harness.beginRestoring()
        let enforcementsBefore = harness.historyEnforcementCount
        harness.settings.historyLimit = 100
        await harness.finishRestoring()
        #expect(harness.saves.count == 1)

        // The settings sink defers enforcement to a later main-actor turn.
        // Awaiting that real turn proves it adds no second save.
        await harness.awaitHistoryEnforcement(after: enforcementsBefore)

        #expect(harness.saves.count == 1, "an already-enforced limit saves nothing more")
        #expect(harness.store.items.count == 100)
    }

    @Test func currentSearchAndPinboardSelectionFilterCompletedHistory() async {
        let saved = [
            HistoryRestoreFixture.textItem("alpha"),
            HistoryRestoreFixture.textItem("beta", pinboardName: "Work")
        ]
        let harness = HistoryRestoreHarness(outcomes: [.success(saved)])
        defer { harness.cleanUp() }

        await harness.beginRestoring()
        harness.store.searchText = "alpha"
        harness.store.selectedBoardID = Pinboard.all.id
        harness.store.add(HistoryRestoreFixture.textItem("alpha again"))
        await harness.finishRestoring()

        #expect(harness.store.items.count == 3, "the current query does not truncate restored history")
        #expect(harness.store.filteredItems.map(\.textValue) == ["alpha again", "alpha"])

        // The completed history is filtered by current filter AND query.
        harness.store.selectedBoardID = Pinboard.custom("Work").id
        #expect(
            harness.store.filteredItems.map(\.textValue) == [],
            "the active query still applies on top of the current pinboard filter"
        )
        harness.store.searchText = ""
        #expect(harness.store.filteredItems.map(\.textValue) == ["beta"], "the current filter applies immediately")
    }

    // MARK: - 3.10 Selection-driven enrichment

    @Test func transientBaselineSelectionStartsNoRequestAndEagerInsertionStillWorks() async {
        let baselineURL = HistoryRestoreFixture.urlItem("https://baseline.example")
        let capturedURL = HistoryRestoreFixture.urlItem("https://captured.example")
        let harness = HistoryRestoreHarness(outcomes: [.success([baselineURL])])
        defer { harness.cleanUp() }

        harness.store.panelDidOpen()
        await harness.beginRestoring()
        harness.store.add(capturedURL)
        #expect(harness.metadataRequests.absoluteStrings.isEmpty, "a buffered arrival registers no metadata")

        await harness.finishRestoring()

        #expect(harness.store.selectedID == capturedURL.id)
        // The loader runs in a spawned task, so gate on the request reaching
        // it and on its completion rather than assuming either has run.
        await harness.awaitMetadataRequest(1)
        await harness.awaitMetadataCompletion(1)
        #expect(
            harness.metadataRequests.absoluteStrings == ["https://captured.example"],
            "only the eagerly inserted URL is enriched"
        )
        #expect(
            harness.metadataRequests.absoluteStrings.contains("https://baseline.example") == false,
            "installing the transient baseline selection starts no selection-driven request"
        )

        // A later, independent metadata save is not counted against bootstrap.
        let savesAfterBootstrap = harness.saves.count
        #expect(savesAfterBootstrap == 1)
        harness.store.applyLinkPreview(itemID: capturedURL.id, title: "Captured", linkImage: nil)
        #expect(
            harness.saves.count == savesAfterBootstrap + 1,
            "later metadata enrichment is its own ordinary save"
        )
    }

    // MARK: - Fixtures

    /// `count` text items in the order a real manifest stores them: newest
    /// first, so array order and policy retention order agree.
    private func newestFirstBaseline(count: Int, pinned: Bool = false) -> [ClipboardItem] {
        (0..<count).map { offset in
            HistoryRestoreFixture.textItem("item-\(count - 1 - offset)", isPinned: pinned)
        }
    }

    private func imageReference(id: Int) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .image,
            title: "Image \(id)",
            preview: "Image \(id)",
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(id)),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: nil,
            imageBlobID: String(format: "%064x", id)
        )
    }
}
