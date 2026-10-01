@testable import Copythat
import AppKit
import CryptoKit
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct ClipboardStoreImageDeletionTests {
    @Test func removingImageWithoutPendingCaptureNeedsNoDeletionAuthority() {
        let image = imageItem(data: Data([1, 2, 3]))
        let store = store(items: [image])

        store.remove(image)

        #expect(store.items.isEmpty)
        #expect(!store.hasDeletedContentKey(image.contentKey))
    }

    @Test func clearingHistoryPreservesProtectedItemsWithoutRetainingIdleAuthority() {
        let ordinary = imageItem(data: Data([7]))
        let pinned = imageItem(data: Data([8]), isPinned: true)
        let assigned = imageItem(data: Data([9]), pinboardName: "Work")
        let store = store(items: [ordinary, pinned, assigned])

        let removedCount = store.clearHistory(includePinnedAndPinboardItems: false)

        #expect(removedCount == 1)
        #expect(!store.hasDeletedContentKey(ordinary.contentKey))
        #expect(!store.hasDeletedContentKey(pinned.contentKey))
        #expect(!store.hasDeletedContentKey(assigned.contentKey))
        #expect(store.items.map(\.id) == [pinned.id, assigned.id])
    }

    @Test func normalAddPathCanRecordSameImageAfterDeletion() {
        let image = imageItem(data: Data([10, 11, 12]))
        let store = store(items: [image])

        store.remove(image)
        store.add(image)

        #expect(store.items.map(\.id) == [image.id])
        #expect(!store.hasDeletedContentKey(image.contentKey))
    }

    @Test func deletingCurrentImageClearsPasteboard() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let image = solidImage(color: .systemRed)
        let store = store(items: [], pasteboard: pasteboard)
        let imageData = try #require(store.normalizedImageData(for: image))
        let captured = imageItem(data: imageData)
        store.add(captured)
        pasteboard.clearContents()
        pasteboard.writeObjects([image])

        store.remove(captured)

        #expect(store.items.isEmpty)
        #expect(pasteboard.types?.isEmpty ?? true)
    }

    @Test func deletingCurrentUnloadedImageClearsPasteboardWithoutLoadingBlob() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        let image = solidImage(color: .systemBlue)
        let probeStore = store(items: [], pasteboard: pasteboard)
        let imageData = try #require(probeStore.normalizedImageData(for: image))
        // The reference names no file on disk: a deletion path that tried to
        // materialize history media could not match the current pasteboard.
        let unloaded = unloadedImageItem(blobID: sha256Hex(imageData))
        let store = store(items: [unloaded], pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.writeObjects([image])

        store.remove(unloaded)

        #expect(store.items.isEmpty)
        #expect(pasteboard.types?.isEmpty ?? true)
        AcceptanceMetrics.record(
            scenario: "model-deletion-policy",
            metric: "pasteboardClearedForCurrentLazyImage",
            expected: "true",
            observed: "\(pasteboard.types?.isEmpty ?? true)"
        )
    }

    @Test func deletingOlderItemDoesNotClearCurrentPasteboard() {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.setString("current text", forType: .string)
        let old = textItem("old text")
        let store = store(items: [old], pasteboard: pasteboard)

        store.remove(old)

        #expect(pasteboard.string(forType: .string) == "current text")
    }

    @Test func deletionWithoutOutstandingCapturesRetainsNoAuthority() {
        let store = store(items: [])
        for index in 0..<300 {
            let item = textItem("deleted \(index)")
            store.add(item)
            store.remove(item)
        }

        #expect(store.items.isEmpty)
        #expect(store.retainedDeletionAuthorityCount == 0)
    }

    @Test func clearWithoutOutstandingCapturesRetainsNoAuthority() {
        let store = store(items: [textItem("cleared")])

        #expect(store.clearHistory(includePinnedAndPinboardItems: true) == 1)
        #expect(store.retainedDeletionAuthorityCount == 0)
    }

    // MARK: - Matching-only suppression, through the real capture path

    @Test func deletingUnrelatedContentDoesNotBlockAPendingCapture() async throws {
        let harness = ImagePipelineHarness(capacity: 2)
        let image = ImagePipelineFixture.redImage()
        let blobID = try await ImagePipelineFixture.blobID(of: image)

        harness.capture(image)
        await harness.encoder.waitForStart(reaching: 1)

        let unrelated = ImagePipelineFixture.textItem("unrelated text")
        harness.store.add(unrelated)
        harness.store.remove(unrelated)

        #expect(!harness.store.hasDeletedContentKey("image:\(blobID)"))
        harness.encoder.releaseAll()
        await harness.waitForHandled(1)

        #expect(
            harness.store.items.map(\.imageBlobID) == [blobID],
            "deleting unrelated content must not cancel or block an image capture"
        )
    }

    @Test func deletingMatchingResidentImageRejectsItsLateCompletionWithoutSaving() async throws {
        let harness = ImagePipelineHarness(capacity: 2)
        let image = ImagePipelineFixture.redImage()
        let prepared = try await ImagePipelineFixture.preparedMedia(of: image)

        harness.capture(image)
        await harness.encoder.waitForStart(reaching: 1)

        let resident = residentImageItem(prepared)
        harness.store.add(resident)
        harness.store.remove(resident)
        let savesAfterDeletion = harness.savedCount

        harness.encoder.releaseAll()
        await harness.waitForHandled(1)

        #expect(harness.store.items.isEmpty, "a matching late completion must not reinsert the image")
        #expect(harness.savedCount == savesAfterDeletion, "a rejected completion requests no save")
    }

    @Test func deletingMatchingUnloadedImageRejectsItsLateCompletionWithoutSaving() async throws {
        let harness = ImagePipelineHarness(capacity: 2)
        let image = ImagePipelineFixture.redImage()
        let prepared = try await ImagePipelineFixture.preparedMedia(of: image)
        let blobID = prepared.id

        harness.capture(image)
        await harness.encoder.waitForStart(reaching: 1)

        // The reference carries no bytes: rejection needs no history blob read.
        let unloaded = unloadedImageItem(blobID: blobID)
        harness.store.add(unloaded)
        harness.store.remove(unloaded)
        let savesAfterDeletion = harness.savedCount

        harness.encoder.releaseAll()
        await harness.waitForHandled(1)

        #expect(harness.store.items.isEmpty)
        #expect(harness.savedCount == savesAfterDeletion)
    }

    @Test func aNewSameContentCopyDoesNotAuthorizeAnOlderCompletion() async throws {
        let harness = ImagePipelineHarness(capacity: 3)
        let image = ImagePipelineFixture.redImage()
        let prepared = try await ImagePipelineFixture.preparedMedia(of: image)
        let blobID = prepared.id

        // Old capture, still encoding.
        harness.capture(image)
        await harness.encoder.waitForStart(reaching: 1)

        // Its card exists from an earlier session and is deleted now.
        let existing = residentImageItem(prepared)
        harness.store.add(existing)
        harness.store.remove(existing)

        // An intentional recopy of the same bytes is admitted afterwards.
        harness.capture(image)
        #expect(harness.store.pendingImageCaptureCount == 2)
        let savesBeforeDraining = harness.savedCount

        await harness.drain(through: 2)

        #expect(
            harness.store.items.map(\.imageBlobID) == [blobID],
            "only the newer matching capture may insert"
        )
        #expect(
            harness.savedCount == savesBeforeDraining + 1,
            "one card and one save: the stale completion neither inserts nor saves"
        )
    }

    @Test func aFreshRecopyOfDeletedContentIsRecorded() async throws {
        let harness = ImagePipelineHarness(capacity: 3)
        let image = ImagePipelineFixture.redImage()
        let prepared = try await ImagePipelineFixture.preparedMedia(of: image)
        let blobID = prepared.id

        harness.capture(image)
        await harness.encoder.waitForStart(reaching: 1)
        harness.encoder.releaseAll()
        await harness.waitForHandled(1)
        #expect(harness.store.items.map(\.imageBlobID) == [blobID])

        let existing = try #require(harness.store.items.first)
        harness.store.remove(existing)
        #expect(!harness.store.hasDeletedContentKey("image:\(blobID)"))

        harness.capture(image)
        await harness.encoder.waitForStart(reaching: 2)
        await harness.drain(through: 2)

        #expect(
            harness.store.items.map(\.imageBlobID) == [blobID],
            "an intentional recopy after deletion stays eligible"
        )
    }

    @Test func repeatedDeletionWidensTheCutoffWithoutAuthorizingOlderCompletions() async throws {
        let harness = ImagePipelineHarness(capacity: 3)
        let image = ImagePipelineFixture.redImage()
        let prepared = try await ImagePipelineFixture.preparedMedia(of: image)
        let blobID = prepared.id

        harness.capture(image)
        await harness.encoder.waitForStart(reaching: 1)

        let first = residentImageItem(prepared)
        harness.store.add(first)
        harness.store.remove(first)

        harness.capture(image)
        let second = residentImageItem(prepared)
        harness.store.add(second)
        harness.store.remove(second)

        await harness.drain(through: 2)

        #expect(harness.store.items.isEmpty, "a later deletion suppresses both older and equal admissions")
    }

    @Test func deletionProtectionSurvivesUnrelatedTombstoneChurnAndIsReleasedAfterwards() async throws {
        let harness = ImagePipelineHarness(capacity: 2)
        let image = ImagePipelineFixture.redImage()
        let prepared = try await ImagePipelineFixture.preparedMedia(of: image)
        let blobID = prepared.id

        harness.capture(image)
        await harness.encoder.waitForStart(reaching: 1)

        let existing = residentImageItem(prepared)
        harness.store.add(existing)
        harness.store.remove(existing)

        // Far more unrelated deletions than any fixed-size tombstone window.
        for index in 0..<300 {
            let unrelated = ImagePipelineFixture.textItem("unrelated \(index)")
            harness.store.add(unrelated)
            harness.store.remove(unrelated)
        }
        #expect(
            harness.store.retainedDeletionAuthorityCount > 0,
            "unrelated deletions still leave the outstanding key's authority retained"
        )

        harness.encoder.releaseAll()
        await harness.waitForHandled(1)

        #expect(harness.store.items.isEmpty, "churn must not authorize the outstanding stale completion")
        #expect(
            harness.store.retainedDeletionAuthorityCount == 0,
            "deletion authority is released once nothing outstanding can be rejected"
        )

        harness.capture(image)
        await harness.encoder.waitForStart(reaching: 2)
        await harness.drain(through: 2)

        #expect(harness.store.items.map(\.imageBlobID) == [blobID], "a later intentional copy remains eligible")
        AcceptanceMetrics.record(
            scenario: "model-deletion-policy",
            metric: "staleCompletionRejectedAfterUnrelatedDeletions",
            expected: "true",
            observed: "\(harness.store.items.map(\.imageBlobID) == [blobID])"
        )
    }

    // MARK: - Fixtures

    private func store(items: [ClipboardItem], pasteboard: NSPasteboard = .withUniqueName()) -> ClipboardStore {
        ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults()),
            sourceTracker: CopySourceTracker(),
            initialItems: items,
            pasteboard: pasteboard,
            persistItems: { _ in }
        )
    }

    private func imageItem(data: Data, pinboardName: String? = nil, isPinned: Bool = false) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .image,
            title: "Image",
            preview: "10 x 10",
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(),
            isPinned: isPinned,
            pinboardName: pinboardName,
            textValue: nil,
            fileURLs: [],
            imageData: data
        )
    }

    /// A card whose bytes are genuinely resident, built from the finalized
    /// payload so its content key matches the pipeline's identity.
    private func residentImageItem(_ prepared: PreparedMedia) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .image,
            title: "Image",
            preview: "32 x 32",
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: prepared.data,
            imageBlobID: prepared.id
        )
    }

    private func unloadedImageItem(blobID: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .image,
            title: "Image",
            preview: "10 x 10",
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: nil,
            imageBlobID: blobID
        )
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func textItem(_ text: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .text,
            title: text,
            preview: text,
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(),
            isPinned: false,
            pinboardName: nil,
            textValue: text,
            fileURLs: [],
            imageData: nil
        )
    }

    private func solidImage(color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        image.unlockFocus()
        return image
    }

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "ClipboardStoreImageDeletionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}