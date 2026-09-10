import Foundation

func resolvedName(
    shortcut: CopySourceSnapshot?,
    firstObservedForeground: CopySourceSnapshot? = nil,
    currentForeground: CopySourceSnapshot?,
    recentForeground: CopySourceSnapshot?,
    isSystemGeneratedContent: Bool = false,
    now: Date
) -> String {
    let slot = CopySourceResolution.resolveSlot(
        shortcut: shortcut,
        firstObservedForeground: firstObservedForeground,
        currentForeground: currentForeground,
        recentForeground: recentForeground,
        isSystemGeneratedContent: isSystemGeneratedContent,
        now: now
    )

    switch slot {
    case .shortcut:
        return shortcut?.appName ?? "Unknown"
    case .firstObservedForeground:
        return firstObservedForeground?.appName ?? "Unknown"
    case .currentForeground:
        return currentForeground?.appName ?? "Unknown"
    case .recentForeground:
        return recentForeground?.appName ?? "Unknown"
    case .system:
        return "System"
    case .unknown:
        return "Unknown"
    }
}

@main
struct SourceResolutionVerify {
    static func main() {
        let now = Date()

        precondition(resolvedName(
            shortcut: CopySourceSnapshot(appName: "Safari", capturedAt: now.addingTimeInterval(-1)),
            currentForeground: CopySourceSnapshot(appName: "Xcode", capturedAt: now),
            recentForeground: CopySourceSnapshot(appName: "Finder", capturedAt: now),
            now: now
        ) == "Safari", "recent copy source should resolve")

        precondition(resolvedName(
            shortcut: nil,
            currentForeground: CopySourceSnapshot(appName: "Xcode", capturedAt: now),
            recentForeground: nil,
            now: now
        ) == "Xcode", "event tap unavailable should fall back to current foreground app")

        precondition(resolvedName(
            shortcut: nil,
            firstObservedForeground: CopySourceSnapshot(appName: "Chrome", capturedAt: now),
            currentForeground: CopySourceSnapshot(appName: "Code", capturedAt: now),
            recentForeground: nil,
            now: now
        ) == "Chrome", "first-observed foreground should beat capture-time foreground app")

        precondition(resolvedName(
            shortcut: nil,
            currentForeground: nil,
            recentForeground: CopySourceSnapshot(appName: "Safari", capturedAt: now.addingTimeInterval(-2)),
            now: now
        ) == "Safari", "event tap unavailable should fall back to recent external foreground app")

        precondition(resolvedName(
            shortcut: CopySourceSnapshot(appName: "Xcode", capturedAt: now.addingTimeInterval(-5)),
            currentForeground: nil,
            recentForeground: nil,
            now: now
        ) == "Unknown", "stale shortcut source should not resolve")

        precondition(resolvedName(
            shortcut: CopySourceSnapshot(appName: "System", capturedAt: now.addingTimeInterval(-0.5)),
            currentForeground: nil,
            recentForeground: nil,
            now: now
        ) == "System", "screenshot shortcut source should resolve to System")

        precondition(resolvedName(
            shortcut: nil,
            currentForeground: nil,
            recentForeground: nil,
            isSystemGeneratedContent: true,
            now: now
        ) == "System", "system generated screenshot content should resolve to System")

        precondition(resolvedName(
            shortcut: nil,
            currentForeground: nil,
            recentForeground: nil,
            now: now
        ) == "Unknown", "missing source should resolve to Unknown")

        let pendingSnapshots = [
            CopySourceSnapshot(appName: "App A", capturedAt: now.addingTimeInterval(-1.0), pasteboardChangeCount: 10),
            CopySourceSnapshot(appName: "App B", capturedAt: now.addingTimeInterval(-0.2), pasteboardChangeCount: 12)
        ]

        let singleChangeIndex = CopySourceResolution.pendingShortcutIndex(
            snapshots: pendingSnapshots,
            pasteboardChangeCountDelta: 2,
            currentPasteboardChangeCount: 12,
            now: now
        )
        precondition(singleChangeIndex == 0, "unwritten later shortcut source should not overwrite current content")

        let skippedChangeIndex = CopySourceResolution.pendingShortcutIndex(
            snapshots: pendingSnapshots,
            pasteboardChangeCountDelta: 2,
            currentPasteboardChangeCount: 13,
            now: now
        )
        precondition(skippedChangeIndex == 1, "completed later shortcut source should be used for latest visible content")

        let legacySingleChangeIndex = CopySourceResolution.pendingShortcutIndex(
            snapshots: [
                CopySourceSnapshot(appName: "Legacy A", capturedAt: now.addingTimeInterval(-1.0)),
                CopySourceSnapshot(appName: "Legacy B", capturedAt: now.addingTimeInterval(-0.2))
            ],
            pasteboardChangeCountDelta: 1,
            now: now
        )
        precondition(legacySingleChangeIndex == 0, "single pasteboard change should preserve the earliest unconsumed source")

        let stalePendingIndex = CopySourceResolution.pendingShortcutIndex(
            snapshots: [
                CopySourceSnapshot(appName: "Stale", capturedAt: now.addingTimeInterval(-5.0)),
                CopySourceSnapshot(appName: "Fresh", capturedAt: now.addingTimeInterval(-0.5))
            ],
            pasteboardChangeCountDelta: 1,
            now: now
        )
        precondition(stalePendingIndex == 1, "stale pending shortcut sources should be ignored")

        precondition(!CopySourceResolution.isSourceCandidate(
            processIdentifier: 100,
            currentProcessIdentifier: 100,
            bundleIdentifier: "local.copythat.clipboard",
            localizedName: "Copythat",
            copythatBundleIdentifier: "local.copythat.clipboard"
        ), "Copythat process should not be a source")

        precondition(!CopySourceResolution.isSourceCandidate(
            processIdentifier: 200,
            currentProcessIdentifier: 100,
            bundleIdentifier: "com.apple.systemuiserver",
            localizedName: "SystemUIServer",
            copythatBundleIdentifier: "local.copythat.clipboard"
        ), "SystemUIServer should not be a source")

        precondition(!CopySourceResolution.isSourceCandidate(
            processIdentifier: 400,
            currentProcessIdentifier: 100,
            bundleIdentifier: "local.copythat.clipboard",
            localizedName: "Copythat",
            copythatBundleIdentifier: "local.copythat.clipboard"
        ), "Copythat bundle should not be a source")

        precondition(CopySourceResolution.isSourceCandidate(
            processIdentifier: 300,
            currentProcessIdentifier: 100,
            bundleIdentifier: "com.apple.Safari",
            localizedName: "Safari",
            copythatBundleIdentifier: "local.copythat.clipboard"
        ), "user app should be a source")

        print("source resolution ok")
    }
}
