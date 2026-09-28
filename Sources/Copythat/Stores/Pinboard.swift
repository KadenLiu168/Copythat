import Foundation

/// Board filter identity used by the store and panel UI.
struct Pinboard: Hashable, Identifiable {
    enum Kind: Hashable {
        case all
        case pinned
        case custom
        case unknown
    }

    let kind: Kind
    let title: String
    let customName: String?

    var id: String {
        switch kind {
        case .all: "all"
        case .pinned: "pinned"
        case .custom: "custom:\(customName ?? "")"
        case .unknown: "unknown"
        }
    }

    static let all = Pinboard(kind: .all, title: "All", customName: nil)
    static let pinned = Pinboard(kind: .pinned, title: "Pinned", customName: nil)

    static func custom(_ name: String) -> Pinboard {
        Pinboard(kind: .custom, title: name, customName: name)
    }

    init(id: String) {
        switch id {
        case Self.all.id:
            self = .all
        case Self.pinned.id:
            self = .pinned
        default:
            if id.hasPrefix("custom:") {
                let name = String(id.dropFirst("custom:".count))
                self = .custom(name)
            } else {
                self = Pinboard(kind: .unknown, title: "All", customName: nil)
            }
        }
    }

    init(kind: Kind, title: String, customName: String?) {
        self.kind = kind
        self.title = title
        self.customName = customName
    }
}
