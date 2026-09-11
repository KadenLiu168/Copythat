@testable import Copythat
import Foundation
import Testing

struct ClipboardItemContentKeyTests {
    @Test func contentKeysAreStableForTextURLAndFiles() {
        let text = item(kind: .text, textValue: "copy me", preview: "ignored")
        let sameText = item(kind: .text, textValue: "copy me", preview: "different preview")
        let url = item(kind: .url, textValue: "https://example.com/private", preview: "ignored")
        let files = [
            URL(fileURLWithPath: "/tmp/first.txt"),
            URL(fileURLWithPath: "/tmp/second.txt")
        ]
        let fileItem = item(kind: .file, fileURLs: files)

        #expect(text.contentKey == "text:copy me")
        #expect(sameText.contentKey == text.contentKey)
        #expect(url.contentKey == "url:https://example.com/private")
        #expect(fileItem.contentKey == "file:/tmp/first.txt|/tmp/second.txt")
    }

    @Test func imageContentKeysUseStableDataDigests() {
        let first = item(kind: .image, imageData: Data([0, 1, 2, 3, 4]))
        let same = item(kind: .image, imageData: Data([0, 1, 2, 3, 4]))
        let different = item(kind: .image, imageData: Data([0, 1, 2, 3, 5]))
        let empty = item(kind: .image, imageData: nil)

        #expect(first.contentKey == same.contentKey)
        #expect(first.contentKey != different.contentKey)
        #expect(first.contentKey == "image:08bb5e5d6eaac1049ede0893d30ed022b1a4d9b5b48db414871f51c9cb35283d")
        #expect(empty.contentKey == "image:empty")
    }

    private func item(
        kind: ClipboardKind,
        textValue: String? = nil,
        preview: String = "",
        fileURLs: [URL] = [],
        imageData: Data? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: kind,
            title: "Test item",
            preview: preview,
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            isPinned: false,
            pinboardName: nil,
            textValue: textValue,
            fileURLs: fileURLs,
            imageData: imageData
        )
    }
}
