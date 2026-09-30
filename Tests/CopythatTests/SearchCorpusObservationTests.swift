@testable import Copythat
import Foundation
import Testing

/// Contracts for the search corpus build seam: builds are counted where the
/// normalization actually runs, only inside the window that installed the
/// recorder, and parallel windows never share a count. The cached value is also
/// pinned to the expression search has always evaluated.
struct SearchCorpusObservationTests {
    @Test func buildsAreCountedOnlyInsideTheMeasurementWindow() {
        let recorder = SearchCorpusRecorder()

        let unmeasured = makeItem()
        #expect(recorder.count == 0)

        let measured = SearchCorpusObservation.$recorder.withValue(recorder) {
            (makeItem(), makeItem())
        }

        #expect(recorder.count == 2)
        #expect(measured.0.searchText == unmeasured.searchText)
        #expect(measured.1.searchText == unmeasured.searchText)
    }

    @Test func windowsUseOnlyTheirOwnRecorder() {
        let first = SearchCorpusRecorder()
        let second = SearchCorpusRecorder()

        SearchCorpusObservation.$recorder.withValue(first) { _ = makeItem() }
        #expect(first.count == 1)
        #expect(second.count == 0)

        SearchCorpusObservation.$recorder.withValue(second) {
            _ = makeItem()
            _ = makeItem()
        }
        #expect(first.count == 1)
        #expect(second.count == 2)
    }

    @Test func innerWindowReplacesTheOuterRecorder() {
        let outer = SearchCorpusRecorder()
        let inner = SearchCorpusRecorder()

        SearchCorpusObservation.$recorder.withValue(outer) {
            _ = makeItem()
            SearchCorpusObservation.$recorder.withValue(inner) { _ = makeItem() }
            _ = makeItem()
        }

        #expect(outer.count == 2)
        #expect(inner.count == 1)
    }

    @Test func concurrentBuildsInOneWindowAreAllCounted() async {
        let recorder = SearchCorpusRecorder()

        await SearchCorpusObservation.$recorder.withValue(recorder) {
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<12 {
                    group.addTask { _ = makeItem() }
                }
            }
        }

        #expect(recorder.count == 12)
    }

    @Test func cachedTextMatchesTheOriginalExpression() {
        let cases = [
            makeItem(title: "Clipboard item", preview: "Preview text", linkTitle: "Link title", sourceApp: "Safari"),
            makeItem(title: "Only title", preview: "Preview text", sourceApp: "Finder"),
            makeItem(title: "", preview: "", linkTitle: "", sourceApp: ""),
            makeItem(title: "Title", preview: "Preview", sourceApp: "Notes", fileURLs: [
                URL(fileURLWithPath: "/tmp/corpusfixtures/My File.pdf"),
                URL(fileURLWithPath: "/tmp/a b/c.txt")
            ]),
            makeItem(
                title: "TITLE 标题",
                preview: "CAFÉ Größe",
                linkTitle: "ÜBER",
                sourceApp: "Preview",
                fileURLs: [URL(fileURLWithPath: "/tmp/Ünïcode.json")]
            )
        ]

        for item in cases {
            let expression = (
                [item.title, item.preview, item.linkTitle, item.sourceApp, item.kind.label].compactMap(\.self)
                    + item.fileURLs.map(\.path)
            )
            .joined(separator: " ")
            .localizedLowercase

            #expect(item.searchText == expression)
        }
    }

    @Test func delimiterOrderAndLowercaseStayStable() {
        let item = makeItem(
            title: "Alpha",
            preview: "Beta",
            linkTitle: nil,
            sourceApp: "Gamma",
            fileURLs: [URL(fileURLWithPath: "/tmp/Delta.txt")],
            kind: .url
        )

        #expect(item.searchText == "alpha beta gamma link /tmp/delta.txt")
        #expect(item.searchText.components(separatedBy: " ").count == 5)
    }

    @Test func unchangedTitlesAndImageOnlyEnrichmentEachBuildOnce() {
        let item = makeItem(title: "Stable title", linkTitle: "Stable title")
        let image = PreparedMedia(hashing: Data(repeating: 0xf3, count: 32))

        for linkImage in [nil, image] as [PreparedMedia?] {
            let recorder = SearchCorpusRecorder()
            let merged = SearchCorpusObservation.$recorder.withValue(recorder) {
                item.withLinkPreview(title: item.title, linkImage: linkImage)
            }

            #expect(recorder.count == 1)
            #expect(merged.title == item.title)
            #expect(merged.linkTitle == item.linkTitle)
            #expect(merged.searchText == item.searchText)
            #expect(merged.linkImageData == linkImage?.data)
        }
    }

    @Test func linkPreviewRebuildsTheCorpusOncePerCompletion() async {
        let item = makeItem(
            title: "Image",
            preview: "Image preview",
            linkTitle: "Image link title",
            sourceApp: "Preview",
            kind: .image,
            imageData: Data(repeating: 0xf1, count: 64)
        )
        #expect(item.searchText.contains("image link title"), "the fixture must start with a stale term")

        // Replacement, nil, unchanged and image-only completions each rebuild
        // exactly once, so no stale corpus survives a merge.
        let replacement = PreparedMedia(hashing: Data(repeating: 0xf2, count: 32))
        let completions: [(title: String?, linkImage: PreparedMedia?)] = [
            ("Brand new title", nil),
            (nil, nil),
            ("Image link title", nil),
            (item.title, replacement)
        ]

        for (index, completion) in completions.enumerated() {
            let recorder = SearchCorpusRecorder()
            let merged = await SearchCorpusObservation.$recorder.withValue(recorder) {
                item.withLinkPreview(title: completion.title, linkImage: completion.linkImage)
            }

            #expect(recorder.count == 1, "completion \(index) must rebuild the corpus exactly once")

            switch index {
            case 0:
                #expect(merged.title == "Brand new title")
                #expect(merged.linkTitle == "Brand new title")
                #expect(merged.searchText.contains("brand new title"))
                #expect(!merged.searchText.contains("image link title"))
            case 1:
                #expect(merged.title == item.title, "an absent title keeps the displayed title")
                #expect(merged.linkTitle == nil)
                #expect(!merged.searchText.contains("image link title"))
            case 2:
                #expect(merged.title == "Image link title")
                #expect(merged.linkTitle == "Image link title")
                #expect(merged.searchText.contains("image link title"))
            default:
                #expect(merged.title == item.title)
                #expect(merged.linkTitle == item.title)
                #expect(merged.linkImageBlobID == replacement.id)
                #expect(!merged.searchText.contains("image link title"))
                #expect(merged.searchText.contains("image image preview"))
            }
        }
    }
}

private func makeItem(
    title: String = "Clipboard item",
    preview: String = "Preview text",
    linkTitle: String? = nil,
    sourceApp: String = "Tests",
    fileURLs: [URL] = [],
    kind: ClipboardKind = .text,
    imageData: Data? = nil
) -> ClipboardItem {
    ClipboardItem(
        id: UUID(),
        kind: kind,
        title: title,
        preview: preview,
        sourceApp: sourceApp,
        sourceAppIconData: nil,
        createdAt: Date(timeIntervalSince1970: 0),
        isPinned: false,
        pinboardName: nil,
        textValue: nil,
        fileURLs: fileURLs,
        imageData: imageData,
        linkTitle: linkTitle
    )
}
