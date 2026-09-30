@testable import Copythat
import CryptoKit
import Foundation
import Testing

struct ClipboardHistoryPolicyTests {
    // MARK: - Insertion

    @Test func newItemIsInsertedAtTheNewestPosition() {
        let existing = item(text: "existing")
        let added = item(text: "added")

        let result = ClipboardHistoryPolicy.adding(added, to: [existing], limit: 10)

        #expect(result.items.map(\.id) == [added.id, existing.id])
        #expect(result.selectedItemID == added.id)
        #expect(result.insertedItem?.id == added.id)
        #expect(result.removedItemIDs.isEmpty)
        #expect(result.duplicateSummary == .init(count: 0, itemIDs: [], pinnedCount: 0))
    }

    @Test func duplicateCopiesDoNotRemovePinnedItems() {
        let pinned = item(text: "same", isPinned: true)
        let newer = item(text: "same", isPinned: false)

        let result = ClipboardHistoryPolicy.adding(newer, to: [pinned], limit: 10)

        #expect(result.items.count == 2)
        #expect(result.items[0].id == newer.id)
        #expect(result.items[1].id == pinned.id)
        #expect(result.items[1].isPinned)
        #expect(result.selectedItemID == newer.id)
        #expect(result.insertedItem?.id == newer.id)
        #expect(result.removedItemIDs.isEmpty)
    }

    @Test func duplicateUnpinnedContentMovesExistingItemWithoutReplacingSource() {
        let originalDate = Date(timeIntervalSince1970: 10)
        let original = item(
            text: "same",
            sourceApp: "豆包",
            sourceAppIconData: Data([1, 2, 3]),
            createdAt: originalDate
        )
        let other = item(text: "other")
        let newer = item(
            text: "same",
            sourceApp: "ChatGPT",
            sourceAppIconData: Data([9, 8, 7]),
            createdAt: Date(timeIntervalSince1970: 20)
        )

        let result = ClipboardHistoryPolicy.adding(newer, to: [other, original], limit: 10)

        #expect(result.items.map(\.id) == [original.id, other.id])
        #expect(result.items[0].sourceApp == "豆包")
        #expect(result.items[0].sourceAppIconData == Data([1, 2, 3]))
        #expect(result.items[0].createdAt == originalDate)
        #expect(result.selectedItemID == original.id)
        #expect(result.insertedItem == nil)
        #expect(result.removedItemIDs.isEmpty)
        #expect(result.duplicateSummary.itemIDs == [original.id])
    }

    @Test func firstUnpinnedDuplicateWinsWhenSeveralOrdinaryEntriesMatch() {
        let newerDuplicate = item(text: "same", sourceApp: "Newer", createdAt: Date(timeIntervalSince1970: 20))
        let olderDuplicate = item(text: "same", sourceApp: "Older", createdAt: Date(timeIntervalSince1970: 10))
        let incoming = item(text: "same", sourceApp: "Incoming", createdAt: Date(timeIntervalSince1970: 30))

        let result = ClipboardHistoryPolicy.adding(incoming, to: [newerDuplicate, olderDuplicate], limit: 10)

        #expect(result.items.map(\.id) == [newerDuplicate.id, olderDuplicate.id])
        #expect(result.items[0].sourceApp == "Newer")
        #expect(result.items[0].createdAt == newerDuplicate.createdAt)
        #expect(result.selectedItemID == newerDuplicate.id)
        #expect(result.insertedItem == nil)
        #expect(result.duplicateSummary.itemIDs == [newerDuplicate.id, olderDuplicate.id])
    }

