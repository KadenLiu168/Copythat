@testable import Copythat
import Foundation
import Testing

struct CopySourceResolutionTests {
    private static let copythatBundleIdentifier = "local.copythat.clipboard"

    @Test func freshShortcutWinsOverAllOtherCandidates() {
        let now = Date(timeIntervalSince1970: 100)

        let slot = CopySourceResolution.resolveSlot(
            shortcut: snapshot(capturedAt: now.addingTimeInterval(-1)),
            firstObservedForeground: snapshot(capturedAt: now),
            currentForeground: snapshot(capturedAt: now),
            recentForeground: snapshot(capturedAt: now.addingTimeInterval(-1)),
            isSystemGeneratedContent: true,
            now: now
        )

        #expect(slot == .shortcut)
    }

    @Test func freshShortcutWinsWithoutSystemGeneratedContent() {
        let now = Date(timeIntervalSince1970: 100)

        let slot = CopySourceResolution.resolveSlot(
            shortcut: snapshot(appName: "Safari", capturedAt: now.addingTimeInterval(-1)),
            firstObservedForeground: nil,
            currentForeground: snapshot(appName: "Xcode", capturedAt: now),
            recentForeground: snapshot(appName: "Finder", capturedAt: now),
            isSystemGeneratedContent: false,
            now: now
        )

        #expect(slot == .shortcut)
    }

    @Test func staleShortcutIsRejected() {
        let now = Date(timeIntervalSince1970: 100)

        let slot = CopySourceResolution.resolveSlot(
            shortcut: snapshot(appName: "Xcode", capturedAt: now.addingTimeInterval(-5)),
            firstObservedForeground: nil,
            currentForeground: nil,
            recentForeground: nil,
            isSystemGeneratedContent: false,
            now: now
        )

        #expect(slot == .unknown)
    }

    /// The screenshot shortcut's own name is snapshot content, so a fresh
    /// shortcut observation still occupies the shortcut slot.
    @Test func systemShortcutStillResolvesToTheShortcutSlot() {
        let now = Date(timeIntervalSince1970: 100)
        let shortcut = snapshot(appName: "System", capturedAt: now.addingTimeInterval(-0.5))

        let slot = CopySourceResolution.resolveSlot(
            shortcut: shortcut,
            firstObservedForeground: nil,
            currentForeground: nil,
            recentForeground: nil,
            isSystemGeneratedContent: false,
            now: now
        )

        #expect(slot == .shortcut)
        #expect(shortcut.appName == "System")
    }

    @Test func systemGeneratedContentWinsWithNoCandidates() {
        let now = Date(timeIntervalSince1970: 100)

        let slot = CopySourceResolution.resolveSlot(
            shortcut: nil,
            firstObservedForeground: nil,
            currentForeground: nil,
            recentForeground: nil,
            isSystemGeneratedContent: true,
            now: now
        )

        #expect(slot == .system)
    }

    @Test func missingSourceWithoutSystemContentResolvesToUnknown() {
        let now = Date(timeIntervalSince1970: 100)

        let slot = CopySourceResolution.resolveSlot(
            shortcut: nil,
            firstObservedForeground: nil,
            currentForeground: nil,
            recentForeground: nil,
            isSystemGeneratedContent: false,
            now: now
        )

        #expect(slot == .unknown)
    }

    @Test func firstObservedForegroundWinsOverCaptureTimeForeground() {
        let now = Date(timeIntervalSince1970: 100)

        let slot = CopySourceResolution.resolveSlot(
            shortcut: nil,
            firstObservedForeground: snapshot(appName: "First App", capturedAt: now),
            currentForeground: snapshot(appName: "Second App", capturedAt: now),
            recentForeground: nil,
            isSystemGeneratedContent: false,
            now: now
        )

        #expect(slot == .firstObservedForeground)
    }

    @Test func nilFirstObservedForegroundPreservesCurrentForegroundOrdering() {
        let now = Date(timeIntervalSince1970: 100)

        let slot = CopySourceResolution.resolveSlot(
            shortcut: nil,
            firstObservedForeground: nil,
            currentForeground: snapshot(capturedAt: now),
            recentForeground: snapshot(capturedAt: now.addingTimeInterval(-1)),
            isSystemGeneratedContent: true,
            now: now
        )

        #expect(slot == .currentForeground)
    }

    @Test func freshRecentForegroundWinsWithoutShortcutOrCurrentForeground() {
        let now = Date(timeIntervalSince1970: 100)

        let slot = CopySourceResolution.resolveSlot(
            shortcut: nil,
            firstObservedForeground: nil,
            currentForeground: nil,
            recentForeground: snapshot(capturedAt: now.addingTimeInterval(-7)),
            isSystemGeneratedContent: true,
            now: now
        )

        #expect(slot == .recentForeground)
    }

    @Test func staleRecentForegroundFallsBackToSystem() {
        let now = Date(timeIntervalSince1970: 100)

        let slot = CopySourceResolution.resolveSlot(
            shortcut: nil,
            firstObservedForeground: nil,
            currentForeground: nil,
            recentForeground: snapshot(capturedAt: now.addingTimeInterval(-9)),
            isSystemGeneratedContent: true,
            now: now
        )

        #expect(slot == .system)
    }

    @Test func staleRecentForegroundFallsBackToUnknown() {
        let now = Date(timeIntervalSince1970: 100)

        let slot = CopySourceResolution.resolveSlot(
            shortcut: nil,
            firstObservedForeground: nil,
            currentForeground: nil,
            recentForeground: snapshot(capturedAt: now.addingTimeInterval(-9)),
            isSystemGeneratedContent: false,
            now: now
        )

        #expect(slot == .unknown)
    }

