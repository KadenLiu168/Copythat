@testable import Copythat
import AppKit
import Foundation
import Testing

/// Preview payloads arrive finalized: merging them, reusing the session cache,
/// or updating only their title never re-encodes and never hashes the bytes.
@MainActor
@Suite(.serialized)
struct ClipboardStorePreviewIdentityTests {
    private let defaults = LinkPreviewFixture.tempDefaults("preview-identity")
    private let counter = LinkPreviewCounter()
    private let snapshot = PreparedMedia(hashing: LinkPreviewFixture.testImage().pngData(maxPixel: 32) ?? Data())

    @Test func metadataMergeAppliesPreparedMediaWithoutHashing() async throws {
        let counters = MediaOperationCounters()
        let gate = LinkPreviewGate()
        let item = LinkPreviewFixture.urlItem(urlString: "https://preview-identity.example.com/")
        let saveRecorder = LinkPreviewSaveRecorder()
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [item],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { saveRecorder.record($0) },
            fetchLinkMetadata: { _ in
                counter.begin("metadata")
                defer { counter.end("metadata") }
                await gate.waitOrCancelled()
                return LinkPreviewMetadata(title: "Finalized", image: self.snapshot)
            },
            fetchLinkSnapshot: { _ in throw URLError(.badServerResponse) }
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }
        store.panelDidOpen()
        await counter.waitFor("metadata", reaching: 1)

        counters.reset()
        gate.release()
        await counter.waitFor("handled", reaching: 1)
        await counters.measure {
            await drainTasks()
        }

        let merged = try #require(store.items.first)
        #expect(merged.linkTitle == "Finalized")
        #expect(merged.linkImageData == snapshot.data)
        #expect(merged.linkImageBlobID == snapshot.id)
        #expect(counters.mediaHashCount == 0)
        #expect(saveRecorder.last?.first?.linkImageBlobID == snapshot.id)
        AcceptanceMetrics.record(
            scenario: "preview-identity",
            metric: "mediaHashesWhenApplyingFinalizedMetadataPreview",
            expected: "0",
            observed: "\(counters.mediaHashCount)"
        )
    }

    @Test func positiveCacheReuseAppliesPreparedMediaWithoutHashing() async throws {
        let counters = MediaOperationCounters()
        let url = "https://preview-cache.example.com/"
        let pinned = LinkPreviewFixture.urlItem(urlString: url, isPinned: true)
        let fresh = LinkPreviewFixture.urlItem(urlString: url)
        let saveRecorder = LinkPreviewSaveRecorder()
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [pinned],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { saveRecorder.record($0) },
            fetchLinkMetadata: { _ in LinkPreviewMetadata(title: "Example", image: nil) },
            fetchLinkSnapshot: { _ in
                self.counter.mark("snapshot:loader")
                return self.snapshot
            }
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }
        store.panelDidOpen()
        store.add(fresh)
        await counter.waitFor("handled", reaching: 3)
        #expect(counter.value("snapshot:loader") == 1)
        #expect(store.snapshotPositiveCache[url]?.id == snapshot.id)

        let savesAfterFresh = saveRecorder.count
        counters.reset()
        await counters.measure {
            store.select(pinned)
            await counter.waitFor("handled", reaching: 3)
            await saveRecorder.waitForSaveCount(savesAfterFresh + 1)
        }

        #expect(counter.value("snapshot:loader") == 1)
        #expect(store.items.first { $0.id == pinned.id }?.linkImageBlobID == snapshot.id)
        #expect(counters.mediaHashCount == 0)
        AcceptanceMetrics.record(
            scenario: "preview-identity",
            metric: "mediaHashesOnSnapshotCacheReuse",
            expected: "0",
            observed: "\(counters.mediaHashCount)"
        )
    }

    @Test func titleOnlyUpdateKeepsPreparedBytesAndHashesNothing() async throws {
        let counters = MediaOperationCounters()
        let item = ClipboardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000b2")!,
            kind: .url,
            title: "preview-title.example.com",
            preview: "https://preview-title.example.com/",
            sourceApp: "Safari",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_300),
            isPinned: false,
            pinboardName: nil,
            textValue: "https://preview-title.example.com/",
            fileURLs: [],
            imageData: nil,
            linkTitle: "Original",
            linkImageData: snapshot.data,
            linkImageBlobID: snapshot.id
        )
        let saveRecorder = LinkPreviewSaveRecorder()
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [item],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { saveRecorder.record($0) },
            fetchLinkMetadata: { _ in throw URLError(.unsupportedURL) },
            fetchLinkSnapshot: { _ in throw URLError(.unsupportedURL) }
        )

        counters.reset()
        await counters.measure {
            store.applyLinkPreview(itemID: item.id, title: "Renamed", linkImage: nil)
        }

        let merged = try #require(store.items.first)
        #expect(merged.linkTitle == "Renamed")
        #expect(merged.linkImageData == snapshot.data)
        #expect(merged.linkImageBlobID == snapshot.id)
        #expect(counters.mediaHashCount == 0)
        #expect(saveRecorder.last?.first?.linkImageData == snapshot.data)
        AcceptanceMetrics.record(
            scenario: "preview-identity",
            metric: "mediaHashesOnTitleOnlyPreviewUpdate",
            expected: "0",
            observed: "\(counters.mediaHashCount)"
        )
    }

    private func drainTasks() async {
        for _ in 0..<8 {
            await Task.yield()
        }
    }
}
