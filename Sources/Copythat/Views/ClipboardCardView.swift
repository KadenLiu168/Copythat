import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardCardView: View, Equatable {
    private let cardSize = CGSize(width: 236, height: 236)
    private let headerHeight: CGFloat = 52
    private let headerIconSize: CGFloat = 52
    private let cardCornerRadius: CGFloat = 23
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
    }
    let item: ClipboardItem
    let pinboards: [CustomPinboard]
    let isSelected: Bool
    let hidesPreview: Bool
    let onSelect: () -> Void
    let onPaste: () -> Void
    let onTogglePin: () -> Void
    let onMoveToPinboard: (String?) -> Void
    let onDelete: () -> Void

    static func == (lhs: ClipboardCardView, rhs: ClipboardCardView) -> Bool {
        lhs.item == rhs.item &&
            lhs.pinboards == rhs.pinboards &&
            lhs.isSelected == rhs.isSelected &&
            lhs.hidesPreview == rhs.hidesPreview
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .frame(height: headerHeight)
            contentSection
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .background {
            cardShape
                .fill(contentBackground)
        }
        .clipShape(cardShape)
        .overlay {
            cardShape
                .stroke(isSelected ? sourceAccent : Color.black.opacity(0.06), lineWidth: isSelected ? 4 : 1)
        }
        .shadow(color: isSelected ? sourceAccent.opacity(0.30) : .black.opacity(0.08), radius: isSelected ? 18 : 8, y: isSelected ? 8 : 4)
        .scaleEffect(isSelected ? 1.025 : 1)
        .offset(y: isSelected ? -5 : 0)
        .zIndex(isSelected ? 1 : 0)
        .contentShape(cardShape)
        .animation(.snappy(duration: 0.10), value: isSelected)
        .onTapGesture(perform: selectForClick)
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    selectForClick()
                    onPaste()
                }
        )
        .contextMenu {
            Button(item.isPinned ? "Unpin" : "Pin", action: onTogglePin)
            if !pinboards.isEmpty {
                Menu("Pinboard") {
                    ForEach(pinboards) { pinboard in
                        Button(pinboard.name) { onMoveToPinboard(pinboard.name) }
                    }
                    if item.pinboardName != nil {
                        Divider()
                        Button("Remove from Pinboard") { onMoveToPinboard(nil) }
                    }
                }
            }
            Button("Paste", action: onPaste)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
        .onDrag { dragProvider(for: item) }
    }

    private var headerSection: some View {
        ZStack(alignment: .topTrailing) {
            sourceAccent

            VStack(alignment: .leading, spacing: 1) {
                Text(item.kind.label)
                    .font(CopythatFont.font(size: 16.5, weight: .semibold))
                    .foregroundStyle(headerForeground)
                    .lineLimit(1)

                Text(RelativeTime.string(from: item.createdAt))
                    .font(CopythatFont.font(size: 12, weight: .medium))
                    .foregroundStyle(headerForeground.opacity(0.76))
                    .lineLimit(1)
            }
            .padding(.leading, 17)
            .padding(.trailing, headerIconSize + 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            iconCarrier
                .id(sourceLogoIdentity)
        }
    }

    private var contentSection: some View {
        ZStack {
            if hidesPreview {
                concealedPreview
            } else {
                switch item.kind {
                case .image:
                    imagePreview
                case .url:
                    linkPreview
                case .file:
                    filePreview
                case .text:
                    textPreview
                }
            }
        }
        .frame(width: cardSize.width, height: cardSize.height - headerHeight)
        .clipped()
    }

    @ViewBuilder
    private var iconCarrier: some View {
        if let icon = sourceIconForDisplay {
            SourceLogoImageView(image: icon, identity: sourceIconIdentity)
                .id(sourceIconIdentity)
                .frame(width: headerIconSize, height: headerIconSize)
                .saturation(1.18)
                .contrast(1.08)
        } else {
            fallbackSourceLogo
                .frame(width: headerHeight, height: headerHeight)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.20))
                        .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
                }
        }
    }

    private var fallbackSourceLogo: some View {
        Image(systemName: item.sourceApp == "System" ? "camera.viewfinder" : item.kind.symbolName)
            .font(CopythatFont.font(size: 38, weight: .semibold))
            .foregroundStyle(sourceAccent)
            .opacity(0.9)
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let image = item.image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(alignment: .bottom) {
                    Text(imageDetail)
                        .font(CopythatFont.font(size: 13, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.38), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(.bottom, 10)
                }
        } else {
            fallbackPreview
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var linkPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image = item.linkImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 105)
                    .frame(maxWidth: .infinity)
                    .clipped()
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(linkDisplayTitle)
                    .font(CopythatFont.font(size: item.linkImage == nil ? 19 : 16, weight: .semibold))
                    .foregroundStyle(primaryText)
                    .lineLimit(item.linkImage == nil ? 3 : 2)
                    .lineSpacing(1)

                Text(linkDisplayURL)
                    .font(CopythatFont.font(size: 13, weight: .medium))
                    .foregroundStyle(secondaryText)
                    .lineLimit(2)
            }
            .padding(.horizontal, 15)
            .padding(.top, item.linkImage == nil ? 22 : 10)
            .padding(.bottom, 13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var filePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "doc.fill")
                    .font(CopythatFont.font(size: 32, weight: .semibold))
                    .foregroundStyle(sourceAccent)

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(CopythatFont.font(size: 16, weight: .semibold))
                        .foregroundStyle(primaryText)
                        .lineLimit(2)
                    Text(fileDetail)
                        .font(CopythatFont.font(size: 12, weight: .medium))
                        .foregroundStyle(secondaryText)
                        .lineLimit(4)
                }
            }

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var textPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.preview)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(primaryText)
                .lineSpacing(1)
                .lineLimit(10)
                .fixedSize(horizontal: false, vertical: false)

            Spacer(minLength: 0)

            Text("\(characterCount) characters")
                .font(CopythatFont.font(size: 12, weight: .medium))
                .foregroundStyle(secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var fallbackPreview: some View {
        Label(item.preview, systemImage: item.kind.symbolName)
            .font(CopythatFont.font(size: 13, weight: .medium))
            .foregroundStyle(secondaryText)
    }

    private var concealedPreview: some View {
        VStack(spacing: 9) {
            Image(systemName: "eye.slash")
                .font(CopythatFont.font(size: 24, weight: .semibold))
                .foregroundStyle(sourceAccent.opacity(0.82))
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(sourceAccent.opacity(0.12))
                )

            Text("Preview Hidden")
                .font(CopythatFont.font(size: 13, weight: .semibold))
                .foregroundStyle(primaryText.opacity(0.82))
                .lineLimit(1)

            Text("Use the eye control to show previews")
                .font(CopythatFont.font(size: 11, weight: .medium))
                .foregroundStyle(secondaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var linkDisplayTitle: String {
        (item.linkTitle ?? item.title).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var linkDisplayURL: String {
        let raw = (item.textValue ?? item.preview).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw) else { return raw }
        guard let host = url.host(percentEncoded: false) else { return raw }
        let path = url.path.isEmpty ? "" : url.path
        return "\(host)\(path)"
    }

    private var fileDetail: String {
        if item.fileURLs.count > 1 {
            return "\(item.fileURLs.count) files"
        }
        return item.fileURLs.first?.path ?? item.preview
    }

    private var characterCount: Int {
        (item.textValue ?? item.preview).count
    }

    private var imageDetail: String {
        guard let image = item.image else { return item.preview }
        let width = Int(image.size.width.rounded())
        let height = Int(image.size.height.rounded())
        guard width > 0, height > 0 else { return item.preview }
        return "\(width) x \(height)"
    }

    private var sourceAccent: Color {
        Color(nsColor: sourceAccentNSColor)
    }

    private var sourceAccentNSColor: NSColor {
        SourceThemeColor.accent(iconData: item.sourceAppIconData)
    }

    private var headerForeground: Color {
        Color(nsColor: sourceAccentNSColor.prefersDarkForeground ? NSColor(white: 0.08, alpha: 1) : .white)
    }

    private var contentBackground: Color {
        Color(red: 0.985, green: 0.982, blue: 0.970)
    }

    private var primaryText: Color {
        Color(red: 0.18, green: 0.17, blue: 0.16)
    }

    private var secondaryText: Color {
        Color(red: 0.49, green: 0.47, blue: 0.44)
    }

    private func dragProvider(for item: ClipboardItem) -> NSItemProvider {
        if let url = item.fileURLs.first {
            return NSItemProvider(object: url as NSURL)
        }
        if let image = item.image {
            return NSItemProvider(object: image)
        }
        return NSItemProvider(object: (item.textValue ?? item.preview) as NSString)
    }

    private func selectForClick() {
        onSelect()
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    var sourceIconForDisplay: NSImage? {
        item.sourceAppIcon
    }

    var sourceIconIdentity: Int {
        item.sourceAppIconData?.hashValue ?? 0
    }

    var sourceLogoIdentity: String {
        "\(item.id.uuidString):\(sourceIconIdentity)"
    }
}

private struct SourceLogoImageView: NSViewRepresentable {
    let image: NSImage
    let identity: Int

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.image = image.copy() as? NSImage ?? image
        context.coordinator.identity = identity
        return imageView
    }

    func updateNSView(_ imageView: NSImageView, context: Context) {
        guard context.coordinator.identity != identity || imageView.image == nil else { return }
        imageView.image = image.copy() as? NSImage ?? image
        context.coordinator.identity = identity
    }

    // Without this, SwiftUI sizes the NSImageView by its intrinsicContentSize
    // (= the image's point size) whenever that exceeds the proposed frame, so
    // high-resolution icons render beyond the 52pt header slot.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite, width > 0, height > 0 else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var identity: Int?
    }
}

private extension NSColor {
    var prefersDarkForeground: Bool {
        guard let color = usingColorSpace(.sRGB) else { return false }

        func linearized(_ component: CGFloat) -> CGFloat {
            if component <= 0.03928 {
                return component / 12.92
            }
            return pow((component + 0.055) / 1.055, 2.4)
        }

        let luminance = 0.2126 * linearized(color.redComponent) +
            0.7152 * linearized(color.greenComponent) +
            0.0722 * linearized(color.blueComponent)

        return luminance > 0.52
    }
}
