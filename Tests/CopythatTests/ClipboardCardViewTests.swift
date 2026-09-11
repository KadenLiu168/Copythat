@testable import Copythat
import AppKit
import SwiftUI
import Testing

struct ClipboardCardViewTests {
    @Test func textCardsUseTheirOwnCapturedSourceIcons() throws {
        let redCard = card(text: "First text", icon: solidIcon(red: 0.92, green: 0.16, blue: 0.12))
        let blueCard = card(text: "Second text", icon: solidIcon(red: 0.10, green: 0.42, blue: 0.92))

        let redColor = try #require(redCard.sourceIconForDisplay.flatMap(centerColor))
        let blueColor = try #require(blueCard.sourceIconForDisplay.flatMap(centerColor))

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
            hidesPreview: false,
            onSelect: {},
            onPaste: {},
            onTogglePin: {},
            onMoveToPinboard: { _ in },
            onDelete: {}
        )
    }

    @Test func previewPrivacyStateControlsCardPreviewVisibility() {
        let visibleCard = card(text: "Private launch token", hidesPreview: false)
        let hiddenCard = card(text: "Private launch token", hidesPreview: true)

        #expect(!visibleCard.previewContentIsHidden)
        #expect(hiddenCard.previewContentIsHidden)
        #expect(hiddenCard.concealedPreviewTitle == "Preview Hidden")
        #expect(visibleCard != hiddenCard)
    }

    @Test func highResolutionSourceIconStaysWithinHeaderSlot() throws {
        // Regression: NSImageView sizes itself to the image's intrinsic point
        // size unless the representable implements sizeThatFits, so a 160px
        // icon previously rendered far beyond the 52pt header slot.
        let iconData = try #require(highResIcon().pngData(maxPixel: 160))
        let card = ClipboardCardView(
            item: item(text: "High-res icon", iconData: iconData),
            pinboards: [],
            isSelected: false,
            hidesPreview: false,
            onSelect: {},
            onPaste: {},
            onTogglePin: {},
            onMoveToPinboard: { _ in },
            onDelete: {}
        )

        let hosting = NSHostingView(rootView: card)
        hosting.frame = NSRect(x: 0, y: 0, width: 236, height: 236)
        hosting.layoutSubtreeIfNeeded()

        let iconView = try #require(
            allSubviews(of: hosting).compactMap { $0 as? NSImageView }.first
        )
        #expect(iconView.frame.width <= 52.5)
        #expect(iconView.frame.height <= 52.5)
    }

    private func highResIcon() -> NSImage {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 160,
            pixelsHigh: 160,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!

        let color = NSColor(calibratedRed: 0.10, green: 0.42, blue: 0.92, alpha: 1)
        for x in 0..<160 {
            for y in 0..<160 {
                bitmap.setColor(color, atX: x, y: y)
            }
        }

        let image = NSImage(size: NSSize(width: 160, height: 160))
        image.addRepresentation(bitmap)
        return image
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + allSubviews(of: $0) }
    }

    private func card(text: String, hidesPreview: Bool) -> ClipboardCardView {
        ClipboardCardView(
            item: item(text: text, iconData: nil),
            pinboards: [],
            isSelected: false,
            hidesPreview: hidesPreview,
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

/// Samples the center pixel of a solid-color icon. The card tests only need to
/// prove that each card surfaces its own captured source icon, so a single
/// pixel is enough and keeps this assertion independent of production helpers.
private func centerColor(of image: NSImage) -> NSColor? {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData) else {
        return nil
    }

    let x = bitmap.pixelsWide / 2
    let y = bitmap.pixelsHigh / 2
    return bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
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
