import AppKit
import Testing
@testable import Copythat

struct SourceThemeColorTests {
    @Test func redLogoUsesRedSourceAccent() {
        let color = SourceThemeColor.accent(icon: solidIcon(red: 0.92, green: 0.16, blue: 0.12))

        #expect(color.isRedDominant)
        #expect(color.isClose(red: 0.92, green: 0.16, blue: 0.12))
    }

    @Test func blueLogoUsesBlueSourceAccent() {
        let color = SourceThemeColor.accent(icon: solidIcon(red: 0.10, green: 0.42, blue: 0.92))

        #expect(color.isBlueDominant)
        #expect(color.isClose(red: 0.10, green: 0.42, blue: 0.92))
    }

    @Test func sameLogoProducesSameAccentForDifferentContentKinds() {
        let icon = solidIcon(red: 0.10, green: 0.42, blue: 0.92)

        let textColor = SourceThemeColor.accent(icon: icon)
        let imageColor = SourceThemeColor.accent(icon: icon)

        #expect(textColor.matches(imageColor))
    }

    @Test func multicolorLogoUsesVividAccent() {
        let color = SourceThemeColor.accent(icon: chromeLikeIcon())

        #expect(color.isVivid)
    }

    @Test func missingLogoUsesNeutralAccent() {
        let color = SourceThemeColor.accent(icon: nil)

        #expect(color.matches(SourceThemeColor.neutralAccent))
    }

    @Test func iconDataAccentIsCached() throws {
        let iconData = try #require(solidIcon(red: 0.88, green: 0.10, blue: 0.62).pngData(maxPixel: 32))

        let first = SourceThemeColor.accent(iconData: iconData)
        let second = SourceThemeColor.accent(iconData: iconData)

        #expect(first === second)
        #expect(first.isVivid)
    }
}

private func solidIcon(red: CGFloat, green: CGFloat, blue: CGFloat) -> NSImage {
    bitmapIcon(width: 32, height: 32) { _, _ in
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
    }
}

private func chromeLikeIcon() -> NSImage {
    bitmapIcon(width: 40, height: 40) { x, y in
        if x < 20, y < 20 {
            return NSColor(calibratedRed: 0.92, green: 0.16, blue: 0.12, alpha: 1)
        }
        if x >= 20, y < 20 {
            return NSColor(calibratedRed: 0.96, green: 0.76, blue: 0.10, alpha: 1)
        }
        if x < 20, y >= 20 {
            return NSColor(calibratedRed: 0.16, green: 0.68, blue: 0.26, alpha: 1)
        }
        return NSColor(calibratedRed: 0.10, green: 0.42, blue: 0.92, alpha: 1)
    }
}

private func bitmapIcon(width: Int, height: Int, colorAt: (Int, Int) -> NSColor) -> NSImage {
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

    for x in 0..<width {
        for y in 0..<height {
            bitmap.setColor(colorAt(x, y), atX: x, y: y)
        }
    }

    let image = NSImage(size: NSSize(width: width, height: height))
    image.addRepresentation(bitmap)
    return image
}

private extension NSColor {
    var isRedDominant: Bool {
        let components = rgbaComponents
        return components.red > components.green && components.red > components.blue
    }

    var isBlueDominant: Bool {
        let components = rgbaComponents
        return components.blue > components.red && components.blue > components.green
    }

    var isVivid: Bool {
        let components = rgbaComponents
        let maxComponent = max(components.red, components.green, components.blue)
        let minComponent = min(components.red, components.green, components.blue)
        return maxComponent - minComponent > 0.45 && maxComponent > 0.65
    }

    func matches(_ other: NSColor) -> Bool {
        let components = rgbaComponents
        let otherComponents = other.rgbaComponents

        return abs(components.red - otherComponents.red) < 0.001 &&
            abs(components.green - otherComponents.green) < 0.001 &&
            abs(components.blue - otherComponents.blue) < 0.001
    }

    func matches(red: CGFloat, green: CGFloat, blue: CGFloat) -> Bool {
        let components = rgbaComponents

        return abs(components.red - red) < 0.001 &&
            abs(components.green - green) < 0.001 &&
            abs(components.blue - blue) < 0.001
    }

    func isClose(red: CGFloat, green: CGFloat, blue: CGFloat) -> Bool {
        let components = rgbaComponents

        return abs(components.red - red) < 0.10 &&
            abs(components.green - green) < 0.10 &&
            abs(components.blue - blue) < 0.10
    }

    private var rgbaComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var colorRed: CGFloat = 0
        var colorGreen: CGFloat = 0
        var colorBlue: CGFloat = 0
        var colorAlpha: CGFloat = 0
        getRed(&colorRed, green: &colorGreen, blue: &colorBlue, alpha: &colorAlpha)
        return (colorRed, colorGreen, colorBlue, colorAlpha)
    }
}
