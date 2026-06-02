@testable import Copythat
import Foundation
import Testing

struct ClipboardHistoryPolicyTests {
    @Test func duplicateCopiesDoNotRemovePinnedItems() {
        let pinned = item(text: "same", isPinned: true)
        let newer = item(text: "same", isPinned: false)

        let result = ClipboardHistoryPolicy.adding(newer, to: [pinned], limit: 10)

        #expect(result.count == 2)
        #expect(result[0].id == newer.id)
        #expect(result[1].id == pinned.id)
        #expect(result[1].isPinned)
    }

    @Test func overflowDoesNotRemovePinnedItemsWhenAllItemsArePinned() {
        let oldPinned = item(text: "old", isPinned: true)
        let newPinned = item(text: "new", isPinned: true)

        let result = ClipboardHistoryPolicy.adding(newPinned, to: [oldPinned], limit: 1)

        #expect(result.map(\.id) == [newPinned.id, oldPinned.id])
        #expect(result.allSatisfy { $0.isPinned })
    }

    @Test func unpinnedImageHistoryIsCapped() {
        let existing = (0..<100).map { imageItem(index: $0, isPinned: false) }
        let pinned = imageItem(index: 100, isPinned: true)
        let newest = imageItem(index: 101, isPinned: false)

        let result = ClipboardHistoryPolicy.adding(newest, to: existing + [pinned], limit: 1_000)
        let unpinnedImageCount = result.filter { $0.kind == .image && !$0.isPinned }.count

        #expect(unpinnedImageCount == 100)
        #expect(result.contains { $0.id == pinned.id })
        #expect(result.contains { $0.id == newest.id })
    }

    private func item(text: String, isPinned: Bool) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .text,
            title: text,
            preview: text,
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(),
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