    // MARK: - Pending shortcut snapshots

    /// Written baselines 10 / 12 against the current count decide which snapshot
    /// the newest visible content belongs to.
    @Test func pendingShortcutIndexUsesTheLastWrittenBaselineBelowTheCurrentCount() {
        let now = Date(timeIntervalSince1970: 100)
        let snapshots = [
            CopySourceSnapshot(appName: "App A", capturedAt: now.addingTimeInterval(-1), pasteboardChangeCount: 10),
            CopySourceSnapshot(appName: "App B", capturedAt: now.addingTimeInterval(-0.2), pasteboardChangeCount: 12)
        ]

        let unwrittenLaterIndex = CopySourceResolution.pendingShortcutIndex(
            snapshots: snapshots,
            pasteboardChangeCountDelta: 2,
            currentPasteboardChangeCount: 12,
            now: now
        )
        let completedLaterIndex = CopySourceResolution.pendingShortcutIndex(
            snapshots: snapshots,
            pasteboardChangeCountDelta: 2,
            currentPasteboardChangeCount: 13,
            now: now
        )

        #expect(unwrittenLaterIndex == 0, "a later source that never wrote the current content must not be used")
        #expect(completedLaterIndex == 1, "a completed later write owns the newest visible content")
    }

    /// Without a recorded baseline, a multi-change batch takes the latest fresh
    /// snapshot and a single change keeps the earliest unconsumed one.
    @Test func pendingShortcutIndexWithoutBaselinesUsesTheChangeCountDelta() {
        let now = Date(timeIntervalSince1970: 100)
        let snapshots = [
            snapshot(appName: "Legacy A", capturedAt: now.addingTimeInterval(-1)),
            snapshot(appName: "Legacy B", capturedAt: now.addingTimeInterval(-0.2))
        ]

        let multiChangeIndex = CopySourceResolution.pendingShortcutIndex(
            snapshots: snapshots,
            pasteboardChangeCountDelta: 2,
            now: now
        )
        let singleChangeIndex = CopySourceResolution.pendingShortcutIndex(
            snapshots: snapshots,
            pasteboardChangeCountDelta: 1,
            now: now
        )

        #expect(multiChangeIndex == 1)
        #expect(singleChangeIndex == 0, "one pasteboard change preserves the earliest unconsumed source")
    }

    /// Stale snapshots are filtered before selection, so the returned index still
    /// addresses the original array.
    @Test func pendingShortcutIndexIgnoresStaleSnapshotsAndKeepsTheArrayIndex() {
        let now = Date(timeIntervalSince1970: 100)
        let snapshots = [
            snapshot(appName: "Stale", capturedAt: now.addingTimeInterval(-5)),
            snapshot(appName: "Fresh", capturedAt: now.addingTimeInterval(-0.5))
        ]

        let index = CopySourceResolution.pendingShortcutIndex(
            snapshots: snapshots,
            pasteboardChangeCountDelta: 1,
            now: now
        )

        #expect(index == 1)
    }

    @Test func pendingShortcutIndexIsNilWithoutFreshSnapshots() {
        let now = Date(timeIntervalSince1970: 100)

        let index = CopySourceResolution.pendingShortcutIndex(
            snapshots: [snapshot(appName: "Stale", capturedAt: now.addingTimeInterval(-5))],
            pasteboardChangeCountDelta: 1,
            now: now
        )

        #expect(index == nil)
    }

    // MARK: - Source candidate exclusion

    @Test func copythatProcessIsNotASourceCandidate() {
        #expect(!CopySourceResolution.isSourceCandidate(
            processIdentifier: 100,
            currentProcessIdentifier: 100,
            bundleIdentifier: Self.copythatBundleIdentifier,
            localizedName: "Copythat",
            copythatBundleIdentifier: Self.copythatBundleIdentifier
        ))
    }

    @Test func systemUIServerIsNotASourceCandidate() {
        #expect(!CopySourceResolution.isSourceCandidate(
            processIdentifier: 200,
            currentProcessIdentifier: 100,
            bundleIdentifier: "com.apple.systemuiserver",
            localizedName: "SystemUIServer",
            copythatBundleIdentifier: Self.copythatBundleIdentifier
        ))
    }

    @Test func anotherCopythatBundleIsNotASourceCandidate() {
        #expect(!CopySourceResolution.isSourceCandidate(
            processIdentifier: 400,
            currentProcessIdentifier: 100,
            bundleIdentifier: Self.copythatBundleIdentifier,
            localizedName: "Copythat",
            copythatBundleIdentifier: Self.copythatBundleIdentifier
        ))
    }

    @Test func userApplicationIsASourceCandidate() {
        #expect(CopySourceResolution.isSourceCandidate(
            processIdentifier: 300,
            currentProcessIdentifier: 100,
            bundleIdentifier: "com.apple.Safari",
            localizedName: "Safari",
            copythatBundleIdentifier: Self.copythatBundleIdentifier
        ))
    }

    private func snapshot(
        appName: String = "Test App",
        capturedAt: Date,
        pasteboardChangeCount: Int? = nil
    ) -> CopySourceSnapshot {
        CopySourceSnapshot(
            appName: appName,
            capturedAt: capturedAt,
            pasteboardChangeCount: pasteboardChangeCount
        )
    }
}
