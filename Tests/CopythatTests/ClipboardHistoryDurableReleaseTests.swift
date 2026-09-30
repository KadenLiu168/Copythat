@testable import Copythat
import Foundation
import Testing

private enum WriteFailure: String {
    case blobWrite
    case manifestWrite
}

/// Durability and generation-ordering acceptance for committed media: a failed
/// transaction authorizes nothing, retry reuses the same identities, and only
/// the media identity that actually committed is ever released.
@MainActor
@Suite(.serialized)
struct ClipboardHistoryDurableReleaseTests {
    // MARK: - 4.1 Persistence failures

    @Test func failedCommitKeepsResidentMediaAndRetriesWithTheSameIdentity() async throws {
        try await expectFailedCommitRecovers(.blobWrite)
        try await expectFailedCommitRecovers(.manifestWrite)
    }

    private func expectFailedCommitRecovers(_ failure: WriteFailure) async throws {
        let harness = DurableReleaseHarness()
        defer { harness.cleanup() }
        let image = PreparedMedia(hashing: Data(repeating: 0x51, count: 160))
        let preview = PreparedMedia(hashing: Data(repeating: 0x52, count: 96))
        let itemID = UUID()
        let store = harness.makeStore(initialItems: [DurableReleaseHarness.textItem()])
        #expect(await harness.saveAndFlush(store), "\(failure.rawValue): the baseline manifest must commit")
        let baselineManifest = try harness.manifestData()

        switch failure {
        case .blobWrite: harness.writeFailures.failBlobWrites()
        case .manifestWrite: harness.writeFailures.failManifestWrites()
        }

        harness.counters.reset()
        let failedFlush = await harness.counters.measure {
            store.add(DurableReleaseHarness.bothRolesItem(id: itemID, image: image, linkImage: preview))
            return await harness.flush()
        }
        #expect(!failedFlush, "\(failure.rawValue): a rejected write must fail the commit")

        let residentImage = try #require(store.items.first { $0.id == itemID })
        #expect(residentImage.imageData == image.data, "\(failure.rawValue): uncommitted image bytes stay resident")
        #expect(residentImage.linkImageData == preview.data)
        let residentFiltered = try #require(store.filteredItems.first { $0.id == itemID })
        #expect(residentFiltered.imageData == image.data)
        #expect(residentFiltered.linkImageData == preview.data)
        #expect(store.pendingDurableMediaRelease.isEmpty, "\(failure.rawValue): nothing is seeded or released")
        #expect(await harness.loader.retainedByteCost == 0)
        #expect(try harness.manifestData() == baselineManifest, "\(failure.rawValue): the old manifest stays usable")
        #expect(try harness.persistence.loadItems().count == 1)
        #expect(harness.counters.mediaHashCount == 0)
        AcceptanceMetrics.record(
            scenario: "durable-media-release",
            metric: "residentBytesAfterFailedCommit-\(failure.rawValue)",
            expected: "\(image.data.count + preview.data.count)",
            observed: "\((residentImage.imageData?.count ?? 0) + (residentImage.linkImageData?.count ?? 0))"
        )

        harness.writeFailures.allowWrites()
        harness.counters.reset()
        let retried = await harness.counters.measure { await harness.coordinator.retryLatest() }
        #expect(retried, "\(failure.rawValue): retry must succeed")

        #expect(store.items.first { $0.id == itemID }?.imageData == nil)
        #expect(store.items.first { $0.id == itemID }?.imageBlobID == image.id)
        #expect(store.filteredItems.first { $0.id == itemID }?.linkImageData == nil)
        #expect(store.filteredItems.first { $0.id == itemID }?.linkImageBlobID == preview.id)
        #expect(harness.counters.mediaHashCount == 0, "\(failure.rawValue): retry reuses the same identities")
        let committed = try harness.persistence.loadItems()
        #expect(committed.first { $0.id == itemID }?.imageBlobID == image.id)
        #expect(committed.first { $0.id == itemID }?.linkImageBlobID == preview.id)
    }

    // MARK: - 4.2 Generation ordering

    @Test func olderCommitNeverReleasesNewerMediaIdentity() async throws {
        let harness = DurableReleaseHarness()
        defer { harness.cleanup() }
        let mediaA = PreparedMedia(hashing: Data(repeating: 0x53, count: 128))
        let mediaB = PreparedMedia(hashing: Data(repeating: 0x54, count: 144))
        let itemID = UUID()
        let worker = BlockableHistorySaveWorker(
            persistence: harness.persistence,
            blockedGenerations: [1, 2]
        )
        let store = harness.makeStore(
            initialItems: [DurableReleaseHarness.imageItem(id: itemID, media: mediaA)],
            worker: worker
        )

        harness.coordinator.requestSave(store.items)
        await worker.waitUntilStarted(1)

        store.updateItem(at: 0) { _ in DurableReleaseHarness.imageItem(id: itemID, media: mediaB) }
        store.refreshFilteredItems()
        harness.coordinator.requestSave(store.items)

        await worker.release(1)
        await worker.waitUntilStarted(2)
        #expect(store.items.first?.imageData == mediaB.data, "the older commit must not release B")
        #expect(store.items.first?.imageBlobID == mediaB.id)
        #expect(store.pendingDurableMediaRelease.isEmpty)

        await worker.release(2)
        #expect(await harness.flush())
        #expect(store.items.first?.imageData == nil, "B is released only by its own successful commit")
        #expect(store.items.first?.imageBlobID == mediaB.id)
        #expect(store.pendingDurableMediaRelease.isEmpty)
    }

