import AppKit

extension NSImage {
    func pngData(maxPixel: CGFloat) -> Data? {
        guard let resized = resized(maxPixel: maxPixel),
              let tiffData = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// Exports the best available high-resolution representation (e.g. an
    /// `NSWorkspace` app icon that reports a small logical point size while
    /// carrying representations up to 2048px) into a PNG bounded by `maxPixel`
    /// on its longest side. Lower-resolution sources are never upscaled.
    func appIconPNGData(maxPixel: CGFloat) -> Data? {
        let targetSize = NSSize(width: maxPixel, height: maxPixel)
        guard let representation = bestRepresentation(for: NSRect(origin: .zero, size: targetSize),
                                                      context: nil,
                                                      hints: nil) else {
            return nil
        }

        let pixelWidth = representation.pixelsWide
        let pixelHeight = representation.pixelsHigh
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let scale = min(1, maxPixel / max(CGFloat(pixelWidth), CGFloat(pixelHeight)))
        let outputPixelWidth = max(1, Int((CGFloat(pixelWidth) * scale).rounded()))
        let outputPixelHeight = max(1, Int((CGFloat(pixelHeight) * scale).rounded()))
        let outputSize = NSSize(width: CGFloat(outputPixelWidth), height: CGFloat(outputPixelHeight))

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: outputPixelWidth,
            pixelsHigh: outputPixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        representation.draw(in: NSRect(origin: .zero, size: outputSize))
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .png, properties: [:])
    }

    private func resized(maxPixel: CGFloat) -> NSImage? {
        let largestSide = max(size.width, size.height)
        guard largestSide > 0 else { return nil }
        let scale = min(1, maxPixel / largestSide)
        let targetSize = NSSize(width: max(1, size.width * scale), height: max(1, size.height * scale))

        let image = NSImage(size: targetSize)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1)
        image.unlockFocus()
        return image
    }
}
