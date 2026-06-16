@testable import Copythat
import Foundation
import Testing

struct ClipboardDiagnosticsTests {
    @Test func diagnosticsAreDisabledByDefault() {
        let suiteName = "ClipboardDiagnosticsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let diagnostics = ClipboardDiagnostics(defaults: defaults)

        #expect(!diagnostics.isEnabled)
    }

    @Test func contentSummaryDoesNotExposeRawTextPayload() {
        let payload = "secret launch token from chat"
        let item = textItem(text: payload, sourceApp: "ChatGPT")

        let summary = ClipboardDiagnostics.contentSummary(for: item)

        #expect(summary.kind == ClipboardKind.text.rawValue)
        #expect(summary.contentLength == payload.count)
        #expect(summary.contentKeyDigest.count == 16)
        #expect(summary.contentKeyDigest != payload)
        #expect(!summary.contentKeyDigest.contains("secret"))
        #expect(!summary.contentKeyDigest.contains("chat"))
    }

    @Test func contentSummaryDoesNotExposeRawURLOrFilePathPayloads() {
        let url = "https://example.com/private/path?token=secret"
        let urlSummary = ClipboardDiagnostics.contentSummary(for: urlItem(url))
        let fileURL = URL(fileURLWithPath: "/Users/kaden/private/secret.txt")
        let fileSummary = ClipboardDiagnostics.contentSummary(for: fileItem(fileURL))

        #expect(urlSummary.contentLength == url.count)
        #expect(!urlSummary.contentKeyDigest.contains("example"))
        #expect(!urlSummary.contentKeyDigest.contains("secret"))
        #expect(fileSummary.contentLength == 1)
        #expect(!fileSummary.contentKeyDigest.contains("Users"))
        #expect(!fileSummary.contentKeyDigest.contains("secret"))
    }

    @Test func duplicateMetadataReportsMatchingItemsAndPinnedStatus() {
        let duplicateID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let pinnedDuplicateID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let differentID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let pending = textItem(text: "same", sourceApp: "ChatGPT")
        let duplicate = textItem(id: duplicateID, text: "same", sourceApp: "Doubao")
        let pinnedDuplicate = textItem(id: pinnedDuplicateID, text: "same", sourceApp: "Safari", isPinned: true)
        let different = textItem(id: differentID, text: "different", sourceApp: "ChatGPT")

        let metadata = ClipboardDiagnostics.duplicateMetadata(
            for: pending,
            in: [duplicate, pinnedDuplicate, different]
        )

        #expect(metadata.count == 2)
        #expect(metadata.itemIDs == [duplicateID, pinnedDuplicateID])
        #expect(metadata.pinnedCount == 1)
        #expect(metadata.itemIDList.contains(duplicateID.uuidString))
        #expect(metadata.itemIDList.contains(pinnedDuplicateID.uuidString))
        #expect(!metadata.itemIDList.contains(differentID.uuidString))
    }

    private func textItem(
        id: UUID = UUID(),
        text: String,
        sourceApp: String,
        isPinned: Bool = false
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: .text,
            title: text,
            preview: text,
            sourceApp: sourceApp,
            sourceAppIconData: nil,
            createdAt: Date(),
            isPinned: isPinned,
            pinboardName: nil,
            textValue: text,
            fileURLs: [],
            imageData: nil
        )
    }

    private func urlItem(_ url: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .url,
            title: "example.com",
            preview: url,
            sourceApp: "Safari",
            sourceAppIconData: nil,
            createdAt: Date(),
            isPinned: false,
            pinboardName: nil,
            textValue: url,
            fileURLs: [],
            imageData: nil
        )
    }

    private func fileItem(_ url: URL) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .file,
            title: url.lastPathComponent,
            preview: url.path,
            sourceApp: "Finder",
            sourceAppIconData: nil,
            createdAt: Date(),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [url],
            imageData: nil
        )
    }
}
