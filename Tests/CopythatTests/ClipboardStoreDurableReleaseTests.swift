@testable import Copythat
import Combine
import Foundation
import Testing

/// Counts `objectWillChange` publications so ownership transitions can be
/// asserted without a diff: one assignment per history array means exactly one
/// publication per array, and a no-op release publishes nothing.
@MainActor
private final class StorePublicationCounter {
    private(set) var count = 0
    private var cancellable: AnyCancellable?

    init(store: ClipboardStore) {
        cancellable = store.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.count += 1 }
        }
    }

    func reset() {
        count = 0
    }
}

@MainActor
@Suite(.serialized)
struct ClipboardStoreDurableReleaseTests {
    // MARK: - 3.1 Receipt handling

    @Test func hiddenCommitReleasesImageBytesFromBothArraysWithoutAnotherSave() async throws {
        let environment = DurableReleaseHarness()
        defer { environment.cleanup() }
        let media = PreparedMedia(hashing: Data(repeating: 0xe1, count: 176))
        let itemID = UUID(uuidString: "00000000-0000-0000-0000-0000000000e1")!
        let item = imageItem(id: itemID, media: media)
        let store = environment.makeStore(initialItems: [item])

        environment.counters.reset()
        #expect(await environment.saveAndFlush(store))

        #expect(store.items.first?.imageData == nil)
        #expect(store.items.first?.imageBlobID == media.id)
        #expect(store.items.first?.title == item.title)
        #expect(store.items.first?.contentKey == item.contentKey)
        #expect(store.items.first?.hasImagePayload == true)
        #expect(store.filteredItems.first?.imageData == nil)
        #expect(store.filteredItems.first?.imageBlobID == media.id)
        #expect(store.pendingDurableMediaRelease.isEmpty)
        #expect(environment.counters.manifestWriteCount == 1, "release must not request another save")
        #expect(environment.counters.blobWriteCount == 1)
        #expect(!environment.coordinator.hasUnsavedChanges)
        #expect(store.linkMetadataStates.isEmpty, "release must not trigger preview work")
        #expect(store.activeFallback == nil)

        environment.counters.reset()
        #expect(try await environment.loader.load(blobID: media.id) == media.data)
        #expect(environment.counters.blobReadCount == 0, "committed bytes must be seeded before release")
        AcceptanceMetrics.record(
            scenario: "durable-media-release",
            metric: "manifestWritesForHiddenCommit",
            expected: "1",
            observed: "\(environment.counters.manifestWriteCount)"
        )
    }

    @Test func hiddenCommitReleasesLinkImageBytesWithoutPreviewWork() async throws {
        let environment = DurableReleaseHarness()
        defer { environment.cleanup() }
        let preview = PreparedMedia(hashing: Data(repeating: 0xe2, count: 128))
        let itemID = UUID(uuidString: "00000000-0000-0000-0000-0000000000e2")!
        let item = urlItem(id: itemID, linkTitle: "Example", linkImage: preview)
        let store = environment.makeStore(initialItems: [item])

        environment.counters.reset()
        #expect(await environment.saveAndFlush(store))

        #expect(store.items.first?.imageData == nil)
        #expect(store.items.first?.imageBlobID == nil, "a URL item has no image role to release")
        #expect(store.items.first?.linkImageData == nil)
        #expect(store.items.first?.linkImageBlobID == preview.id)
        #expect(store.items.first?.linkTitle == "Example")
        #expect(store.items.first?.hasLinkImagePayload == true)
        #expect(store.items.first?.contentKey == item.contentKey)
        #expect(store.filteredItems.first?.linkImageData == nil)
        #expect(store.filteredItems.first?.linkImageBlobID == preview.id)
        #expect(environment.counters.manifestWriteCount == 1)
        #expect(store.linkMetadataStates.isEmpty, "a released preview keeps its payload and needs no metadata run")
        #expect(store.metadataTasks.isEmpty)
        #expect(store.activeFallback == nil)
        #expect(store.snapshotPositiveCache.isEmpty)
    }

