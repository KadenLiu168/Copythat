import AppKit

enum SourceThemeColor {
    static let neutralAccent = NSColor(calibratedRed: 0.72, green: 0.66, blue: 0.58, alpha: 1)

    static func accent(icon: NSImage?) -> NSColor {
        icon?.logoThemeColor ?? neutralAccent
    }
}

private extension NSImage {
    var logoThemeColor: NSColor? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else { return nil }

        let stepX = max(1, width / 20)
        let stepY = max(1, height / 20)
        var bestColor: NSColor?
        var bestScore: CGFloat = 0

        for x in stride(from: stepX / 2, to: width, by: stepX) {
            for y in stride(from: stepY / 2, to: height, by: stepY) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.35 else {
                    continue
                }

                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                var alpha: CGFloat = 0
                color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

                guard saturation > 0.20, brightness > 0.16, brightness < 0.99 else {
                    continue
                }

                let chroma = max(color.redComponent, color.greenComponent, color.blueComponent) -
                    min(color.redComponent, color.greenComponent, color.blueComponent)
                let score = saturation * 0.52 + brightness * 0.24 + chroma * 0.24
                if score > bestScore {
                    bestScore = score
                    bestColor = color
                }
            }
        }

        return bestColor
    }
}
