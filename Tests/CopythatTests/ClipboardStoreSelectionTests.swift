@testable import Copythat
import AppKit
import Combine
import Foundation
import Testing

private final class PersistedItemsCapture {
    var calls: [[ClipboardItem]] = []
}

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
            initialItems: [assigned, item(text: "Other")],
            persistItems: { _ in }
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
            initialItems: [existing],
            persistItems: { _ in }
        )

        let created = settings.createCustomPinboard(name: "Research", color: .pink)

        #expect(created != nil)
        #expect(store.items[0].pinboardName == nil)
    }

    @Test func unpinningCurrentPinnedItemRefreshesVisibleItemsAndSelection() {
        let first = item(text: "First", isPinned: true)
        let second = item(text: "Second", isPinned: true)
        let store = store(items: [first, second])
        store.selectedBoardID = Pinboard.pinned.id
        store.select(first)

        store.togglePin(first)

        #expect(store.items.first { $0.id == first.id }?.isPinned == false)
        #expect(store.filteredItems.map(\.id) == [second.id])
        #expect(store.selectedID == second.id)
    }

    @Test func unpinningOnlyPinnedItemClearsVisibleItemsAndSelection() {
        let pinned = item(text: "Pinned", isPinned: true)
        let store = store(items: [pinned])
        store.selectedBoardID = Pinboard.pinned.id

        store.togglePin(pinned)

        #expect(store.filteredItems.isEmpty)
        #expect(store.selectedID == nil)
    }

    @Test func removingCurrentCustomPinboardAssignmentRefreshesVisibleItemsAndSelection() {
        let first = item(text: "First", pinboardName: "Work")
        let second = item(text: "Second", pinboardName: "Work")
        let store = store(items: [first, second])
        store.selectedBoardID = Pinboard.custom("Work").id
        store.select(first)

        store.move(first, toPinboard: nil)

        #expect(store.items.first { $0.id == first.id }?.pinboardName == nil)
        #expect(store.filteredItems.map(\.id) == [second.id])
        #expect(store.selectedID == second.id)
    }

    @Test func customPinboardAssignmentDoesNotChangePinnedState() {
        let unpinned = item(text: "Unpinned")
        let pinned = item(text: "Pinned", isPinned: true)
        let store = store(items: [unpinned, pinned])

        store.move(unpinned, toPinboard: "Work")
        store.move(pinned, toPinboard: "Work")
        store.move(pinned, toPinboard: nil)

        #expect(store.items.first { $0.id == unpinned.id }?.pinboardName == "Work")
        #expect(store.items.first { $0.id == unpinned.id }?.isPinned == false)
        #expect(store.items.first { $0.id == pinned.id }?.pinboardName == nil)
        #expect(store.items.first { $0.id == pinned.id }?.isPinned == true)
    }

    @Test func clearingPinboardAssignmentsMovesItemsOutWithoutDeletingOrUnpinning() {
        let assigned = item(text: "Assigned", pinboardName: "Work", isPinned: true)
        let otherAssigned = item(text: "Other assigned", pinboardName: "Ideas", isPinned: true)
        let unassigned = item(text: "Unassigned")
        let store = store(items: [assigned, otherAssigned, unassigned])

        #expect(store.pinboardAssignmentCount(named: "Work") == 1)

        store.clearPinboardAssignments(named: "Work")

        #expect(store.items.map(\.id) == [assigned.id, otherAssigned.id, unassigned.id])
        #expect(store.items.first { $0.id == assigned.id }?.pinboardName == nil)
        #expect(store.items.first { $0.id == assigned.id }?.isPinned == true)
        #expect(store.items.first { $0.id == otherAssigned.id }?.pinboardName == "Ideas")
        #expect(store.items.first { $0.id == unassigned.id }?.pinboardName == nil)
        #expect(store.pinboardAssignmentCount(named: "Work") == 0)
    }

    @Test func clearingPinboardAssignmentsRefreshesVisibleItemsAndPreservesSearch() {
        let matching = item(text: "Alpha assigned", pinboardName: "Work")
        let other = item(text: "Alpha other")
        let store = store(items: [matching, other])
        store.selectedBoardID = Pinboard.custom("Work").id
        store.searchText = "alpha"

        #expect(store.filteredItems.map(\.id) == [matching.id])

        store.clearPinboardAssignments(named: "Work")

        #expect(store.searchText == "alpha")
        #expect(store.filteredItems.isEmpty)
        #expect(store.selectedID == nil)
        #expect(store.items.first { $0.id == matching.id }?.pinboardName == nil)
    }

    @Test func deletingCurrentPinboardFallsBackToClipboardAndPreservesSearch() {
        let matching = item(text: "Alpha assigned", pinboardName: "Work")
        let other = item(text: "Alpha other")
        let store = store(items: [matching, other])
        store.selectedBoardID = Pinboard.custom("Work").id
        store.searchText = "alpha"

        store.selectClipboardIfViewingPinboard(named: "Work")

        #expect(store.selectedBoardID == Pinboard.all.id)
        #expect(store.searchText == "alpha")
        #expect(store.filteredItems.map(\.id) == [matching.id, other.id])
    }

    @Test func deletingNonSelectedPinboardKeepsCurrentFilterAndPreservesSearch() {
        let work = item(text: "Alpha work", pinboardName: "Work")
        let ideas = item(text: "Alpha ideas", pinboardName: "Ideas")
        let store = store(items: [work, ideas])
        store.selectedBoardID = Pinboard.custom("Ideas").id
        store.searchText = "alpha"

        store.selectClipboardIfViewingPinboard(named: "Work")

        #expect(store.selectedBoardID == Pinboard.custom("Ideas").id)
        #expect(store.searchText == "alpha")
        #expect(store.filteredItems.map(\.id) == [ideas.id])
    }

    @Test func clearingHistoryKeepsPinnedAndPinboardItemsByDefault() {
        let ordinary = item(text: "Ordinary")
        let pinned = item(text: "Pinned", isPinned: true)
        let assigned = item(text: "Assigned", pinboardName: "Work")
        let store = store(items: [ordinary, pinned, assigned])

        let removedCount = store.clearHistory(includePinnedAndPinboardItems: false)

        #expect(removedCount == 1)
        #expect(store.items.map(\.id) == [pinned.id, assigned.id])
        #expect(store.filteredItems.map(\.id) == [pinned.id, assigned.id])
    }

    @Test func clearingAllHistoryRemovesPinnedAndPinboardItems() {
        let pinned = item(text: "Pinned", isPinned: true)
        let assigned = item(text: "Assigned", pinboardName: "Work")
        let store = store(items: [pinned, assigned])
        store.selectedBoardID = Pinboard.pinned.id
        store.select(pinned)

        let removedCount = store.clearHistory(includePinnedAndPinboardItems: true)

        #expect(removedCount == 2)
        #expect(store.items.isEmpty)
        #expect(store.filteredItems.isEmpty)
        #expect(store.selectedID == nil)
    }

    @Test func pasteboardCaptureWaitsForStableFinalChangeCount() {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults()),
            sourceTracker: CopySourceTracker(),
            initialItems: [],
            pasteboard: pasteboard,
            persistItems: { _ in }
        )

        pasteboard.clearContents()
        pasteboard.setString("old transient text", forType: .string)
        store.pollPasteboard()

        pasteboard.clearContents()
        pasteboard.setString("final chatgpt text", forType: .string)
        store.pollPasteboard()
        store.pollPasteboard()

        #expect(store.items.count == 1)
        #expect(store.items.first?.textValue == "final chatgpt text")
        #expect(store.items.first?.textValue != "old transient text")
    }

    @Test func writingToPasteboardClearsPendingExternalCapture() {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults()),
            sourceTracker: CopySourceTracker(),
            initialItems: [],
            pasteboard: pasteboard,
            persistItems: { _ in }
        )

        pasteboard.setString("external pending text", forType: .string)
        store.pollPasteboard()

        let wrote = store.writeToPasteboard(item(text: "restore me"))
        store.pollPasteboard()

        #expect(wrote)
        #expect(pasteboard.string(forType: .string) == "restore me")
        #expect(store.items.isEmpty)
    }

    @Test func renamingPinboardAssignmentsMigratesMatchingItemsOnly() {
        let capture = PersistedItemsCapture()
        let assigned = item(text: "Assigned", pinboardName: "Work", isPinned: true)
        let otherAssigned = item(text: "Other assigned", pinboardName: "Ideas")
        let unassigned = item(text: "Unassigned")
        let store = ClipboardStore(
            settings: AppSettings(),
            sourceTracker: CopySourceTracker(),
            initialItems: [assigned, otherAssigned, unassigned],
            persistItems: { capture.calls.append($0) }
        )
        store.selectedBoardID = Pinboard.custom("Work").id

        #expect(store.filteredItems.map(\.id) == [assigned.id])

        store.renamePinboardAssignments(from: "Work", to: "Project")

        let migrated = store.items.first { $0.id == assigned.id }
        #expect(migrated?.pinboardName == "Project")
        #expect(migrated?.isPinned == true)
        #expect(migrated?.textValue == "Assigned")
        #expect(store.items.first { $0.id == otherAssigned.id }?.pinboardName == "Ideas")
        #expect(store.items.first { $0.id == unassigned.id }?.pinboardName == nil)
        #expect(store.filteredItems.isEmpty)
        #expect(capture.calls.last?.first { $0.id == assigned.id }?.pinboardName == "Project")
        #expect(capture.calls.last?.count == 3)
    }

    @Test func renamingSelectedPinboardFollowsRenameAndPreservesSearch() {
        let assigned = item(text: "Alpha assigned", pinboardName: "Work")
        let other = item(text: "Alpha other")
        let store = store(items: [assigned, other])
        store.selectedBoardID = Pinboard.custom("Work").id
        store.searchText = "alpha"

        #expect(store.filteredItems.map(\.id) == [assigned.id])

        store.renamePinboardAssignments(from: "Work", to: "Project")
        store.migrateSelectionAfterPinboardRename(from: "Work", to: "Project")

        #expect(store.selectedBoardID == Pinboard.custom("Project").id)
        #expect(store.searchText == "alpha")
        #expect(store.filteredItems.map(\.id) == [assigned.id])
        #expect(store.items.first { $0.id == assigned.id }?.pinboardName == "Project")
    }

    @Test func renamingNonSelectedPinboardKeepsSelectionAndSearch() {
        let work = item(text: "Alpha work", pinboardName: "Work")
        let ideas = item(text: "Alpha ideas", pinboardName: "Ideas")
        let store = store(items: [work, ideas])
        store.selectedBoardID = Pinboard.custom("Ideas").id
        store.searchText = "alpha"

        store.renamePinboardAssignments(from: "Work", to: "Project")
        store.migrateSelectionAfterPinboardRename(from: "Work", to: "Project")

        #expect(store.selectedBoardID == Pinboard.custom("Ideas").id)
        #expect(store.searchText == "alpha")
        #expect(store.filteredItems.map(\.id) == [ideas.id])
    }

    @Test func colorOnlySettingsUpdateDoesNotRewriteAssignments() {
        let defaults = temporaryDefaults()
        defaults.set("Work", forKey: "pinboardsText")
        let settings = AppSettings(defaults: defaults)
        let assigned = item(text: "Assigned", pinboardName: "Work", isPinned: true)
        let store = ClipboardStore(
            settings: settings,
            sourceTracker: CopySourceTracker(),
            initialItems: [assigned],
            persistItems: { _ in }
        )
        let itemsBefore = store.items
        let filteredBefore = store.filteredItems

        #expect(settings.updateCustomPinboard(named: "Work", newName: "Work", color: .blue))

        #expect(store.items == itemsBefore)
        #expect(store.filteredItems == filteredBefore)
        #expect(settings.customPinboards == [CustomPinboard(name: "Work", color: .blue)])
    }

    private func store(items: [ClipboardItem]) -> ClipboardStore {
        ClipboardStore(
            settings: AppSettings(),
            sourceTracker: CopySourceTracker(),
            initialItems: items,
            persistItems: { _ in }
        )
    }

    private func item(text: String, pinboardName: String? = nil, isPinned: Bool = false) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .text,
            title: text,
            preview: text,
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(),
            isPinned: isPinned,
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
