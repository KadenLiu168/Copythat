import Foundation

struct CopySourceSnapshot {
    let appName: String
    let capturedAt: Date
    let pasteboardChangeCount: Int?

    init(appName: String, capturedAt: Date, pasteboardChangeCount: Int? = nil) {
        self.appName = appName
        self.capturedAt = capturedAt
        self.pasteboardChangeCount = pasteboardChangeCount
    }
}

enum CopySourceResolutionSlot: Equatable {
    case shortcut
    case currentForeground
    case recentForeground
    case system
    case unknown
}

enum CopySourceResolution {
    static let shortcutMaxAge: TimeInterval = 3
    static let foregroundMaxAge: TimeInterval = 8

    static func pendingShortcutIndex(
        snapshots: [CopySourceSnapshot],
        pasteboardChangeCountDelta: Int,
        currentPasteboardChangeCount: Int? = nil,
        now: Date
    ) -> Int? {
        let freshSnapshots = snapshots.enumerated().filter { _, snapshot in
            isFresh(snapshot, maxAge: shortcutMaxAge, now: now)
        }
        guard !freshSnapshots.isEmpty else {
            return nil
        }

        if let currentPasteboardChangeCount {
            return freshSnapshots.last { _, snapshot in
                guard let pasteboardChangeCount = snapshot.pasteboardChangeCount else {
                    return false
                }
                return pasteboardChangeCount < currentPasteboardChangeCount
            }?.offset
        }

        if pasteboardChangeCountDelta > 1 {
            return freshSnapshots.last?.offset
        }

        return freshSnapshots.first?.offset
    }

    static func resolveSlot(
        shortcut: CopySourceSnapshot?,
        currentForeground: CopySourceSnapshot?,
        recentForeground: CopySourceSnapshot?,
        isSystemGeneratedContent: Bool,
        now: Date
    ) -> CopySourceResolutionSlot {
        if isFresh(shortcut, maxAge: shortcutMaxAge, now: now) {
            return .shortcut
        }

        if currentForeground != nil {
            return .currentForeground
        }

        if isFresh(recentForeground, maxAge: foregroundMaxAge, now: now) {
            return .recentForeground
        }

        if isSystemGeneratedContent {
            return .system
        }

        return .unknown
    }

    static func isSourceCandidate(
        processIdentifier: Int32,
        currentProcessIdentifier: Int32,
        bundleIdentifier: String?,
        localizedName: String?,
        copythatBundleIdentifier: String?
    ) -> Bool {
        guard processIdentifier != currentProcessIdentifier,
              let localizedName,
              !localizedName.isEmpty else {
            return false
        }

        if localizedName == "Copythat" || localizedName == "SystemUIServer" {
            return false
        }

        if let bundleIdentifier,
           bundleIdentifier == copythatBundleIdentifier ||
           bundleIdentifier == "local.copythat.clipboard" ||
           bundleIdentifier == "com.apple.systemuiserver" {
            return false
        }

        return true
    }

    private static func isFresh(_ snapshot: CopySourceSnapshot?, maxAge: TimeInterval, now: Date) -> Bool {
        guard let snapshot else { return false }
        return now.timeIntervalSince(snapshot.capturedAt) <= maxAge
    }
}
