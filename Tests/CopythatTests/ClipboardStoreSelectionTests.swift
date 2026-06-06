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

    @Test func migratedPinboardNameKeepsAssignedItemsVisible() {
        let defaults = temporaryDefaults()
        defaults.set("Work", forKey: "pinboardsText")
        let settings = AppSettings(defaults: defaults)
        let assigned = item(text: "Assigned", pinboardName: "Work")
        let store = ClipboardStore(
            settings: settings,
            sourceTracker: CopySourceTracker(),
            initialItems: [assigned, item(text: "Other")]
        )

        store.selectedBoardID = Pinboard.custom(settings.customPinboards[0].name).id

        #expect(store.filteredItems.map(\.id) == [assigned.id])
        #expect(store.items.first(where: { $0.id == assigned.id })?.pinboardName == "Work")
    }

    @Test func creatingPinboardDoesNotAssignExistingItems() {
        let defaults = temporaryDefaults()
        defaults.set("", forKey: "pinboardsText")
        let settings = AppSettings(defaults: defaults)
        let existing = item(text: "Existing")
        let store = ClipboardStore(
            settings: settings,
            sourceTracker: CopySourceTracker(),
            initialItems: [existing]
        )

        let created = settings.createCustomPinboard(name: "Research", color: .pink)

        #expect(created != nil)
        #expect(store.items[0].pinboardName == nil)
    }

    private func store(items: [ClipboardItem]) -> ClipboardStore {
        ClipboardStore(
            settings: AppSettings(),
            sourceTracker: CopySourceTracker(),
            initialItems: items
        )
    }

    private func item(text: String, pinboardName: String? = nil) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .text,
            title: text,
            preview: text,
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(),
            isPinned: false,
            pinboardName: pinboardName,
            textValue: text,
            fileURLs: [],
            imageData: nil
        )
    }

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "ClipboardStoreSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
