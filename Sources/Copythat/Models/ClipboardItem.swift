import AppKit
import Foundation

// Every stored field is a value type, so restored history can cross the
// restore actor boundary structurally. The computed AppKit accessors below
// build values on demand and store nothing.
enum ClipboardKind: String, Codable, CaseIterable, Sendable {
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

struct ClipboardItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let kind: ClipboardKind
    /// Display fields the model's own transforms replace. They stay `private(set)`
    /// so a preview merge or an optimization cannot be assembled field by field
    /// from outside, where a new field would be easy to drop.
    private(set) var title: String
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
    private(set) var imageData: Data?
    private(set) var linkTitle: String?
    private(set) var linkImageData: Data?
    /// Content address of the bytes backing `imageData`. Retained while V2
    /// history restores heavy media without reading it, so identity and
    /// persistence survive without resident bytes. Replaced only together with
    /// its bytes by the transforms that own the role.
    private(set) var imageBlobID: String?
    private(set) var linkImageBlobID: String?
    /// Runtime-derived searchable text, established once by the initializer or
    /// decoder and replaced by the one transform that changes searchable
    /// metadata. Never persisted: it is always rebuilt from decoded metadata.
    private(set) var searchText: String

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
        searchText = Self.makeSearchText(
            title: title,
            preview: preview,
            linkTitle: linkTitle,
            sourceApp: sourceApp,
            kind: kind,
            fileURLs: fileURLs
        )
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
        searchText = Self.makeSearchText(
            title: title,
            preview: preview,
            linkTitle: linkTitle,
            sourceApp: sourceApp,
            kind: kind,
            fileURLs: fileURLs
        )
    }

    /// The single place a search corpus is assembled. Field set, order, space
    /// delimiter and localized case normalization are the expression search
    /// has always applied; only its lifetime changed.
    private static func makeSearchText(
        title: String,
        preview: String,
        linkTitle: String?,
        sourceApp: String,
        kind: ClipboardKind,
        fileURLs: [URL]
    ) -> String {
        SearchCorpusObservation.record()
        return ([title, preview, linkTitle, sourceApp, kind.label].compactMap(\.self) + fileURLs.map(\.path))
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

        var optimized = self
        // Each role assigns its bytes and final address together, so no other
        // field is restated and no half-updated payload can exist.
        optimized.imageData = optimizedImage.data
        optimized.imageBlobID = finalBlobID(matching: optimizedImage)
        optimized.linkImageData = optimizedLinkImage.data
        optimized.linkImageBlobID = finalBlobID(matching: optimizedLinkImage)
        return optimized
    }

    /// Applies an already finalized preview payload, which carries its own
    /// address; passing nil keeps the current preview bytes and address, and
    /// passing nil for the title keeps the current displayed title while the
    /// link title is assigned that nil.
    func withLinkPreview(title: String?, linkImage: PreparedMedia?) -> ClipboardItem {
        var merged = self
        merged.title = title ?? merged.title
        merged.linkTitle = title
        if let linkImage {
            merged.linkImageData = linkImage.data
            merged.linkImageBlobID = linkImage.id
        }
        merged.searchText = Self.makeSearchText(
            title: merged.title,
            preview: merged.preview,
            linkTitle: merged.linkTitle,
            sourceApp: merged.sourceApp,
            kind: merged.kind,
            fileURLs: merged.fileURLs
        )
        return merged
    }

    /// Drops resident heavy media whose blob identity a successful save has
    /// durably committed, keeping every reference, all metadata, source icons,
    /// and content identity unchanged. Each role is evaluated independently:
    /// a role with no resident bytes, no current address, or a nonmatching
    /// durable address keeps its bytes.
    ///
    /// Returns nil when nothing was released, so ownership changes are decided
    /// without comparing fields. Addresses are carried over untouched, which
    /// never re-hashes media.
    func releasingResidentMedia(
        durableImageBlobID: String?,
        durableLinkImageBlobID: String?
    ) -> ClipboardItem? {
        let releasesImage = matchesResidentMedia(
            data: imageData,
            blobID: imageBlobID,
            durableBlobID: durableImageBlobID
        )
        let releasesLinkImage = matchesResidentMedia(
            data: linkImageData,
            blobID: linkImageBlobID,
            durableBlobID: durableLinkImageBlobID
        )
        guard releasesImage || releasesLinkImage else { return nil }
        var released = self
        if releasesImage {
            released.imageData = nil
        }
        if releasesLinkImage {
            released.linkImageData = nil
        }
        return released
    }

    /// Replaces only the image role's bytes, for a temporary paste copy that
    /// carries the verified payload of the blob this item already references.
    /// Every other field, and the payload's known address, are carried over, so
    /// the caller never restates them and no identity work happens here.
    func materializedForPaste(_ media: PreparedMedia) -> ClipboardItem {
        var materialized = self
        materialized.imageData = media.data
        materialized.imageBlobID = media.id
        return materialized
    }

    private func matchesResidentMedia(data: Data?, blobID: String?, durableBlobID: String?) -> Bool {
        guard data != nil, let blobID, let durableBlobID else { return false }
        return blobID == durableBlobID
    }

    /// Storage optimization for raw or unbounded media. Unchanged bytes report
    /// their existing address, changed output reports none so its replacement
    /// payload establishes the new one, and a conversion that yields no payload
    /// clears both. Reference-only media has no bytes to convert and keeps its
    /// reference.
    private func storageOptimizedMedia(
        imageData: Data?,
        blobID: String?,
        maxPixel: CGFloat
    ) -> (data: Data?, knownBlobID: String?) {
        guard let imageData else { return (nil, blobID) }
        guard let optimized = NSImage(data: imageData)?.pngData(maxPixel: maxPixel) else { return (nil, nil) }
        return optimized == imageData ? (optimized, blobID) : (optimized, nil)
    }

    /// The address an optimized role ends up with. Payloads that kept their bytes
    /// forward the address they already had, so nothing is hashed twice; a
    /// replaced payload establishes its own address once, through the same rule
    /// raw construction follows.
    private func finalBlobID(matching optimized: (data: Data?, knownBlobID: String?)) -> String? {
        Self.mediaBlobID(known: optimized.knownBlobID, data: optimized.data)
    }
}

/// Test-installed sink for actual search corpus builds. One recorder belongs to
/// one test: counting is lock-guarded so concurrent work inside that test is
/// accounted for, and tests without a recorder observe nothing. It holds a
/// count only, never clipboard content.
final class SearchCorpusRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var buildCount = 0

    func record() {
        lock.lock()
        buildCount += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return buildCount
    }
}

/// Observation seam for search corpus builds. The recorder is task-local, so
/// parallel tests never share counters and production runs without one.
/// Corpus builds run synchronously inside model construction and transforms,
/// so no detached boundary needs explicit propagation.
enum SearchCorpusObservation {
    @TaskLocal static var recorder: SearchCorpusRecorder?

    static func record() {
        recorder?.record()
    }
}
