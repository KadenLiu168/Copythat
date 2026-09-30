@testable import Copythat
import Foundation
import Testing

struct ClipboardItemDecodingTests {
    @Test func olderEncodedItemsDecodeWithDefaultsForMissingFields() throws {
        let json = """
        [{
            "id": "00000000-0000-0000-0000-000000000001",
            "kind": "text",
            "title": "Title",
            "preview": "Preview",
            "sourceApp": "Safari",
            "createdAt": 0,
            "isPinned": true,
            "textValue": "Preview"
        }]
        """.data(using: .utf8)!

        let recorder = SearchCorpusRecorder()
        let decoded = try SearchCorpusObservation.$recorder.withValue(recorder) {
            try JSONDecoder().decode([ClipboardItem].self, from: json)
        }

        #expect(recorder.count == 1)
        #expect(decoded.count == 1)
        #expect(decoded[0].fileURLs.isEmpty)
        #expect(decoded[0].imageData == nil)
        #expect(decoded[0].sourceAppIconData == nil)
        #expect(decoded[0].pinboardName == nil)
        #expect(decoded[0].linkTitle == nil)
        #expect(decoded[0].isPinned)
        #expect(decoded[0].searchText.contains("title"))
        #expect(decoded[0].searchText.contains("safari"))
    }

    @Test func legacyRoundTripEncodesNoCorpusAndRebuildsItOnce() throws {
        let original = ClipboardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            kind: .url,
            title: "Example Domain",
            preview: "https://example.com/path",
            sourceApp: "Safari",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            isPinned: true,
            pinboardName: "Work",
            textValue: "https://example.com/path",
            fileURLs: [],
            imageData: nil,
            linkTitle: "Example link"
        )
        let encoded = try JSONEncoder().encode(original)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["searchText"] == nil)
        #expect(object["searchCorpus"] == nil)

        let recorder = SearchCorpusRecorder()
        let decoded = try SearchCorpusObservation.$recorder.withValue(recorder) {
            try JSONDecoder().decode(ClipboardItem.self, from: encoded)
        }

        #expect(recorder.count == 1, "decoding builds exactly one corpus per item")
        #expect(decoded == original)
        #expect(decoded.searchText == original.searchText)
    }

    @Test func injectedCorpusFieldsNeverOverrideMetadata() throws {
        let json = Data("""
        [{
            "id": "00000000-0000-0000-0000-000000000003",
            "kind": "text",
            "title": "Real title",
            "preview": "Real preview",
            "sourceApp": "Safari",
            "createdAt": 0,
            "isPinned": false,
            "textValue": "Real preview",
            "searchText": "injectedmark",
            "searchCorpus": "injectedmark"
        }]
        """.utf8)

        let recorder = SearchCorpusRecorder()
        let decoded = try SearchCorpusObservation.$recorder.withValue(recorder) {
            try JSONDecoder().decode([ClipboardItem].self, from: json)
        }

        #expect(recorder.count == 1)
        #expect(decoded[0].searchText.contains("real title"))
        #expect(decoded[0].searchText.contains("real preview"))
        #expect(!decoded[0].searchText.contains("injectedmark"))
    }
}
