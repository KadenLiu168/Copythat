@testable import Copythat
import AppKit
import CryptoKit
import Testing

struct ClipboardItemStorageOptimizationTests {
    @Test func storageOptimizedPreservesSourceIconData() throws {
        let sourceIconData = try #require(testImage(width: 160, height: 160).pngData(maxPixel: 160))
        let item = clipboardItem(sourceAppIconData: sourceIconData)

        let optimized = item.storageOptimized

        #expect(optimized.sourceAppIconData == sourceIconData)
    }

    @Test func storageOptimizedPreservesEveryUntouchedField() throws {
        let icon = PreparedMedia(hashing: Data(repeating: 0x71, count: 96))
        let fileURL = URL(fileURLWithPath: "/tmp/copythat-optimization-fixture.txt")
        let createdAt = Date(timeIntervalSince1970: 1_700_000_700)
        let item = ClipboardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000071")!,
            kind: .url,
            title: "example.com",
            preview: "https://example.com/optimized",
            sourceApp: "Fixture",
            sourceAppIconData: icon.data,
            sourceAppIconBlobID: icon.id,
            createdAt: createdAt,
            isPinned: true,
            pinboardName: "Archive",
            textValue: "https://example.com/optimized",
            fileURLs: [fileURL],
            imageData: nil,
            imageBlobID: sha256Hex(Data([0x72])),
            linkTitle: "Optimization link",
            linkImageData: nil,
            linkImageBlobID: sha256Hex(Data([0x73]))
        )

        let optimized = item.storageOptimized

