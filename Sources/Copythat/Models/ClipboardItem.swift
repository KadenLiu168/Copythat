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
    /// Content address of the persisted image blob backing `imageData`.
    /// Retained while V2 history restores heavy media without reading it, so
    /// identity and persistence survive without resident bytes.
    let persistedImageBlobID: String?
    let persistedLinkImageBlobID: String?

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
        linkImageData: Data? = nil,
        persistedImageBlobID: String? = nil,
        persistedLinkImageBlobID: String? = nil
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
        self.persistedImageBlobID = persistedImageBlobID
        self.persistedLinkImageBlobID = persistedLinkImageBlobID
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
        persistedImageBlobID = nil
        persistedLinkImageBlobID = nil
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

    /// Whether an image payload exists, whether resident or still on disk.
    var hasImagePayload: Bool {
        imageData != nil || persistedImageBlobID != nil
    }

    /// Whether a link-preview image payload exists, resident or still on disk.
    var hasLinkImagePayload: Bool {
        linkImageData != nil || persistedLinkImageBlobID != nil
    }

    var contentKey: String {
        switch kind {
        case .text, .url:
            return "\(kind.rawValue):\(textValue ?? preview)"
        case .file:
            return "file:\(fileURLs.map(\.path).joined(separator: "|"))"
        case .image:
            if let imageData {
                return "image:\(imageData.stableDigest)"
            }
            if let persistedImageBlobID {
                return "image:\(persistedImageBlobID)"
            }
            return "image:empty"
        }
    }

    var storageOptimized: ClipboardItem {
        let optimizedImageData = imageData == nil ? nil : image?.pngData(maxPixel: 1_200)
        let optimizedLinkImageData = linkImageData == nil ? nil : linkImage?.pngData(maxPixel: 640)
        return ClipboardItem(
            id: id,
            kind: kind,
            title: title,
            preview: preview,
            sourceApp: sourceApp,
            sourceAppIconData: sourceAppIconData,
            createdAt: createdAt,
            isPinned: isPinned,
            pinboardName: pinboardName,
            textValue: textValue,
            fileURLs: fileURLs,
            imageData: optimizedImageData,
            linkTitle: linkTitle,
            linkImageData: optimizedLinkImageData,
            persistedImageBlobID: persistedReference(
                persistedImageBlobID,
                original: imageData,
                optimized: optimizedImageData
            ),
            persistedLinkImageBlobID: persistedReference(
                persistedLinkImageBlobID,
                original: linkImageData,
                optimized: optimizedLinkImageData
            )
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
            linkImageData: linkImageData ?? self.linkImageData,
            persistedImageBlobID: persistedImageBlobID,
            persistedLinkImageBlobID: linkImageData == nil ? persistedLinkImageBlobID : nil
        )
    }

    /// A reference stays valid only while the bytes it addresses are unchanged.
    private func persistedReference(_ blobID: String?, original: Data?, optimized: Data?) -> String? {
        guard let original else { return blobID }
        guard let optimized, optimized == original else { return nil }
        return blobID
    }
}

private extension Data {
    var stableDigest: String {
        SHA256.hash(data: self)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
