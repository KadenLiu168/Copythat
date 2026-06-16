@testable import Copythat
import Foundation
import Testing

struct ClipboardHistoryPolicyTests {
    @Test func duplicateCopiesDoNotRemovePinnedItems() {
        let pinned = item(text: "same", isPinned: true)
        let newer = item(text: "same", isPinned: false)

        let result = ClipboardHistoryPolicy.adding(newer, to: [pinned], limit: 10)

        #expect(result.items.count == 2)
        #expect(result.items[0].id == newer.id)
        #expect(result.items[1].id == pinned.id)
        #expect(result.items[1].isPinned)
        #expect(result.selectedID == newer.id)
        #expect(result.insertedItem?.id == newer.id)
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
        #expect(result.selectedID == original.id)
        #expect(result.insertedItem == nil)
    }

    @Test func overflowDoesNotRemovePinnedItemsWhenAllItemsArePinned() {
        let oldPinned = item(text: "old", isPinned: true)
        let newPinned = item(text: "new", isPinned: true)

        let result = ClipboardHistoryPolicy.adding(newPinned, to: [oldPinned], limit: 1)

        #expect(result.items.map(\.id) == [newPinned.id, oldPinned.id])
        #expect(result.items.allSatisfy { $0.isPinned })
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
