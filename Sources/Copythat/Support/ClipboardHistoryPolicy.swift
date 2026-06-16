import Foundation

enum ClipboardHistoryPolicy {
    private static let maxUnpinnedImageItems = 100

    struct InsertionResult: Equatable {
        let items: [ClipboardItem]
        let selectedID: UUID
        let insertedItem: ClipboardItem?
    }

    static func adding(_ item: ClipboardItem, to items: [ClipboardItem], limit: Int) -> InsertionResult {
        let effectiveLimit = max(limit, 1)
        if let duplicateIndex = items.firstIndex(where: { !$0.isPinned && $0.contentKey == item.contentKey }) {
            let existing = items[duplicateIndex]
            var updated = items
            updated.remove(at: duplicateIndex)
            updated.insert(existing, at: 0)
            updated = limited(updated, effectiveLimit: effectiveLimit)
            return InsertionResult(items: updated, selectedID: existing.id, insertedItem: nil)
        }

        var updated = items.filter { existing in
            existing.isPinned || existing.contentKey != item.contentKey
        }
        updated.insert(item, at: 0)
        updated = limited(updated, effectiveLimit: effectiveLimit)
        return InsertionResult(items: updated, selectedID: item.id, insertedItem: item)
    }

    private static func limited(_ items: [ClipboardItem], effectiveLimit: Int) -> [ClipboardItem] {
        var updated = items
        while updated.filter({ $0.kind == .image && !$0.isPinned }).count > maxUnpinnedImageItems {
            guard let removalIndex = updated.lastIndex(where: { $0.kind == .image && !$0.isPinned }) else {
                break
            }
            updated.remove(at: removalIndex)
        }

        while updated.count > effectiveLimit {
            guard let removalIndex = updated.lastIndex(where: { !$0.isPinned }) else {
                break
            }
            updated.remove(at: removalIndex)
        }

        return updated
    }
}