    @Test func duplicateSummaryReportsMatchesInHistoryOrder() {
        let newerDuplicate = item(text: "same", sourceApp: "Newer")
        let other = item(text: "other")
        let pinnedDuplicate = item(text: "same", sourceApp: "Pinned", isPinned: true)
        let pending = item(text: "same", sourceApp: "Pending")

        let result = ClipboardHistoryPolicy.adding(
            pending,
            to: [newerDuplicate, other, pinnedDuplicate],
            limit: 10
        )

        #expect(result.duplicateSummary.count == 2)
        #expect(result.duplicateSummary.itemIDs == [newerDuplicate.id, pinnedDuplicate.id])
        #expect(result.duplicateSummary.pinnedCount == 1)
        #expect(!result.duplicateSummary.itemIDList.contains(other.id.uuidString))
        #expect(result.selectedItemID == newerDuplicate.id)
        #expect(result.insertedItem == nil)
    }

    @Test func unloadedImageDuplicateMovesExistingItemWithoutReplacingSource() {
        let bytes = Data([21, 22, 23])
        let originalDate = Date(timeIntervalSince1970: 10)
        let unloaded = imageItem(
            data: nil,
            imageBlobID: sha256Hex(bytes),
            sourceApp: "豆包",
            sourceAppIconData: Data([1, 2, 3]),
            createdAt: originalDate
        )
        let other = item(text: "other")
        let captured = imageItem(data: bytes, sourceApp: "ChatGPT")

        let result = ClipboardHistoryPolicy.adding(captured, to: [other, unloaded], limit: 10)

        #expect(result.items.map(\.id) == [unloaded.id, other.id])
        #expect(result.items[0].sourceApp == "豆包")
        #expect(result.items[0].createdAt == originalDate)
        #expect(result.items[0].imageBlobID == sha256Hex(bytes))
        #expect(result.items[0].imageData == nil)
        #expect(result.selectedItemID == unloaded.id)
        #expect(result.insertedItem == nil)
    }

    @Test func pinnedUnloadedImageSurvivesNewDuplicateCapture() {
        let bytes = Data([31, 32, 33])
        let pinned = imageItem(data: nil, imageBlobID: sha256Hex(bytes), isPinned: true)
        let captured = imageItem(data: bytes)

        let result = ClipboardHistoryPolicy.adding(captured, to: [pinned], limit: 10)

        #expect(result.items.map(\.id) == [captured.id, pinned.id])
        #expect(result.items[1].isPinned)
        #expect(result.items[1].imageData == nil)
        #expect(result.selectedItemID == captured.id)
        #expect(result.insertedItem?.id == captured.id)
        #expect(result.duplicateSummary.pinnedCount == 1)
    }

    @Test func pinnedItemsAtTheLimitDiscardTheIncomingItem() {
        let pinnedItems = (0..<100).map { item(text: "pinned \($0)", isPinned: true) }
        let incoming = item(text: "incoming")

        let result = ClipboardHistoryPolicy.adding(incoming, to: pinnedItems, limit: 100)

        #expect(result.items.map(\.id) == pinnedItems.map(\.id))
        #expect(result.selectedItemID == nil)
        #expect(result.insertedItem == nil)
        #expect(result.removedItemIDs.isEmpty)
    }

    @Test func pinnedItemsAboveTheLimitDiscardTheIncomingItem() {
        let pinnedItems = (0..<3).map { item(text: "pinned \($0)", isPinned: true) }
        let incoming = item(text: "incoming")

        let result = ClipboardHistoryPolicy.adding(incoming, to: pinnedItems, limit: 2)

        #expect(result.items.map(\.id) == pinnedItems.map(\.id))
        #expect(result.selectedItemID == nil)
        #expect(result.insertedItem == nil)
        #expect(result.removedItemIDs.isEmpty)
    }

    @Test func addingRemovesOldestOrdinaryItemsAndReportsTheirIDs() {
        let existing = (0..<10).map { item(text: "item \($0)") }
        let incoming = item(text: "incoming")

        let result = ClipboardHistoryPolicy.adding(incoming, to: existing, limit: 5)

        #expect(result.items.map(\.id) == [incoming.id] + existing.prefix(4).map(\.id))
        #expect(result.removedItemIDs == existing.suffix(6).map(\.id))
        #expect(result.selectedItemID == incoming.id)
        #expect(result.insertedItem?.id == incoming.id)
    }

