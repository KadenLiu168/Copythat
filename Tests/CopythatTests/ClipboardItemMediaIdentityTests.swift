@testable import Copythat
import CryptoKit
import Foundation
import Testing

/// Model-level contracts for runtime media identity: resident bytes always
/// carry their content address, prepared payloads are forwarded without a
/// second hash, and legacy encoding keeps its payload keys.
struct ClipboardItemMediaIdentityTests {
    @Test func residentBytesEstablishOneAddressPerPayloadAtConstruction() async {
        let counters = MediaOperationCounters()
        let icon = Data(repeating: 0x11, count: 64)
        let image = Data(repeating: 0x22, count: 256)
        let linkImage = Data(repeating: 0x33, count: 128)

        let item = await counters.measure {
            makeItem(sourceIcon: icon, imageData: image, linkImageData: linkImage)
        }

        #expect(item.sourceAppIconBlobID == sha256Hex(icon))
        #expect(item.imageBlobID == sha256Hex(image))
        #expect(item.linkImageBlobID == sha256Hex(linkImage))
        #expect(counters.identityHashCount == 3)
        #expect(counters.integrityHashCount == 0)
    }

    @Test func preparedMediaIsForwardedWithoutHashing() async {
        let counters = MediaOperationCounters()
        let image = Data(repeating: 0x44, count: 512)
        let prepared = PreparedMedia(hashing: image)
        counters.reset()

        let item = await counters.measure {
            makeItem(imageData: prepared.data, imageBlobID: prepared.id)
        }

        #expect(item.imageBlobID == prepared.id)
        #expect(counters.mediaHashCount == 0)
    }

    @Test func referenceOnlyAndAbsentMediaStayDistinctWithoutHashing() async {
        let counters = MediaOperationCounters()
        let reference = sha256Hex(Data(repeating: 0x55, count: 32))

        let item = await counters.measure {
            makeItem(imageBlobID: reference, linkImageBlobID: reference)
        }
        let empty = await counters.measure {
            makeItem()
        }

        #expect(item.imageData == nil)
        #expect(item.linkImageData == nil)
        #expect(item.imageBlobID == reference)
        #expect(item.linkImageBlobID == reference)
        #expect(item.hasImagePayload)
        #expect(item.hasLinkImagePayload)
        #expect(item.contentKey == "image:\(reference)")

        #expect(empty.imageBlobID == nil)
        #expect(empty.linkImageBlobID == nil)
        #expect(empty.sourceAppIconBlobID == nil)
        #expect(!empty.hasImagePayload)
        #expect(!empty.hasLinkImagePayload)
        #expect(empty.contentKey == "image:empty")
        #expect(counters.mediaHashCount == 0)
    }

    @Test func contentKeyAccessReusesTheStoredAddressForEagerAndLazyImages() async {
        let counters = MediaOperationCounters()
        let bytes = Data(repeating: 0x66, count: 300)
        let prepared = PreparedMedia(hashing: bytes)
        let eager = makeItem(imageData: prepared.data, imageBlobID: prepared.id)
        let lazy = makeItem(imageBlobID: prepared.id)
        counters.reset()

        let eagerKeys = await counters.measure {
            [eager.contentKey, eager.contentKey]
        }
        let lazyKey = await counters.measure { lazy.contentKey }

        #expect(eagerKeys == ["image:\(prepared.id)", "image:\(prepared.id)"])
        #expect(lazyKey == eagerKeys[0])
        #expect(counters.mediaHashCount == 0)
    }

    @Test func codablePayloadStaysUnchangedAndDecodingEstablishesIdentities() async throws {
        let counters = MediaOperationCounters()
        let icon = Data(repeating: 0x77, count: 48)
        let image = Data(repeating: 0x88, count: 96)
        let linkImage = Data(repeating: 0x99, count: 64)
        let item = makeItem(sourceIcon: icon, imageData: image, linkImageData: linkImage)

        let encoded = try JSONEncoder().encode(item)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        // Payload keys stay exactly as they were; runtime addresses never enter
        // the encoded form.
        #expect(object["imageData"] as? String == image.base64EncodedString())
        #expect(object["linkImageData"] as? String == linkImage.base64EncodedString())
        #expect(object["sourceAppIconData"] as? String == icon.base64EncodedString())
        #expect(object.keys.allSatisfy { !$0.hasSuffix("BlobID") })

        counters.reset()
        let decoded = try await counters.measure {
            try JSONDecoder().decode(ClipboardItem.self, from: encoded)
        }

        #expect(decoded == item)
        #expect(decoded.sourceAppIconBlobID == sha256Hex(icon))
        #expect(decoded.imageBlobID == sha256Hex(image))
        #expect(decoded.linkImageBlobID == sha256Hex(linkImage))
        // Inline legacy payloads receive their address exactly once, here,
        // instead of deferring the hash to a later save.
        #expect(counters.identityHashCount == 3)
    }

    private func makeItem(
        sourceIcon: Data? = nil,
        imageData: Data? = nil,
        imageBlobID: String? = nil,
        linkImageData: Data? = nil,
        linkImageBlobID: String? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000a1")!,
            kind: .image,
            title: "Image",
            preview: "Image preview",
            sourceApp: "Preview",
            sourceAppIconData: sourceIcon,
            createdAt: Date(timeIntervalSince1970: 1_700_000_200),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: imageData,
            imageBlobID: imageBlobID,
            linkImageData: linkImageData,
            linkImageBlobID: linkImageBlobID
        )
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
