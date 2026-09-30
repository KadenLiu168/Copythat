import Foundation

/// Count-only observation seam for policy item visits. One recorder belongs to
/// one test: counting is lock-guarded and never holds clipboard content.
final class HistoryPolicyVisitRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var visits = 0

    func record() {
        lock.lock()
        visits += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return visits
    }
}

/// Observation seam for actual per-item classification and retention visits.
/// The recorder is task-local, so parallel tests never share counters and
/// production runs without one observe nothing. Policy work is synchronous, so
/// no detached boundary needs explicit propagation.
enum ClipboardHistoryPolicyObservation {
    @TaskLocal static var recorder: HistoryPolicyVisitRecorder?

    static func recordVisit() {
        recorder?.record()
    }
}

enum ClipboardHistoryPolicy {
    private static let maxUnpinnedImageItems = 100

    /// Matches classified for one insertion, in history order. The policy owns
    /// this summary, so logging consumes the decision instead of rescanning
    /// history for duplicate facts.
    struct DuplicateSummary: Equatable {
        let count: Int
        let itemIDs: [UUID]
        let pinnedCount: Int

        var itemIDList: String {
            itemIDs.map(\.uuidString).joined(separator: ",")
        }
    }

    struct InsertionResult: Equatable {
        let items: [ClipboardItem]
        /// The entry a caller may select: the moved duplicate, or the new item
        /// only when it was retained. Nil when nothing new is selectable.
        let selectedItemID: UUID?
        /// The newly copied item when it survived retention; nil for a moved
        /// duplicate and for an incoming item discarded immediately.
        let insertedItem: ClipboardItem?
        /// IDs of existing items removed by retention, in history order.
        let removedItemIDs: [UUID]
        let duplicateSummary: DuplicateSummary
    }

    struct EnforcementResult: Equatable {
        let items: [ClipboardItem]
        /// IDs of existing items removed by retention, in history order.
        let removedItemIDs: [UUID]
    }

    static func adding(_ item: ClipboardItem, to items: [ClipboardItem], limit: Int) -> InsertionResult {
        let incomingContentKey = item.contentKey
        var matchingIDs: [UUID] = []
        var matchingPinnedCount = 0
        var firstUnpinnedMatchIndex: Int?

        for (index, existing) in items.enumerated() {
            ClipboardHistoryPolicyObservation.recordVisit()
            guard existing.contentKey == incomingContentKey else { continue }
            matchingIDs.append(existing.id)
            if existing.isPinned {
                matchingPinnedCount += 1
            } else if firstUnpinnedMatchIndex == nil {
                firstUnpinnedMatchIndex = index
            }
        }

        let duplicateSummary = DuplicateSummary(
            count: matchingIDs.count,
            itemIDs: matchingIDs,
            pinnedCount: matchingPinnedCount
        )

        let head: ClipboardItem
        let headIsIncomingItem: Bool
        let skippedOriginalIndex: Int?
        if let firstUnpinnedMatchIndex {
            head = items[firstUnpinnedMatchIndex]
            headIsIncomingItem = false
            skippedOriginalIndex = firstUnpinnedMatchIndex
        } else {
            head = item
            headIsIncomingItem = true
            skippedOriginalIndex = nil
        }

        let retention = retain(
            head: head,
            headIsOriginal: !headIsIncomingItem,
            originals: items,
            skippedOriginalIndex: skippedOriginalIndex,
            limit: limit
        )
        return InsertionResult(
            items: retention.items,
            selectedItemID: retention.headSurvived ? head.id : nil,
            insertedItem: headIsIncomingItem && retention.headSurvived ? head : nil,
            removedItemIDs: retention.removedOriginalIDs,
            duplicateSummary: duplicateSummary
        )
    }

    static func enforcingLimits(on items: [ClipboardItem], limit: Int) -> EnforcementResult {
        let retention = retain(
            head: nil,
            headIsOriginal: false,
            originals: items,
            skippedOriginalIndex: nil,
            limit: limit
        )
        return EnforcementResult(items: retention.items, removedItemIDs: retention.removedOriginalIDs)
    }

    private struct RetentionOutcome {
        let items: [ClipboardItem]
        let removedOriginalIDs: [UUID]
        let headSurvived: Bool
    }

    /// Retains the logical newest-first sequence with pinned capacity reserved
    /// up front: one scan counts pinned items, then one scan decides each
    /// candidate in visit order and appends survivors. Visit order is already
    /// newest-first, so no middle-array removal or second compaction pass is
    /// needed.
    private static func retain(
        head: ClipboardItem?,
        headIsOriginal: Bool,
        originals: [ClipboardItem],
        skippedOriginalIndex: Int?,
        limit: Int
    ) -> RetentionOutcome {
        var pinnedCount = 0
        if let head {
            ClipboardHistoryPolicyObservation.recordVisit()
            if head.isPinned { pinnedCount += 1 }
        }
        for (index, item) in originals.enumerated() where index != skippedOriginalIndex {
            ClipboardHistoryPolicyObservation.recordVisit()
            if item.isPinned { pinnedCount += 1 }
        }

        let effectiveLimit = max(limit, 1)
        let ordinaryCapacity = max(0, effectiveLimit - pinnedCount)
        var retainedItems: [ClipboardItem] = []
        var removedOriginalIDs: [UUID] = []
        var headSurvived = false
        var retainedUnpinnedImages = 0
        var retainedOrdinaryCount = 0

        func shouldRetain(_ candidate: ClipboardItem) -> Bool {
            if candidate.isPinned { return true }
            if candidate.kind == .image, retainedUnpinnedImages >= maxUnpinnedImageItems {
                // An image rejected by the image bound never consumes the
                // ordinary-item quota, matching the original image-first policy.
                return false
            }
            guard retainedOrdinaryCount < ordinaryCapacity else { return false }
            retainedOrdinaryCount += 1
            if candidate.kind == .image {
                retainedUnpinnedImages += 1
            }
            return true
        }

        if let head {
            ClipboardHistoryPolicyObservation.recordVisit()
            if shouldRetain(head) {
                retainedItems.append(head)
                headSurvived = true
            } else if headIsOriginal {
                removedOriginalIDs.append(head.id)
            }
        }
        for (index, item) in originals.enumerated() where index != skippedOriginalIndex {
            ClipboardHistoryPolicyObservation.recordVisit()
            if shouldRetain(item) {
                retainedItems.append(item)
            } else {
                removedOriginalIDs.append(item.id)
            }
        }

        return RetentionOutcome(
            items: retainedItems,
            removedOriginalIDs: removedOriginalIDs,
            headSurvived: headSurvived
        )
    }
}