    @Test func overflowDoesNotRemovePinnedItemsWhenAllItemsArePinned() {
        let oldPinned = item(text: "old", isPinned: true)
        let newPinned = item(text: "new", isPinned: true)

        let result = ClipboardHistoryPolicy.adding(newPinned, to: [oldPinned], limit: 1)

        #expect(result.items.map(\.id) == [newPinned.id, oldPinned.id])
        #expect(result.items.allSatisfy { $0.isPinned })
        #expect(result.selectedItemID == newPinned.id)
        #expect(result.insertedItem?.id == newPinned.id)
        #expect(result.removedItemIDs.isEmpty)
    }

    @Test func imageCapAndPinnedItemsInterleaveWithoutRemovingPinnedItems() {
        let existingImages = (0..<100).map { imageItem(index: $0, isPinned: false) }
        let pinnedText = item(text: "pinned text", isPinned: true)
        let pinnedImage = imageItem(index: 200, isPinned: true)
        let incomingImage = imageItem(index: 201, isPinned: false)

        let result = ClipboardHistoryPolicy.adding(
            incomingImage,
            to: existingImages + [pinnedText, pinnedImage],
            limit: 1_000
        )

        #expect(result.items.first?.id == incomingImage.id)
        #expect(result.items.filter { $0.kind == .image && !$0.isPinned }.count == 100)
        #expect(!result.items.contains { $0.id == existingImages[99].id })
        #expect(result.items.contains { $0.id == pinnedText.id })
        #expect(result.items.contains { $0.id == pinnedImage.id })
        #expect(result.selectedItemID == incomingImage.id)
        #expect(result.removedItemIDs == [existingImages[99].id])
    }

    @Test func imageCapRejectionDoesNotConsumeOrdinaryCapacity() {
        let existingImages = (0..<100).map { imageItem(index: $0, isPinned: false) }
        let newerText = item(text: "newer text")
        let olderText = item(text: "older text")
        let incomingImage = imageItem(index: 500, isPinned: false)

        let result = ClipboardHistoryPolicy.adding(
            incomingImage,
            to: existingImages + [newerText, olderText],
            limit: 102
        )

        #expect(result.items.contains { $0.id == newerText.id })
        #expect(result.items.contains { $0.id == olderText.id })
        #expect(!result.items.contains { $0.id == existingImages[99].id })
        #expect(result.items.filter { $0.kind == .image }.count == 100)
        #expect(result.removedItemIDs == [existingImages[99].id])
    }

    @Test func unpinnedImageHistoryIsCapped() {
        let existing = (0..<100).map { imageItem(index: $0, isPinned: false) }
        let pinned = imageItem(index: 100, isPinned: true)
        let newest = imageItem(index: 101, isPinned: false)

        let result = ClipboardHistoryPolicy.adding(newest, to: existing + [pinned], limit: 1_000)
        let unpinnedImageCount = result.items.filter { $0.kind == .image && !$0.isPinned }.count

        #expect(unpinnedImageCount == 100)
        #expect(result.items.contains { $0.id == pinned.id })
        #expect(result.items.contains { $0.id == newest.id })
        #expect(result.removedItemIDs == [existing[99].id])
        #expect(result.selectedItemID == newest.id)
        #expect(result.insertedItem?.id == newest.id)
    }

    // MARK: - Existing-history enforcement

    @Test func enforcingLimitsTrimsOldestOrdinaryItemsAndReportsTheirIDs() {
        let existing = (0..<10).map { item(text: "item \($0)") }

        let result = ClipboardHistoryPolicy.enforcingLimits(on: existing, limit: 4)

        #expect(result.items.map(\.id) == existing.prefix(4).map(\.id))
        #expect(result.removedItemIDs == existing.suffix(6).map(\.id))
    }

