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

    var representativeColor: NSColor? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else { return nil }

        let stepX = max(1, width / 12)
        let stepY = max(1, height / 12)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var weight: CGFloat = 0

        for x in stride(from: stepX / 2, to: width, by: stepX) {
            for y in stride(from: stepY / 2, to: height, by: stepY) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.35 else {
                    continue
                }
                let saturation = max(color.redComponent, color.greenComponent, color.blueComponent) -
                    min(color.redComponent, color.greenComponent, color.blueComponent)
                let sampleWeight = 0.35 + saturation
                red += color.redComponent * sampleWeight
                green += color.greenComponent * sampleWeight
                blue += color.blueComponent * sampleWeight
                weight += sampleWeight
            }
        }

        guard weight > 0 else { return nil }
        return NSColor(
            calibratedRed: red / weight,
            green: green / weight,
            blue: blue / weight,
            alpha: 1
        )
    }

    var warmThemeColor: NSColor? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else { return nil }

        let stepX = max(1, width / 18)
        let stepY = max(1, height / 18)
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

                guard saturation > 0.18, brightness > 0.18, brightness < 0.98 else {
                    continue
                }

                let warmDistance = min(abs(hue - 0.07), abs(hue - 1.0), abs(hue - 0.13))
                let warmScore = max(0, 1 - warmDistance * 4.5)
                let score = saturation * 0.45 + brightness * 0.2 + warmScore * 0.75

                if score > bestScore {
                    bestScore = score
                    bestColor = color.normalizedCardAccent
                }
            }
        }

        return bestColor
    }

    var foregroundLogoCutout: NSImage {
        let trimmed = trimmingTransparentEdges
        guard let cutout = trimmed.removingEdgeBackground else {
            return trimmed
        }
        return cutout.trimmingTransparentEdges
    }

    var trimmingTransparentEdges: NSImage {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return self
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else { return self }

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for x in 0..<width {
            for y in 0..<height {
                guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.04 else {
                    continue
                }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else { return self }

        let cropRect = CGRect(
            x: CGFloat(minX),
            y: CGFloat(minY),
            width: CGFloat(maxX - minX + 1),
            height: CGFloat(maxY - minY + 1)
        )
        guard let cropped = cgImage.cropping(to: cropRect) else { return self }

        return NSImage(
            cgImage: cropped,
            size: NSSize(width: cropped.width, height: cropped.height)
        )
    }

    private var removingEdgeBackground: NSImage? {
        guard let tiffData = tiffRepresentation,
              let sourceBitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        let width = sourceBitmap.pixelsWide
        let height = sourceBitmap.pixelsHigh
        guard width > 8, height > 8 else { return nil }

        let edgeLimitX = max(1, width / 8)
        let edgeLimitY = max(1, height / 8)
        var edgeColors: [NSColor] = []
        edgeColors.reserveCapacity(200)
        var edgeZoneArea = 0

        for x in 0..<width {
            for y in 0..<height where x < edgeLimitX || x >= width - edgeLimitX || y < edgeLimitY || y >= height - edgeLimitY {
                edgeZoneArea += 1
                guard let color = sourceBitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.45 else {
                    continue
                }
                edgeColors.append(color)
            }
        }

        guard edgeColors.count > max(24, width * height / 80) else {
            return nil
        }
        guard CGFloat(edgeColors.count) / CGFloat(max(edgeZoneArea, 1)) > 0.22 else {
            return nil
        }

        let background = edgeColors.averageColor
        guard background.isInformativeBackground else { return nil }

        guard let output = NSBitmapImageRep(
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
        ) else {
            return nil
        }

        let pixelCount = width * height
        var removeMask = Array(repeating: false, count: pixelCount)
        var visited = Array(repeating: false, count: pixelCount)
        var queue: [(x: Int, y: Int)] = []
        queue.reserveCapacity(edgeColors.count)

        func offset(_ x: Int, _ y: Int) -> Int {
            y * width + x
        }

        for x in 0..<width {
            for y in 0..<height where x == 0 || x == width - 1 || y == 0 || y == height - 1 || x < edgeLimitX || x >= width - edgeLimitX || y < edgeLimitY || y >= height - edgeLimitY {
                guard let color = sourceBitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.45 else {
                    continue
                }
                queue.append((x, y))
            }
        }

        var cursor = 0
        while cursor < queue.count {
            let point = queue[cursor]
            cursor += 1
            let pointOffset = offset(point.x, point.y)
            guard !visited[pointOffset],
                  let pointColor = sourceBitmap.colorAt(x: point.x, y: point.y)?.usingColorSpace(.sRGB),
                  pointColor.alphaComponent > 0.04 else {
                continue
            }

            visited[pointOffset] = true
            removeMask[pointOffset] = true

            for neighbor in [(point.x - 1, point.y), (point.x + 1, point.y), (point.x, point.y - 1), (point.x, point.y + 1)] {
                let x = neighbor.0
                let y = neighbor.1
                guard x >= 0, x < width, y >= 0, y < height else { continue }

                let neighborOffset = offset(x, y)
                guard !visited[neighborOffset],
                      let neighborColor = sourceBitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      neighborColor.alphaComponent > 0.04 else {
                    continue
                }

                if neighborColor.perceptualDistance(to: pointColor) < 0.24 ||
                    neighborColor.perceptualDistance(to: background) < 0.34 {
                    queue.append((x, y))
                }
            }
        }

        var keptPixels = 0
        var removedPixels = 0

        for x in 0..<width {
            for y in 0..<height {
                guard let color = sourceBitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.04 else {
                    output.setColor(.clear, atX: x, y: y)
                    continue
                }

                if removeMask[offset(x, y)] {
                    output.setColor(.clear, atX: x, y: y)
                    removedPixels += 1
                } else {
                    output.setColor(color, atX: x, y: y)
                    keptPixels += 1
                }
            }
        }

        guard keptPixels > max(16, width * height / 10),
              removedPixels > width * height / 20,
              removedPixels < width * height * 9 / 10 else {
            return nil
        }

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(output)
        return image
    }
}

private extension NSColor {
    var normalizedCardAccent: NSColor {
        guard let color = usingColorSpace(.sRGB) else { return self }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return NSColor(
            calibratedHue: hue,
            saturation: min(max(saturation, 0.72), 0.96),
            brightness: min(max(brightness, 0.74), 0.98),
            alpha: 1
        )
    }

    var isInformativeBackground: Bool {
        guard let color = usingColorSpace(.sRGB) else { return false }
        let brightness = max(color.redComponent, color.greenComponent, color.blueComponent)
        return brightness > 0.12 && brightness <= 1
    }

    func perceptualDistance(to other: NSColor) -> CGFloat {
        guard let lhs = usingColorSpace(.sRGB),
              let rhs = other.usingColorSpace(.sRGB) else {
            return 1
        }
        let red = lhs.redComponent - rhs.redComponent
        let green = lhs.greenComponent - rhs.greenComponent
        let blue = lhs.blueComponent - rhs.blueComponent
        return sqrt(red * red * 0.7 + green * green + blue * blue * 0.7)
    }
}

private extension Array where Element == NSColor {
    var averageColor: NSColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0

        for color in self {
            guard let color = color.usingColorSpace(.sRGB) else { continue }
            red += color.redComponent
            green += color.greenComponent
            blue += color.blueComponent
        }

        let count = Swift.max(CGFloat(self.count), 1)
        return NSColor(
            calibratedRed: red / count,
            green: green / count,
            blue: blue / count,
            alpha: 1
        )
    }
}
