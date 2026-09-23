@testable import Copythat
import AppKit
import Carbon
import CoreGraphics
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

    @Test func snapshotReturnsPreviousFrontmostWhenWritePredatesActivation() {
        let currentFrontmost = ClipboardSource(appName: "App B", iconData: nil, capturedAt: Date())
        let tracker = CopySourceTracker(frontmostSourceProvider: { currentFrontmost })

        tracker.recordActivatedSource(
            ClipboardSource(appName: "App A", iconData: nil, capturedAt: Date()),
            currentChangeCount: 9
        )
        tracker.recordActivatedSource(currentFrontmost, currentChangeCount: 10)

        let snapshot = tracker.frontmostSourceSnapshot(pasteboardChangeCount: 10)

        #expect(snapshot?.appName == "App A")
    }

    @Test func snapshotKeepsCurrentFrontmostWhenWriteFollowsActivation() {
        let currentFrontmost = ClipboardSource(appName: "App B", iconData: nil, capturedAt: Date())
        let tracker = CopySourceTracker(frontmostSourceProvider: { currentFrontmost })

        tracker.recordActivatedSource(
            ClipboardSource(appName: "App A", iconData: nil, capturedAt: Date()),
            currentChangeCount: 9
        )
        tracker.recordActivatedSource(currentFrontmost, currentChangeCount: 9)

        let snapshot = tracker.frontmostSourceSnapshot(pasteboardChangeCount: 10)

        #expect(snapshot?.appName == "App B")
    }

    @Test func recognizedCopyAndCutShortcutsDeliverExactlyOneWake() {
        let tracker = CopySourceTracker(frontmostSourceProvider: { nil })
        var wakes = 0
        tracker.onCopyIntentWake = { wakes += 1 }

        tracker.handle(type: .keyDown, event: keyDown(keyCode: kVK_ANSI_C, flags: .maskCommand))
        tracker.handle(type: .keyDown, event: keyDown(keyCode: kVK_ANSI_X, flags: .maskCommand))

        #expect(wakes == 2, "each supported copy/cut intent must deliver exactly one wake")
    }

    @Test func screenshotShortcutDeliversWakeWithSystemSourceQueued() {
        let tracker = CopySourceTracker(frontmostSourceProvider: { nil })
        var wakes = 0
        tracker.onCopyIntentWake = { wakes += 1 }

        tracker.handle(
            type: .keyDown,
            event: keyDown(keyCode: kVK_ANSI_3, flags: [.maskCommand, .maskControl, .maskShift])
        )

        #expect(wakes == 1)
        let baseline = NSPasteboard.general.changeCount
        let resolved = tracker.resolveSource(currentPasteboardChangeCount: baseline + 1)
        #expect(resolved.appName == "System")
    }

    @Test func unrelatedKeyDownDoesNotWake() {
        let tracker = CopySourceTracker(frontmostSourceProvider: { nil })
        var wakes = 0
        tracker.onCopyIntentWake = { wakes += 1 }

        tracker.handle(type: .keyDown, event: keyDown(keyCode: kVK_ANSI_D, flags: .maskCommand))
        tracker.handle(type: .keyDown, event: keyDown(keyCode: kVK_ANSI_C, flags: [.maskCommand, .maskControl]))
        tracker.handle(type: .flagsChanged, event: keyDown(keyCode: kVK_ANSI_C, flags: .maskCommand))

        #expect(wakes == 0)
    }

    @Test func shortcutEvidenceIsQueuedBeforeWakeDelivery() {
        let chromeSource = ClipboardSource(appName: "Chrome", iconData: nil, capturedAt: Date())
        var sources: [ClipboardSource?] = [chromeSource, nil]
        let tracker = CopySourceTracker(frontmostSourceProvider: { sources.removeFirst() })
        var wakes = 0
        tracker.onCopyIntentWake = { wakes += 1 }

        tracker.handle(type: .keyDown, event: keyDown(keyCode: kVK_ANSI_C, flags: .maskCommand))

        #expect(wakes == 1)
        let baseline = NSPasteboard.general.changeCount
        let resolved = tracker.resolveSource(currentPasteboardChangeCount: baseline + 1)
        #expect(
            resolved.appName == "Chrome",
            "the shortcut source queued during wake handling must resolve after the wake"
        )
    }

    private func keyDown(keyCode: Int, flags: CGEventFlags) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true)
        event?.flags = flags
        return event!
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
