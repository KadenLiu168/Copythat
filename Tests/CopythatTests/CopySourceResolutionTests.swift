@testable import Copythat
import Foundation
import Testing

struct CopySourceResolutionTests {
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

    private func snapshot(appName: String = "Test App", capturedAt: Date) -> CopySourceSnapshot {
        CopySourceSnapshot(appName: appName, capturedAt: capturedAt)
    }
}
