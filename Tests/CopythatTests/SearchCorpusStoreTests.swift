@testable import Copythat
import AppKit
import Foundation
import Testing

/// Store-level contracts over the cached corpus: each searchable field matches
/// independently, query normalization is unchanged, and organization, removal
/// and duplicate handling reuse the stored corpus while filtered results and
/// selection keep their existing rules.
@MainActor
struct SearchCorpusStoreTests {
    @Test func eachSearchableFieldMatchesItsOwnToken() {
        let titleItem = item(title: "titlemark", preview: "neutral preview")
        let previewItem = item(title: "second", preview: "previewmark")
        let linkItem = item(title: "third", linkTitle: "linkmark")
        let sourceItem = item(title: "fourth", sourceApp: "SourceMark")
        let kindItem = item(title: "fifth", kind: .image)
        let fileItem = item(
            title: "sixth",
            kind: .file,
            fileURLs: [URL(fileURLWithPath: "/tmp/corpusfixtures/filemark.txt")]
        )
        let chineseItem = item(title: "中文标题", preview: "中文预览")

        let store = store(items: [titleItem, previewItem, linkItem, sourceItem, kindItem, fileItem, chineseItem])
        let expectations: [(query: String, expected: ClipboardItem)] = [
            ("titlemark", titleItem),
            ("previewmark", previewItem),
            ("linkmark", linkItem),
            ("sourcemark", sourceItem),
            ("image", kindItem),
            ("filemark", fileItem),
            ("中文", chineseItem)
        ]

        for expectation in expectations {
            store.searchText = expectation.query
            #expect(
                store.filteredItems.map(\.id) == [expectation.expected.id],
                "\(expectation.query) must match through its own field only"
            )
        }
    }

    @Test func queryCaseAndWhitespaceNormalizationAreUnchanged() {
        let titleItem = item(title: "titlemark")
        let previewItem = item(title: "second", preview: "previewmark")
        let store = store(items: [titleItem, previewItem])

        store.searchText = "TITLEMARK"
        #expect(store.filteredItems.map(\.id) == [titleItem.id])

        store.searchText = "  PreviewMark  "
        #expect(store.filteredItems.map(\.id) == [previewItem.id])
    }

    @Test func organizationFieldsAreNotSearchable() {
        let pinned = item(title: "Alpha", pinboardName: "Work", isPinned: true)
        let store = store(items: [pinned])

        store.searchText = "work"
        #expect(store.filteredItems.isEmpty)

        store.searchText = "pinned"
        #expect(store.filteredItems.isEmpty)

        #expect(!pinned.searchText.contains("work"))
        #expect(!pinned.searchText.contains("pinned"))
    }

    @Test func organizationMutationsBuildNoCorpusAndKeepVisibleResults() {
        let work = item(title: "Alpha work", pinboardName: "Work", isPinned: true)
        let other = item(title: "Alpha other")
        let store = store(items: [work, other])
        store.searchText = "alpha"

        let recorder = SearchCorpusRecorder()
        SearchCorpusObservation.$recorder.withValue(recorder) {
            store.togglePin(work)
            store.move(work, toPinboard: "Project")
            store.renamePinboardAssignments(from: "Project", to: "Renamed")
            store.clearPinboardAssignments(named: "Renamed")
            store.togglePin(other)
            store.togglePin(other)
        }

        #expect(recorder.count == 0, "organization state is not searchable metadata")
        #expect(store.searchText == "alpha")
        #expect(store.filteredItems.map(\.id) == [work.id, other.id])
        #expect(store.items.first { $0.id == work.id }?.isPinned == false)
        #expect(store.items.first { $0.id == work.id }?.pinboardName == nil)
        #expect(store.items.first { $0.id == other.id }?.isPinned == false)
    }

    @Test func pinboardMutationsKeepFilterAndSelectionFallbacks() {
        let first = item(title: "Alpha first", pinboardName: "Work")
        let second = item(title: "Alpha second", pinboardName: "Work")
        let store = store(items: [first, second])
        store.selectedBoardID = Pinboard.custom("Work").id
        store.searchText = "alpha"
        store.select(first)

        let recorder = SearchCorpusRecorder()
        SearchCorpusObservation.$recorder.withValue(recorder) {
            store.move(first, toPinboard: nil)
            store.renamePinboardAssignments(from: "Work", to: "Project")
            store.clearPinboardAssignments(named: "Project")
        }

        #expect(recorder.count == 0)
        #expect(store.searchText == "alpha")
        #expect(store.filteredItems.isEmpty)
        #expect(store.selectedID == nil)
        #expect(store.items.allSatisfy { $0.pinboardName == nil })
    }

    @Test func duplicateInsertionReordersAndKeepsSelectionWithoutRebuilding() {
        let existing = item(title: "Alpha existing", textValue: "alpha-payload")
        let other = item(title: "Beta")
        let store = store(items: [other, existing])
        let duplicate = item(title: "Alpha duplicate", textValue: "alpha-payload")

        let recorder = SearchCorpusRecorder()
        SearchCorpusObservation.$recorder.withValue(recorder) {
            store.add(duplicate)
        }

        #expect(recorder.count == 0, "an unpinned duplicate reuses the existing item")
        #expect(store.items.map(\.id) == [existing.id, other.id])
        #expect(store.items.first?.title == "Alpha existing", "duplicate metadata must not replace the item")
        #expect(store.filteredItems.map(\.id) == [existing.id, other.id])
        #expect(store.selectedID == existing.id)
    }

    @Test func removalAndHistoryClearKeepFilteredResultsAndSelection() {
        let removed = item(title: "Alpha removed")
        let kept = item(title: "Alpha kept", pinboardName: "Work")
        let ordinary = item(title: "Alpha ordinary")
        let store = store(items: [removed, kept, ordinary])
        store.searchText = "alpha"
        store.select(removed)

        let removalRecorder = SearchCorpusRecorder()
        SearchCorpusObservation.$recorder.withValue(removalRecorder) {
            store.remove(removed)
        }

        #expect(removalRecorder.count == 0)
        #expect(store.filteredItems.map(\.id) == [kept.id, ordinary.id])
        #expect(store.selectedID == kept.id)

        store.select(ordinary)
        let clearRecorder = SearchCorpusRecorder()
        SearchCorpusObservation.$recorder.withValue(clearRecorder) {
            store.clearHistory(includePinnedAndPinboardItems: false)
        }

        #expect(clearRecorder.count == 0)
        #expect(store.searchText == "alpha")
        #expect(store.filteredItems.map(\.id) == [kept.id])
        #expect(store.selectedID == kept.id)
    }

    private func store(items: [ClipboardItem]) -> ClipboardStore {
        ClipboardStore(
            settings: isolatedAppSettings(),
            sourceTracker: CopySourceTracker(),
            initialItems: items,
            pasteboard: NSPasteboard.withUniqueName(),
            persistItems: { _ in }
        )
    }

    private func item(
        title: String,
        preview: String? = nil,
        linkTitle: String? = nil,
        sourceApp: String = "Tests",
        kind: ClipboardKind = .text,
        textValue: String? = nil,
        fileURLs: [URL] = [],
        pinboardName: String? = nil,
        isPinned: Bool = false
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: kind,
            title: title,
            preview: preview ?? title,
            sourceApp: sourceApp,
            sourceAppIconData: nil,
            createdAt: Date(),
            isPinned: isPinned,
            pinboardName: pinboardName,
            textValue: textValue,
            fileURLs: fileURLs,
            imageData: nil,
            linkTitle: linkTitle
        )
    }
}
