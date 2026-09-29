@testable import Copythat
import AppKit
import CryptoKit
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct StoreLazyLinkPreviewTests {
    @Test func restoredURLWithPersistedPreviewNeverRequestsMetadataOrFallback() async throws {
        let defaults = LinkPreviewFixture.tempDefaults("lazy-restored")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LazyLinkPreview-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = ClipboardHistoryPersistence(directoryURL: directory, userDefaults: defaults)
        let preview = try #require(LinkPreviewFixture.testImage().pngData(maxPixel: 32))
        let saved = LinkPreviewFixture.urlItem(
            urlString: "https://restored-preview.example.com/",
            linkTitle: "Persisted title",
            linkImageData: preview
        )
        try persistence.save([saved])

        let counter = LinkPreviewCounter()
        let store = makeStore(
            defaults: defaults,
            items: try persistence.loadItems(),
            counter: counter
        )
        let restored = try #require(store.items.first)
        #expect(restored.linkImageData == nil)
        #expect(restored.linkImageBlobID != nil)
        #expect(restored.linkTitle == "Persisted title")

        store.panelDidOpen()
        store.select(restored)
        store.selectedBoardID = Pinboard.pinned.id
        store.selectedBoardID = Pinboard.all.id
        store.panelDidClose()
        store.panelDidOpen()
        await drainPendingTasks()

        #expect(counter.value("metadata") == 0)
        #expect(counter.value("snapshot") == 0)
        #expect(store.items.first?.linkImageBlobID == restored.linkImageBlobID)
        #expect(store.items.first?.linkImageData == nil)

        AcceptanceMetrics.record(
            scenario: "link-preview-lazy",
            metric: "metadataFetchesForRestoredPreviewURL",
            expected: "0",
            observed: "\(counter.value("metadata"))"
        )
        AcceptanceMetrics.record(
            scenario: "link-preview-lazy",
            metric: "snapshotFetchesForRestoredPreviewURL",
            expected: "0",
            observed: "\(counter.value("snapshot"))"
        )
    }

    @Test func inaccessiblePersistedPreviewDoesNotAuthorizeNetworkRepair() async throws {
        let defaults = LinkPreviewFixture.tempDefaults("lazy-missing")
        let counter = LinkPreviewCounter()
        // The reference names no stored blob: reading it would fail, yet that
        // failure must not clear the reference or enable the network path.
        let blobID = sha256Hex(Data(repeating: 0x91, count: 128))
        let item = withPersistedPreviewReference(
            LinkPreviewFixture.urlItem(urlString: "https://missing-preview.example.com/", linkTitle: "Stored"),
            blobID: blobID
        )
        let store = makeStore(defaults: defaults, items: [item], counter: counter)

        store.panelDidOpen()
        store.select(item)
        await drainPendingTasks()

        #expect(counter.value("metadata") == 0)
        #expect(counter.value("snapshot") == 0)
        #expect(store.items.first?.linkImageData == nil)
        #expect(store.items.first?.linkImageBlobID == blobID)
        #expect(store.items.first?.linkTitle == "Stored")
        AcceptanceMetrics.record(
            scenario: "link-preview-lazy",
            metric: "networkFetchesForUnreadablePersistedPreview",
            expected: "0",
            observed: "\(counter.value("metadata") + counter.value("snapshot"))"
        )
    }

    @Test func titleOnlyCompletionKeepsPersistedPreviewReferenceAndBlocksFallback() async throws {
        let defaults = LinkPreviewFixture.tempDefaults("lazy-title-only")
        let counter = LinkPreviewCounter()
        let gate = LinkPreviewGate()
        let item = LinkPreviewFixture.urlItem(urlString: "https://pending-title.example.com/")
        let snapshotImage = try #require(LinkPreviewFixture.testImage().pngData(maxPixel: 32))
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [item],
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { _ in },
            fetchLinkMetadata: { _ in
                counter.begin("metadata")
                defer { counter.end("metadata") }
                await gate.waitOrCancelled()
                return LinkPreviewMetadata(title: "Late title", image: nil)
            },
            fetchLinkSnapshot: { _ in
                counter.mark("snapshot")
                return PreparedMedia(hashing: snapshotImage)
            }
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }
        store.panelDidOpen()
        await counter.waitFor("metadata", reaching: 1)

        // A persisted preview reference arrives while metadata is still pending.
        let blobID = sha256Hex(Data(repeating: 0x92, count: 256))
        store.updateItem(at: 0) { withPersistedPreviewReference($0, blobID: blobID) }
        store.refreshFilteredItems()

        gate.release()
        await counter.waitFor("handled", reaching: 1)
        await drainPendingTasks()

        let merged = try #require(store.items.first)
        #expect(merged.linkTitle == "Late title")
        #expect(merged.linkImageBlobID == blobID)
        #expect(merged.linkImageData == nil)
        #expect(store.linkMetadataStates[item.id] == .successWithImage)
        #expect(counter.value("snapshot") == 0)
        AcceptanceMetrics.record(
            scenario: "link-preview-lazy",
            metric: "snapshotFetchesAfterTitleOnlyCompletion",
            expected: "0",
            observed: "\(counter.value("snapshot"))"
        )
    }

    @Test func newMetadataImageOnItemWithoutPreviewMaterializesNewIdentity() async throws {
        let defaults = LinkPreviewFixture.tempDefaults("lazy-new-image")
        let counter = LinkPreviewCounter()
        let gate = LinkPreviewGate()
        let item = LinkPreviewFixture.urlItem(urlString: "https://fresh-image.example.com/")
        let saveRecorder = LinkPreviewSaveRecorder()
        let metadataImage = try #require(LinkPreviewFixture.testImage().pngData(maxPixel: 32))
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
                return LinkPreviewMetadata(title: "Fresh", image: PreparedMedia(hashing: metadataImage))
            },
            fetchLinkSnapshot: { _ in throw URLError(.badServerResponse) }
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }
        store.panelDidOpen()
        await counter.waitFor("metadata", reaching: 1)
        gate.release()
        await counter.waitFor("handled", reaching: 1)

        let merged = try #require(store.items.first)
        #expect(merged.linkTitle == "Fresh")
        #expect(merged.linkImageData == metadataImage)
        #expect(merged.linkImageBlobID == sha256Hex(metadataImage))
        #expect(merged.hasLinkImagePayload)
        let savedImage = try #require(saveRecorder.last?.first?.linkImageData)
        #expect(savedImage == merged.linkImageData)
    }

    private func makeStore(
        defaults: UserDefaults,
        items: [ClipboardItem],
        counter: LinkPreviewCounter
    ) -> ClipboardStore {
        ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: items,
            pasteboard: LinkPreviewFixture.uniquePasteboard(),
            persistItems: { _ in },
            fetchLinkMetadata: { _ in
                counter.mark("metadata")
                throw URLError(.unsupportedURL)
            },
            fetchLinkSnapshot: { _ in
                counter.mark("snapshot")
                throw URLError(.badServerResponse)
            }
        )
    }

    /// The store's eligibility paths are synchronous; yielding lets any task a
    /// missed check created record itself before the zero-count assertions.
    private func drainPendingTasks() async {
        for _ in 0..<8 {
            await Task.yield()
        }
    }

    private func withPersistedPreviewReference(_ item: ClipboardItem, blobID: String) -> ClipboardItem {
        ClipboardItem(
            id: item.id,
            kind: item.kind,
            title: item.title,
            preview: item.preview,
            sourceApp: item.sourceApp,
            sourceAppIconData: item.sourceAppIconData,
            createdAt: item.createdAt,
            isPinned: item.isPinned,
            pinboardName: item.pinboardName,
            textValue: item.textValue,
            fileURLs: item.fileURLs,
            imageData: item.imageData,
            imageBlobID: item.imageBlobID,
            linkTitle: item.linkTitle,
            linkImageData: item.linkImageData,
            linkImageBlobID: blobID
        )
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
