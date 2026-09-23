import CryptoKit
import Foundation

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
        let persistedItems = items.map { item in
            PersistedClipboardItemV2(
                item: item,
                sourceAppIconBlob: blobID(for: item.sourceAppIconData, pendingBlobs: &pendingBlobs),
                imageBlob: blobID(for: item.imageData, pendingBlobs: &pendingBlobs),
                linkImageBlob: blobID(for: item.linkImageData, pendingBlobs: &pendingBlobs)
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
                var blobCache: [String: Data] = [:]
                return try file.items.map { persistedItem in
                    try persistedItem.makeClipboardItem { blobID in
                        try loadBlob(blobID, cache: &blobCache)
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

    private func blobID(for data: Data?, pendingBlobs: inout [String: Data]) -> String? {
        guard let data else { return nil }
        let blobID = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()

        if pendingBlobs[blobID] != nil { return blobID }
        let blobURL = mediaDirectoryURL.appendingPathComponent("\(blobID).blob")
        guard FileManager.default.fileExists(atPath: blobURL.path) else {
            pendingBlobs[blobID] = data
            return blobID
        }

        if let existingData = try? readData(blobURL) {
            let existingBlobID = SHA256.hash(data: existingData)
                .map { String(format: "%02x", $0) }
                .joined()
            if existingBlobID == blobID { return blobID }
        }

        pendingBlobs[blobID] = data
        return blobID
    }

    private func loadBlob(_ blobID: String?, cache: inout [String: Data]) throws -> Data? {
        guard let blobID else { return nil }
        guard blobID.count == 64,
              blobID == blobID.lowercased(),
              blobID.allSatisfy(\.isHexDigit) else {
            throw ClipboardHistoryPersistenceError.invalidBlob(blobID)
        }
        if let cached = cache[blobID] { return cached }
        let data = try readData(mediaDirectoryURL.appendingPathComponent("\(blobID).blob"))
        let actualID = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard actualID == blobID else {
            throw ClipboardHistoryPersistenceError.invalidBlob(blobID)
        }
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

    func makeClipboardItem(loadBlob: (String?) throws -> Data?) throws -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: kind,
            title: title,
            preview: preview,
            sourceApp: sourceApp,
            sourceAppIconData: try loadBlob(sourceAppIconBlob),
            createdAt: createdAt,
            isPinned: isPinned,
            pinboardName: pinboardName,
            textValue: textValue,
            fileURLs: fileURLs,
            imageData: try loadBlob(imageBlob),
            linkTitle: linkTitle,
            linkImageData: try loadBlob(linkImageBlob)
        )
    }
}

private enum ClipboardHistoryPersistenceError: Error {
    case unsupportedVersion(Int)
    case invalidBlob(String)
}
