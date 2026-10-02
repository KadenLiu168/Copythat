@testable import Copythat
import Foundation
import Testing

/// The loading surface contract, pinned so a refactor cannot quietly restore
/// an empty timeline or an authoritative zero while history is still unknown.
///
/// These assert the exact strings observed in a real production launch over
/// persisted media-heavy history, so the panel and Settings surfaces stay
/// verifiable without relying on catching a sub-second window by eye.
struct HistoryPresentationTests {

    // MARK: - Loading outranks every empty state

    @Test func loadingIsShownInsteadOfTheEmptyTimeline() throws {
        let copy = try #require(HistoryPresentation.timelineCopy(
            isRestoring: true,
            isFilteredEmpty: true,
            searchText: "",
            board: Pinboard.all
        ))
        #expect(copy.title == "Loading clipboard history…")
        #expect(copy.description == "Restoring your saved clips.")
    }

    @Test func loadingOutranksSearchAndPinboardEmptyCopy() throws {
        for board in [Pinboard.all, .pinned, .custom("Work"), .custom("")] {
            let copy = try #require(HistoryPresentation.timelineCopy(
                isRestoring: true,
                isFilteredEmpty: true,
                searchText: "anything",
                board: board
            ))
            #expect(copy.title == HistoryPresentation.loadingTitle, "\(board) must not claim empty history")
        }
    }

    @Test func loadingWinsEvenWhenFiltersWouldMatchSomething() throws {
        // An in-flight query can never produce results before the baseline
        // exists, so a "no matches" claim would be wrong in both directions.
        let copy = try #require(HistoryPresentation.timelineCopy(
            isRestoring: true,
            isFilteredEmpty: false,
            searchText: "Item 499",
            board: Pinboard.all
        ))
        #expect(copy.title == HistoryPresentation.loadingTitle)
    }

    // MARK: - Counts never read as an authoritative zero

    @Test func loadingCountsAreIdentifiedAsLoading() {
        #expect(HistoryPresentation.visibleCount(isRestoring: true, visible: 0) == "Loading…")
        #expect(HistoryPresentation.visibleCount(isRestoring: true, visible: 500) == "Loading…")
        #expect(HistoryPresentation.cardSummary(isRestoring: true, cardCount: 0) == "Clipboard cards: loading…")
        #expect(HistoryPresentation.cardSummary(isRestoring: true, cardCount: 500) == "Clipboard cards: loading…")
    }

    @Test func readyCountsReportRealValues() {
        #expect(HistoryPresentation.visibleCount(isRestoring: false, visible: 0) == "0 items")
        #expect(HistoryPresentation.visibleCount(isRestoring: false, visible: 500) == "500 items")
        #expect(HistoryPresentation.cardSummary(isRestoring: false, cardCount: 500) == "Clipboard cards: 500")
    }

    // MARK: - Ready surfaces return to ordinary behaviour

    @Test func readyHistoryWithCardsRendersCards() {
        #expect(HistoryPresentation.timelineCopy(
            isRestoring: false,
            isFilteredEmpty: false,
            searchText: "",
            board: Pinboard.all
        ) == nil)
    }

    @Test func readyEmptyHistoryKeepsItsContextualCopy() throws {
        let empty = try #require(HistoryPresentation.timelineCopy(
            isRestoring: false,
            isFilteredEmpty: true,
            searchText: "",
            board: Pinboard.all
        ))
        #expect(empty.title == "Copy something to start")

        let search = try #require(HistoryPresentation.timelineCopy(
            isRestoring: false,
            isFilteredEmpty: true,
            searchText: "query",
            board: Pinboard.all
        ))
        #expect(search.title == "No matching clips")

        let pinned = try #require(HistoryPresentation.timelineCopy(
            isRestoring: false,
            isFilteredEmpty: true,
            searchText: "",
            board: .pinned
        ))
        #expect(pinned.title == "No pinned clips")

        let named = try #require(HistoryPresentation.timelineCopy(
            isRestoring: false,
            isFilteredEmpty: true,
            searchText: "",
            board: .custom("Work")
        ))
        #expect(named.title == "No clips in Work")

        let unnamed = try #require(HistoryPresentation.timelineCopy(
            isRestoring: false,
            isFilteredEmpty: true,
            searchText: "",
            board: .custom("")
        ))
        #expect(unnamed.title == "No clips in this pinboard")
    }

    @Test func whitespaceOnlyQueryIsNotTreatedAsSearch() throws {
        let copy = try #require(HistoryPresentation.timelineCopy(
            isRestoring: false,
            isFilteredEmpty: true,
            searchText: "   ",
            board: Pinboard.all
        ))
        #expect(copy.title == "Copy something to start")
    }

    // MARK: - Clear availability follows readiness

    @Test func clearCardsIsUnavailableWhileLoadingOrMutationBlocked() {
        #expect(HistoryPresentation.canClearCards(isRestoring: true, canMutateHistory: true, cardCount: 500) == false)
        #expect(HistoryPresentation.canClearCards(isRestoring: false, canMutateHistory: false, cardCount: 500) == false)
        #expect(HistoryPresentation.canClearCards(isRestoring: true, canMutateHistory: false, cardCount: 500) == false)
        #expect(HistoryPresentation.canClearCards(isRestoring: false, canMutateHistory: true, cardCount: 0) == false)
    }

    @Test func clearCardsIsAvailableOnlyWhenReadyWithCards() {
        #expect(HistoryPresentation.canClearCards(isRestoring: false, canMutateHistory: true, cardCount: 500) == true)
    }
}