    @Test func seedingFavorsNewerMediaUnderCachePressureAndKeepsReleaseIndependent() async throws {
        let environment = DurableReleaseHarness(byteBudget: 300)
        defer { environment.cleanup() }
        let older = PreparedMedia(hashing: Data(repeating: 0xe3, count: 200))
        let newer = PreparedMedia(hashing: Data(repeating: 0xe4, count: 200))
        let olderID = UUID(uuidString: "00000000-0000-0000-0000-0000000000e3")!
        let newerID = UUID(uuidString: "00000000-0000-0000-0000-0000000000e4")!
        // History is newest first, so the older item is offered to the cache first.
        let store = environment.makeStore(initialItems: [
            imageItem(id: newerID, media: newer),
            imageItem(id: olderID, media: older)
        ])

        #expect(await environment.saveAndFlush(store))

        #expect(store.items.allSatisfy { $0.imageData == nil }, "release must not depend on cache admission")
        #expect(await environment.loader.retainedByteCost == newer.data.count)

        environment.counters.reset()
        #expect(try await environment.loader.load(blobID: newer.id) == newer.data)
        #expect(environment.counters.blobReadCount == 0)
        #expect(try await environment.loader.load(blobID: older.id) == older.data)
        #expect(environment.counters.blobReadCount == 1, "an evicted identity is still readable from disk")
    }

    // MARK: - 3.2 Deferred release and panel close

    @Test func visibleCommitSeedsButRetainsInlineBytesUntilClose() async throws {
        let environment = DurableReleaseHarness()
        defer { environment.cleanup() }
        let media = PreparedMedia(hashing: Data(repeating: 0xe5, count: 160))
        let itemID = UUID(uuidString: "00000000-0000-0000-0000-0000000000e5")!
        let store = environment.makeStore(initialItems: [imageItem(id: itemID, media: media)])
        store.panelDidOpen()

        #expect(await environment.saveAndFlush(store))
        #expect(store.items.first?.imageData == media.data, "a visible commit must not switch inline ownership")
        #expect(store.items.first?.imageData != nil)
        #expect(store.filteredItems.first?.imageData == media.data)
        #expect(store.pendingDurableMediaRelease[itemID]?.imageBlobID == media.id)

        store.panelDidClose()

        #expect(store.items.first?.imageData == nil)
        #expect(store.filteredItems.first?.imageData == nil)
        #expect(store.items.first?.imageBlobID == media.id)
        #expect(store.items.first?.hasImagePayload == true)
        #expect(store.pendingDurableMediaRelease.isEmpty)

        environment.counters.reset()
        #expect(try await environment.loader.load(blobID: media.id) == media.data)
        #expect(environment.counters.blobReadCount == 0, "the visible commit must still have seeded the cache")
        AcceptanceMetrics.record(
            scenario: "durable-media-release",
            metric: "diskReadsAfterVisibleCommitAndClose",
            expected: "0",
            observed: "\(environment.counters.blobReadCount)"
        )
    }

    @Test func repeatedAndNonMatchingReleasesNeverRepublish() async throws {
        let environment = DurableReleaseHarness()
        defer { environment.cleanup() }
        let media = PreparedMedia(hashing: Data(repeating: 0xe6, count: 144))
        let itemID = UUID(uuidString: "00000000-0000-0000-0000-0000000000e6")!
        let store = environment.makeStore(initialItems: [imageItem(id: itemID, media: media)])
        let publications = StorePublicationCounter(store: store)

        let nonMatching = ClipboardHistoryDurableMediaCommit(
            generation: 1,
            entries: [.init(
                itemID: itemID,
                image: PreparedMedia(hashing: Data(repeating: 0xe7, count: 32)),
                linkImage: nil
            )]
        )
        publications.reset()
        await store.handleDurableMediaCommit(nonMatching)
        #expect(publications.count == 0, "an unmatched identity must not publish a new history array")
        #expect(store.items.first?.imageData == media.data, "unmatched media must stay resident")

        let matching = ClipboardHistoryDurableMediaCommit(
            generation: 2,
            entries: [.init(itemID: itemID, image: media, linkImage: nil)]
        )
        publications.reset()
        await store.handleDurableMediaCommit(matching)
        #expect(publications.count == 2, "one assignment per changed array, with no filter or selection work")
        #expect(store.items.first?.imageData == nil)
        #expect(store.filteredItems.first?.imageData == nil)

        publications.reset()
        await store.handleDurableMediaCommit(matching)
        #expect(publications.count == 0, "a repeated release must not publish anything")
    }

    // MARK: - 3.3 Bounded pending lifetime

