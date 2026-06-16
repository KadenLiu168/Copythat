@testable import Copythat
import AppKit
import Testing

struct ClipboardItemStorageOptimizationTests {
    @Test func storageOptimizedPreservesSourceIconData() throws {
        let sourceIconData = try #require(testImage(width: 160, height: 160).pngData(maxPixel: 160))
        let item = clipboardItem(sourceAppIconData: sourceIconData)

        let optimized = item.storageOptimized

        #expect(optimized.sourceAppIconData == sourceIconData)
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
        linkImageData: Data? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: imageData == nil ? .url : .image,
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
            linkImageData: linkImageData
        )
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
