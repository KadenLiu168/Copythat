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

        let decoded = try JSONDecoder().decode([ClipboardItem].self, from: json)

        #expect(decoded.count == 1)
        #expect(decoded[0].fileURLs.isEmpty)
        #expect(decoded[0].imageData == nil)
        #expect(decoded[0].sourceAppIconData == nil)
        #expect(decoded[0].pinboardName == nil)
        #expect(decoded[0].linkTitle == nil)
        #expect(decoded[0].isPinned)
    }
}