    @Test func deletionAndClearHistoryDiscardPendingReferencesWithoutResurrection() async throws {
        let environment = DurableReleaseHarness()
        defer { environment.cleanup() }
        let media = PreparedMedia(hashing: Data(repeating: 0xe8, count: 96))
        let itemID = UUID(uuidString: "00000000-0000-0000-0000-0000000000e8")!
        let store = environment.makeStore(initialItems: [])
        store.panelDidOpen()
        store.add(imageItem(id: itemID, media: media))
        #expect(await environment.flush())
        let pending = try #require(store.pendingDurableMediaRelease[itemID])
        #expect(pending.imageBlobID == media.id)

        store.remove(try #require(store.items.first { $0.id == itemID }))

        #expect(store.pendingDurableMediaRelease[itemID] == nil)
        #expect(!store.items.contains { $0.id == itemID })
        #expect(store.items.isEmpty)

        let secondID = UUID(uuidString: "00000000-0000-0000-0000-0000000000e9")!
        let second = PreparedMedia(hashing: Data(repeating: 0xe9, count: 96))
        store.add(imageItem(id: secondID, media: second))
        #expect(await environment.flush())
        #expect(store.pendingDurableMediaRelease[secondID]?.imageBlobID == second.id)
        #expect(store.clearHistory(includePinnedAndPinboardItems: true) == 1)
        #expect(store.pendingDurableMediaRelease[secondID] == nil)
        #expect(!store.items.contains { $0.id == secondID })
    }

    @Test func historyLimitEvictionDiscardsPendingReferences() async throws {
        let environment = DurableReleaseHarness()
        defer { environment.cleanup() }
        environment.settings.historyLimit = 100
        let media = PreparedMedia(hashing: Data(repeating: 0xea, count: 96))
        let evictedID = UUID(uuidString: "00000000-0000-0000-0000-0000000000ea")!
        let store = environment.makeStore(initialItems: [])
        store.panelDidOpen()
        store.add(imageItem(id: evictedID, media: media))
        #expect(await environment.flush())
        #expect(store.pendingDurableMediaRelease[evictedID]?.imageBlobID == media.id)

        for index in 0..<100 {
            store.add(textItem(index: index))
        }
        #expect(await environment.flush())

        #expect(!store.items.contains { $0.id == evictedID }, "the limit must evict the oldest item")
        #expect(store.pendingDurableMediaRelease[evictedID] == nil, "an evicted item must not keep a pending proof")
        #expect(store.items.count == 100)
    }

    @Test func replacedLinkImageDropsOnlyItsOwnPendingRole() async throws {
        let environment = DurableReleaseHarness()
        defer { environment.cleanup() }
        let image = PreparedMedia(hashing: Data(repeating: 0xeb, count: 120))
        let originalPreview = PreparedMedia(hashing: Data(repeating: 0xec, count: 88))
        let replacement = PreparedMedia(hashing: Data(repeating: 0xed, count: 64))
        let itemID = UUID(uuidString: "00000000-0000-0000-0000-0000000000eb")!
        let item = ClipboardItem(
            id: itemID,
            kind: .image,
            title: "Both roles",
            preview: "Both roles",
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_400),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: image.data,
            imageBlobID: image.id,
            linkImageData: originalPreview.data,
            linkImageBlobID: originalPreview.id
        )
        let store = environment.makeStore(initialItems: [item])
        store.panelDidOpen()
        #expect(await environment.saveAndFlush(store))
        #expect(store.pendingDurableMediaRelease[itemID]?.imageBlobID == image.id)
        #expect(store.pendingDurableMediaRelease[itemID]?.linkImageBlobID == originalPreview.id)

        store.applyLinkPreview(itemID: itemID, title: "Replaced", linkImage: replacement)

        #expect(store.pendingDurableMediaRelease[itemID]?.linkImageBlobID == nil, "the old identity is no longer proof")
        #expect(store.pendingDurableMediaRelease[itemID]?.imageBlobID == image.id, "the other role keeps its proof")
        #expect(store.items.first?.linkImageBlobID == replacement.id)
        #expect(store.items.first?.linkImageData == replacement.data)
        #expect(store.items.first?.imageData == image.data, "an unrelated role must stay resident")
    }

    // MARK: - Fixtures

    private func imageItem(id: UUID, media: PreparedMedia) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: .image,
            title: "Image \(id.uuidString.prefix(4))",
            preview: "Preview",
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_410),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: media.data,
            imageBlobID: media.id
        )
    }

    private func urlItem(id: UUID, linkTitle: String, linkImage: PreparedMedia) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: .url,
            title: "example.com",
            preview: "https://example.com/\(id.uuidString)",
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_420),
            isPinned: false,
            pinboardName: nil,
            textValue: "https://example.com/\(id.uuidString)",
            fileURLs: [],
            imageData: nil,
            linkTitle: linkTitle,
            linkImageData: linkImage.data,
            linkImageBlobID: linkImage.id
        )
    }

    private func textItem(index: Int) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .text,
            title: "Text \(index)",
            preview: "Text \(index)",
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_500 + Double(index)),
            isPinned: false,
            pinboardName: nil,
            textValue: "Text \(index)",
            fileURLs: [],
            imageData: nil
        )
    }
}
