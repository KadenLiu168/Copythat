@testable import Copythat
import AppKit
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct StoreLinkPreviewCacheTests {
    private let defaults = LinkPreviewFixture.tempDefaults("cache")
    private let recorder = LinkPreviewSaveRecorder()
    private let counter = LinkPreviewCounter()
    private let snapshotData: Data

    init() {
        snapshotData = LinkPreviewFixture.testImage().pngData(maxPixel: 32) ?? Data()
    }

    // Case 8: same absolute URL reuses the session cache; query strings differ.
    @Test func positiveCacheHitDoesNotStartLoaderAndQueryDoesNotShare() async throws {
        let pinnedURL = "https://shared.example.com/"
        let pinned = LinkPreviewFixture.urlItem(urlString: pinnedURL, isPinned: true)
        let fresh = LinkPreviewFixture.urlItem(urlString: pinnedURL)
        let otherQuery = LinkPreviewFixture.urlItem(urlString: "https://shared.example.com/?ref=1")
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [pinned],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            fetchLinkMetadata: { _ in LinkPreviewMetadata(title: "Example", imageData: nil) },
            fetchLinkSnapshot: { _ in
                counter.mark("snapshot:loader")
                return snapshotData
            }
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }

        store.panelDidOpen()
        store.add(fresh)
        await counter.waitFor("handled", reaching: 3)

        #expect(counter.value("snapshot:loader") == 1)
        #expect(store.snapshotPositiveCache[pinnedURL] != nil)

        // The pinned duplicate of the same URL is eligible after lazy metadata
        // and reuses the cached image without a loader. The cache-hit apply
        // saves through applyLinkPreview; a fallback completion never fires.
        let savesAfterFresh = recorder.count
        store.select(pinned)
        await counter.waitFor("handled", reaching: 3)
        await recorder.waitForSaveCount(savesAfterFresh + 1)
        #expect(counter.value("snapshot:loader") == 1)
        let pinnedSaved = recorder.last?.first { $0.id == pinned.id }
        #expect(pinnedSaved?.linkImageData != nil)

        // A different query string is a distinct cache identity.
        store.add(otherQuery)
        await counter.waitFor("snapshot:loader", reaching: 2)
        await counter.waitFor("handled", reaching: 5)
        #expect(counter.value("snapshot:loader") == 2)
        #expect(store.snapshotPositiveCache.count == 2)
    }

    // Case 8: positive cache stays bounded at 64 entries.
    @Test func positiveCacheEvictsEarliestInsertedBeyond64() async throws {
        let firstURL = URL(string: "https://bounded0.example.com/")!
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            fetchLinkMetadata: { _ in LinkPreviewMetadata(title: "Example", imageData: nil) },
            fetchLinkSnapshot: { _ in self.snapshotData }
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }
        store.panelDidOpen()

        var firstItemID: UUID?
        for index in 0..<65 {
            let item = LinkPreviewFixture.urlItem(urlString: "https://bounded\(index).example.com/")
            if index == 0 { firstItemID = item.id }
            store.add(item)
            await counter.waitFor("handled", reaching: (index + 1) * 2)
        }

        #expect(store.snapshotPositiveCache.count == 64)
        #expect(store.snapshotPositiveCache["https://bounded0.example.com/"] == nil)
        #expect(store.snapshotPositiveCache["https://bounded64.example.com/"] != nil)
        #expect(firstItemID != nil)
    }

    // Case 9: failure suppresses retries for 300 seconds of uptime.
    @Test func snapshotFailureSuppressesRetryUntilTTLExpiry() async throws {
        let clock = LinkPreviewClock()
        let url = "https://retry.example.com/"
        let item = LinkPreviewFixture.urlItem(urlString: url)
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [item],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            uptimeProvider: { clock.now },
            fetchLinkMetadata: { _ in LinkPreviewMetadata(title: "Example", imageData: nil) },
            fetchLinkSnapshot: { _ in
                counter.mark("snapshot:attempts")
                throw URLError(.badServerResponse)
            }
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }
        store.panelDidOpen()
        await counter.waitFor("handled", reaching: 2)
        #expect(counter.value("snapshot:attempts") == 1)

        // Reselecting the current item during the suppression window must not
        // start another attempt.
        store.select(item)
        #expect(counter.value("snapshot:attempts") == 1)

        clock.now += 299
        store.select(item)
        #expect(counter.value("snapshot:attempts") == 1)

        clock.now += 1
        store.select(item)
        await counter.waitFor("handled", reaching: 3)
        #expect(counter.value("snapshot:attempts") == 2)
        #expect(store.snapshotNegativeUntil.isEmpty == false)
        #expect(store.snapshotNegativeUntil.isEmpty == false)
    }

    // Case 9: negative cache is bounded at 64 entries.
    @Test func negativeCacheStaysBoundedAt64() async throws {
        let clock = LinkPreviewClock()
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            uptimeProvider: { clock.now },
            fetchLinkMetadata: { _ in LinkPreviewMetadata(title: "Example", imageData: nil) },
            fetchLinkSnapshot: { _ in throw URLError(.badServerResponse) }
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }
        store.panelDidOpen()

        for index in 0..<65 {
            let item = LinkPreviewFixture.urlItem(urlString: "https://failing\(index).example.com/")
            clock.now += 1
            store.add(item)
            await counter.waitFor("handled", reaching: (index + 1) * 2)
        }

        #expect(store.snapshotNegativeUntil.count == 64)
        #expect(store.snapshotNegativeUntil["https://failing0.example.com/"] == nil)
        #expect(store.snapshotNegativeUntil["https://failing64.example.com/"] != nil)
    }

    // Case 10: pending metadata resolving to an image prevents fallback.
    @Test func metadataPendingImageOutcomePreventsFallback() async throws {
        let url = "https://example.com/"
        let item = LinkPreviewFixture.urlItem(urlString: url)
        let metadataGate = LinkPreviewGate()
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [item],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            fetchLinkMetadata: LinkPreviewMetadataScript
                .gated(metadataGate, then: .image(snapshotData))
                .loader(counter: counter, key: url),
            fetchLinkSnapshot: { _ in
                counter.mark("snapshot:loader")
                return self.snapshotData
            }
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }

        store.panelDidOpen()
        #expect(counter.value("snapshot:loader") == 0)

        metadataGate.release()
        await counter.waitFor("handled", reaching: 1)

        #expect(counter.value("metadata:\(url)") == 1)
        #expect(counter.value("snapshot:loader") == 0)
        #expect(store.linkMetadataStates[item.id] == .successWithImage)
    }

    // Case 10: metadata failure disables fallback and does not retry on reselect.
    @Test func metadataFailureNoFallbackAndNoRetryOnReselect() async throws {
        let url = "https://example.com/"
        let item = LinkPreviewFixture.urlItem(urlString: url)
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [item],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            fetchLinkMetadata: { _ in
                counter.mark("metadata:\(url)")
                throw URLError(.badServerResponse)
            },
            fetchLinkSnapshot: { _ in
                counter.mark("snapshot:loader")
                return self.snapshotData
            }
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }

        store.panelDidOpen()
        await counter.waitFor("handled", reaching: 1)

        store.select(item)

        #expect(counter.value("metadata:\(url)") == 1)
        #expect(counter.value("snapshot:loader") == 0)
        #expect(store.linkMetadataStates[item.id] == .failure)
    }

    // Case 10: a restored URL with a persisted title receives lazy metadata and
    // keeps its title through the fallback apply.
    @Test func restoredURLWithTitleReceivesLazyMetadataAndKeepsTitle() async throws {
        let url = "https://restored.example.com/"
        let restored = LinkPreviewFixture.urlItem(urlString: url, linkTitle: "Persisted Title")
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [restored],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            fetchLinkMetadata: { _ in
                counter.mark("metadata:\(url)")
                return LinkPreviewMetadata(title: "Fresh", imageData: nil)
            },
            fetchLinkSnapshot: { _ in
                counter.mark("snapshot:loader")
                return self.snapshotData
            }
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }

        #expect(counter.value("metadata:\(url)") == 0)
        store.panelDidOpen()
        await counter.waitFor("handled", reaching: 2)

        #expect(counter.value("metadata:\(url)") == 1)
        #expect(counter.value("snapshot:loader") == 1)
        let saved = recorder.last?.first { $0.id == restored.id }
        #expect(saved?.linkImageData != nil)
        // The current-session metadata title is authoritative over the
        // persisted title (which alone never proved eligibility).
        #expect(store.items.first { $0.id == restored.id }?.linkTitle == "Fresh")
    }

    // Case 10: a restored URL that already stores an image is never refetched.
    @Test func restoredURLWithImageNeverRefetches() async throws {
        let url = "https://imaged.example.com/"
        let restored = LinkPreviewFixture.urlItem(urlString: url, linkImageData: snapshotData)
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [restored],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { recorder.record($0) },
            fetchLinkMetadata: { _ in
                counter.mark("metadata:loader")
                return LinkPreviewMetadata(title: "Fresh", imageData: nil)
            },
            fetchLinkSnapshot: { _ in
                counter.mark("snapshot:loader")
                return self.snapshotData
            }
        )

        store.panelDidOpen()
        store.selectFirstVisibleItem()

        #expect(counter.value("metadata:loader") == 0)
        #expect(counter.value("snapshot:loader") == 0)
    }
}
