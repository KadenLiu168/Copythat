import Foundation

enum ClipboardHistoryPersistence {
    private static let legacyKey = "clipboardItems"
    private static let fileName = "clipboard-history.json"
    private static let currentSchemaVersion = 1

    static func loadItems() -> [ClipboardItem] {
        if let fileData = try? Data(contentsOf: historyURL) {
            do {
                return try decode(data: fileData)
            } catch {
                backup(data: fileData, suffix: "decode-failed")
                return []
            }
        }

        guard let legacyData = UserDefaults.standard.data(forKey: legacyKey) else {
            return []
        }

        do {
            let items = try JSONDecoder().decode([ClipboardItem].self, from: legacyData)
            save(items)
            UserDefaults.standard.removeObject(forKey: legacyKey)
            return items
        } catch {
            backup(data: legacyData, suffix: "legacy-decode-failed")
            return []
        }
    }

    static func save(_ items: [ClipboardItem]) {
        do {
            let file = ClipboardHistoryFile(version: currentSchemaVersion, items: items)
            let data = try JSONEncoder().encode(file)
            try FileManager.default.createDirectory(
                at: historyURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: historyURL, options: [.atomic])
        } catch {
            return
        }
    }

    static var historyURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Copythat", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private static func backup(data: Data, suffix: String) {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupURL = historyURL
            .deletingLastPathComponent()
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

    private static func decode(data: Data) throws -> [ClipboardItem] {
        if let file = try? JSONDecoder().decode(ClipboardHistoryFile.self, from: data) {
            return file.items
        }
        let legacyItems = try JSONDecoder().decode([ClipboardItem].self, from: data)
        save(legacyItems)
        return legacyItems
    }
}

private struct ClipboardHistoryFile: Codable {
    let version: Int
    let items: [ClipboardItem]
}
