@testable import Copythat
import AppKit
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct StoreLinkPreviewCancellationTests {
    private let defaults = LinkPreviewFixture.tempDefaults("cancel")
    private let recorder = LinkPreviewSaveRecorder()
    private let counter = LinkPreviewCounter()
    private let snapshotData: Data

    init() {
        snapshotData = LinkPreviewFixture.testImage().pngData(maxPixel: 32) ?? Data()
    }

    private func makeURLItem(_ urlString: String) -> ClipboardItem {
        LinkPreviewFixture.urlItem(urlString: urlString)
    }

    // Case 4: close during fallback cancels work; reopen retries because
    // cancellation never writes the negative cache.
    @Test func closeCancelsFallbackAndReopenRetries() async throws {
        let url = "https://example.com/"
        let item = makeURLItem(url)
        let gate = LinkPreviewGate()
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [item],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            fetchLinkMetadata: { _ in LinkPreviewMetadata(title: "Example", image: nil) },
            fetchLinkSnapshot: LinkPreviewSnapshotScript
                .gated(gate, then: .image(snapshotData))
                .loader(counter: counter, key: url)
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }

        store.panelDidOpen()
        await counter.waitFor("snapshot:\(url)", reaching: 1)
        store.panelDidClose()
        await counter.waitFor("cancelled:\(url)", reaching: 1)

        // Reopen starts a fresh attempt: cancellation is not a failure entry.
        store.panelDidOpen()
        await counter.waitFor("snapshot:\(url)", reaching: 2)
        gate.release()
        await counter.waitFor("handled", reaching: 3)

        #expect(counter.value("snapshot:\(url)") == 2)
        let saved = recorder.last?.first { $0.id == item.id }
        #expect(saved?.linkImageData != nil)
        #expect(counter.peakConcurrency() == 1)
    }

    // Case 4: a deliberately late result after close is discarded entirely.
    @Test func lateResultAfterCloseIsDiscarded() async throws {
        let url = "https://example.com/"
        let item = makeURLItem(url)
        let gate = LinkPreviewGate()
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [item],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            fetchLinkMetadata: { _ in LinkPreviewMetadata(title: "Example", image: nil) },
            fetchLinkSnapshot: LinkPreviewSnapshotScript
                .lateAfterCancel(gate, then: .image(snapshotData))
                .loader(counter: counter, key: url)
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }

        store.panelDidOpen()
        await counter.waitFor("snapshot:\(url)", reaching: 1)
        store.panelDidClose()
        gate.release()
        await counter.waitFor("handled", reaching: 2)

        let baselineSaves = recorder.count
        #expect(recorder.recordedSaves().last?.first { $0.id == item.id }?.linkImageData == nil)

        // Reopen starts attempt #2 (the late image was not cached) and applies.
        store.panelDidOpen()
        await counter.waitFor("snapshot:\(url)", reaching: 2)
        await counter.waitFor("handled", reaching: 3)
        await recorder.waitForSaveCount(baselineSaves + 1)

        #expect(counter.value("snapshot:\(url)") == 2)
        #expect(recorder.last?.first { $0.id == item.id }?.linkImageData != nil)
    }

    // Old A must not apply when eligibility returns before its cleanup ends.
    @Test(arguments: [false, true])
    func roundTripDiscardsOldResultAndWaitsForCleanup(closePanel: Bool) async {
        let alphaURL = "https://alpha.example.com/"
        let alpha = makeURLItem(alphaURL)
        let beta = makeURLItem("https://beta.example.com/")
        let oldGate = LinkPreviewGate()
        let newGate = LinkPreviewGate()
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [alpha, beta],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            fetchLinkMetadata: { _ in LinkPreviewMetadata(title: "Example", image: nil) },
            fetchLinkSnapshot: { url in
                counter.begin("snapshot:\(url.absoluteString)")
                defer { counter.end("snapshot:\(url.absoluteString)") }
                let attempt = counter.value("snapshot:\(alphaURL)")
                await (attempt == 1 ? oldGate : newGate).waitUntilReleased()
                return PreparedMedia(hashing: snapshotData)
            }
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }
        store.panelDidOpen()
        await counter.waitFor("snapshot:\(alphaURL)", reaching: 1)
        let baselineSaves = recorder.count
        if closePanel {
            store.panelDidClose()
            store.panelDidOpen()
        } else {
            store.select(beta)
            store.select(alpha)
        }
        #expect(counter.value("snapshot:\(alphaURL)") == 1)
        oldGate.release()
        await counter.waitFor("snapshot:\(alphaURL)", reaching: 2)
        #expect(store.items.first?.linkImageData == nil)
        #expect(store.snapshotPositiveCache.isEmpty)
        #expect(store.snapshotNegativeUntil.isEmpty)
        #expect(counter.value("snapshot:https://beta.example.com/") == 0)
        // Lazy B metadata can save its title; no old snapshot may save media.
        #expect(recorder.recordedSaves().dropFirst(baselineSaves).allSatisfy {
            $0.allSatisfy { $0.linkImageData == nil }
        })
        let savesBeforeNewResult = recorder.count
        newGate.release()
        await counter.waitForEnd("snapshot:\(alphaURL)", reaching: 2)
        await recorder.waitForSaveCount(savesBeforeNewResult + 1)
        #expect(store.items.first?.linkImageData != nil)
        #expect(counter.peakConcurrency() == 1)
    }

    @Test func imageAppliedDuringFallbackCancelsWorkAndDiscardsLateResult() async {
        let item = makeURLItem("https://example.com/")
        let gate = LinkPreviewGate()
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [item],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            fetchLinkMetadata: { _ in LinkPreviewMetadata(title: "Example", image: nil) },
            fetchLinkSnapshot: LinkPreviewSnapshotScript.lateAfterCancel(gate, then: .image(snapshotData))
                .loader(counter: counter, key: "pending")
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }
        store.panelDidOpen()
        await counter.waitFor("snapshot:pending", reaching: 1)
        store.applyLinkPreview(itemID: item.id, title: "Existing", linkImage: PreparedMedia(hashing: snapshotData))
        #expect(store.activeFallback?.isCancelled == true)
        let savesBeforeLateResult = recorder.count
        gate.release()
        await counter.waitFor("handled", reaching: 2)
        #expect(recorder.count == savesBeforeLateResult)
        #expect(store.snapshotPositiveCache.isEmpty)
        #expect(store.snapshotNegativeUntil.isEmpty)
        #expect(store.items.first?.linkTitle == "Existing")
    }

    // Case 5: A active, cleanup blocks; B then C chosen; only C starts after release.
    @Test func cleanupHandoffSkipsSupersededTargets() async throws {
        let urlA = "https://a.example.com/"
        let urlB = "https://b.example.com/"
        let urlC = "https://c.example.com/"
        let itemA = makeURLItem(urlA)
        let itemB = makeURLItem(urlB)
        let itemC = makeURLItem(urlC)
        let cancelGate = LinkPreviewGate()
        let cleanupGate = LinkPreviewGate()
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [itemA, itemB, itemC],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            fetchLinkMetadata: { _ in LinkPreviewMetadata(title: "Example", image: nil) },
            fetchLinkSnapshot: { url in
                counter.begin("snapshot:\(url.absoluteString)")
                defer { counter.end("snapshot:\(url.absoluteString)") }
                switch url.absoluteString {
                case urlA:
                    return try await LinkPreviewSnapshotScript.cleanupAfterCancel(
                        cancelGate,
                        cleanupGate,
                        then: .image(snapshotData)
                    ).evaluate(counter: counter, key: urlA)
                default:
                    return try await LinkPreviewSnapshotScript
                        .image(snapshotData)
                        .evaluate(counter: counter, key: url.absoluteString)
                }
            }
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }

        store.panelDidOpen()
        await counter.waitFor("snapshot:\(urlA)", reaching: 1)

        store.select(itemB)
        // Cancellation is requested immediately; cleanup blocks the slot, so
        // neither B nor C may start while A is releasing resources.
        #expect(counter.value("snapshot:\(urlB)") == 0)

        store.select(itemC)
        #expect(counter.value("snapshot:\(urlB)") == 0)
        #expect(counter.value("snapshot:\(urlC)") == 0)

        cleanupGate.release()
        await counter.waitFor("cleanupDone:\(urlA)", reaching: 1)
        await counter.waitFor("snapshot:\(urlC)", reaching: 1)
        await counter.waitFor("handled", reaching: 4)

        #expect(counter.value("snapshot:\(urlB)") == 0)
        #expect(counter.value("snapshot:\(urlC)") == 1)
        #expect(counter.peakConcurrency() == 1)
        let saved = recorder.last?.first { $0.id == itemC.id }
        #expect(saved?.linkImageData != nil)
    }
}
