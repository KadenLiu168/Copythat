@testable import Copythat
import AppKit
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct StoreLinkPreviewRemovalTests {
    private let defaults = LinkPreviewFixture.tempDefaults("removal")
    private let recorder = LinkPreviewSaveRecorder()
    private let counter = LinkPreviewCounter()
    private let snapshotData: Data

    init() {
        snapshotData = LinkPreviewFixture.testImage().pngData(maxPixel: 32) ?? Data()
    }

    private func titleOnlyMetadataLoader() -> ClipboardStore.LinkMetadataLoader {
        { _ in LinkPreviewMetadata(title: "Example", image: nil) }
    }

    @Test func oldMetadataCompletionCannotClearReplacementRequest() async {
        let item = LinkPreviewFixture.urlItem(urlString: "https://example.com/")
        let oldGate = LinkPreviewGate()
        let newGate = LinkPreviewGate()
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            fetchLinkMetadata: { _ in
                counter.mark("metadata")
                let attempt = counter.value("metadata")
                await (attempt == 1 ? oldGate : newGate).waitUntilReleased()
                return LinkPreviewMetadata(title: "Current", image: nil)
            },
            fetchLinkSnapshot: { _ in throw URLError(.badServerResponse) }
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }
        store.add(item)
        await counter.waitFor("metadata", reaching: 1)
        store.remove(item)
        store.add(item)
        await counter.waitFor("metadata", reaching: 2)
        oldGate.release()
        await counter.waitFor("handled", reaching: 1)
        #expect(store.metadataTasks[item.id] != nil)
        #expect(store.linkMetadataStates[item.id] == .pending)
        newGate.release()
        await counter.waitFor("handled", reaching: 2)
        #expect(store.items.first?.linkTitle == "Current")
    }

    @Test func pendingMetadataPreservesImageAlreadyApplied() async {
        let item = LinkPreviewFixture.urlItem(urlString: "https://example.com/")
        let gate = LinkPreviewGate()
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            fetchLinkMetadata: LinkPreviewMetadataScript.gated(gate, then: .titleOnly("Fresh"))
                .loader(counter: counter, key: "pending"),
            fetchLinkSnapshot: { _ in throw URLError(.badServerResponse) }
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }
        store.add(item)
        await counter.waitFor("metadata:pending", reaching: 1)
        store.applyLinkPreview(itemID: item.id, title: "Existing", linkImage: PreparedMedia(hashing: snapshotData))
        gate.release()
        await counter.waitFor("handled", reaching: 1)
        #expect(store.items.first?.linkImageData == snapshotData)
        #expect(store.linkMetadataStates[item.id] == .successWithImage)
    }

    // Case 6: delete cancels pending metadata; the late title is discarded.
    @Test func deleteCancelsPendingMetadataAndDiscardsLateResult() async throws {
        let url = "https://example.com/"
        let item = LinkPreviewFixture.urlItem(urlString: url)
        let gate = LinkPreviewGate()
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            fetchLinkMetadata: LinkPreviewMetadataScript
                .lateAfterCancel(gate, then: .titleOnly("Late Title"))
                .loader(counter: counter, key: url),
            fetchLinkSnapshot: { _ in throw URLError(.badServerResponse) }
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }

        store.add(item)
        await counter.waitFor("metadata:\(url)", reaching: 1)
        store.remove(item)
        let savesAfterRemoval = recorder.count
        gate.release()
        await counter.waitFor("handled", reaching: 1)

        #expect(counter.value("metadata:\(url)") == 1)
        #expect(store.items.isEmpty)
        #expect(store.linkMetadataStates[item.id] == nil)
        #expect(recorder.count == savesAfterRemoval)
        #expect(recorder.recordedSaves().allSatisfy { saves in
            saves.first { $0.id == item.id }?.linkTitle == nil
        })
    }

    // Case 6: Clear History cleans removed items, retained pinned items keep
    // working under the current selection.
    @Test func clearHistoryRetainsPinnedWorkAndCleansRemoved() async throws {
        let removedURL = "https://removed.example.com/"
        let pinnedURL = "https://pinned.example.com/"
        let removed = LinkPreviewFixture.urlItem(urlString: removedURL)
        let pinned = LinkPreviewFixture.urlItem(urlString: pinnedURL, isPinned: true)
        let gate = LinkPreviewGate()
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [removed, pinned],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            fetchLinkMetadata: { url in
                counter.begin("metadata:\(url.absoluteString)")
                defer { counter.end("metadata:\(url.absoluteString)") }
                if url.absoluteString == removedURL {
                    return try await LinkPreviewMetadataScript
                        .lateAfterCancel(gate, then: .titleOnly("Late"))
                        .evaluate(counter: counter, key: removedURL)
                }
                return LinkPreviewMetadata(title: "Pinned", image: nil)
            },
            fetchLinkSnapshot: { url in
                counter.begin("snapshot:\(url.absoluteString)")
                defer { counter.end("snapshot:\(url.absoluteString)") }
                return PreparedMedia(hashing: snapshotData)
            }
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }

        store.panelDidOpen()
        await counter.waitFor("metadata:\(removedURL)", reaching: 1)
        #expect(store.clearHistory(includePinnedAndPinboardItems: false) == 1)
        await counter.waitFor("handled", reaching: 2)
        gate.release()
        await counter.waitFor("handled", reaching: 3)

        #expect(store.items.map(\.id) == [pinned.id])
        #expect(counter.value("metadata:\(removedURL)") == 1)
        #expect(counter.value("snapshot:\(pinnedURL)") == 1)
        #expect(counter.value("metadata:\(pinnedURL)") == 1)

        let savedPinned = recorder.last?.first { $0.id == pinned.id }
        #expect(savedPinned?.linkTitle == "Pinned")
        #expect(savedPinned?.linkImageData != nil)
    }

    @Test(arguments: ["delete", "partial-clear", "full-clear", "eviction"])
    func removalCancelsPendingSnapshotWithoutSavingLateImage(operation: String) async {
        let item = LinkPreviewFixture.urlItem(urlString: "https://removed.example.com/")
        let pinned = LinkPreviewFixture.urlItem(
            urlString: "https://pinned.example.com/", linkImageData: snapshotData, isPinned: true
        )
        let fillers = (0..<98).map { LinkPreviewFixture.textItem(text: "filler \($0)") }
        let gate = LinkPreviewGate()
        defaults.set(100, forKey: "historyLimit")
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [pinned] + fillers + [item],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            fetchLinkMetadata: { _ in LinkPreviewMetadata(title: nil, image: nil) },
            fetchLinkSnapshot: LinkPreviewSnapshotScript.lateAfterCancel(gate, then: .image(snapshotData))
                .loader(counter: counter, key: "removed")
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }
        store.panelDidOpen()
        store.select(item)
        await counter.waitFor("snapshot:removed", reaching: 1)
        switch operation {
        case "delete": store.remove(item)
        case "partial-clear": #expect(store.clearHistory(includePinnedAndPinboardItems: false) == 99)
        case "full-clear": #expect(store.clearHistory(includePinnedAndPinboardItems: true) == 100)
        default: store.add(LinkPreviewFixture.textItem(text: "new item evicts last URL"))
        }
        #expect(store.items.contains { $0.id == item.id } == false)
        #expect(store.linkMetadataStates[item.id] == nil)
        #expect(store.activeFallback?.isCancelled == true)
        let savesBeforeLateResult = recorder.count
        gate.release()
        await counter.waitFor("handled", reaching: 2)
        #expect(recorder.count == savesBeforeLateResult)
        #expect(store.snapshotPositiveCache.isEmpty)
        #expect(store.snapshotNegativeUntil.isEmpty)
        #expect(store.items.contains { $0.id == pinned.id } == (operation != "full-clear"))
    }

    // Case 7: a fully pinned history evicts the freshly inserted URL itself,
    // which must not start metadata.
    @Test func evictedInsertedItemDoesNotStartMetadata() async throws {
        let limitDefaults = LinkPreviewFixture.tempDefaults("eviction")
        limitDefaults.set(100, forKey: "historyLimit")
        var pinnedItems: [ClipboardItem] = []
        for index in 0..<100 {
            pinnedItems.append(
                LinkPreviewFixture.textItem(
                    id: UUID(),
                    text: "Pinned history filler \(index)"
                )
            )
        }
        for index in pinnedItems.indices {
            pinnedItems[index].isPinned = true
        }
        let urlItem = LinkPreviewFixture.urlItem(urlString: "https://evicted.example.com/")
        let metadataCounterCalls = counter
        let store = ClipboardStore(
            settings: AppSettings(defaults: limitDefaults),
            sourceTracker: CopySourceTracker(),
            initialItems: pinnedItems,
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            fetchLinkMetadata: { url in
                metadataCounterCalls.mark("metadata:\(url.absoluteString)")
                return LinkPreviewMetadata(title: "Example", image: nil)
            },
            fetchLinkSnapshot: { _ in throw URLError(.badServerResponse) }
        )

        store.add(urlItem)

        #expect(store.items.count == 100)
        #expect(store.items.contains { $0.id == urlItem.id } == false)
        #expect(store.selectedID == pinnedItems.first?.id, "a discarded incoming item must not become selected")
        #expect(counter.value("metadata:https://evicted.example.com/") == 0)
    }

    @Test func directLimitReductionCancelsEvictedMetadataAndKeepsRetainedWork() async {
        let evictedURL = "https://evicted-limit.example.com/"
        let keptURL = "https://kept-limit.example.com/"
        let evicted = LinkPreviewFixture.urlItem(urlString: evictedURL)
        let kept = LinkPreviewFixture.urlItem(urlString: keptURL)
        let fillers = (0..<198).map { LinkPreviewFixture.textItem(text: "limit metadata filler \($0)") }
        let evictedGate = LinkPreviewGate()
        let keptGate = LinkPreviewGate()
        let limitDefaults = LinkPreviewFixture.tempDefaults("limit-metadata")
        limitDefaults.set(200, forKey: "historyLimit")
        let settings = AppSettings(defaults: limitDefaults)
        let store = ClipboardStore(
            settings: settings,
            sourceTracker: CopySourceTracker(),
            initialItems: [kept] + fillers + [evicted],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            fetchLinkMetadata: { url in
                counter.mark("limit-metadata:\(url.absoluteString)")
                if url.absoluteString == evictedURL {
                    await evictedGate.waitOrCancelled()
                } else {
                    await keptGate.waitOrCancelled()
                }
                return LinkPreviewMetadata(title: "Title", image: nil)
            },
            fetchLinkSnapshot: { _ in throw URLError(.badServerResponse) }
        )
        store.linkPreviewHandledObserver = { counter.mark("limit-metadata-handled") }

        store.panelDidOpen()
        await counter.waitFor("limit-metadata:\(keptURL)", reaching: 1)
        store.select(evicted)
        await counter.waitFor("limit-metadata:\(evictedURL)", reaching: 1)

        let savesBeforeReduction = recorder.count
        settings.historyLimit = 100
        await waitForHistoryLimitEnforcement()

        #expect(!store.items.contains { $0.id == evicted.id })
        #expect(store.items.count == 100)
        #expect(store.metadataTasks[evicted.id] == nil)
        #expect(store.linkMetadataStates[evicted.id] == nil)
        #expect(store.metadataTasks[kept.id] != nil)
        #expect(store.linkMetadataStates[kept.id] == .pending)
        #expect(recorder.count == savesBeforeReduction + 1, "the trim itself requests one save")

        let savesAfterTrim = recorder.count
        evictedGate.release()
        await counter.waitFor("limit-metadata-handled", reaching: 1)
        #expect(recorder.count == savesAfterTrim, "a late evicted metadata result must not save")

        keptGate.release()
        await counter.waitFor("limit-metadata-handled", reaching: 2)
        #expect(store.items.first { $0.id == kept.id }?.linkTitle == "Title")
        #expect(recorder.count == savesAfterTrim + 1, "retained metadata still applies")
    }

    @Test func directLimitReductionCancelsPendingFallbackWithoutLateSave() async {
        let evictedURL = "https://evicted-fallback.example.com/"
        let evicted = LinkPreviewFixture.urlItem(urlString: evictedURL)
        let kept = LinkPreviewFixture.textItem(text: "fallback kept head")
        let fillers = (0..<198).map { LinkPreviewFixture.textItem(text: "limit fallback filler \($0)") }
        let gate = LinkPreviewGate()
        let limitDefaults = LinkPreviewFixture.tempDefaults("limit-fallback")
        limitDefaults.set(200, forKey: "historyLimit")
        let settings = AppSettings(defaults: limitDefaults)
        let store = ClipboardStore(
            settings: settings,
            sourceTracker: CopySourceTracker(),
            initialItems: [kept] + fillers + [evicted],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            fetchLinkMetadata: { url in
                counter.mark("limit-fallback-metadata:\(url.absoluteString)")
                return LinkPreviewMetadata(title: "Title", image: nil)
            },
            fetchLinkSnapshot: LinkPreviewSnapshotScript.lateAfterCancel(gate, then: .image(snapshotData))
                .loader(counter: counter, key: "limit-fallback")
        )
        store.linkPreviewHandledObserver = { counter.mark("limit-fallback-handled") }

        store.panelDidOpen()
        store.select(evicted)
        await counter.waitFor("limit-fallback-metadata:\(evictedURL)", reaching: 1)
        await counter.waitFor("snapshot:limit-fallback", reaching: 1)

        let savesBeforeReduction = recorder.count
        settings.historyLimit = 100
        await waitForHistoryLimitEnforcement()

        #expect(!store.items.contains { $0.id == evicted.id })
        #expect(store.activeFallback?.isCancelled == true)
        #expect(recorder.count == savesBeforeReduction + 1, "the trim itself requests one save")

        let savesAfterTrim = recorder.count
        gate.release()
        await counter.waitFor("limit-fallback-handled", reaching: 1)
        #expect(recorder.count == savesAfterTrim, "a late evicted snapshot must not save")
        #expect(store.snapshotPositiveCache.isEmpty)
    }

    private func waitForHistoryLimitEnforcement() async {
        await Task.yield()
        await Task.yield()
    }

    // Case 7: a plain duplicate keeps the existing item ID and its in-flight
    // metadata task, which still lands on the same item.
    @Test func plainDuplicateKeepsExistingIDAndOngoingMetadata() async throws {
        let url = "https://example.com/"
        let item = LinkPreviewFixture.urlItem(urlString: url)
        let gate = LinkPreviewGate()
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            fetchLinkMetadata: LinkPreviewMetadataScript
                .gated(gate, then: .titleOnly("Example"))
                .loader(counter: counter, key: url),
            fetchLinkSnapshot: { _ in throw URLError(.badServerResponse) }
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }

        store.add(item)
        await counter.waitFor("metadata:\(url)", reaching: 1)
        let duplicate = LinkPreviewFixture.urlItem(urlString: url)
        store.add(duplicate)

        #expect(store.items.count == 1)
        #expect(store.items.first?.id == item.id)
        #expect(store.selectedID == item.id, "a moved duplicate keeps the existing entry selected")
        #expect(counter.value("metadata:\(url)") == 1)

        gate.release()
        await counter.waitFor("handled", reaching: 1)
        #expect(recorder.last?.first { $0.id == item.id }?.linkTitle == "Example")
        #expect(store.items.first?.id == item.id)
    }

    // 6.3: releasing the Store cancels pending preview work without a save.
    @Test func releasingStoreCancelsPendingWorkWithoutSaving() async throws {
        let url = "https://example.com/"
        let item = LinkPreviewFixture.urlItem(urlString: url)
        let gate = LinkPreviewGate()
        var store: ClipboardStore? = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            fetchLinkMetadata: LinkPreviewMetadataScript
                .gated(gate, then: .titleOnly("Late"))
                .loader(counter: counter, key: url),
            fetchLinkSnapshot: { _ in throw URLError(.badServerResponse) }
        )

        weak var weakStore: ClipboardStore?
        weakStore = store
        store?.add(item)
        await counter.waitFor("metadata:\(url)", reaching: 1)

        let savesBeforeRelease = recorder.count
        store = nil
        await counter.waitFor("cancelled:\(url)", reaching: 1)

        #expect(weakStore == nil)
        #expect(recorder.count == savesBeforeRelease)
    }
}
