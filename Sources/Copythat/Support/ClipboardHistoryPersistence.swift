import CryptoKit
import Foundation

/// Shared access to the persisted heavy-media blob directory. History
/// persistence saves and restores through it, and the on-demand media loader
/// reads through the same validation and SHA256 verification path so blob
/// syntax rules exist in exactly one place.
struct ClipboardHistoryBlobStore: @unchecked Sendable {
    let directoryURL: URL
    let readData: (URL) throws -> Data

    /// Validates an ID and maps it to its blob URL without touching disk.
    func blobURL(for blobID: String) throws -> URL {
        guard Self.isCanonicalBlobID(blobID) else {
            throw ClipboardHistoryPersistenceError.invalidBlob(blobID)
        }
        return directoryURL.appendingPathComponent("\(blobID).blob")
    }

    /// Reads a blob and verifies its SHA256 before releasing bytes.
    func read(blobID: String) throws -> Data {
        let data = try readData(try blobURL(for: blobID))
        guard Self.sha256Hex(data) == blobID else {
            throw ClipboardHistoryPersistenceError.invalidBlob(blobID)
        }
        return data
    }

    /// Exactly 64 lowercase ASCII hex characters. Unicode hex digits and
    /// uppercase letters are rejected so an ID can only ever name a file
    /// directly inside the media directory.
    static func isCanonicalBlobID(_ blobID: String) -> Bool {
        let bytes = blobID.utf8
        guard bytes.count == 64 else { return false }
        return bytes.allSatisfy { byte in
            (byte >= 0x30 && byte <= 0x39) || (byte >= 0x61 && byte <= 0x66)
        }
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

final class ClipboardHistoryPersistence: @unchecked Sendable {
    private static let legacyKey = "clipboardItems"
    private static let fileName = "clipboard-history.json"
    private static let currentSchemaVersion = 2
    private static let mediaDirectoryName = "history-media"
    static let shared = ClipboardHistoryPersistence(directoryURL: defaultDirectoryURL)

    private let directoryURL: URL
    private let userDefaults: UserDefaults
    private let writeData: (Data, URL) throws -> Void
    private let readData: (URL) throws -> Data
    private let removeItemAtURL: (URL) throws -> Void
    private let blobs: ClipboardHistoryBlobStore

    init(
        directoryURL: URL,
        userDefaults: UserDefaults = .standard,
        readData: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) },
        writeData: @escaping (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: [.atomic])
        },
        removeItem: @escaping (URL) throws -> Void = { url in
            try FileManager.default.removeItem(at: url)
        }
    ) {
        self.directoryURL = directoryURL
        self.userDefaults = userDefaults
        self.readData = readData
        self.writeData = writeData
        removeItemAtURL = removeItem
        blobs = ClipboardHistoryBlobStore(
            directoryURL: directoryURL.appendingPathComponent(Self.mediaDirectoryName, isDirectory: true),
            readData: readData
        )
    }

    /// The shared blob access for the same media directory and reader this
    /// persistence uses, so on-demand consumers read the exact stored bytes.
    var blobStore: ClipboardHistoryBlobStore {
        blobs
    }

    static var historyURL: URL {
        shared.historyURL
    }

    static func loadItems() -> [ClipboardItem] {
        do {
            return try shared.loadItems()
        } catch {
            return []
        }
    }

    static func save(_ items: [ClipboardItem]) {
        try? shared.save(items)
    }

    var historyURL: URL {
        directoryURL.appendingPathComponent(Self.fileName)
    }

    private var mediaDirectoryURL: URL {
        directoryURL.appendingPathComponent(Self.mediaDirectoryName, isDirectory: true)
    }

    func loadItems() throws -> [ClipboardItem] {
        if FileManager.default.fileExists(atPath: historyURL.path) {
            let fileData = try readData(historyURL)
            do {
                return try decode(data: fileData)
            } catch {
                backup(data: fileData, suffix: "decode-failed")
                throw error
            }
        }

        guard let legacyData = userDefaults.data(forKey: Self.legacyKey) else {
            return []
        }

        do {
            return try JSONDecoder().decode([ClipboardItem].self, from: legacyData)
        } catch {
            backup(data: legacyData, suffix: "legacy-decode-failed")
            throw error
        }
    }

    func save(_ items: [ClipboardItem], garbageCollect: Bool = true) throws {
        var pendingBlobs: [String: Data] = [:]
        let persistedItems = try items.map { item in
            PersistedClipboardItemV2(
                item: item,
                sourceAppIconBlob: blobID(for: item.sourceAppIconData, pendingBlobs: &pendingBlobs),
                imageBlob: try blobID(
                    for: item.imageData,
                    persistedBlobID: item.persistedImageBlobID,
                    pendingBlobs: &pendingBlobs
                ),
                linkImageBlob: try blobID(
                    for: item.linkImageData,
                    persistedBlobID: item.persistedLinkImageBlobID,
                    pendingBlobs: &pendingBlobs
                )
            )
        }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: mediaDirectoryURL,
            withIntermediateDirectories: true
        )
        for (blobID, data) in pendingBlobs {
            let blobURL = mediaDirectoryURL.appendingPathComponent("\(blobID).blob")
            try writeData(data, blobURL)
        }

        let file = ClipboardHistoryFileV2(version: Self.currentSchemaVersion, items: persistedItems)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(file)
        try writeData(data, historyURL)
        userDefaults.removeObject(forKey: Self.legacyKey)
        if garbageCollect {
            collectGarbage()
        }
    }

    func collectGarbage() {
        guard let manifest = try? readData(historyURL),
              let file = try? JSONDecoder().decode(ClipboardHistoryFileV2.self, from: manifest),
              let blobURLs = try? FileManager.default.contentsOfDirectory(
                at: mediaDirectoryURL,
                includingPropertiesForKeys: nil
              ) else {
            return
        }
        let referencedBlobIDs = Set(file.items.flatMap(\.blobIDs))
        for blobURL in blobURLs where blobURL.pathExtension == "blob" {
            guard !referencedBlobIDs.contains(blobURL.deletingPathExtension().lastPathComponent) else { continue }
            try? removeItemAtURL(blobURL)
        }
    }

    private func backup(data: Data, suffix: String) {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupURL = directoryURL
            .appendingPathComponent("clipboard-history-\(suffix)-\(timestamp).json")
        do {
            try FileManager.default.createDirectory(
                at: backupURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: backupURL, options: [.atomic])
        } catch {
            return
        }
    }

    private func decode(data: Data) throws -> [ClipboardItem] {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let version = object["version"] as? Int {
            switch version {
            case 2:
                let file = try JSONDecoder().decode(ClipboardHistoryFileV2.self, from: data)
                // Every reference is validated before any of them becomes a
                // file path; heavy payloads are only read on demand later.
                for persistedItem in file.items {
                    try persistedItem.validateBlobReferences(in: blobs)
                }
                var iconCache: [String: Data] = [:]
                return try file.items.map { persistedItem in
                    try persistedItem.makeClipboardItem { iconBlobID in
                        try loadBlob(iconBlobID, cache: &iconCache)
                    }
                }
            case 1:
                return try JSONDecoder().decode(ClipboardHistoryFileV1.self, from: data).items
            default:
                throw ClipboardHistoryPersistenceError.unsupportedVersion(version)
            }
        }
        return try JSONDecoder().decode([ClipboardItem].self, from: data)
    }

    /// Media bytes win. An item without resident bytes reuses its validated
    /// reference without reading or hashing the referenced payload; an invalid
    /// reference fails the save before any manifest or GC work starts.
    private func blobID(
        for data: Data?,
        persistedBlobID: String?,
        pendingBlobs: inout [String: Data]
    ) throws -> String? {
        if let data {
            return blobID(for: data, pendingBlobs: &pendingBlobs)
        }
        guard let persistedBlobID else { return nil }
        _ = try blobs.blobURL(for: persistedBlobID)
        return persistedBlobID
    }

    private func blobID(for data: Data?, pendingBlobs: inout [String: Data]) -> String? {
        guard let data else { return nil }
        let blobID = ClipboardHistoryBlobStore.sha256Hex(data)

        if pendingBlobs[blobID] != nil { return blobID }
        let blobURL = try? blobs.blobURL(for: blobID)
        guard let blobURL, FileManager.default.fileExists(atPath: blobURL.path) else {
            pendingBlobs[blobID] = data
            return blobID
        }

        if let existingData = try? readData(blobURL),
           ClipboardHistoryBlobStore.sha256Hex(existingData) == blobID {
            return blobID
        }

        pendingBlobs[blobID] = data
        return blobID
    }

    private func loadBlob(_ blobID: String?, cache: inout [String: Data]) throws -> Data? {
        guard let blobID else { return nil }
        if let cached = cache[blobID] { return cached }
        let data = try blobs.read(blobID: blobID)
        cache[blobID] = data
        return data
    }

    private static var defaultDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Copythat", isDirectory: true)
    }
}

