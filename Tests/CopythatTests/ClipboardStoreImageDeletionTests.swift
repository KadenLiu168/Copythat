@testable import Copythat
import AppKit
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct ClipboardStoreImageDeletionTests {
    @Test func removingImageRemembersDeletedContentKey() {
        let image = imageItem(data: Data([1, 2, 3]))
        let store = store(items: [image])

        store.remove(image)

        #expect(store.items.isEmpty)
        #expect(store.hasDeletedContentKey(image.contentKey))
    }

    @Test func encodedImageCompletionIsRejectedAfterDeletion() {
        let image = imageItem(data: Data([4, 5, 6]))
        let store = store(items: [image])

        store.remove(image)

        #expect(!store.shouldInsertEncodedItem(image))
    }

    @Test func clearingHistoryRemembersOnlyActuallyRemovedItems() {
        let ordinary = imageItem(data: Data([7]))
        let pinned = imageItem(data: Data([8]), isPinned: true)
        let assigned = imageItem(data: Data([9]), pinboardName: "Work")
        let store = store(items: [ordinary, pinned, assigned])

        let removedCount = store.clearHistory(includePinnedAndPinboardItems: false)

        #expect(removedCount == 1)
        #expect(store.hasDeletedContentKey(ordinary.contentKey))
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
        #expect(store.hasDeletedContentKey(image.contentKey))
    }

    @Test func deletingCurrentImageClearsPasteboardAndCancelsPendingEncoding() async throws {
        let pasteboard = NSPasteboard.general
        let image = solidImage(color: .systemRed)
        let store = store(items: [])
        let imageData = try #require(store.normalizedImageData(for: image))
        let captured = imageItem(data: imageData)
        store.add(captured)
        pasteboard.clearContents()
        pasteboard.writeObjects([image])

        store.remove(captured)

        #expect(store.items.isEmpty)
        #expect(!store.hasPendingImageEncodingTask)
        #expect(pasteboard.types?.isEmpty ?? true)
    }

    @Test func deletingOlderItemDoesNotClearCurrentPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("current text", forType: .string)
        let old = textItem("old text")
        let store = store(items: [old])

        store.remove(old)

        #expect(pasteboard.string(forType: .string) == "current text")
    }

    private func store(items: [ClipboardItem]) -> ClipboardStore {
        ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults()),
            sourceTracker: CopySourceTracker(),
            initialItems: items,
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
