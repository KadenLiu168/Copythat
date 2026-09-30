@testable import Copythat
import AppKit
import CryptoKit
import Foundation
import Testing

@MainActor
struct ClipboardHistoryPerformanceTests {
    @Test func versionTwoRestoreOfMediaHeavyHistoryReadsNoHeavyBlobs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryMediaPerformance-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "ClipboardHistoryPerformanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        var blobReads: [String] = []
        let persistence = ClipboardHistoryPersistence(
            directoryURL: directory,
            userDefaults: defaults,
            readData: { url in
                blobReads.append(url.lastPathComponent)
                return try Data(contentsOf: url)
            }
        )
        // Four distinct source icons shared across 500 items: restore must
        // deduplicate them while never touching the per-item heavy payloads.
        let (items, heavyBlobIDs) = Self.mediaHeavyHistory()
        try persistence.save(items)
        blobReads.removeAll()

        let restored = try persistence.loadItems()

        #expect(restored.count == 500)
        #expect(blobReads.filter { $0 == "clipboard-history.json" }.count == 1)
        let iconReads = blobReads.filter { $0.hasSuffix(".blob") }
        #expect(iconReads.count == 4, "shared source icons are read once each")
        #expect(iconReads.allSatisfy { !heavyBlobIDs.contains(String($0.dropLast(5))) })
        #expect(restored.allSatisfy { $0.imageData == nil && $0.linkImageData == nil })
        #expect(restored.filter { $0.imageBlobID != nil }.count == 250)
        #expect(restored.filter { $0.linkImageBlobID != nil }.count == 250)
        #expect(restored.allSatisfy { $0.sourceAppIconData != nil })
        #expect(restored.map(\.contentKey) == items.map(\.contentKey))

        // Metadata is searchable and pinboard-ready before any media access.
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: restored,
            pasteboard: NSPasteboard.withUniqueName(),
            persistItems: { _ in }
        )
        #expect(store.filteredItems.count == 500)
        store.searchText = "Item 499"
        #expect(store.filteredItems.count == 1)
        store.searchText = ""
        let restoredBlobReads = blobReads.filter { $0.hasSuffix(".blob") }
        #expect(restoredBlobReads.count == 4)

        AcceptanceMetrics.record(
            scenario: "history-performance-read-counters",
            metric: "heavyBlobReadsFor500ItemRestore",
            expected: "0",
            observed: "\(restoredBlobReads.filter { heavyBlobIDs.contains(String($0.dropLast(5))) }.count)"
        )
        AcceptanceMetrics.record(
            scenario: "history-performance-read-counters",
            metric: "sourceIconBlobReads",
            expected: "4 (deduplicated)",
            observed: "\(restoredBlobReads.count)"
        )
    }

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

    @Test func repeatedQueriesOverAConfiguredHistoryReuseEachCorpusOnce() {
        let buckets = ["alpha", "bravo", "charlie", "delta", "echo"]
        let recorder = SearchCorpusRecorder()
        var items: [ClipboardItem] = []
        items.reserveCapacity(1_000)

        // Every item is created inside the measurement window, so the positive
        // count below proves the recorder is actually installed.
        SearchCorpusObservation.$recorder.withValue(recorder) {
            for index in 0..<1_000 {
                items.append(
                    ClipboardItem(
                        id: UUID(),
                        kind: .text,
                        title: "Item \(index)",
                        preview: "\(buckets[index % buckets.count]) payload \(index)",
                        sourceApp: "Generator",
                        sourceAppIconData: nil,
                        createdAt: Date(timeIntervalSince1970: TimeInterval(-index)),
                        isPinned: false,
                        pinboardName: nil,
                        textValue: "payload \(index)",
                        fileURLs: [],
                        imageData: nil
                    )
                )
            }

            #expect(recorder.count == 1_000, "each created item builds its corpus exactly once")

            let store = ClipboardStore(
                settings: AppSettings(defaults: temporaryDefaults()),
                sourceTracker: CopySourceTracker(),
                initialItems: items,
                pasteboard: NSPasteboard.withUniqueName(),
                persistItems: { _ in }
            )

            #expect(store.filteredItems.map(\.id) == items.map(\.id))
            #expect(recorder.count == 1_000, "constructing the history view must not rebuild a corpus")

            for (bucketIndex, bucket) in buckets.enumerated() {
                store.searchText = bucket
                let expected = stride(from: bucketIndex, to: 1_000, by: 5).map { items[$0].id }
                #expect(store.filteredItems.map(\.id) == expected, "query \(bucket) must return matches in history order")
            }

            store.searchText = "ALPHA"
            #expect(store.filteredItems.map(\.id) == stride(from: 0, to: 1_000, by: 5).map { items[$0].id })

            store.searchText = "zulu"
            #expect(store.filteredItems.isEmpty)

            #expect(recorder.count == 1_000, "query changes reuse each corpus; no query rebuilds one")
        }
    }

    /// Four distinct source icons shared across 500 items, half image and half
    /// URL with a link image. Restore must deduplicate the icons while never
    /// touching the per-item heavy payloads.
    private static func mediaHeavyHistory() -> (items: [ClipboardItem], heavyBlobIDs: Set<String>) {
        let icons = (0..<4).map { Data(repeating: UInt8(0x40 + $0), count: 96) }
        var items: [ClipboardItem] = []
        items.reserveCapacity(500)
        var heavyBlobIDs: Set<String> = []
        for index in 0..<500 {
            let icon = icons[index % icons.count]
            let media = Data(
                [UInt8(index >> 8), UInt8(index & 0xFF)] + [UInt8](repeating: 0x5A, count: 62)
            )
            heavyBlobIDs.insert(Self.sha256Hex(media))
            if index.isMultiple(of: 2) {
                items.append(
                    ClipboardItem(
                        id: UUID(),
                        kind: .image,
                        title: "Image \(index)",
                        preview: "64 x 64",
                        sourceApp: "Preview",
                        sourceAppIconData: icon,
                        createdAt: Date(timeIntervalSince1970: TimeInterval(-index)),
                        isPinned: false,
                        pinboardName: nil,
                        textValue: nil,
                        fileURLs: [],
                        imageData: media
                    )
                )
            } else {
                let url = "https://media.example.com/item/\(index)"
                items.append(
                    ClipboardItem(
                        id: UUID(),
                        kind: .url,
                        title: "media.example.com",
                        preview: url,
                        sourceApp: "Safari",
                        sourceAppIconData: icon,
                        createdAt: Date(timeIntervalSince1970: TimeInterval(-index)),
                        isPinned: false,
                        pinboardName: nil,
                        textValue: url,
                        fileURLs: [],
                        imageData: nil,
                        linkTitle: "Item \(index)",
                        linkImageData: media
                    )
                )
            }
        }
        return (items, heavyBlobIDs)
    }

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "ClipboardHistoryPerformanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
