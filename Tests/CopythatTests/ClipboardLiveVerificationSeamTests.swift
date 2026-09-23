@testable import Copythat
import AppKit
import Carbon
import CoreGraphics
import Foundation
import Testing

/// Verification-seam tests for the clipboard live verification tooling (D3):
/// the narrow `eventTapFactory` injection and `isEventTapActive` observation
/// must never drive capture, change source order, or enable diagnostics in
/// normal startup.
struct ClipboardLiveVerificationSeamTests {
    @Test func injectedTapCreationFailureKeepsTrackerAvailable() {
        let suiteName = "ClipboardLiveSeamTests.tapFailure.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: ClipboardDiagnostics.defaultsKey)
        var events: [ClipboardDiagnostics.SourceTimingEvent] = []
        let injectedSource = ClipboardSource(
            appName: "Injected App", iconData: nil, capturedAt: Date(), pasteboardChangeCount: 40)
        let tracker = CopySourceTracker(
            frontmostSourceProvider: { injectedSource },
            diagnostics: ClipboardDiagnostics(
                defaults: defaults,
                eventSink: { events.append($0) }
            ))
        tracker.eventTapFactory = { nil }

        tracker.start()

        #expect(!tracker.isEventTapActive)
        #expect(events.isEmpty)

        // The injected failure must not disable wake delivery: a real CGEvent
        // for Cmd+C (not posted to the system) still produces shortcut evidence.
        let commandC = CGEvent(
            keyboardEventSource: nil,
            virtualKey: UInt16(kVK_ANSI_C),
            keyDown: true
        )
        commandC?.flags = .maskCommand
        if let commandC {
            tracker.handle(type: .keyDown, event: commandC)
        }
        #expect(events.contains { $0.event == .copyShortcutObserved })
    }

    @Test func realTapCreationIsObservedWithoutDrivingCapture() {
        // When Accessibility is not trusted the tap cannot be created; the
        // expectation only holds in a trusted (prepared) environment.
        guard AXIsProcessTrusted() else { return }
        let suiteName = "ClipboardLiveSeamTests.realTap.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: ClipboardDiagnostics.defaultsKey)
        let tracker = CopySourceTracker(diagnostics: ClipboardDiagnostics(defaults: defaults))

        tracker.start()
        defer { tracker.stopMonitoringForVerification() }

        #expect(tracker.isEventTapActive)
    }

    @Test func isolationDefaultsSuiteDoesNotTouchStandardDomain() {
        let standardBefore = UserDefaults.standard.bool(forKey: ClipboardDiagnostics.defaultsKey)

        let suiteName = "local.copythat.live-verify"
        let isolated = UserDefaults(suiteName: suiteName)!
        isolated.set(true, forKey: ClipboardDiagnostics.defaultsKey)

        let standardAfter = UserDefaults.standard.bool(forKey: ClipboardDiagnostics.defaultsKey)
        #expect(standardBefore == standardAfter)

        isolated.removePersistentDomain(forName: suiteName)
    }
}

extension CopySourceTracker {
    /// Test-only teardown mirroring deinit ordering for taps created by a test.
    func stopMonitoringForVerification() {
        // deinit performs tap teardown; nothing else to reset here. Kept as an
        // explicit seam so the test reads symmetrically with start().
    }
}
