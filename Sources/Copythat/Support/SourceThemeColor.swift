import AppKit

enum SourceThemeColor {
    static let neutralAccent = NSColor(calibratedRed: 0.72, green: 0.66, blue: 0.58, alpha: 1)
    private static let accentCache: NSCache<NSData, NSColor> = {
        let cache = NSCache<NSData, NSColor>()
        cache.countLimit = 128
        return cache
    }()

    static func accent(icon: NSImage?) -> NSColor {
        icon?.logoThemeColor ?? neutralAccent
    }

    static func accent(iconData: Data?) -> NSColor {
        guard let iconData else { return neutralAccent }
        let key = iconData as NSData
        if let cached = accentCache.object(forKey: key) {
            return cached
        }

        let accent = accent(icon: NSImage(data: iconData))
        accentCache.setObject(accent, forKey: key)
        return accent
    }
}

private extension NSImage {
    static let hueBucketCount = 12

    var logoThemeColor: NSColor? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else { return nil }

        let stepX = max(1, width / 24)
        let stepY = max(1, height / 24)

        var bucketCounts = [Int](repeating: 0, count: Self.hueBucketCount)
        var bucketRed = [CGFloat](repeating: 0, count: Self.hueBucketCount)
        var bucketGreen = [CGFloat](repeating: 0, count: Self.hueBucketCount)
        var bucketBlue = [CGFloat](repeating: 0, count: Self.hueBucketCount)
        var totalSamples = 0

        for x in stride(from: stepX / 2, to: width, by: stepX) {
            for y in stride(from: stepY / 2, to: height, by: stepY) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent >= 0.35 else {
                    continue
                }

                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                var alpha: CGFloat = 0
                color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

                guard saturation >= 0.20, brightness > 0.16, brightness < 0.99 else {
                    continue
                }

                let bucket = min(Int(hue * CGFloat(Self.hueBucketCount)), Self.hueBucketCount - 1)
                bucketCounts[bucket] += 1
                bucketRed[bucket] += color.redComponent
                bucketGreen[bucket] += color.greenComponent
                bucketBlue[bucket] += color.blueComponent
                totalSamples += 1
            }
        }

        guard totalSamples > 0 else { return nil }

        var bestScore: CGFloat = 0
        var bestColor: NSColor?
        for bucket in 0..<Self.hueBucketCount where bucketCounts[bucket] > 0 {
            let count = CGFloat(bucketCounts[bucket])
            let coverage = count / CGFloat(totalSamples)
            let meanColor = NSColor(
                calibratedRed: bucketRed[bucket] / count,
                green: bucketGreen[bucket] / count,
                blue: bucketBlue[bucket] / count,
                alpha: 1
            )

            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var alpha: CGFloat = 0
            meanColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            let chroma = max(meanColor.redComponent, meanColor.greenComponent, meanColor.blueComponent) -
                min(meanColor.redComponent, meanColor.greenComponent, meanColor.blueComponent)

            let score = coverage * (0.5 + saturation) * (0.5 + chroma)
            if score > bestScore {
                bestScore = score
                bestColor = meanColor
            }
        }

        return bestColor?.normalizedThemeAccent
    }
}

private extension NSColor {
    /// Adaptive saturation normalization: muted brand colors gain mild
    /// vividness, mid-range colors get a small boost, and everything is
    /// bounded below the neon threshold (design D2 step 5).
    var normalizedThemeAccent: NSColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        if saturation < 0.35 {
            let progress = max(0, saturation - 0.20) / 0.15
            saturation = 0.35 + progress * 0.15
        } else if saturation <= 0.7 {
            saturation = min(saturation * 1.12, 0.92)
        }

        return NSColor(
            calibratedHue: hue,
            saturation: min(saturation, 0.92),
            brightness: min(max(brightness, 0.3), 0.95),
            alpha: 1
        )
    }
}
