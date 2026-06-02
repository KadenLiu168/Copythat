import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardCardView: View {
    private let cardShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
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
            topSection
                .frame(height: 76)

            bottomSection
        }
        .frame(width: 280, height: 270)
        .background {
            cardShape
                .fill(.regularMaterial)
        }
        .clipShape(cardShape)
        .overlay {
            cardShape
                .stroke(isSelected ? sourceAccent : sourceAccent.opacity(0.32), lineWidth: isSelected ? 2.5 : 1)
        }
        .shadow(color: isSelected ? sourceAccent.opacity(0.34) : .clear, radius: isSelected ? 8 : 0, y: 1)
        .contentShape(cardShape)
        .animation(.snappy(duration: 0.16), value: isSelected)
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

    private var topSection: some View {
        ZStack(alignment: .topTrailing) {
            sourceAccent

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(item.kind.label)
                        .font(CopythatFont.font(size: 22, weight: .semibold))
                        .foregroundStyle(headerForeground)
                        .lineLimit(1)

                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(CopythatFont.font(size: 12, weight: .semibold))
                            .foregroundStyle(headerForeground)
                    }
                }

                Text(RelativeTime.string(from: item.createdAt))
                    .font(CopythatFont.font(size: 14, weight: .medium))
                    .foregroundStyle(headerForeground.opacity(0.76))
                    .lineLimit(1)

                if let pinboardName = item.pinboardName {
                    Text(pinboardName)
                        .font(CopythatFont.font(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(headerForeground.opacity(0.18), in: Capsule())
                        .foregroundStyle(headerForeground)
                }
            }
            .padding(.leading, 14)
            .padding(.top, 10)
            .padding(.trailing, 80)
            .frame(maxWidth: .infinity, alignment: .leading)

            sourceLogo
                .frame(width: 66, height: 66)
                .padding(.trailing, 8)
                .offset(y: -4)
        }
    }

    private var bottomSection: some View {
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

    @ViewBuilder
    private var sourceLogo: some View {
        if let icon = sourceLogoIcon ?? item.sourceAppIcon {
            Image(nsImage: icon.foregroundLogoCutout)
                .resizable()
                .scaledToFit()
                .saturation(1.18)
                .contrast(1.08)
                .drawingGroup()
                .shadow(color: headerForeground.opacity(0.38), radius: 3, y: 0)
                .shadow(color: .black.opacity(0.16), radius: 8, y: 2)
        } else {
            Image(systemName: item.sourceApp == "System" ? "camera.viewfinder" : item.kind.symbolName)
                .font(CopythatFont.font(size: 46, weight: .semibold))
                .foregroundStyle(headerForeground)
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
                .overlay(alignment: .bottomTrailing) {
                    Text(item.preview)
                        .font(CopythatFont.font(size: 12, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.36), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(10)
                }
        } else {
            fallbackPreview
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var linkPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image = item.linkImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 104)
                    .frame(maxWidth: .infinity)
                    .clipped()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(linkDisplayTitle)
                    .font(CopythatFont.font(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(item.linkImage == nil ? 3 : 2)

                Text(linkDisplayURL)
                    .font(CopythatFont.font(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 14)
            .padding(.top, item.linkImage == nil ? 18 : 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var filePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "doc.fill")
                    .font(CopythatFont.font(size: 30))
                    .foregroundStyle(sourceAccent)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(CopythatFont.font(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(fileDetail)
                        .font(CopythatFont.font(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var textPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.preview)
                .font(CopythatFont.font(size: 16))
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: false)

            Spacer(minLength: 0)

            Text("\(characterCount) characters")
                .font(CopythatFont.font(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var fallbackPreview: some View {
        Label(item.preview, systemImage: item.kind.symbolName)
            .font(CopythatFont.font(size: 13))
            .foregroundStyle(.secondary)
    }

    private var linkDisplayTitle: String {
        (item.linkTitle ?? item.title).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var linkDisplayURL: String {
        let raw = (item.textValue ?? item.preview).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw) else { return raw }
        let host = url.host(percentEncoded: false) ?? raw
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

    private var sourceAccent: Color {
        Color(nsColor: sourceAccentNSColor)
    }

    private var sourceAccentNSColor: NSColor {
        if let color = (sourceLogoIcon ?? item.sourceAppIcon)?.warmThemeColor {
            return color
        }
        return item.kind.fallbackAccentColor
    }

    private var headerForeground: Color {
        Color(nsColor: sourceAccentNSColor.prefersDarkForeground ? NSColor(white: 0.08, alpha: 1) : .white)
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
            return NSColor(calibratedRed: 0.02, green: 0.48, blue: 1.0, alpha: 1)
        case .url:
            return NSColor(calibratedRed: 0.12, green: 0.80, blue: 0.34, alpha: 1)
        case .image:
            return NSColor(calibratedRed: 1.0, green: 0.18, blue: 0.25, alpha: 1)
        case .file:
            return NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.0, alpha: 1)
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
