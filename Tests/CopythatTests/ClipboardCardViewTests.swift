@testable import Copythat
import AppKit
import SwiftUI
import Testing

@MainActor
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
            panelVisible: false,
            authorizationGeneration: 0,
            mediaLoader: Self.mediaLoader,
            store: Self.store,
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

        #expect(!visibleCard.hidesPreview)
        #expect(hiddenCard.hidesPreview)
        #expect(visibleCard != hiddenCard)
    }

    // MARK: - Card render identity

    @Test func identicalInputsRenderAsUnchanged() {
        let base = ItemFixture()
        #expect(card(base) == card(base))
        #expect(card(base).renderIdentity == card(base).renderIdentity)
        #expect(card(base).renderIdentity.id == base.id)
        #expect(card(base).renderIdentity.createdAt == base.createdAt)
    }

    @Test func everyProjectedMetadataFieldInvalidatesTheRenderIdentity() {
        // ID and timestamp are fixed in the fixture, so each expectation below
        // can only fail because the one field it changes changed.
        let base = ItemFixture()
        var variant: ItemFixture

        variant = base; variant.id = UUID()
        #expect(card(variant).renderIdentity != card(base).renderIdentity)

        variant = base; variant.kind = .file
        #expect(card(variant).renderIdentity != card(base).renderIdentity)

        variant = base; variant.title = "Other title"
        #expect(card(variant).renderIdentity != card(base).renderIdentity)

        variant = base; variant.preview = "Other preview"
        #expect(card(variant).renderIdentity != card(base).renderIdentity)

        variant = base; variant.sourceApp = "Other Source"
        #expect(card(variant).renderIdentity != card(base).renderIdentity)

        variant = base; variant.createdAt = base.createdAt.addingTimeInterval(60)
        #expect(card(variant).renderIdentity != card(base).renderIdentity)

        variant = base; variant.isPinned = true
        #expect(card(variant).renderIdentity != card(base).renderIdentity)

        variant = base; variant.pinboardName = "Work"
        #expect(card(variant).renderIdentity != card(base).renderIdentity)

        variant = base; variant.textValue = "Other text"
        #expect(card(variant).renderIdentity != card(base).renderIdentity)

        variant = base; variant.fileURLs = [URL(fileURLWithPath: "/tmp/other.txt")]
        #expect(card(variant).renderIdentity != card(base).renderIdentity)

        variant = base; variant.linkTitle = "Other link title"
        #expect(card(variant).renderIdentity != card(base).renderIdentity)
    }

    @Test func everyMediaRoleTracksItsAddressResidencyAndPresence() {
        for role in MediaRole.allCases {
            let withoutPayload = ItemFixture(kind: .url)
            let reference = withoutPayload.with(.reference(payloadA), for: role)
            let sameAddressResident = withoutPayload.with(.resident(payloadA), for: role)
            let otherAddress = withoutPayload.with(.reference(payloadB), for: role)

            // Nothing changed: address and residency are both held constant.
            #expect(card(reference).renderIdentity == card(reference).renderIdentity)
            // A different content address.
            #expect(card(reference).renderIdentity != card(otherAddress).renderIdentity)
            // Both residency directions at one unchanged address.
            #expect(card(reference).renderIdentity != card(sameAddressResident).renderIdentity)
            #expect(card(sameAddressResident).renderIdentity != card(reference).renderIdentity)
            // Payload insertion and removal.
            #expect(card(reference).renderIdentity != card(withoutPayload).renderIdentity)
            #expect(card(withoutPayload).renderIdentity != card(reference).renderIdentity)
        }
    }

    @Test func everyExternalDisplayInputInvalidatesTheCard() {
        let base = ItemFixture()
        #expect(card(base) == card(base))

        #expect(card(base, pinboards: [CustomPinboard(name: "Work", color: .amber)]) != card(base))
        #expect(card(base, isSelected: true) != card(base))
        #expect(card(base, hidesPreview: true) != card(base))
        #expect(card(base, panelVisible: true) != card(base))
        #expect(card(base, authorizationGeneration: 1) != card(base))
        #expect(card(base, canMutateHistory: false) != card(base))

        // These inputs sit outside the item projection, so they change card
        // equality without changing what the item itself renders.
        #expect(card(base, panelVisible: true).renderIdentity == card(base).renderIdentity)
    }

    // MARK: - Media task identity

    @Test func mediaTaskIdentityTracksAddressesResidencyEligibilityAndGeneration() {
        let withoutPayload = ItemFixture(kind: .url)
        for role in MediaRole.displayRequestRoles {
            let reference = withoutPayload.with(.reference(payloadA), for: role)
            let resident = withoutPayload.with(.resident(payloadA), for: role)
            let otherAddress = withoutPayload.with(.reference(payloadB), for: role)

            #expect(card(reference).mediaTaskIdentity == card(reference).mediaTaskIdentity)
            #expect(card(reference).mediaTaskIdentity != card(otherAddress).mediaTaskIdentity)
            #expect(card(reference).mediaTaskIdentity != card(resident).mediaTaskIdentity)
            #expect(card(resident).mediaTaskIdentity != card(reference).mediaTaskIdentity)
            #expect(card(reference).mediaTaskIdentity != card(withoutPayload).mediaTaskIdentity)
            #expect(card(withoutPayload).mediaTaskIdentity != card(reference).mediaTaskIdentity)
        }

        let image = withoutPayload.with(.reference(payloadA), for: .image)
        #expect(card(image, panelVisible: true).mediaTaskIdentity != card(image, panelVisible: false).mediaTaskIdentity)
        #expect(card(image, hidesPreview: true, panelVisible: true).mediaTaskIdentity != card(image, panelVisible: true).mediaTaskIdentity)
        #expect(card(image, authorizationGeneration: 1).mediaTaskIdentity != card(image).mediaTaskIdentity)

        var otherItem = image
        otherItem.id = UUID()
        #expect(card(otherItem).mediaTaskIdentity != card(image).mediaTaskIdentity)
    }

    @Test func mediaTaskIdentityCarriesOnlyAddressesAndResidency() {
        let resident = ItemFixture(kind: .image).with(.resident(payloadA), for: .image)
        let identity = card(resident).mediaTaskIdentity

        #expect(identity.itemID == resident.id)
        #expect(
            identity.image == ClipboardCardView.MediaPayloadIdentity(
                blobID: ClipboardHistoryBlobStore.sha256Hex(payloadA),
                isResident: true
            )
        )
        #expect(identity.linkImage == ClipboardCardView.MediaPayloadIdentity(blobID: nil, isResident: false))
        #expect(card(resident, panelVisible: true).mediaTaskIdentity.eligible)
    }

    // MARK: - Captured source icon identity

    @Test func capturedSourceIconIdentitiesFollowTheirContentAddress() throws {
        let iconData = try #require(solidIcon(red: 0.92, green: 0.16, blue: 0.12).pngData(maxPixel: 32))
        let otherIconData = try #require(solidIcon(red: 0.10, green: 0.42, blue: 0.92).pngData(maxPixel: 32))
        let resident = ItemFixture(kind: .url).with(.resident(iconData), for: .sourceIcon)
        let sameAddressWithoutBytes = resident.with(.reference(iconData), for: .sourceIcon)
        let otherIcon = ItemFixture(kind: .url).with(.resident(otherIconData), for: .sourceIcon)
        let noIcon = ItemFixture()

        #expect(card(resident).sourceIconIdentity == ClipboardHistoryBlobStore.sha256Hex(iconData))
        #expect(card(resident).sourceIconIdentity == card(sameAddressWithoutBytes).sourceIconIdentity)
        #expect(card(resident).sourceIconIdentity != card(otherIcon).sourceIconIdentity)
        #expect(card(noIcon).sourceIconIdentity == nil)

        // One address, bytes gained and lost: the card must move between the
        // captured icon and its fallback appearance.
        #expect(card(resident).renderIdentity != card(sameAddressWithoutBytes).renderIdentity)
        #expect(card(sameAddressWithoutBytes).renderIdentity != card(resident).renderIdentity)

        // The icon view stays scoped to its card even at an equal address.
        var otherCard = resident
        otherCard.id = UUID()
        #expect(card(resident).sourceLogoIdentity != card(otherCard).sourceLogoIdentity)
        #expect(card(resident).sourceLogoIdentity == card(sameAddressWithoutBytes).sourceLogoIdentity)
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
            panelVisible: false,
            authorizationGeneration: 0,
            mediaLoader: Self.mediaLoader,
            store: Self.store,
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
        for column in 0..<160 {
            for row in 0..<160 {
                bitmap.setColor(color, atX: column, y: row)
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
            panelVisible: false,
            authorizationGeneration: 0,
            mediaLoader: Self.mediaLoader,
            store: Self.store,
            onSelect: {},
            onPaste: {},
            onTogglePin: {},
            onMoveToPinboard: { _ in },
            onDelete: {}
        )
    }

    /// One card per combination of projection and external inputs. The media
    /// state is never injected here: these tests compare identity, not display.
    private func card(
        _ fixture: ItemFixture,
        pinboards: [CustomPinboard] = [],
        isSelected: Bool = false,
        hidesPreview: Bool = false,
        panelVisible: Bool = false,
        authorizationGeneration: Int = 0,
        canMutateHistory: Bool = true
    ) -> ClipboardCardView {
        ClipboardCardView(
            item: fixture.item,
            pinboards: pinboards,
            isSelected: isSelected,
            hidesPreview: hidesPreview,
            panelVisible: panelVisible,
            authorizationGeneration: authorizationGeneration,
            canMutateHistory: canMutateHistory,
            mediaLoader: Self.mediaLoader,
            store: Self.store,
            onSelect: {},
            onPaste: {},
            onTogglePin: {},
            onMoveToPinboard: { _ in },
            onDelete: {}
        )
    }

    /// Isolated store and loader shared by the card fixtures; these tests never
    /// touch persisted history.
    private static let store: ClipboardStore = {
        let suiteName = "ClipboardCardViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [],
            pasteboard: NSPasteboard.withUniqueName(),
            mediaLoader: mediaLoader,
            persistItems: { _ in }
        )
    }()

    private static let mediaLoader = ClipboardHistoryMediaLoader(
        blobStore: ClipboardHistoryBlobStore(
            directoryURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("ClipboardCardViewTests-\(UUID().uuidString)/history-media", isDirectory: true),
            readData: { try Data(contentsOf: $0) }
        )
    )

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

    private func solidIcon(red: CGFloat, green: CGFloat, blue: CGFloat) -> NSImage {        let bitmap = NSBitmapImageRep(
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
        for column in 0..<32 {
            for row in 0..<32 {
                bitmap.setColor(color, atX: column, y: row)
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

    let middleColumn = bitmap.pixelsWide / 2
    let middleRow = bitmap.pixelsHigh / 2
    return bitmap.colorAt(x: middleColumn, y: middleRow)?.usingColorSpace(.sRGB)
}

/// Distinct media contents, so two fixtures differ by address when they must and
/// by residency alone when only the bytes' location changed.
private let payloadA = Data([0x8F, 0x1C, 0xA2])
private let payloadB = Data([0x11, 0x7E, 0x5B])

/// The three media roles a card reconciles. Each is exercised on its own, so a
/// role that still compares bytes cannot hide behind another that does not.
private enum MediaRole: CaseIterable {
    case image, linkImage, sourceIcon

    /// Roles that drive an on-demand display request. The captured source icon
    /// is drawn from the item itself and never loaded, so it takes part in render
    /// identity only.
    static let displayRequestRoles: [MediaRole] = [.image, .linkImage]
}

/// One role's payload. Every address is derived from the content it describes,
/// so a reference and a resident payload of the same content differ only in
/// residency and no fixture invents an address its bytes do not have.
private enum Payload {
    case none
    case reference(Data)
    case resident(Data)

    /// The bytes the item currently carries.
    var bytes: Data? {
        if case .resident(let data) = self { return data }
        return nil
    }

    /// The content address, which outlives a release: both cases describe the
    /// same content, so both carry its address.
    var blobID: String? {
        switch self {
        case .none:
            nil
        case .reference(let data), .resident(let data):
            ClipboardHistoryBlobStore.sha256Hex(data)
        }
    }
}

/// Every field the card projects, with a fixed ID and timestamp. A comparison
/// between two fixtures therefore differs only because a test changed a field.
private struct ItemFixture {
    var id = UUID(uuidString: "2C0E1B9A-0000-4000-8000-00000000CA4D")!
    var kind: ClipboardKind = .text
    var title = "Title"
    var preview = "Preview"
    var sourceApp = "Source"
    var sourceAppIconData: Data?
    var sourceAppIconBlobID: String?
    var createdAt = Date(timeIntervalSince1970: 1_700_000_000)
    var isPinned = false
    var pinboardName: String?
    var textValue: String?
    var fileURLs: [URL] = []
    var imageData: Data?
    var imageBlobID: String?
    var linkTitle: String?
    var linkImageData: Data?
    var linkImageBlobID: String?

    var item: ClipboardItem {
        ClipboardItem(
            id: id,
            kind: kind,
            title: title,
            preview: preview,
            sourceApp: sourceApp,
            sourceAppIconData: sourceAppIconData,
            sourceAppIconBlobID: sourceAppIconBlobID,
            createdAt: createdAt,
            isPinned: isPinned,
            pinboardName: pinboardName,
            textValue: textValue,
            fileURLs: fileURLs,
            imageData: imageData,
            imageBlobID: imageBlobID,
            linkTitle: linkTitle,
            linkImageData: linkImageData,
            linkImageBlobID: linkImageBlobID
        )
    }

    func with(_ payload: Payload, for role: MediaRole) -> ItemFixture {
        var copy = self
        switch role {
        case .image:
            copy.imageData = payload.bytes
            copy.imageBlobID = payload.blobID
        case .linkImage:
            copy.linkImageData = payload.bytes
            copy.linkImageBlobID = payload.blobID
        case .sourceIcon:
            copy.sourceAppIconData = payload.bytes
            copy.sourceAppIconBlobID = payload.blobID
        }
        return copy
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
