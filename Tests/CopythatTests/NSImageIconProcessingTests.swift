import AppKit
import Testing
@testable import Copythat

struct NSImageIconProcessingTests {
    @Test func multiRepresentationIconExportsHighResolutionPNG() throws {
        let image = multiRepresentationIcon(pixelSizes: [16, 64, 256])

        let data = try #require(image.appIconPNGData(maxPixel: 160))
        let bitmap = try #require(NSBitmapImageRep(data: data))
        let longestSide = max(bitmap.pixelsWide, bitmap.pixelsHigh)

        #expect(longestSide > 104)
        #expect(longestSide <= 160)
    }

    @Test func lowResolutionIconIsNotUpscaled() throws {
        let image = multiRepresentationIcon(pixelSizes: [16, 64])

        let data = try #require(image.appIconPNGData(maxPixel: 160))
        let bitmap = try #require(NSBitmapImageRep(data: data))
        let longestSide = max(bitmap.pixelsWide, bitmap.pixelsHigh)

        #expect(longestSide == 64)
    }
}

private func multiRepresentationIcon(pixelSizes: [Int]) -> NSImage {
    let image = NSImage(size: NSSize(width: 32, height: 32))
    for pixelSize in pixelSizes {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let channel = CGFloat(pixelSize) / 256
        bitmap.setColor(
            NSColor(calibratedRed: channel, green: 0.4, blue: 0.8, alpha: 1),
            atX: 0,
            y: 0
        )
        image.addRepresentation(bitmap)
    }
    return image
}
