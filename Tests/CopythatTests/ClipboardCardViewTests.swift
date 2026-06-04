@testable import Copythat
import AppKit
import Testing

struct ClipboardCardViewTests {
    @Test func textCardsUseTheirOwnCapturedSourceIcons() throws {
        let redCard = card(text: "First text", icon: solidIcon(red: 0.92, green: 0.16, blue: 0.12))
        let blueCard = card(text: "Second text", icon: solidIcon(red: 0.10, green: 0.42, blue: 0.92))

        let redColor = try #require(redCard.sourceIconForDisplay?.representativeColor)
        let blueColor = try #require(blueCard.sourceIconForDisplay?.representativeColor)

        #expect(redColor.isRedDominant)
        #expect(blueColor.isBlueDominant)
        #expect(redCard.sourceIconIdentity != blueCard.sourceIconIdentity)
        #expect(redCard.sourceLogoIdentity != blueCard.sourceLogoIdentity)
    }

    private func card(text: String, icon: NSImage) -> ClipboardCardView {
        ClipboardCardView(
            item: item(text: text, iconData: icon.pngData(maxPixel: 32)),
            pinboards: [],
            isSelected: false,
            onSelect: {},
            onPaste: {},
            onTogglePin: {},
            onMoveToPinboard: { _ in },
            onDelete: {}
        )
    }

    private func item(text: String, iconData: Data?) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .text,
            title: text,
            preview: text,
            sourceApp: "Same Source Name",
            sourceAppIconData: iconData,
            createdAt: Date(),
            isPinned: false,
            pinboardName: nil,
            textValue: text,
            fileURLs: [],
            imageData: nil
        )
    }

    private func solidIcon(red: CGFloat, green: CGFloat, blue: CGFloat) -> NSImage {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 32,
            pixelsHigh: 32,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!

        let color = NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
        for x in 0..<32 {
            for y in 0..<32 {
                bitmap.setColor(color, atX: x, y: y)
            }
        }

        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.addRepresentation(bitmap)
        return image
    }
}

private extension NSColor {
    var isRedDominant: Bool {
        guard let color = usingColorSpace(.sRGB) else { return false }
        return color.redComponent > color.greenComponent && color.redComponent > color.blueComponent
    }

    var isBlueDominant: Bool {
        guard let color = usingColorSpace(.sRGB) else { return false }
        return color.blueComponent > color.redComponent && color.blueComponent > color.greenComponent
    }
}