    @Test func enforcingLimitsKeepsPinnedItemsAndReservesTheirCapacity() {
        let pinned = (0..<3).map { item(text: "pinned \($0)", isPinned: true) }
        let ordinary = (0..<5).map { item(text: "ordinary \($0)") }

        let result = ClipboardHistoryPolicy.enforcingLimits(on: pinned + ordinary, limit: 4)

        #expect(result.items.map(\.id) == pinned.map(\.id) + [ordinary[0].id])
        #expect(result.removedItemIDs == ordinary.dropFirst().map(\.id))
    }

    @Test func enforcingLimitsAppliesTheUnpinnedImageBound() {
        let images = (0..<102).map { imageItem(index: $0, isPinned: false) }
        let pinnedImage = imageItem(index: 200, isPinned: true)

        let result = ClipboardHistoryPolicy.enforcingLimits(on: images + [pinnedImage], limit: 1_000)

        #expect(result.items.filter { $0.kind == .image && !$0.isPinned }.count == 100)
        #expect(result.items.contains { $0.id == pinnedImage.id })
        #expect(result.removedItemIDs == [images[100].id, images[101].id])
    }

    @Test func enforcingLimitsWithinBoundsKeepsHistoryAndReportsNoRemovals() {
        let items = (0..<3).map { item(text: "item \($0)") }

        let result = ClipboardHistoryPolicy.enforcingLimits(on: items, limit: 10)

        #expect(result.items == items)
        #expect(result.removedItemIDs.isEmpty)
    }

    @Test func enforcingLimitsKeepsFullyPinnedHistoryAboveTheLimit() {
        let pinned = (0..<5).map { item(text: "pinned \($0)", isPinned: true) }

        let result = ClipboardHistoryPolicy.enforcingLimits(on: pinned, limit: 2)

        #expect(result.items == pinned)
        #expect(result.removedItemIDs.isEmpty)
    }

    @Test func thousandItemTrimVisitsEachItemALinearNumberOfTimes() {
        let items = (0..<1_000).map { item(text: "item \($0)") }
        let recorder = HistoryPolicyVisitRecorder()

        let result = ClipboardHistoryPolicyObservation.$recorder.withValue(recorder) {
            ClipboardHistoryPolicy.enforcingLimits(on: items, limit: 100)
        }

        #expect(result.items.map(\.id) == items.prefix(100).map(\.id))
        #expect(result.removedItemIDs == items.dropFirst(100).map(\.id))
        #expect(recorder.count >= 2_000, "both policy passes must count every visited item")
        #expect(recorder.count <= 4_000, "1,000 items must be visited a linear number of times")
    }

    private func item(
        text: String,
        sourceApp: String = "Tests",
        sourceAppIconData: Data? = nil,
        createdAt: Date = Date(),
        isPinned: Bool = false
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .text,
            title: text,
            preview: text,
            sourceApp: sourceApp,
            sourceAppIconData: sourceAppIconData,
            createdAt: createdAt,
            isPinned: isPinned,
            pinboardName: nil,
            textValue: text,
            fileURLs: [],
            imageData: nil
        )
    }

    private func imageItem(
        data: Data?,
        imageBlobID: String? = nil,
        sourceApp: String = "Tests",
        sourceAppIconData: Data? = nil,
        createdAt: Date = Date(),
        isPinned: Bool = false
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .image,
            title: "Image",
            preview: "10 x 10",
            sourceApp: sourceApp,
            sourceAppIconData: sourceAppIconData,
            createdAt: createdAt,
            isPinned: isPinned,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: data,
            imageBlobID: imageBlobID
        )
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func imageItem(index: Int, isPinned: Bool) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .image,
            title: "Image \(index)",
            preview: "\(index)",
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(),
            isPinned: isPinned,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: Data([UInt8(index % 255)])
        )
    }
}
