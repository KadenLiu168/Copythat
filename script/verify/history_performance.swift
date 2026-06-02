import Foundation

enum ClipboardKind: String, Codable {
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
}

struct ClipboardItem: Codable {
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

    var searchText: String {
        ([title, preview, sourceApp, kind.label] + fileURLs.map(\.path))
            .joined(separator: " ")
            .localizedLowercase
    }
}

enum Pinboard {
    case all
    case pinned
    case custom(String)

    init(id: String) {
        if id == "pinned" {
            self = .pinned
        } else if id.hasPrefix("custom:") {
            self = .custom(String(id.dropFirst("custom:".count)))
        } else {
            self = .all
        }
    }
}

func filtered(_ items: [ClipboardItem], query: String, boardID: String) -> [ClipboardItem] {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    let board = Pinboard(id: boardID)

    return items.filter { item in
        let boardMatches: Bool
        switch board {
        case .all:
            boardMatches = true
        case .pinned:
            boardMatches = item.isPinned
        case .custom(let name):
            boardMatches = item.pinboardName == name
        }

        return boardMatches && (normalizedQuery.isEmpty || item.searchText.contains(normalizedQuery))
    }
}

let now = Date()
var items: [ClipboardItem] = []
items.reserveCapacity(5_000)

for index in 0..<5_000 {
    let kind: ClipboardKind = index.isMultiple(of: 17) ? .url : .text
    let value = kind == .url ? "https://example.com/history/\(index)" : "Copythat history performance item \(index)"
    items.append(
        ClipboardItem(
            id: UUID(),
            kind: kind,
            title: kind == .url ? "example.com" : "History item \(index)",
            preview: value,
            sourceApp: index.isMultiple(of: 2) ? "Safari" : "Xcode",
            sourceAppIconData: nil,
            createdAt: now.addingTimeInterval(TimeInterval(-index)),
            isPinned: index.isMultiple(of: 250),
            pinboardName: index.isMultiple(of: 500) ? "Work" : nil,
            textValue: value,
            fileURLs: [],
            imageData: nil
        )
    )
}

let encoded = try JSONEncoder().encode(items)
let decoded = try JSONDecoder().decode([ClipboardItem].self, from: encoded)
let allStart = ContinuousClock.now
let allResults = filtered(decoded, query: "", boardID: "all")
let allDuration = allStart.duration(to: .now)
let searchStart = ContinuousClock.now
let searchResults = filtered(decoded, query: "4997", boardID: "all")
let searchDuration = searchStart.duration(to: .now)
let pinnedResults = filtered(decoded, query: "", boardID: "pinned")
let workResults = filtered(decoded, query: "", boardID: "custom:Work")

precondition(decoded.count == 5_000, "expected 5,000 decoded items")
precondition(allResults.count == 5_000, "All board should include every item")
precondition(searchResults.count == 1, "query should find exactly one item")
precondition(pinnedResults.count == 20, "expected 20 pinned items")
precondition(workResults.count == 10, "expected 10 Work pinboard items")
precondition(encoded.count < 2_000_000, "history fixture is unexpectedly large: \(encoded.count) bytes")

print("history ok count=\(decoded.count) bytes=\(encoded.count) all=\(allDuration) search=\(searchDuration) pinned=\(pinnedResults.count) work=\(workResults.count)")
