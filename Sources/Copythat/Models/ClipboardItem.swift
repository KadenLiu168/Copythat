import AppKit
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
    /// Content address of the bytes backing `sourceAppIconData`, established
    /// once when the icon is prepared and forwarded with it afterwards.
    let sourceAppIconBlobID: String?
    let createdAt: Date
    var isPinned: Bool
    var pinboardName: String?
    let textValue: String?
    let fileURLs: [URL]
    let imageData: Data?
    let linkTitle: String?
    let linkImageData: Data?
    /// Content address of the bytes backing `imageData`. Retained while V2
    /// history restores heavy media without reading it, so identity and
    /// persistence survive without resident bytes.
    let imageBlobID: String?
    let linkImageBlobID: String?

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
        sourceAppIconBlobID: String? = nil,
        createdAt: Date,
        isPinned: Bool,
        pinboardName: String?,
        textValue: String?,
        fileURLs: [URL],
        imageData: Data?,
        imageBlobID: String? = nil,
        linkTitle: String? = nil,
        linkImageData: Data? = nil,
        linkImageBlobID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.preview = preview
        self.sourceApp = sourceApp
        self.sourceAppIconData = sourceAppIconData
        self.sourceAppIconBlobID = Self.mediaBlobID(known: sourceAppIconBlobID, data: sourceAppIconData)
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.pinboardName = pinboardName
        self.textValue = textValue
        self.fileURLs = fileURLs
        self.imageData = imageData
        self.linkTitle = linkTitle
        self.linkImageData = linkImageData
        self.imageBlobID = Self.mediaBlobID(known: imageBlobID, data: imageData)
        self.linkImageBlobID = Self.mediaBlobID(known: linkImageBlobID, data: linkImageData)
    }

    /// Resident bytes imply an address. Raw construction establishes that address
    /// once here instead of deferring hashing to save, while a prepared payload
    /// forwards the identity its producer already computed.
    private static func mediaBlobID(known: String?, data: Data?) -> String? {
        guard let data else { return known }
        return known ?? PreparedMedia(hashing: data).id
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
        let decodedImageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        let decodedLinkImageData = try container.decodeIfPresent(Data.self, forKey: .linkImageData)
        imageData = decodedImageData
        linkTitle = try container.decodeIfPresent(String.self, forKey: .linkTitle)
        linkImageData = decodedLinkImageData
        // Legacy inline media carries no address, so decoding establishes each
        // payload's identity once before any normal save sees it.
        imageBlobID = Self.mediaBlobID(known: nil, data: decodedImageData)
        linkImageBlobID = Self.mediaBlobID(known: nil, data: decodedLinkImageData)
        sourceAppIconBlobID = Self.mediaBlobID(known: nil, data: sourceAppIconData)
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
        imageBlobID != nil
    }

    /// Whether a link-preview image payload exists, resident or still on disk.
    var hasLinkImagePayload: Bool {
        linkImageBlobID != nil
    }

    /// Resident and restored images share one key: the address of their stored
    /// bytes. Comparing identities therefore needs no resident bytes at all.
    var contentKey: String {
        switch kind {
        case .text, .url:
            return "\(kind.rawValue):\(textValue ?? preview)"
        case .file:
            return "file:\(fileURLs.map(\.path).joined(separator: "|"))"
        case .image:
            guard let imageBlobID else { return "image:empty" }
            return "image:\(imageBlobID)"
        }
    }

    var storageOptimized: ClipboardItem {
        let optimizedImage = storageOptimizedMedia(imageData: imageData, blobID: imageBlobID, maxPixel: 1_200)
        let optimizedLinkImage = storageOptimizedMedia(
            imageData: linkImageData,
            blobID: linkImageBlobID,
            maxPixel: 640
        )
        return ClipboardItem(
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
            imageData: optimizedImage.data,
            imageBlobID: optimizedImage.blobID,
            linkTitle: linkTitle,
            linkImageData: optimizedLinkImage.data,
            linkImageBlobID: optimizedLinkImage.blobID
        )
    }

    /// Applies an already finalized preview payload, which carries its own
    /// address; passing nil keeps the current title and preview unchanged.
    func withLinkPreview(title: String?, linkImage: PreparedMedia?) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: kind,
            title: title ?? self.title,
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
            linkTitle: title,
            linkImageData: linkImage?.data ?? linkImageData,
            linkImageBlobID: linkImage?.id ?? linkImageBlobID
        )
    }

    /// Storage optimization for raw or unbounded media. Unchanged bytes keep
    /// their address, changed output receives a new one, and a conversion that
    /// yields no payload clears the pair. Reference-only media has no bytes to
    /// convert and keeps its reference.
    private func storageOptimizedMedia(
        imageData: Data?,
        blobID: String?,
        maxPixel: CGFloat
    ) -> (data: Data?, blobID: String?) {
        guard let imageData else { return (nil, blobID) }
        guard let optimized = NSImage(data: imageData)?.pngData(maxPixel: maxPixel) else { return (nil, nil) }
        return optimized == imageData ? (optimized, blobID) : (optimized, nil)
    }
}
