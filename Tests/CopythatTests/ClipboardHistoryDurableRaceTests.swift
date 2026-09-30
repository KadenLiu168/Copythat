@testable import Copythat
import Foundation
import Testing

/// Asynchronous race, flush, and quiescent-ownership acceptance for committed
/// media. Handling is held exactly at the loader boundary so post-await
/// decisions are observable without sleeps.
@MainActor
@Suite(.serialized)
struct ClipboardHistoryDurableRaceTests {
    // MARK: - 4.3 State changes during seeding

    @Test func replacementDuringSeedingKeepsNewerMediaResident() async throws {
        let gate = GatedBlobReader()
        let harness = DurableReleaseHarness(gatedReader: gate)
        defer { harness.cleanup() }
        let mediaA = PreparedMedia(hashing: Data(repeating: 0x5a, count: 128))
        let mediaB = PreparedMedia(hashing: Data(repeating: 0x5b, count: 144))
        let itemID = UUID()
        let store = harness.makeStore(initialItems: [DurableReleaseHarness.imageItem(id: itemID, media: mediaA)])

        let handle = try await harness.holdSeeding(
            gate: gate,
            store: store,
            commit: DurableReleaseHarness.commit(generation: 1, itemID: itemID, image: mediaA)
        )

        store.updateItem(at: 0) { _ in DurableReleaseHarness.imageItem(id: itemID, media: mediaB) }
        store.refreshFilteredItems()
        gate.releaseRead.signal()
        await handle.value

        #expect(store.items.first?.imageData == mediaB.data, "the post-await identity keeps newer media resident")
        #expect(store.items.first?.imageBlobID == mediaB.id)
        #expect(store.pendingDurableMediaRelease.isEmpty)
        #expect(harness.counters.manifestWriteCount == 0, "handling must not request persistence")
    }

