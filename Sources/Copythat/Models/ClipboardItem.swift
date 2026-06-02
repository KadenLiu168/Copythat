import AppKit
import CryptoKit
import Foundation

enum ClipboardKind: String, Codable, CaseIterable {
    case text
    case url
    case image
    case file

    var label: String {
        switch self {
        case .text: "Text"
        case .url: "Link"
        case .image: "Image"
        case .file: "File"
        }
    }

    var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .url: "link"
        case .image: "photo"
        case .file: "doc"
        }
    }
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: ClipboardKind
    let title: String
    let preview: String
    let sourceApp: String
    let sourceAppIconData: Data?
    let createdAt: Date
    var isPinned: Bool
    var pinboardName: String?
    let textValue: String?
    let fileURLs: [URL]
    let imageData: Data?
    let linkTitle: String?
    let linkImageData: Data?

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case preview
        case sourceApp
        case sourceAppIconData
        case createdAt
        case isPinned
        case pinboardName
        case textValue
        case fileURLs
        case imageData
        case linkTitle
        case linkImageData
    }

    init(
        id: UUID,
        kind: ClipboardKind,
        title: String,
        preview: String,
        sourceApp: String,
        sourceAppIconData: Data?,
        createdAt: Date,
        isPinned: Bool,
        pinboardName: String?,
        textValue: String?,
        fileURLs: [URL],
        imageData: Data?,
        linkTitle: String? = nil,
        linkImageData: Data? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.preview = preview
        self.sourceApp = sourceApp
        self.sourceAppIconData = sourceAppIconData
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.pinboardName = pinboardName
        self.textValue = textValue
        self.fileURLs = fileURLs
        self.imageData = imageData
        self.linkTitle = linkTitle
        self.linkImageData = linkImageData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decode(ClipboardKind.self, forKey: .kind)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        preview = try container.decodeIfPresent(String.self, forKey: .preview) ?? title
        sourceApp = try container.decodeIfPresent(String.self, forKey: .sourceApp) ?? "Unknown"
        sourceAppIconData = try container.decodeIfPresent(Data.self, forKey: .sourceAppIconData)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        pinboardName = try container.decodeIfPresent(String.self, forKey: .pinboardName)
        textValue = try container.decodeIfPresent(String.self, forKey: .textValue)
        fileURLs = try container.decodeIfPresent([URL].self, forKey: .fileURLs) ?? []
        imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        linkTitle = try container.decodeIfPresent(String.self, forKey: .linkTitle)
        linkImageData = try container.decodeIfPresent(Data.self, forKey: .linkImageData)
    }

    var searchText: String {
        ([title, preview, linkTitle, sourceApp, kind.label].compactMap(\.self) + fileURLs.map(\.path))
            .joined(separator: " ")
            .localizedLowercase
    }

    var image: NSImage? {
        imageData.flatMap(NSImage.init(data:))
    }

    var sourceAppIcon: NSImage? {
        sourceAppIconData.flatMap(NSImage.init(data:))
    }

    var linkImage: NSImage? {
        linkImageData.flatMap(NSImage.init(data:))
    }

    var contentKey: String {
        switch kind {
        case .text, .url:
            return "\(kind.rawValue):\(textValue ?? preview)"
        case .file:
            return "file:\(fileURLs.map(\.path).joined(separator: "|"))"
        case .image:
            return "image:\(imageData?.stableDigest ?? "empty")"
        }
    }

    var storageOptimized: ClipboardItem {
        ClipboardItem(
            id: id,
            kind: kind,
            title: title,
            preview: preview,
            sourceApp: sourceApp,
            sourceAppIconData: sourceAppIcon?.pngData(maxPixel: 64),
            createdAt: createdAt,
            isPinned: isPinned,
            pinboardName: pinboardName,
            textValue: textValue,
            fileURLs: fileURLs,
            imageData: imageData == nil ? nil : image?.pngData(maxPixel: 1_200),
            linkTitle: linkTitle,
            linkImageData: linkImageData == nil ? nil : linkImage?.pngData(maxPixel: 640)
        )
    }

    func withLinkPreview(title: String?, linkImageData: Data?) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: kind,
            title: title ?? self.title,
            preview: preview,
            sourceApp: sourceApp,
            sourceAppIconData: sourceAppIconData,
            createdAt: createdAt,
            isPinned: isPinned,
            pinboardName: pinboardName,
            textValue: textValue,
            fileURLs: fileURLs,
            imageData: imageData,
            linkTitle: title,
            linkImageData: linkImageData
        )
    }
}

private extension Data {
    var stableDigest: String {
        SHA256.hash(data: self)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

extension ClipboardItem {
    static func sample(_ index: Int, kind: ClipboardKind) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: kind,
            title: ["Design notes", "openai.com", "Screenshot", "Project brief.pdf"][index % 4],
            preview: [
                "Copythat-style clipboard history with fast search and pinned groups.",
                "https://openai.com",
                "PNG image, 1440 x 900",
                "/Users/kaden/Documents/Project brief.pdf"
            ][index % 4],
            sourceApp: ["Safari", "Xcode", "Preview", "Finder"][index % 4],
            sourceAppIconData: nil,
            createdAt: Date().addingTimeInterval(Double(-index * 180)),
            isPinned: index == 1,
            pinboardName: index == 1 ? "Work" : nil,
            textValue: kind == .image ? nil : "Sample clipboard content \(index)",
            fileURLs: [],
            imageData: nil
        )
    }
}
