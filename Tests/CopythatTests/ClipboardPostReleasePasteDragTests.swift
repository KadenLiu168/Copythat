@testable import Copythat
import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers

/// Paste and drag after an actual durable release: history keeps only
/// references, and the existing lazy materialization path still delivers image
/// payloads from a seeded cache hit and from a verified disk read, without a
/// text fallback or preview refetch.
@MainActor
@Suite(.serialized)
struct ClipboardPostReleasePasteDragTests {
    @Test func pasteAfterReleaseDeliversImageFromASeededHitWithoutTextFallback() async throws {
        let harness = DurableReleaseHarness()
        defer { harness.cleanup() }
        let png = DurableReleaseHarness.pngBytes(size: 24)
        let media = PreparedMedia(hashing: png)
        let store = harness.makeStore(initialItems: [DurableReleaseHarness.imageItem(id: UUID(), media: media)])
        #expect(await harness.saveAndFlush(store))
        let released = try #require(store.items.first)
        #expect(released.imageData == nil, "the durable commit released the resident bytes")
        #expect(released.hasImagePayload, "the reference survives release")

        harness.counters.reset()
        let materialized = try await store.materializedItemForPaste(released)

        #expect(materialized.imageData == png)
        #expect(materialized.imageBlobID == media.id)
        #expect(materialized.image != nil)
        #expect(harness.counters.blobReadCount == 0, "a seeded hit must not read disk")
        #expect(store.writeToPasteboard(materialized))

        let pasted = try #require(
            (harness.pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.first
        )
        #expect(pasted.size == NSSize(width: 24, height: 24))
        #expect(harness.pasteboard.string(forType: .string) == nil, "an image must not fall back to text")
        #expect(store.items.first?.imageData == nil, "paste must not repopulate history")
        #expect(!harness.coordinator.hasUnsavedChanges, "paste must not request persistence")
        #expect(store.linkMetadataStates.isEmpty, "paste must not trigger preview work")
        AcceptanceMetrics.record(
            scenario: "post-release-paste-drag",
            metric: "diskReadsForPasteAfterRelease",
            expected: "0",
            observed: "\(harness.counters.blobReadCount)"
        )
    }

    @Test func pasteAfterReleaseFallsBackToAVerifiedDiskReadWhenSeedingSkippedIt() async throws {
        // A budget smaller than the payload makes seeding skip it, so release is
        // independent of cache admission and paste reads and verifies the blob.
        let harness = DurableReleaseHarness(byteBudget: 1)
        defer { harness.cleanup() }
        let png = DurableReleaseHarness.pngBytes(size: 24)
        let media = PreparedMedia(hashing: png)
        let store = harness.makeStore(initialItems: [DurableReleaseHarness.imageItem(id: UUID(), media: media)])
        #expect(await harness.saveAndFlush(store))
        let released = try #require(store.items.first)
        #expect(released.imageData == nil)
        #expect(await harness.loader.retainedByteCost == 0, "the oversized payload was not seeded")

        harness.counters.reset()
        let materialized = try await harness.counters.measure {
            try await store.materializedItemForPaste(released)
        }

        #expect(materialized.imageData == png)
        #expect(harness.counters.blobReadCount == 1)
        #expect(harness.counters.integrityHashCount == 1, "an uncached payload is verified on read")
        #expect(store.writeToPasteboard(materialized))
        #expect(harness.pasteboard.string(forType: .string) == nil)
    }

    @Test func dragAfterReleaseDeliversPNGFromASeededHitAndFromASkippedSeed() async throws {
        let png = DurableReleaseHarness.pngBytes(size: 32)
        let media = PreparedMedia(hashing: png)

        let seeded = DurableReleaseHarness()
        defer { seeded.cleanup() }
        let seededStore = seeded.makeStore(initialItems: [DurableReleaseHarness.imageItem(id: UUID(), media: media)])
        #expect(await seeded.saveAndFlush(seededStore))
        let seededItem = try #require(seededStore.items.first)

        let seededProvider = ClipboardImageDragProvider.provider(for: seededItem, mediaLoader: seeded.loader)
        #expect(
            !seededProvider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier),
            "a released image with a reference must never degrade to text"
        )
        seeded.counters.reset()
        let seededPNG = try await loadPNG(from: seededProvider)
        #expect(NSImage(data: seededPNG)?.size == NSSize(width: 32, height: 32))
        #expect(seeded.counters.blobReadCount == 0, "the seeded hit must not read disk")

        let evicted = DurableReleaseHarness(byteBudget: 1)
        defer { evicted.cleanup() }
        let evictedStore = evicted.makeStore(initialItems: [DurableReleaseHarness.imageItem(id: UUID(), media: media)])
        #expect(await evicted.saveAndFlush(evictedStore))
        let evictedItem = try #require(evictedStore.items.first)

        let evictedProvider = ClipboardImageDragProvider.provider(for: evictedItem, mediaLoader: evicted.loader)
        evicted.counters.reset()
        let evictedPNG = try await loadPNG(from: evictedProvider)
        #expect(NSImage(data: evictedPNG)?.size == NSSize(width: 32, height: 32))
        #expect(evicted.counters.blobReadCount == 1, "an unseeded payload is read and verified")
    }

    @Test func missingAndCorruptBlobsKeepTheirExistingFailuresAfterRelease() async throws {
        let harness = DurableReleaseHarness()
        defer { harness.cleanup() }
        harness.pasteboard.clearContents()
        harness.pasteboard.setString("sentinel", forType: .string)
        let store = harness.makeStore(initialItems: [])
        let png = DurableReleaseHarness.pngBytes(size: 24)

        // Never written: the reference exists but the blob does not.
        let missingID = PreparedMedia(hashing: Data(repeating: 0x11, count: 64)).id
        let missingItem = referenceImageItem(blobID: missingID)
        await #expect(throws: (any Error).self) {
            try await store.materializedItemForPaste(missingItem)
        }

        // Written with the wrong bytes: verification rejects them.
        let corruptID = PreparedMedia(hashing: png).id
        let blobDirectory = harness.persistence.blobStore.directoryURL
        try FileManager.default.createDirectory(at: blobDirectory, withIntermediateDirectories: true)
        try Data([0x00]).write(to: blobDirectory.appendingPathComponent("\(corruptID).blob"))
        let corruptItem = referenceImageItem(blobID: corruptID)
        await #expect(throws: (any Error).self) {
            try await store.materializedItemForPaste(corruptItem)
        }

        // Both keep the drag path image-only rather than degrading to text.
        for item in [missingItem, corruptItem] {
            let provider = ClipboardImageDragProvider.provider(for: item, mediaLoader: harness.loader)
            #expect(!provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier))
        }

        #expect(harness.pasteboard.string(forType: .string) == "sentinel", "a failed restore writes nothing")
    }

    private func referenceImageItem(blobID: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .image,
            title: "Image",
            preview: "Reference only",
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_900),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: nil,
            imageBlobID: blobID
        )
    }

    private func loadPNG(from provider: NSItemProvider) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? ClipboardImageDragError.undecodableImage)
                }
            }
        }
    }
}
