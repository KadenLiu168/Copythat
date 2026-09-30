@testable import Copythat
import AppKit
import Foundation
import Testing

private final class PersistedItemsCapture {
    var calls: [[ClipboardItem]] = []
}

@MainActor
struct ClipboardStoreHistoryLimitTests {
    @Test func reducingHistoryLimitTrimsExistingHistoryAndSavesOnce() async {
        let capture = PersistedItemsCapture()
        let settings = AppSettings(defaults: defaultsWithHistoryLimit(500))
        let fixture = (0..<200).map { item(text: "history item \($0)") }
        let store = makeStore(settings: settings, items: fixture, persistItems: { capture.calls.append($0) })
        #expect(capture.calls.isEmpty, "startup history within bounds must not save")

        settings.historyLimit = 100
        await waitForHistoryLimitEnforcement()

        #expect(store.items.map(\.id) == fixture.prefix(100).map(\.id))
        #expect(store.filteredItems.map(\.id) == fixture.prefix(100).map(\.id))
        #expect(capture.calls.count == 1, "one trim requests exactly one history save")
        #expect(capture.calls.last?.map(\.id) == fixture.prefix(100).map(\.id))
    }

    @Test func increasingHistoryLimitKeepsHistorySelectionAndUnsavedState() async {
        let capture = PersistedItemsCapture()
        let settings = AppSettings(defaults: defaultsWithHistoryLimit(500))
        let fixture = (0..<200).map { item(text: "history item \($0)") }
        let store = makeStore(settings: settings, items: fixture, persistItems: { capture.calls.append($0) })
        let selected = fixture[10]
        store.select(selected)

        settings.historyLimit = 600
        await waitForHistoryLimitEnforcement()

        #expect(store.items.map(\.id) == fixture.map(\.id))
        #expect(store.selectedID == selected.id)
        #expect(capture.calls.isEmpty, "a no-op limit change must not request a save")
    }

    @Test func oversizedHistoryIsTrimmedAtStartupAndSavedOnce() {
        let capture = PersistedItemsCapture()
        let settings = AppSettings(defaults: defaultsWithHistoryLimit(100))
        let fixture = (0..<150).map { item(text: "history item \($0)") }
        let store = makeStore(settings: settings, items: fixture, persistItems: { capture.calls.append($0) })

        #expect(store.items.map(\.id) == fixture.prefix(100).map(\.id))
        #expect(store.filteredItems.map(\.id) == fixture.prefix(100).map(\.id))
        #expect(capture.calls.count == 1)
        #expect(capture.calls.last?.count == 100)
    }

    @Test func startupHistoryWithinBoundsDoesNotSave() {
        let capture = PersistedItemsCapture()
        let settings = AppSettings(defaults: defaultsWithHistoryLimit(500))
        let fixture = (0..<10).map { item(text: "history item \($0)") }
        let store = makeStore(settings: settings, items: fixture, persistItems: { capture.calls.append($0) })

        #expect(store.items.map(\.id) == fixture.map(\.id))
        #expect(capture.calls.isEmpty)
    }

    @Test func rapidHistoryLimitChangesTrimOnce() async {
        let capture = PersistedItemsCapture()
        let settings = AppSettings(defaults: defaultsWithHistoryLimit(500))
        let fixture = (0..<200).map { item(text: "history item \($0)") }
        let store = makeStore(settings: settings, items: fixture, persistItems: { capture.calls.append($0) })

        settings.historyLimit = 150
        settings.historyLimit = 100
        await waitForHistoryLimitEnforcement()

        #expect(store.items.map(\.id) == fixture.prefix(100).map(\.id))
        #expect(capture.calls.count == 1, "redundant evaluations must not add saves")
    }

    @Test func reducingLimitEvictingTheSelectedItemRepointsSelection() async {
        let capture = PersistedItemsCapture()
        let settings = AppSettings(defaults: defaultsWithHistoryLimit(500))
        let fixture = (0..<200).map { item(text: "history item \($0)") }
        let store = makeStore(settings: settings, items: fixture, persistItems: { capture.calls.append($0) })
        let selected = fixture[150]
        store.select(selected)

        settings.historyLimit = 100
        await waitForHistoryLimitEnforcement()

        #expect(!store.items.contains { $0.id == selected.id })
        #expect(store.selectedID == fixture.first?.id)
        #expect(capture.calls.count == 1)
    }

    @Test func historyLimitEvictionIsNotAUserDeletion() async {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let capture = PersistedItemsCapture()
        let settings = AppSettings(defaults: defaultsWithHistoryLimit(500))
        let evictedText = "evicted payload \(UUID().uuidString)"
        var fixture = (0..<199).map { item(text: "history item \($0)") }
        fixture.append(item(text: evictedText))
        let store = ClipboardStore(
            settings: settings,
            sourceTracker: CopySourceTracker(),
            initialItems: fixture,
            pasteboard: pasteboard,
            persistItems: { capture.calls.append($0) }
        )
        let evicted = fixture[199]
        pasteboard.setString(evictedText, forType: .string)

        settings.historyLimit = 100
        await waitForHistoryLimitEnforcement()

        #expect(!store.items.contains { $0.id == evicted.id })
        #expect(
            pasteboard.string(forType: .string) == evictedText,
            "automatic eviction must not clear matching pasteboard content"
        )
        #expect(!store.hasDeletedContentKey(evicted.contentKey))

        store.add(item(text: evictedText))
        #expect(store.items.first?.textValue == evictedText, "a later intentional copy must reappear")
    }

    private func makeStore(
        settings: AppSettings,
        items: [ClipboardItem],
        persistItems: @escaping ([ClipboardItem]) -> Void
    ) -> ClipboardStore {
        ClipboardStore(
            settings: settings,
            sourceTracker: CopySourceTracker(),
            initialItems: items,
            pasteboard: NSPasteboard.withUniqueName(),
            persistItems: persistItems
        )
    }

    private func waitForHistoryLimitEnforcement() async {
        await Task.yield()
        await Task.yield()
    }

    private func defaultsWithHistoryLimit(_ limit: Int) -> UserDefaults {
        let suiteName = "ClipboardStoreHistoryLimitTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(limit, forKey: "historyLimit")
        return defaults
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
