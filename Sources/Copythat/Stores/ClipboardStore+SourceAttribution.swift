import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Source attribution helpers

extension ClipboardStore {
    func normalizedImageData(for image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = Self.pngData(cgImage: cgImage, maxPixel: 1_200) else { return nil }
        return data
    }

    func sourceMetadata(
        kind: ClipboardKind,
        isSystemGeneratedContent: Bool = false,
        changeCountDelta: Int,
        currentChangeCount: Int,
        firstObservedSource: ClipboardSource?
    ) -> ClipboardSource {
        let source = sourceTracker.resolveSource(
            isSystemGeneratedContent: isSystemGeneratedContent,
            firstObservedSource: firstObservedSource,
            pasteboardChangeCountDelta: changeCountDelta,
            currentPasteboardChangeCount: currentChangeCount
        )
        diagnostics.logCapture(
            kind: kind,
            source: source,
            currentChangeCount: currentChangeCount,
            changeCountDelta: changeCountDelta
        )
        return source
    }

    /// Identity of the current pasteboard image, in the same form as an item's
    /// `contentKey`, so a restored unloaded image matches without being read.
    func imageContentKey(for image: NSImage) -> String? {
        guard let data = normalizedImageData(for: image) else { return nil }
        return "image:\(PreparedMedia(hashing: data).id)"
    }

    nonisolated static func pngData(cgImage: CGImage, maxPixel: CGFloat) -> Data? {
        let largestSide = max(cgImage.width, cgImage.height)
        guard largestSide > 0 else { return nil }
        let scale = min(1, maxPixel / CGFloat(largestSide))
        let width = max(1, Int((CGFloat(cgImage.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(cgImage.height) * scale).rounded()))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let resized = context.makeImage() else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, resized, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
