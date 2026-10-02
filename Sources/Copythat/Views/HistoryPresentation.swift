import Foundation

/// Loading and empty copy, counts and availability for the panel and Settings
/// surfaces.
///
/// Restoration owns the wording so both surfaces agree on one rule: while the
/// persisted baseline is still loading, history is *unknown*, never empty, and
/// a count must never be presented as an authoritative zero.
enum HistoryPresentation {
    /// Shown instead of any empty, search or pinboard copy while restoring.
    static let loadingTitle = "Loading clipboard history…"
    static let loadingDescription = "Restoring your saved clips."
    /// A count taken while loading must not read as "0 items".
    static let loadingCount = "Loading…"
    static let loadingCardSummary = "Clipboard cards: loading…"

    /// Copy for the history content area, or `nil` when it should render cards.
    ///
    /// Loading outranks every empty state: before the baseline is installed,
    /// an empty timeline or a "no matches" claim would be a statement about
    /// history the Store has not read yet.
    static func timelineCopy(
        isRestoring: Bool,
        isFilteredEmpty: Bool,
        searchText: String,
        board: Pinboard
    ) -> (title: String, description: String)? {
        if isRestoring { return (loadingTitle, loadingDescription) }
        guard isFilteredEmpty else { return nil }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return ("No matching clips", "Try another search or clear the query.")
        }
        switch board.kind {
        case .all, .unknown:
            return ("Copy something to start", "Text, links, images, and file paths will appear here.")
        case .pinned:
            return ("No pinned clips", "Pin copied items to keep them close.")
        case .custom:
            let title = board.title.isEmpty ? "this pinboard" : board.title
            return ("No clips in \(title)", "Move copied items here from a card menu.")
        }
    }

    /// Footer count for the visible cards.
    static func visibleCount(isRestoring: Bool, visible: Int) -> String {
        isRestoring ? loadingCount : "\(visible) items"
    }

    /// Settings' card-count summary.
    static func cardSummary(isRestoring: Bool, cardCount: Int) -> String {
        isRestoring ? loadingCardSummary : "Clipboard cards: \(cardCount)"
    }

    /// Whether the Settings clear-cards action is available. A loading or
    /// otherwise mutation-blocked Store cannot be cleared, and neither can an
    /// empty one.
    static func canClearCards(isRestoring: Bool, canMutateHistory: Bool, cardCount: Int) -> Bool {
        !isRestoring && canMutateHistory && cardCount > 0
    }
}