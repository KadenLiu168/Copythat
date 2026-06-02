import Foundation

enum ClipboardHistoryPolicy {
    private static let maxUnpinnedImageItems = 100

    static func adding(_ item: ClipboardItem, to items: [ClipboardItem], limit: Int) -> [ClipboardItem] {
        let effectiveLimit = max(limit, 1)
        var updated = items.filter { existing in
            existing.isPinned || existing.contentKey != item.contentKey
        }
        updated.insert(item, at: 0)

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
