@testable import Copythat
import AppKit
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct StoreLinkPreviewOrchestrationTests {
    private let defaults = LinkPreviewFixture.tempDefaults("orchestration")
    private let recorder = LinkPreviewSaveRecorder()
    private let counter = LinkPreviewCounter()
    private let snapshotData: Data

    init() {
        snapshotData = LinkPreviewFixture.testImage().pngData(maxPixel: 32) ?? Data()
    }

    private func makeStore(
        items: [ClipboardItem] = [],
        metadata: LinkPreviewMetadataScript,
        snapshot: LinkPreviewSnapshotScript,
        clock: LinkPreviewClock? = nil
    ) -> ClipboardStore {
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: items,
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            uptimeProvider: { clock?.now ?? 100 },
            fetchLinkMetadata: metadata.loader(counter: counter, key: "all"),
            fetchLinkSnapshot: snapshot.loader(counter: counter, key: "all")
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }
        return store
    }

    // Case 1: closed panel add URL; metadata title-only success.
    @Test func closedPanelAddURLMetadataTitleOnlyNeverSnapshots() async throws {
        let url = "https://example.com/"
        let item = LinkPreviewFixture.urlItem(urlString: url)
        let store = makeStore(metadata: .titleOnly("Example Domain"), snapshot: .image(snapshotData))

        store.add(item)

        await counter.waitForEnd("metadata:all", reaching: 1)
        await recorder.waitForSaveCount(2)
        await counter.waitFor("handled", reaching: 1)

        #expect(counter.value("metadata:all") == 1)
        #expect(counter.value("snapshot:all") == 0)
        #expect(recorder.last?.first { $0.id == item.id }?.linkTitle == "Example Domain")

        store.searchText = "example domain"
        #expect(store.filteredItems.map(\.id) == [item.id])
    }

    // Case 2: metadata supplies an image; opening the panel never snapshots.
    @Test func metadataImageAppliesAndPanelOpenNeverSnapshots() async throws {
        let url = "https://example.com/"
        let item = LinkPreviewFixture.urlItem(urlString: url)
        let store = makeStore(metadata: .image(snapshotData), snapshot: .image(snapshotData))

        store.add(item)
        await recorder.waitForSaveCount(2)
        await counter.waitFor("handled", reaching: 1)

        #expect(counter.value("snapshot:all") == 0)
        #expect(store.linkMetadataStates[item.id] == .successWithImage)

        store.panelDidOpen()
        #expect(counter.value("snapshot:all") == 0)
        let saved = recorder.last?.first { $0.id == item.id }
        #expect(saved?.linkImageData != nil)
    }

    // Case 3: fallback starts only for the selected visible eligible URL.
    @Test func fallbackRunsForSelectedVisibleEligibleURLOnly() async throws {
        let alpha = LinkPreviewFixture.urlItem(urlString: "https://alpha.example.com/")
        let beta = LinkPreviewFixture.urlItem(urlString: "https://beta.example.com/")
        let store = makeStore(items: [alpha, beta], metadata: .titleOnly("Example"), snapshot: .image(snapshotData))

        store.panelDidOpen()
        await counter.waitFor("handled", reaching: 2)
        #expect(counter.value("snapshot:all") == 1)
        #expect(store.selectedID == alpha.id)

        store.select(beta)
        await counter.waitFor("handled", reaching: 4)

        #expect(counter.value("metadata:all") == 2)
        #expect(counter.value("snapshot:all") == 2)
        #expect(counter.peakConcurrency() == 1)
        let saved = recorder.last?.first { $0.id == beta.id }
        #expect(saved?.linkImageData != nil)
    }

    // Case 3: search filtering cancels the filtered-out item's fallback.
    @Test func searchFilteringCancelsFilteredOutFallback() async throws {
        let alpha = LinkPreviewFixture.urlItem(urlString: "https://alpha.example.com/")
        let beta = LinkPreviewFixture.urlItem(urlString: "https://beta.example.com/")
        let alphaGate = LinkPreviewGate()
        let betaGate = LinkPreviewGate()
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [alpha, beta],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            fetchLinkMetadata: { _ in
                LinkPreviewMetadata(title: "Example", image: nil)
            },
            fetchLinkSnapshot: { url in
                counter.begin("snapshot:\(url.absoluteString)")
                defer { counter.end("snapshot:\(url.absoluteString)") }
                let gate = url.absoluteString.contains("alpha") ? alphaGate : betaGate
                return try await LinkPreviewSnapshotScript
                    .gated(gate, then: .image(snapshotData))
                    .evaluate(counter: counter, key: url.absoluteString)
            }
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }

        store.panelDidOpen()
        await counter.waitFor("handled", reaching: 1)
        store.select(beta)
        await counter.waitFor("snapshot:https://beta.example.com/", reaching: 1)

        store.searchText = "alpha"
        await counter.waitFor("cancelled:https://beta.example.com/", reaching: 1)

        // Selection falls back to alpha, whose fallback restarts; release it and
        // the late result for the cancelled beta request must not apply.
        alphaGate.release()
        await counter.waitFor("snapshot:https://alpha.example.com/", reaching: 2)
        await counter.waitFor("handled", reaching: 5)

        let savedBeta = recorder.recordedSaves().last?.first { $0.id == beta.id }
        #expect(savedBeta?.linkImageData == nil)
        let savedAlpha = recorder.recordedSaves().last?.first { $0.id == alpha.id }
        #expect(savedAlpha?.linkImageData != nil)
        #expect(store.searchText == "alpha")
    }

    @Test func pinboardFilterAndAssignmentCancelIneligibleFallback() async {
        let item = LinkPreviewFixture.urlItem(urlString: "https://example.com/", pinboardName: "Research")
        let gate = LinkPreviewGate()
        let store = makeStore(
            items: [item], metadata: .empty, snapshot: .lateAfterCancel(gate, then: .image(snapshotData))
        )
        store.selectedBoardID = Pinboard.custom("Research").id
        store.panelDidOpen()
        await counter.waitFor("snapshot:all", reaching: 1)
        store.move(item, toPinboard: "Other")
        #expect(store.filteredItems.isEmpty)
        #expect(store.selectedID == nil)
        #expect(store.activeFallback?.isCancelled == true)
        let savesBeforeLateResult = recorder.count
        gate.release()
        await counter.waitFor("handled", reaching: 2)
        #expect(recorder.count == savesBeforeLateResult)
        #expect(store.items.first?.linkImageData == nil)
        #expect(store.snapshotPositiveCache.isEmpty)
    }

    // Case 3: pending metadata never authorizes fallback.
    @Test func pendingMetadataDoesNotAuthorizeFallbackUntilNoImageOutcome() async throws {
        let url = "https://example.com/"
        let item = LinkPreviewFixture.urlItem(urlString: url)
        let metadataGate = LinkPreviewGate()
        let snapshotGate = LinkPreviewGate()
        let store = makeStore(
            metadata: .gated(metadataGate, then: .titleOnly("Example")),
            snapshot: .gated(snapshotGate, then: .image(snapshotData))
        )

        store.add(item)
        store.panelDidOpen()
        #expect(counter.value("snapshot:all") == 0)

        metadataGate.release()
        await counter.waitFor("handled", reaching: 1)
        await counter.waitFor("snapshot:all", reaching: 1)
        snapshotGate.release()
        await counter.waitFor("handled", reaching: 2)
        await recorder.waitForSaveCount(3)

        #expect(counter.value("metadata:all") == 1)
        #expect(counter.value("snapshot:all") == 1)
        let saved = recorder.last?.first { $0.id == item.id }
        #expect(saved?.linkImageData != nil)
    }

    // Case 3: an empty selection (no visible item) authorizes nothing.
    @Test func emptyFilteredSelectionAuthorizesNoFallback() async throws {
        let alpha = LinkPreviewFixture.urlItem(urlString: "https://alpha.example.com/")
        let store = makeStore(items: [alpha], metadata: .titleOnly("Example"), snapshot: .image(snapshotData))

        store.panelDidOpen()
        await counter.waitFor("handled", reaching: 2)
        #expect(counter.value("snapshot:all") == 1)

        store.searchText = "nomatch"
        #expect(store.filteredItems.isEmpty)
        #expect(store.selectedID == nil)
        #expect(counter.value("snapshot:all") == 1)
    }
}

@MainActor
final class LinkPreviewClock {
    var now: TimeInterval = 100
}