private struct ClipboardHistoryFile: Codable {
    let version: Int
    let items: [ClipboardItem]
}

private typealias ClipboardHistoryFileV1 = ClipboardHistoryFile

private struct ClipboardHistoryFileV2: Codable {
    let version: Int
    let items: [PersistedClipboardItemV2]
}

private struct PersistedClipboardItemV2: Codable {
    let id: UUID
    let kind: ClipboardKind
    let title: String
    let preview: String
    let sourceApp: String
    let sourceAppIconBlob: String?
    let createdAt: Date
    let isPinned: Bool
    let pinboardName: String?
    let textValue: String?
    let fileURLs: [URL]
    let imageBlob: String?
    let linkTitle: String?
    let linkImageBlob: String?

    var blobIDs: [String] {
        [sourceAppIconBlob, imageBlob, linkImageBlob].compactMap(\.self)
    }

    init(
        item: ClipboardItem,
        sourceAppIconBlob: String?,
        imageBlob: String?,
        linkImageBlob: String?
    ) {
        id = item.id
        kind = item.kind
        title = item.title
        preview = item.preview
        sourceApp = item.sourceApp
        self.sourceAppIconBlob = sourceAppIconBlob
        createdAt = item.createdAt
        isPinned = item.isPinned
        pinboardName = item.pinboardName
        textValue = item.textValue
        fileURLs = item.fileURLs
        self.imageBlob = imageBlob
        linkTitle = item.linkTitle
        self.linkImageBlob = linkImageBlob
    }

    /// Rejects a manifest whose references could not be used as file paths.
    func validateBlobReferences(in blobStore: ClipboardHistoryBlobStore) throws {
        for blobID in blobIDs {
            _ = try blobStore.blobURL(for: blobID)
        }
    }

    /// Source icons stay eager; heavy media is represented by its persisted
    /// content address so restore does not read or hash it.
    func makeClipboardItem(loadIcon: (String?) throws -> Data?) throws -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: kind,
            title: title,
            preview: preview,
            sourceApp: sourceApp,
            sourceAppIconData: try loadIcon(sourceAppIconBlob),
            createdAt: createdAt,
            isPinned: isPinned,
            pinboardName: pinboardName,
            textValue: textValue,
            fileURLs: fileURLs,
            imageData: nil,
            linkTitle: linkTitle,
            linkImageData: nil,
            persistedImageBlobID: imageBlob,
            persistedLinkImageBlobID: linkImageBlob
        )
    }
}

private enum ClipboardHistoryPersistenceError: Error {
    case unsupportedVersion(Int)
    case invalidBlob(String)
}