    @Test func olderCommitReleasesOnlyTheRoleWhoseIdentityIsStillCurrent() async throws {
        let harness = DurableReleaseHarness()
        defer { harness.cleanup() }
        let image = PreparedMedia(hashing: Data(repeating: 0x55, count: 120))
        let originalPreview = PreparedMedia(hashing: Data(repeating: 0x56, count: 88))
        let replacementPreview = PreparedMedia(hashing: Data(repeating: 0x57, count: 72))
        let itemID = UUID()
        let worker = BlockableHistorySaveWorker(
            persistence: harness.persistence,
            blockedGenerations: [1, 2]
        )
        let store = harness.makeStore(
            initialItems: [DurableReleaseHarness.bothRolesItem(id: itemID, image: image, linkImage: originalPreview)],
            worker: worker
        )

        harness.coordinator.requestSave(store.items)
        await worker.waitUntilStarted(1)

        store.applyLinkPreview(itemID: itemID, title: "Replaced", linkImage: replacementPreview)

        await worker.release(1)
        await worker.waitUntilStarted(2)
        #expect(store.items.first?.imageData == nil, "the unchanged image identity is covered by the receipt")
        #expect(store.items.first?.imageBlobID == image.id)
        #expect(store.items.first?.linkImageData == replacementPreview.data, "roles are evaluated independently")
        #expect(store.items.first?.linkImageBlobID == replacementPreview.id)

        await worker.release(2)
        #expect(await harness.flush())
        #expect(store.items.first?.linkImageData == nil, "the replacement is released by its own commit")
        #expect(store.items.first?.linkImageBlobID == replacementPreview.id)
    }

    @Test func metadataChangeKeepsCommittedIdentityEligibleForRelease() async throws {
        let harness = DurableReleaseHarness()
        defer { harness.cleanup() }
        let media = PreparedMedia(hashing: Data(repeating: 0x58, count: 112))
        let itemID = UUID()
        let worker = BlockableHistorySaveWorker(
            persistence: harness.persistence,
            blockedGenerations: [1, 2]
        )
        let store = harness.makeStore(
            initialItems: [DurableReleaseHarness.imageItem(id: itemID, media: media)],
            worker: worker
        )

        harness.coordinator.requestSave(store.items)
        await worker.waitUntilStarted(1)

        // Metadata advances while the commit is in flight, with the media
        // identity unchanged.
        store.togglePin(store.items[0])

        await worker.release(1)
        await worker.waitUntilStarted(2)
        #expect(store.items.first?.isPinned == true)
        #expect(store.items.first?.imageData == nil, "an unchanged identity stays eligible across metadata changes")
        #expect(store.items.first?.imageBlobID == media.id)
        #expect(store.items.first?.hasImagePayload == true)

        await worker.release(2)
        #expect(await harness.flush())
    }

    @Test func coalescedGenerationsAndLatestFailureAuthorizeNoRelease() async throws {
        let harness = DurableReleaseHarness()
        defer { harness.cleanup() }
        let media = PreparedMedia(hashing: Data(repeating: 0x59, count: 128))
        let itemID = UUID()
        let worker = BlockableHistorySaveWorker(
            persistence: harness.persistence,
            blockedGenerations: [1],
            failingGenerations: [1, 3]
        )
        let store = harness.makeStore(
            initialItems: [DurableReleaseHarness.imageItem(id: itemID, media: media)],
            worker: worker
        )

        harness.coordinator.requestSave(store.items)
        await worker.waitUntilStarted(1)
        store.togglePin(store.items[0])
        store.togglePin(store.items[0])

        await worker.release(1)
        #expect(!(await harness.flush()), "the latest coalesced generation failed")

        #expect(store.items.first?.imageData == media.data, "no successful receipt means no release")
        #expect(store.pendingDurableMediaRelease.isEmpty)
        #expect(await harness.loader.retainedByteCost == 0, "a failed commit seeds nothing")
        #expect(harness.counters.manifestWriteCount == 0)
        #expect(harness.coordinator.hasRetainedRetrySnapshot, "the latest failure stays retryable")

        #expect(await harness.coordinator.retryLatest())
        #expect(store.items.first?.imageData == nil, "only a successful commit authorizes release")
        #expect(store.items.first?.imageBlobID == media.id)
        #expect(!harness.coordinator.hasRetainedRetrySnapshot)
    }
}
