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

    @Test func referenceOnlyMediaReportsPayloadPresence() {
        let referenceOnly = clipboardItem(
            sourceAppIconData: nil,
            persistedImageBlobID: sha256Hex(Data([1, 2, 3])),
            persistedLinkImageBlobID: sha256Hex(Data([4, 5, 6]))
        )
        let empty = clipboardItem(sourceAppIconData: nil)

        #expect(referenceOnly.hasImagePayload)
        #expect(referenceOnly.hasLinkImagePayload)
        #expect(!empty.hasImagePayload)
        #expect(!empty.hasLinkImagePayload)
    }

    @Test func eagerAndLazyImagesShareContentKey() {
        let bytes = Data([7, 7, 7, 9])
        let eager = clipboardItem(sourceAppIconData: nil, imageData: bytes)
        let lazy = clipboardItem(
            sourceAppIconData: nil,
            persistedImageBlobID: sha256Hex(bytes)
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
            persistedImageBlobID: imageBlobID,
            persistedLinkImageBlobID: linkImageBlobID
        )

        let optimized = item.storageOptimized

        #expect(optimized.imageData == nil)
        #expect(optimized.linkImageData == nil)
        #expect(optimized.persistedImageBlobID == imageBlobID)
        #expect(optimized.persistedLinkImageBlobID == linkImageBlobID)
        #expect(optimized.contentKey == item.contentKey)
        AcceptanceMetrics.record(
            scenario: "model-identity",
            metric: "referencesRetainedByStorageOptimized",
            expected: "2",
            observed: "\([optimized.persistedImageBlobID != nil, optimized.persistedLinkImageBlobID != nil].filter { $0 }.count)"
        )
    }

    @Test func storageOptimizedDropsReferenceWhenBytesChange() throws {
        let sourceData = try #require(testImage(width: 1_600, height: 900).pngData(maxPixel: 1_600))
        let item = clipboardItem(
            sourceAppIconData: nil,
            imageData: sourceData,
            persistedImageBlobID: sha256Hex(sourceData)
        )

        let optimized = item.storageOptimized

        let optimizedData = try #require(optimized.imageData)
        #expect(optimizedData != sourceData)
        #expect(optimized.persistedImageBlobID == nil)
        #expect(optimized.contentKey == "image:\(sha256Hex(optimizedData))")
    }

    @Test func titleOnlyCompletionPreservesUnloadedPreviewImage() {
        let linkImageBlobID = sha256Hex(Data([8, 8, 8]))
        let item = clipboardItem(
            sourceAppIconData: nil,
            linkImageData: nil,
            persistedImageBlobID: sha256Hex(Data([9])),
            persistedLinkImageBlobID: linkImageBlobID
        )

        let merged = item.withLinkPreview(title: "Updated title", linkImageData: nil)

        #expect(merged.title == "Updated title")
        #expect(merged.linkTitle == "Updated title")
        #expect(merged.linkImageData == nil)
        #expect(merged.persistedLinkImageBlobID == linkImageBlobID)
        #expect(merged.hasLinkImagePayload)
        #expect(merged.persistedImageBlobID == item.persistedImageBlobID)
    }

    @Test func titleOnlyCompletionPreservesMaterializedPreviewImage() {
        let linkImageData = Data([4, 2, 0])
        let item = clipboardItem(sourceAppIconData: nil, linkImageData: linkImageData)

        let merged = item.withLinkPreview(title: "Updated title", linkImageData: nil)

        #expect(merged.linkImageData == linkImageData)
        #expect(merged.persistedLinkImageBlobID == nil)
        #expect(merged.hasLinkImagePayload)
    }

    @Test func newPreviewClearsPriorReferenceAndPropagatesImageReference() {
        let newLinkImageData = Data([5, 5, 1])
        let imageBlobID = sha256Hex(Data([1, 2]))
        let item = clipboardItem(
            sourceAppIconData: nil,
            persistedImageBlobID: imageBlobID,
            persistedLinkImageBlobID: sha256Hex(Data([6, 6]))
        )

        let merged = item.withLinkPreview(title: "New preview", linkImageData: newLinkImageData)

        #expect(merged.linkImageData == newLinkImageData)
        #expect(merged.persistedLinkImageBlobID == nil)
        #expect(merged.persistedImageBlobID == imageBlobID)
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
        imageData: Data? = nil,
        linkImageData: Data? = nil,
        persistedImageBlobID: String? = nil,
        persistedLinkImageBlobID: String? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: imageData == nil && persistedImageBlobID == nil ? .url : .image,
            title: "Example",
            preview: "https://example.com",
            sourceApp: "Safari",
            sourceAppIconData: sourceAppIconData,
            createdAt: Date(),
            isPinned: false,
            pinboardName: nil,
            textValue: "https://example.com",
            fileURLs: [],
            imageData: imageData,
            linkTitle: "Example",
            linkImageData: linkImageData,
            persistedImageBlobID: persistedImageBlobID,
            persistedLinkImageBlobID: persistedLinkImageBlobID
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
