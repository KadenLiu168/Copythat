@testable import Copythat
import AppKit
import Foundation
import Testing

@MainActor
struct ClipboardHistoryPerformanceTests {
    @Test func productionHistoryEncodingAndFilteringHandleFiveThousandItems() throws {
        let now = Date(timeIntervalSince1970: 0)
        var items: [ClipboardItem] = []
        items.reserveCapacity(5_000)

        for index in 0..<5_000 {
            let kind: ClipboardKind = index.isMultiple(of: 17) ? .url : .text
            let value = kind == .url
                ? "https://example.com/history/\(index)"
                : "Copythat history performance item \(index)"
            items.append(
                ClipboardItem(
                    id: UUID(),
                    kind: kind,
                    title: kind == .url ? "example.com" : "History item \(index)",
                    preview: value,
                    sourceApp: index.isMultiple(of: 2) ? "Safari" : "Xcode",
                    sourceAppIconData: nil,
                    createdAt: now.addingTimeInterval(TimeInterval(-index)),
                    isPinned: index.isMultiple(of: 250),
                    pinboardName: index.isMultiple(of: 500) ? "Work" : nil,
                    textValue: value,
                    fileURLs: [],
                    imageData: nil
                )
            )
        }

        let encoded = try JSONEncoder().encode(items)
        let decoded = try JSONDecoder().decode([ClipboardItem].self, from: encoded)
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults()),
            sourceTracker: CopySourceTracker(),
            initialItems: decoded,
            pasteboard: NSPasteboard.withUniqueName(),
            persistItems: { _ in }
        )

        let allResults = store.filteredItems
        store.searchText = "4997"
        let searchResults = store.filteredItems
        store.searchText = ""
        store.selectedBoardID = Pinboard.pinned.id
        let pinnedResults = store.filteredItems
        store.selectedBoardID = Pinboard.custom("Work").id
        let workResults = store.filteredItems

        #expect(decoded.count == 5_000)
        #expect(allResults.count == 5_000)
        #expect(searchResults.count == 1)
        #expect(pinnedResults.count == 20)
        #expect(workResults.count == 10)
        #expect(encoded.count < 2_000_000)
    }

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "ClipboardHistoryPerformanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
