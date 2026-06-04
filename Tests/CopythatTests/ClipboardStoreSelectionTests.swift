@testable import Copythat
import Combine
import Foundation
import Testing

@MainActor
struct ClipboardStoreSelectionTests {
    @Test func selectingCurrentItemDoesNotPublishChange() {
        let first = item(text: "First")
        let store = store(items: [first, item(text: "Second")])
        store.select(first)

        var publishCount = 0
        let cancellable = store.objectWillChange.sink {
            publishCount += 1
        }

        store.select(first)
        store.moveSelection(-1)

        #expect(store.selectedID == first.id)
        #expect(publishCount == 0)
        cancellable.cancel()
    }

    @Test func filteringKeepsSelectionVisible() {
        let alpha = item(text: "Alpha match")
        let beta = item(text: "Beta only")
        let store = store(items: [alpha, beta])
        store.select(beta)

        store.searchText = "alpha"

        #expect(store.filteredItems.map(\.id) == [alpha.id])
        #expect(store.selectedID == alpha.id)
    }

    @Test func filteringToNoItemsClearsSelection() {
        let store = store(items: [item(text: "Alpha match")])

        store.searchText = "missing"

        #expect(store.filteredItems.isEmpty)
        #expect(store.selectedID == nil)
    }

    private func store(items: [ClipboardItem]) -> ClipboardStore {
        ClipboardStore(
            settings: AppSettings(),
            sourceTracker: CopySourceTracker(),
            initialItems: items
        )
    }

    private func item(text: String) -> ClipboardItem {
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
}
