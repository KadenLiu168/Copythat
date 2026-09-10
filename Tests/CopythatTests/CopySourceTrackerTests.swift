@testable import Copythat
import Foundation
import Testing

struct CopySourceTrackerTests {
    @Test func frontmostSnapshotDoesNotUpdateRecentExternalSource() {
        let source = ClipboardSource(
            appName: "First App",
            iconData: nil,
            capturedAt: Date()
        )
        var sources: [ClipboardSource?] = [source, nil]
        let tracker = CopySourceTracker(frontmostSourceProvider: {
            sources.removeFirst()
        })

        let firstObservedSource = tracker.frontmostSourceSnapshot()
        let resolvedSource = tracker.resolveSource()

        #expect(firstObservedSource?.appName == "First App")
        #expect(resolvedSource.appName == "Unknown")
    }

    @Test func activationShortcutAndResolutionEmitCorrelatedDiagnostics() {
        let suiteName = "CopySourceTrackerTests.diagnostics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: ClipboardDiagnostics.defaultsKey)
        var events: [ClipboardDiagnostics.SourceTimingEvent] = []
        let diagnostics = ClipboardDiagnostics(defaults: defaults, eventSink: { events.append($0) })
        let now = Date(timeIntervalSince1970: 100)
        let activatedSource = source(named: "Code", capturedAt: now, changeCount: 40)
        let shortcutSource = source(named: "Google Chrome", capturedAt: now, changeCount: 40)
        let tracker = CopySourceTracker(
            frontmostSourceProvider: { activatedSource },
            diagnostics: diagnostics
        )

        tracker.recordActivatedSource(activatedSource, currentChangeCount: 40, uptime: 9.9)
        tracker.recordShortcutSource(shortcutSource, operation: .copy, uptime: 10)
        let resolved = tracker.resolveSource(
            currentPasteboardChangeCount: 41,
            now: now.addingTimeInterval(0.5),
            uptime: 10.5
        )

        #expect(resolved.appName == "Google Chrome")
        #expect(events.map(\.event) == [
            .appActivated,
            .copyShortcutObserved,
            .sourceResolved
        ])
        #expect(events.map(\.uptime) == [9.9, 10, 10.5])
        #expect(events[0].sourceApp == "Code")
        #expect(events[1].operation == "copy")
        #expect(events[2].changeCount == 41)
        #expect(events[2].sourceApp == "Google Chrome")
        #expect(events[2].resolutionSlot == "shortcut")
    }

    private func source(
        named name: String,
        capturedAt: Date,
        changeCount: Int
    ) -> ClipboardSource {
        ClipboardSource(
            appName: name,
            iconData: nil,
            capturedAt: capturedAt,
            pasteboardChangeCount: changeCount
        )
    }
}
