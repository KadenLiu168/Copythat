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

    @Test func releasingResidentMediaTreatsEachRoleIndependently() async {
        let counters = MediaOperationCounters()
        let image = PreparedMedia(hashing: Data(repeating: 0xa1, count: 200))
        let linkImage = PreparedMedia(hashing: Data(repeating: 0xa2, count: 120))
        let unrelated = sha256Hex(Data(repeating: 0xa3, count: 40))
        let item = makeItem(
            imageData: image.data,
            imageBlobID: image.id,
            linkImageData: linkImage.data,
            linkImageBlobID: linkImage.id
        )

        counters.reset()
        let imageOnly = await counters.measure {
            item.releasingResidentMedia(durableImageBlobID: image.id, durableLinkImageBlobID: nil)
        }
        let linkOnly = await counters.measure {
            item.releasingResidentMedia(durableImageBlobID: nil, durableLinkImageBlobID: linkImage.id)
        }
        let both = await counters.measure {
            item.releasingResidentMedia(durableImageBlobID: image.id, durableLinkImageBlobID: linkImage.id)
        }
        let nonmatching = await counters.measure {
            item.releasingResidentMedia(durableImageBlobID: unrelated, durableLinkImageBlobID: unrelated)
        }
        let absent = await counters.measure {
            item.releasingResidentMedia(durableImageBlobID: nil, durableLinkImageBlobID: nil)
        }

        #expect(imageOnly?.imageData == nil)
        #expect(imageOnly?.imageBlobID == image.id)
        #expect(imageOnly?.linkImageData == linkImage.data, "an absent durable role must not release the other role")

        #expect(linkOnly?.linkImageData == nil)
        #expect(linkOnly?.linkImageBlobID == linkImage.id)
        #expect(linkOnly?.imageData == image.data)

        #expect(both?.imageData == nil)
        #expect(both?.linkImageData == nil)
        #expect(nonmatching == nil, "a different identity must not release resident bytes")
        #expect(absent == nil, "no durable identity means no release")
        #expect(counters.mediaHashCount == 0)
    }

    @Test func releasingResidentMediaLeavesReferenceOnlyItemsUntouchedWithoutHashing() async {
        let counters = MediaOperationCounters()
        let imageReference = sha256Hex(Data(repeating: 0xb1, count: 64))
        let linkReference = sha256Hex(Data(repeating: 0xb2, count: 64))
        let referenceOnly = makeItem(imageBlobID: imageReference, linkImageBlobID: linkReference)
        let empty = makeItem()

        counters.reset()
        let releasedReferenceOnly = await counters.measure {
            referenceOnly.releasingResidentMedia(
                durableImageBlobID: imageReference,
                durableLinkImageBlobID: linkReference
            )
        }
        let releasedEmpty = await counters.measure {
            empty.releasingResidentMedia(durableImageBlobID: nil, durableLinkImageBlobID: nil)
        }

        #expect(releasedReferenceOnly == nil)
        #expect(releasedEmpty == nil)
        #expect(counters.mediaHashCount == 0)
    }

    @Test func releasingBothRolesPreservesIdentityMetadataAndSearch() async {
        let counters = MediaOperationCounters()
        let icon = PreparedMedia(hashing: Data(repeating: 0xc1, count: 48))
        let image = PreparedMedia(hashing: Data(repeating: 0xc2, count: 220))
        let linkImage = PreparedMedia(hashing: Data(repeating: 0xc3, count: 140))
        let fileURL = URL(fileURLWithPath: "/tmp/copythat-release-fixture.txt")
        let item = ClipboardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000c9")!,
            kind: .image,
            title: "Release fixture",
            preview: "Release preview",
            sourceApp: "Fixture",
            sourceAppIconData: icon.data,
            sourceAppIconBlobID: icon.id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_300),
            isPinned: true,
            pinboardName: "Work",
            textValue: "https://example.com/release",
            fileURLs: [fileURL],
            imageData: image.data,
            imageBlobID: image.id,
            linkTitle: "Release link",
            linkImageData: linkImage.data,
            linkImageBlobID: linkImage.id
        )

        counters.reset()
        let released = await counters.measure {
            item.releasingResidentMedia(durableImageBlobID: image.id, durableLinkImageBlobID: linkImage.id)
        }
        let restored = try? #require(released)

        #expect(restored?.id == item.id)
        #expect(restored?.kind == item.kind)
        #expect(restored?.title == item.title)
        #expect(restored?.preview == item.preview)
        #expect(restored?.sourceApp == item.sourceApp)
        #expect(restored?.sourceAppIconData == icon.data)
        #expect(restored?.sourceAppIconBlobID == icon.id)
        #expect(restored?.createdAt == item.createdAt)
        #expect(restored?.isPinned == true)
        #expect(restored?.pinboardName == "Work")
        #expect(restored?.textValue == item.textValue)
        #expect(restored?.fileURLs == [fileURL])
        #expect(restored?.linkTitle == "Release link")
        #expect(restored?.imageData == nil)
        #expect(restored?.imageBlobID == image.id)
        #expect(restored?.linkImageData == nil)
        #expect(restored?.linkImageBlobID == linkImage.id)
        #expect(restored?.contentKey == item.contentKey)
        #expect(restored?.searchText == item.searchText)
        #expect(restored?.hasImagePayload == true)
        #expect(restored?.hasLinkImagePayload == true)
        #expect(counters.mediaHashCount == 0, "release must not re-hash any payload")
    }

    @Test func linkPreviewKeepsSourceIconAndIdentityFieldsWhileReplacingPreviewTitle() async throws {
        let counters = MediaOperationCounters()
        let icon = PreparedMedia(hashing: Data(repeating: 0xd1, count: 52))
        let image = PreparedMedia(hashing: Data(repeating: 0xd2, count: 210))
        let originalPreview = PreparedMedia(hashing: Data(repeating: 0xd3, count: 90))
        let fileURL = URL(fileURLWithPath: "/tmp/copythat-preview-fixture.txt")
        let item = ClipboardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000d4")!,
            kind: .url,
            title: "example.com",
            preview: "https://example.com/preview",
            sourceApp: "Fixture",
            sourceAppIconData: icon.data,
            sourceAppIconBlobID: icon.id,
            createdAt: Date(timeIntervalSince1970: 1_700_000_600),
            isPinned: true,
            pinboardName: "Research",
            textValue: "https://example.com/preview",
            fileURLs: [fileURL],
            imageData: image.data,
            imageBlobID: image.id,
            linkTitle: "Original link title",
            linkImageData: originalPreview.data,
            linkImageBlobID: originalPreview.id
        )
        let replacement = PreparedMedia(hashing: Data(repeating: 0xd5, count: 64))

        counters.reset()
        let merged = await counters.measure {
            item.withLinkPreview(title: "Merged title", linkImage: replacement)
        }

        #expect(merged.id == item.id)
        #expect(merged.kind == item.kind)
        #expect(merged.preview == item.preview)
        #expect(merged.sourceApp == item.sourceApp)
        #expect(merged.sourceAppIconData == icon.data)
        #expect(merged.sourceAppIconBlobID == icon.id)
        #expect(merged.createdAt == item.createdAt)
        #expect(merged.isPinned)
        #expect(merged.pinboardName == "Research")
        #expect(merged.textValue == item.textValue)
        #expect(merged.fileURLs == [fileURL])
        #expect(merged.imageData == image.data)
        #expect(merged.imageBlobID == image.id)
        #expect(merged.title == "Merged title")
        #expect(merged.linkTitle == "Merged title")
        #expect(merged.linkImageData == replacement.data)
        #expect(merged.linkImageBlobID == replacement.id)
        #expect(merged.linkImageBlobID != originalPreview.id)
        #expect(counters.mediaHashCount == 0, "a prepared preview forwards its identity without hashing")
    }

    /// The two nil inputs of a preview merge have opposite meanings: an absent
    /// title keeps the current one, while absent media keeps the current payload
    /// and an absent link title is assigned as nil.
    @Test func linkPreviewAssignsNilLinkTitleAndKeepsNilTitleOnTheDisplayedTitle() async {
        let item = makeItem(
            imageData: Data(repeating: 0xe1, count: 64),
            linkImageData: Data(repeating: 0xe2, count: 96)
        )
        let originalLinkTitle = item.linkTitle
        let originalPreviewData = item.linkImageData
        let originalPreviewID = item.linkImageBlobID

        let merged = item.withLinkPreview(title: nil, linkImage: nil)

        #expect(item.linkTitle != nil, "the fixture must start with a link title for the assignment to be observable")
        #expect(merged.title == item.title, "an absent title keeps the displayed title")
        #expect(merged.linkTitle == nil, "an absent title is assigned, not preserved")
        #expect(originalLinkTitle != nil)
        #expect(merged.preview == item.preview)
        #expect(merged.linkImageData == originalPreviewData)
        #expect(merged.linkImageBlobID == originalPreviewID)
    }

    private func makeItem(        sourceIcon: Data? = nil,
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
            linkTitle: "Image link title",
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