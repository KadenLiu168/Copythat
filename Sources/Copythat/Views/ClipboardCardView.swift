import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardCardView: View {
    private let cardSize = CGSize(width: 236, height: 236)
    private let headerHeight: CGFloat = 58
    private let cardCornerRadius: CGFloat = 23
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
    }
    let item: ClipboardItem
    let pinboards: [String]
    let isSelected: Bool
    let sourceLogoIcon: NSImage?
    let onSelect: () -> Void
    let onPaste: () -> Void
    let onTogglePin: () -> Void
    let onMoveToPinboard: (String?) -> Void
    let onDelete: () -> Void

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
                .stroke(isSelected ? selectedStroke : Color.black.opacity(0.06), lineWidth: isSelected ? 4 : 1)
        }
        .shadow(color: isSelected ? selectedStroke.opacity(0.30) : .black.opacity(0.08), radius: isSelected ? 18 : 8, y: isSelected ? 8 : 4)
        .scaleEffect(isSelected ? 1.025 : 1)
        .offset(y: isSelected ? -5 : 0)
        .zIndex(isSelected ? 1 : 0)
        .contentShape(cardShape)
        .animation(.snappy(duration: 0.18), value: isSelected)
        .onTapGesture {
            onSelect()
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
        .onTapGesture(count: 2, perform: onPaste)
        .contextMenu {
            Button(item.isPinned ? "Unpin" : "Pin", action: onTogglePin)
            if !pinboards.isEmpty {
                Menu("Pinboard") {
                    ForEach(pinboards, id: \.self) { name in
                        Button(name) { onMoveToPinboard(name) }
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
                HStack(spacing: 7) {
                    Text(item.kind.label)
                        .font(CopythatFont.font(size: 19, weight: .semibold))
                        .foregroundStyle(headerForeground)
                        .lineLimit(1)

                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(CopythatFont.font(size: 10, weight: .semibold))
                            .foregroundStyle(headerForeground)
                    }
                }

                Text(RelativeTime.string(from: item.createdAt))
                    .font(CopythatFont.font(size: 13, weight: .medium))
                    .foregroundStyle(headerForeground.opacity(0.76))
                    .lineLimit(1)

                if let pinboardName = item.pinboardName {
                    Text(pinboardName)
                        .font(CopythatFont.font(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(headerForeground.opacity(0.18), in: Capsule())
                        .foregroundStyle(headerForeground)
                }
            }
            .padding(.leading, 15)
            .padding(.top, 9)
            .padding(.trailing, 76)
            .frame(maxWidth: .infinity, alignment: .leading)

            iconCarrier
                .padding(.trailing, -2)
                .offset(y: -5)
        }
    }

    private var contentSection: some View {
        ZStack {
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

    private var iconCarrier: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.86))
                .shadow(color: .black.opacity(0.10), radius: 7, y: 2)

            sourceLogo
                .frame(width: 52, height: 52)
                .padding(6)
        }
        .frame(width: 68, height: 62)
    }

    @ViewBuilder
    private var sourceLogo: some View {
        if let icon = sourceLogoIcon ?? item.sourceAppIcon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .saturation(1.18)
                .contrast(1.08)
                .drawingGroup()
                .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
        } else {
            Image(systemName: item.sourceApp == "System" ? "camera.viewfinder" : item.kind.symbolName)
                .font(CopythatFont.font(size: 38, weight: .semibold))
                .foregroundStyle(sourceAccent)
                .opacity(0.9)
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let image = item.image {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
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
        VStack(alignment: .leading, spacing: 8) {
            Text(item.preview)
                .font(CopythatFont.font(size: 18, weight: .medium))
                .foregroundStyle(primaryText)
                .lineSpacing(5)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: false)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.70),
                            .init(color: .black.opacity(0.12), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Spacer(minLength: 0)

            Text("\(characterCount) characters")
                .font(CopythatFont.font(size: 12, weight: .medium))
                .foregroundStyle(secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var fallbackPreview: some View {
        Label(item.preview, systemImage: item.kind.symbolName)
            .font(CopythatFont.font(size: 13, weight: .medium))
            .foregroundStyle(secondaryText)
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
        return item.kind.fallbackAccentColor
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

    private var selectedStroke: Color {
        Color(red: 0.00, green: 0.53, blue: 0.98)
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
}

private extension ClipboardKind {
    var fallbackAccentColor: NSColor {
        switch self {
        case .text:
            return NSColor(calibratedRed: 0.95, green: 0.70, blue: 0.00, alpha: 1)
        case .url:
            return NSColor(calibratedRed: 0.02, green: 0.52, blue: 0.95, alpha: 1)
        case .image:
            return NSColor(calibratedRed: 1.0, green: 0.20, blue: 0.24, alpha: 1)
        case .file:
            return NSColor(calibratedRed: 0.95, green: 0.62, blue: 0.04, alpha: 1)
        }
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