    @Test func deletionDuringSeedingDoesNotResurrectTheItem() async throws {
        let gate = GatedBlobReader()
        let harness = DurableReleaseHarness(gatedReader: gate)
        defer { harness.cleanup() }
        let media = PreparedMedia(hashing: Data(repeating: 0x5c, count: 128))
        let itemID = UUID()
        let store = harness.makeStore(initialItems: [DurableReleaseHarness.imageItem(id: itemID, media: media)])

        let handle = try await harness.holdSeeding(
            gate: gate,
            store: store,
            commit: DurableReleaseHarness.commit(generation: 1, itemID: itemID, image: media)
        )

        store.remove(try #require(store.items.first))
        gate.releaseRead.signal()
        await handle.value

        #expect(store.items.isEmpty, "a removed item must not be recreated")
        #expect(store.filteredItems.isEmpty)
        #expect(store.pendingDurableMediaRelease.isEmpty)
        // The removal requests its own save; handling adds none of its own, which
        // the replacement scenario asserts where no mutation save is in flight.
        #expect(harness.counters.manifestWriteCount <= 1)
    }

    @Test func closeDuringSeedingReleasesOnceVisibilityIsRevoked() async throws {
        let gate = GatedBlobReader()
        let harness = DurableReleaseHarness(gatedReader: gate)
        defer { harness.cleanup() }
        let media = PreparedMedia(hashing: Data(repeating: 0x5d, count: 128))
        let itemID = UUID()
        let store = harness.makeStore(initialItems: [DurableReleaseHarness.imageItem(id: itemID, media: media)])
        store.panelDidOpen()

        let handle = try await harness.holdSeeding(
            gate: gate,
            store: store,
            commit: DurableReleaseHarness.commit(generation: 1, itemID: itemID, image: media)
        )

        store.panelDidClose()
        gate.releaseRead.signal()
        await handle.value

        #expect(!store.panelVisible)
        #expect(store.items.first?.imageData == nil, "visibility revoked during seeding authorizes release")
        #expect(store.filteredItems.first?.imageData == nil)
        #expect(store.pendingDurableMediaRelease.isEmpty)
    }

    @Test func closeAndReopenDuringSeedingDefersRelease() async throws {
        let gate = GatedBlobReader()
        let harness = DurableReleaseHarness(gatedReader: gate)
        defer { harness.cleanup() }
        let media = PreparedMedia(hashing: Data(repeating: 0x5e, count: 128))
        let itemID = UUID()
        let store = harness.makeStore(initialItems: [DurableReleaseHarness.imageItem(id: itemID, media: media)])
        store.panelDidOpen()

        let handle = try await harness.holdSeeding(
            gate: gate,
            store: store,
            commit: DurableReleaseHarness.commit(generation: 1, itemID: itemID, image: media)
        )

        store.panelDidClose()
        store.panelDidOpen()
        gate.releaseRead.signal()
        await handle.value

        #expect(store.panelVisible)
        #expect(store.items.first?.imageData == media.data, "a reopened panel keeps committed media deferred")
        #expect(store.pendingDurableMediaRelease[itemID]?.imageBlobID == media.id)

        store.panelDidClose()
        #expect(store.items.first?.imageData == nil)
        #expect(store.pendingDurableMediaRelease.isEmpty)
    }

    // MARK: - 4.4 Flush and visible ownership

    @Test func flushWaitsForHandlingAndCompletesWhileThePanelStaysVisible() async throws {
        let gate = GatedBlobReader()
        let harness = DurableReleaseHarness(gatedReader: gate)
        defer { harness.cleanup() }
        let media = PreparedMedia(hashing: Data(repeating: 0x5f, count: 160))
        let itemID = UUID()
        let store = harness.makeStore(initialItems: [DurableReleaseHarness.imageItem(id: itemID, media: media)])
        store.panelDidOpen()

        let blockerID = try harness.stageBlockerBlob(Data(repeating: 0x7f, count: 64))
        let holder = Task { _ = try? await harness.loader.load(blobID: blockerID) }
        let didStart = await DurableReleaseHarness.waitOffMainActor(gate.readStarted, timeout: .now() + 5)
        #expect(didStart == .success)

        harness.counters.reset()
        var flushResolved = false
        var flushTask: Task<Bool, Never>!
        await withCheckedContinuation { handlingStarted in
            harness.coordinator.setDurableMediaHandler { commit in
                handlingStarted.resume()
                await store.handleDurableMediaCommit(commit)
            }
            harness.coordinator.requestSave(store.items)
            flushTask = Task { @MainActor in
                let result = await harness.coordinator.flush()
                flushResolved = result
                return result
            }
        }
        #expect(harness.counters.manifestWriteCount == 1, "the commit completed before seeding was blocked")
        #expect(!flushResolved, "flush must wait for seeding and the release-or-defer decision")
        #expect(store.items.first?.imageData == media.data)

        gate.releaseRead.signal()
        #expect(await flushTask.value)
        await holder.value

        #expect(store.panelVisible, "a visible panel must not make flush wait for the user to close it")
        #expect(store.items.first?.imageData == media.data, "inline bytes remain until close")
        #expect(store.items.first?.imageBlobID == media.id)
        #expect(store.pendingDurableMediaRelease[itemID]?.imageBlobID == media.id)
        #expect(!harness.coordinator.hasRetainedRetrySnapshot, "a latest success clears the retry snapshot")
        #expect(harness.counters.manifestWriteCount == 1, "one mutation commits exactly one manifest")
        #expect(harness.counters.blobWriteCount == 1)
        AcceptanceMetrics.record(
            scenario: "durable-media-release",
            metric: "manifestWritesForOneMutationWhileVisible",
            expected: "1",
            observed: "\(harness.counters.manifestWriteCount)"
        )

        store.panelDidClose()
        #expect(store.items.first?.imageData == nil)
        #expect(store.pendingDurableMediaRelease.isEmpty)
    }

    // MARK: - 4.5 Quiescent ownership

    @Test func quiescentOwnershipHoldsNoResidentBytesAndNoHashOrSaveWork() async throws {
        let harness = DurableReleaseHarness(byteBudget: 200)
        defer { harness.cleanup() }
        // Individually larger than the cache budget, so release cannot depend on
        // cache admission.
        let oversized = PreparedMedia(hashing: Data(repeating: 0x61, count: 512))
        let preview = PreparedMedia(hashing: Data(repeating: 0x62, count: 80))
        let imageID = UUID()
        let previewID = UUID()
        let store = harness.makeStore(initialItems: [
            DurableReleaseHarness.imageItem(id: imageID, media: oversized),
            DurableReleaseHarness.textItem()
        ])
        let previewItem = DurableReleaseHarness.urlItem(id: previewID, linkTitle: "Example", linkImage: preview)
        harness.counters.reset()
        let flushed = await harness.counters.measure {
            store.add(previewItem)
            store.panelDidOpen()
            return await harness.flush()
        }
        #expect(flushed)

        // Deferred while visible: references only, never media bytes.
        #expect(store.pendingDurableMediaRelease[imageID]?.imageBlobID == oversized.id)
        #expect(store.pendingDurableMediaRelease[previewID]?.linkImageBlobID == preview.id)
        #expect(DurableReleaseHarness.residentBytes(store.items).image == oversized.data.count)
        #expect(DurableReleaseHarness.residentBytes(store.items).linkImage == preview.data.count)
        #expect(harness.counters.mediaHashCount == 0, "commit-to-seed adds zero hashes")

        let commitsBeforeRelease = harness.counters.manifestWriteCount
        await harness.counters.measure { store.panelDidClose() }

        #expect(harness.counters.manifestWriteCount == commitsBeforeRelease, "release requests no save")
        let itemBytes = DurableReleaseHarness.residentBytes(store.items)
        let filteredBytes = DurableReleaseHarness.residentBytes(store.filteredItems)
        #expect(itemBytes.image == 0, "history owns no image bytes")
        #expect(itemBytes.linkImage == 0, "history owns no preview bytes")
        #expect(filteredBytes.image == 0, "filtered history owns no image bytes")
        #expect(filteredBytes.linkImage == 0, "filtered history owns no preview bytes")
        #expect(store.pendingDurableMediaRelease.isEmpty)
        #expect(!harness.coordinator.hasRetainedRetrySnapshot)
        #expect(harness.counters.mediaHashCount == 0)
        #expect(store.items.first { $0.id == imageID }?.hasImagePayload == true)
        #expect(store.items.first { $0.id == previewID }?.hasLinkImagePayload == true)

        // Release is independent of cache admission: the oversized payload was
        // skipped by seeding and is still readable from disk.
        #expect(await harness.loader.retainedByteCost == preview.data.count)
        harness.counters.reset()
        #expect(try await harness.loader.load(blobID: oversized.id) == oversized.data)
        #expect(harness.counters.blobReadCount == 1)
        AcceptanceMetrics.record(
            scenario: "durable-media-release",
            metric: "residentBytesAtQuiescence",
            expected: "image=0,linkImage=0",
            observed: "image=\(itemBytes.image + filteredBytes.image)," +
                "linkImage=\(itemBytes.linkImage + filteredBytes.linkImage)"
        )
    }
}
