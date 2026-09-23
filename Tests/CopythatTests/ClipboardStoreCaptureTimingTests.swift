@testable import Copythat
import AppKit
import Foundation
import Testing

@MainActor
final class MutableClock {
    private(set) var now: TimeInterval

    init(now: TimeInterval = 0) {
        self.now = now
    }

    func advance(by interval: TimeInterval) {
        now += interval
    }
}

@MainActor
@Suite(.serialized)
struct ClipboardStoreCaptureTimingTests {
    @Test func pendingCountIsNotCapturedBelowMinimumStabilityDuration() {
        let (store, pasteboard, clock) = makeStore()
        pasteboard.clearContents()
        pasteboard.setString("stable text", forType: .string)

        store.pollPasteboard()
        clock.advance(by: 0.05)
        store.pollPasteboard()

        #expect(store.items.isEmpty)
    }

    @Test func pendingCountIsCapturedAtOrBeyondMinimumStabilityDuration() {
        let (store, pasteboard, clock) = makeStore()
        pasteboard.clearContents()
        pasteboard.setString("stable text", forType: .string)

        store.pollPasteboard()
        clock.advance(by: 1.0)
        store.pollPasteboard()

        #expect(store.items.map(\.textValue) == ["stable text"])
    }

    @Test func newerCountRestartsStabilityDuration() {
        let (store, pasteboard, clock) = makeStore()

        pasteboard.clearContents()
        pasteboard.setString("transient text", forType: .string)
        store.pollPasteboard()
        clock.advance(by: 0.10)
        pasteboard.clearContents()
        pasteboard.setString("final text", forType: .string)
        store.pollPasteboard()
        clock.advance(by: 0.10)
        store.pollPasteboard()

        #expect(store.items.isEmpty)
    }

    @Test func transientCountIsExcludedWhileFinalCountStabilizes() {
        let (store, pasteboard, clock) = makeStore()

        pasteboard.clearContents()
        pasteboard.setString("transient text", forType: .string)
        store.pollPasteboard()
        clock.advance(by: 0.05)
        pasteboard.clearContents()
        pasteboard.setString("final text", forType: .string)
        store.pollPasteboard()
        clock.advance(by: 1.0)
        store.pollPasteboard()

        #expect(store.items.map(\.textValue) == ["final text"])
    }

    @Test func explicitPanelStylePollDoesNotBypassStabilityBelowThreshold() {
        let (store, pasteboard, clock) = makeStore()
        pasteboard.clearContents()
        pasteboard.setString("panel text", forType: .string)

        store.pollPasteboard()
        clock.advance(by: 0.05)
        store.pollPasteboard()

        #expect(store.items.isEmpty)

        clock.advance(by: 1.0)
        store.pollPasteboard()

        #expect(store.items.map(\.textValue) == ["panel text"])
    }

    @Test func successiveShortcutCopiesAfterStabilityRetainBothValues() async {
        let (store, pasteboard) = makeRealTimeStore()
        defer { store.stopMonitoring() }
        store.startMonitoring()

        pasteboard.clearContents()
        pasteboard.setString("copy A", forType: .string)
        store.handleCopyIntentWake()
        let capturedA = await waitUntil(timeout: 2.0) { !store.items.isEmpty }

        pasteboard.clearContents()
        pasteboard.setString("copy B", forType: .string)
        store.handleCopyIntentWake()
        _ = await waitUntil(timeout: 2.0) { store.items.map(\.textValue) == ["copy B", "copy A"] }

        #expect(capturedA, "copy A must be captured by burst polling, not the idle timer")
        #expect(store.items.map(\.textValue) == ["copy B", "copy A"])
    }

    private func makeStore() -> (ClipboardStore, NSPasteboard, MutableClock) {
        let clock = MutableClock()
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults()),
            sourceTracker: CopySourceTracker(frontmostSourceProvider: { nil }),
            initialItems: [],
            pasteboard: pasteboard,
            persistItems: { _ in },
            uptimeProvider: { clock.now }
        )
        return (store, pasteboard, clock)
    }

    private func makeRealTimeStore() -> (ClipboardStore, NSPasteboard) {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults()),
            sourceTracker: CopySourceTracker(frontmostSourceProvider: { nil }),
            initialItems: [],
            pasteboard: pasteboard,
            persistItems: { _ in },
            minimumStabilityInterval: 0.05,
            burstPollInterval: 0.02,
            burstWindow: 0.3
        )
        return (store, pasteboard)
    }

    private func waitUntil(
        timeout seconds: TimeInterval,
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return condition()
    }

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "ClipboardStoreCaptureTimingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