        #expect(optimized.id == item.id)
        #expect(optimized.kind == item.kind)
        #expect(optimized.title == item.title)
        #expect(optimized.preview == item.preview)
        #expect(optimized.sourceApp == item.sourceApp)
        #expect(optimized.sourceAppIconData == icon.data)
        #expect(optimized.sourceAppIconBlobID == icon.id)
        #expect(optimized.createdAt == createdAt)
        #expect(optimized.isPinned)
        #expect(optimized.pinboardName == "Archive")
        #expect(optimized.textValue == item.textValue)
        #expect(optimized.fileURLs == [fileURL])
        #expect(optimized.linkTitle == "Optimization link")
        #expect(optimized.contentKey == item.contentKey)
        #expect(optimized.searchText == item.searchText)
    }

    @Test func referenceOnlyMediaReportsPayloadPresence() {
        let referenceOnly = clipboardItem(
            sourceAppIconData: nil,
            imageBlobID: sha256Hex(Data([1, 2, 3])),
            linkImageBlobID: sha256Hex(Data([4, 5, 6]))
        )
        let empty = clipboardItem(sourceAppIconData: nil)

        #expect(referenceOnly.hasImagePayload)
        #expect(referenceOnly.hasLinkImagePayload)
        #expect(referenceOnly.sourceAppIconBlobID == nil)
        #expect(!empty.hasImagePayload)
        #expect(!empty.hasLinkImagePayload)
        #expect(empty.sourceAppIconBlobID == nil, "absent icon bytes keep an absent address")
    }

    @Test func eagerAndLazyImagesShareContentKey() {
        let bytes = Data([7, 7, 7, 9])
        let eager = clipboardItem(sourceAppIconData: nil, imageData: bytes)
        let lazy = clipboardItem(
            sourceAppIconData: nil,
            imageBlobID: sha256Hex(bytes)
        )

        #expect(eager.contentKey == lazy.contentKey)
        #expect(eager.contentKey == "image:\(sha256Hex(bytes))")
        AcceptanceMetrics.record(
            scenario: "model-identity",
            metric: "eagerAndLazyContentKeysMatch",
            expected: "true",
            observed: "\(eager.contentKey == lazy.contentKey)"
        )
    }

    @Test func storageOptimizedPropagatesUnloadedReferences() {
        let imageBlobID = sha256Hex(Data([1, 1, 2]))
        let linkImageBlobID = sha256Hex(Data([3, 3, 4]))
        let item = clipboardItem(
            sourceAppIconData: nil,
            imageBlobID: imageBlobID,
            linkImageBlobID: linkImageBlobID
        )

        let optimized = item.storageOptimized

        #expect(optimized.imageData == nil)
        #expect(optimized.linkImageData == nil)
        #expect(optimized.imageBlobID == imageBlobID)
        #expect(optimized.linkImageBlobID == linkImageBlobID)
        #expect(optimized.contentKey == item.contentKey)
        AcceptanceMetrics.record(
            scenario: "model-identity",
            metric: "referencesRetainedByStorageOptimized",
            expected: "2",
            observed: "\([optimized.imageBlobID != nil, optimized.linkImageBlobID != nil].filter { $0 }.count)"
        )
    }

    @Test func storageOptimizedReplacesReferenceWhenBytesChange() throws {
        let sourceData = try #require(testImage(width: 1_600, height: 900).pngData(maxPixel: 1_600))
        let item = clipboardItem(
            sourceAppIconData: nil,
            imageData: sourceData,
            imageBlobID: sha256Hex(sourceData)
        )

        let optimized = item.storageOptimized

        let optimizedData = try #require(optimized.imageData)
        #expect(optimizedData != sourceData)
        #expect(optimized.imageBlobID == sha256Hex(optimizedData))
        #expect(optimized.imageBlobID != item.imageBlobID)
        #expect(optimized.contentKey == "image:\(sha256Hex(optimizedData))")
    }

    @Test func storageOptimizedKeepsUnchangedBytesAndAddressWithoutHashing() async throws {
        let counters = MediaOperationCounters()
        let source = try #require(testImage(width: 800, height: 600).pngData(maxPixel: 800))
        let item = clipboardItem(sourceAppIconData: nil, imageData: source, linkImageData: source)
        let once = item.storageOptimized
        let onceImageID = try #require(once.imageBlobID)

        guard once.imageData == source else {
            // Re-encoding changed the bytes, so the replacement must carry its
            // own address rather than the source's.
            #expect(onceImageID == once.imageData.map(sha256Hex))
            return
        }

        counters.reset()
        let twice = await counters.measure { once.storageOptimized }

        #expect(twice.imageData == once.imageData)
        #expect(twice.imageBlobID == onceImageID)
        #expect(counters.mediaHashCount == 0)
    }

    @Test func storageOptimizedClearsPayloadsThatCannotBeConverted() async {
        let counters = MediaOperationCounters()
        let undecodable = Data([0x00, 0x01, 0x02, 0x03])
        let item = clipboardItem(sourceAppIconData: nil, imageData: undecodable, linkImageData: undecodable)

        counters.reset()
        let optimized = await counters.measure { item.storageOptimized }

        #expect(optimized.imageData == nil)
        #expect(optimized.linkImageData == nil)
        #expect(optimized.imageBlobID == nil)
        #expect(optimized.linkImageBlobID == nil)
        #expect(!optimized.hasImagePayload)
        #expect(!optimized.hasLinkImagePayload)
        #expect(counters.mediaHashCount == 0)
    }

    /// Each role clears its own pair, so a failed conversion never disturbs the
    /// payload the other role kept.
    @Test func storageOptimizedClearsOnlyTheFailedRole() throws {
        let decodable = try #require(testImage(width: 64, height: 64).pngData(maxPixel: 64))
        let item = clipboardItem(
            sourceAppIconData: nil,
            imageData: Data([0x00, 0x01, 0x02, 0x03]),
            linkImageData: decodable
        )

        let optimized = item.storageOptimized

        #expect(optimized.imageData == nil)
        #expect(optimized.imageBlobID == nil)
        #expect(optimized.linkImageData == decodable)
        #expect(optimized.linkImageBlobID == sha256Hex(decodable))
        #expect(!optimized.hasImagePayload)
        #expect(optimized.hasLinkImagePayload)
    }

    @Test func storageOptimizedEstablishesOneAddressPerChangedPayload() async throws {
        let counters = MediaOperationCounters()
        let oversizedImage = try #require(testImage(width: 2_400, height: 1_200).pngData(maxPixel: 2_400))
        let oversizedLinkImage = try #require(testImage(width: 1_280, height: 800).pngData(maxPixel: 1_280))
        let item = clipboardItem(
            sourceAppIconData: nil,
            imageData: oversizedImage,
            linkImageData: oversizedLinkImage
        )

        counters.reset()
        let optimized = await counters.measure { item.storageOptimized }

        let optimizedImageData = try #require(optimized.imageData)
        let optimizedLinkImageData = try #require(optimized.linkImageData)
        #expect(optimizedImageData != oversizedImage, "the fixture must actually be re-encoded")
        #expect(optimizedLinkImageData != oversizedLinkImage, "the fixture must actually be re-encoded")
        #expect(optimized.imageBlobID == sha256Hex(optimizedImageData))
        #expect(optimized.linkImageBlobID == sha256Hex(optimizedLinkImageData))
        #expect(optimized.imageBlobID != sha256Hex(oversizedImage), "new bytes must not keep the old address")
        #expect(optimized.linkImageBlobID != sha256Hex(oversizedLinkImage))
        #expect(counters.identityHashCount == 2, "each changed payload establishes its address exactly once")
        #expect(counters.integrityHashCount == 0)
    }

    @Test func titleOnlyCompletionPreservesUnloadedPreviewImage() {
        let linkImageBlobID = sha256Hex(Data([8, 8, 8]))
        let icon = PreparedMedia(hashing: Data(repeating: 0x81, count: 72))
        let item = clipboardItem(
            sourceAppIconData: icon.data,
            sourceAppIconBlobID: icon.id,
            linkImageData: nil,
            imageBlobID: sha256Hex(Data([9])),
            linkImageBlobID: linkImageBlobID
        )

        let merged = item.withLinkPreview(title: "Updated title", linkImage: nil)

        #expect(merged.title == "Updated title")
        #expect(merged.linkTitle == "Updated title")
        #expect(merged.linkImageData == nil)
        #expect(merged.linkImageBlobID == linkImageBlobID)
        #expect(merged.hasLinkImagePayload)
        #expect(merged.imageBlobID == item.imageBlobID)
        #expect(merged.sourceAppIconData == icon.data)
        #expect(merged.sourceAppIconBlobID == icon.id)
    }

    @Test func titleOnlyCompletionPreservesMaterializedPreviewImage() {
        let linkImageData = Data([4, 2, 0])
        let icon = PreparedMedia(hashing: Data(repeating: 0x82, count: 72))
        let item = clipboardItem(
            sourceAppIconData: icon.data,
            sourceAppIconBlobID: icon.id,
            linkImageData: linkImageData
        )

        let merged = item.withLinkPreview(title: "Updated title", linkImage: nil)

        #expect(merged.linkImageData == linkImageData)
        #expect(merged.linkImageBlobID == sha256Hex(linkImageData))
        #expect(merged.hasLinkImagePayload)
        #expect(merged.sourceAppIconData == icon.data)
        #expect(merged.sourceAppIconBlobID == icon.id)
    }

    @Test func titleOnlyCompletionDoesNotHashTheForwardedPayloads() async {
        let counters = MediaOperationCounters()
        let icon = PreparedMedia(hashing: Data(repeating: 0x83, count: 72))
        let linkImage = PreparedMedia(hashing: Data(repeating: 0x84, count: 128))
        let item = clipboardItem(
            sourceAppIconData: icon.data,
            sourceAppIconBlobID: icon.id,
            linkImageData: linkImage.data,
            linkImageBlobID: linkImage.id
        )

        counters.reset()
        let merged = await counters.measure { item.withLinkPreview(title: "Updated title", linkImage: nil) }

        #expect(merged.linkImageBlobID == linkImage.id)
        #expect(merged.sourceAppIconBlobID == icon.id)
        #expect(counters.mediaHashCount == 0)
    }

    @Test func newPreviewClearsPriorReferenceAndPropagatesImageReference() {
        let newLinkImageData = Data([5, 5, 1])
        let imageBlobID = sha256Hex(Data([1, 2]))
        let icon = PreparedMedia(hashing: Data(repeating: 0x85, count: 72))
        let item = clipboardItem(
            sourceAppIconData: icon.data,
            sourceAppIconBlobID: icon.id,
            imageBlobID: imageBlobID,
            linkImageBlobID: sha256Hex(Data([6, 6]))
        )

        let merged = item.withLinkPreview(title: "New preview", linkImage: PreparedMedia(hashing: newLinkImageData))

        #expect(merged.linkImageData == newLinkImageData)
        #expect(merged.linkImageBlobID == sha256Hex(newLinkImageData))
        #expect(merged.imageBlobID == imageBlobID)
        #expect(merged.sourceAppIconData == icon.data)
        #expect(merged.sourceAppIconBlobID == icon.id)
    }

    @Test func storageOptimizedStillBoundsImageAndLinkPreviewData() throws {
        let imageData = try #require(testImage(width: 1_600, height: 900).pngData(maxPixel: 1_600))
        let linkImageData = try #require(testImage(width: 1_200, height: 800).pngData(maxPixel: 1_200))
        let item = clipboardItem(
            sourceAppIconData: nil,
            imageData: imageData,
            linkImageData: linkImageData
        )

        let optimized = item.storageOptimized

        #expect(try #require(imageSize(of: optimized.imageData)).largestSide <= 1_200)
        #expect(try #require(imageSize(of: optimized.linkImageData)).largestSide <= 640)
        #expect(optimized.imageData != imageData)
        #expect(optimized.linkImageData != linkImageData)
    }

    private func clipboardItem(
        sourceAppIconData: Data?,
        sourceAppIconBlobID: String? = nil,
        imageData: Data? = nil,
        linkImageData: Data? = nil,
        imageBlobID: String? = nil,
        linkImageBlobID: String? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: imageData == nil && imageBlobID == nil ? .url : .image,
            title: "Example",
            preview: "https://example.com",
            sourceApp: "Safari",
            sourceAppIconData: sourceAppIconData,
            sourceAppIconBlobID: sourceAppIconBlobID,
            createdAt: Date(),
            isPinned: false,
            pinboardName: nil,
            textValue: "https://example.com",
            fileURLs: [],
            imageData: imageData,
            imageBlobID: imageBlobID,
            linkTitle: "Example",
            linkImageData: linkImageData,
            linkImageBlobID: linkImageBlobID
        )
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func testImage(width: Int, height: Int) -> NSImage {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let color = NSColor(calibratedRed: 0.24, green: 0.48, blue: 0.82, alpha: 1)
        for x in 0..<width {
            for y in 0..<height {
                bitmap.setColor(color, atX: x, y: y)
            }
        }

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(bitmap)
        return image
    }

    private func imageSize(of data: Data?) -> CGSize? {
        guard let data, let image = NSImage(data: data) else { return nil }
        return image.size
    }
}

private extension CGSize {
    var largestSide: CGFloat {
        max(width, height)
    }
}
