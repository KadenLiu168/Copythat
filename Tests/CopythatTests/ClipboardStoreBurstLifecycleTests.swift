@testable import Copythat
import AppKit
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct ClipboardStoreBurstLifecycleTests {
    @Test func copyIntentWakeStartsBurstPollingAndCapturesPromptly() async {
        let (store, pasteboard) = makeRealTimeStore()
        store.startMonitoring()

        pasteboard.clearContents()
        pasteboard.setString("wake text", forType: .string)
        store.handleCopyIntentWake()
        let captured = await waitUntil(timeout: 2.0) { !store.items.isEmpty }

        #expect(captured, "wake must start burst polling that captures without the idle timer")
        #expect(store.items.first?.textValue == "wake text")
    }

    @Test func repeatedCopyIntentsExtendTheSingleBurstDeadline() async {
        let (store, _, clock) = makeStoreWithVirtualTime()
        store.startMonitoring()
        defer { store.stopMonitoring() }

        store.handleCopyIntentWake()
        let firstDeadline = store.burstDeadlineUptime
        #expect(store.isBurstPollingActive, "wake must start one effective burst loop")

        clock.advance(by: 0.2)
        store.handleCopyIntentWake()
        let extendedDeadline = store.burstDeadlineUptime
        #expect(firstDeadline != nil && extendedDeadline != nil)
        #expect((extendedDeadline ?? 0) > (firstDeadline ?? 0), "repeated wake must extend the same burst deadline")
        #expect(store.isBurstPollingActive)
    }

    @Test func burstPollingEndsAfterInactivityDeadline() async {
        let (store, _) = makeRealTimeStore()
        store.startMonitoring()

        store.handleCopyIntentWake()
        #expect(await waitUntil(timeout: 2.0) { store.isBurstPollingActive })

        _ = await waitUntil(timeout: 2.0) { !store.isBurstPollingActive }
        #expect(!store.isBurstPollingActive, "burst polling must end after its deadline")
    }

    @Test func repeatedWakesNeverAccumulateAnUnboundedDeadline() async {
        let (store, _) = makeRealTimeStore()
        store.startMonitoring()

        // Many signals inside one window must not extend the deadline additively.
        for _ in 0..<6 {
            store.handleCopyIntentWake()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        // 6 x 20ms = 120ms of wakes; an additive deadline would survive ~0.72s.
        _ = await waitUntil(timeout: 1.0) { !store.isBurstPollingActive }
        #expect(!store.isBurstPollingActive, "the burst deadline must stay bounded by one window")
    }

    @Test func repeatedStartMonitoringDoesNotCreateAnotherEffectiveLoop() async {
        let (store, pasteboard) = makeRealTimeStore()
        store.startMonitoring()
        store.startMonitoring()

        pasteboard.clearContents()
        pasteboard.setString("repeated start text", forType: .string)
        store.handleCopyIntentWake()
        _ = await waitUntil(timeout: 2.0) { !store.items.isEmpty }

        #expect(store.items.count == 1)
        #expect(store.items.first?.textValue == "repeated start text")
    }

    @Test func restartDiscoversExternalWriteMadeWhileStopped() async {
        let (store, pasteboard) = makeRealTimeStore()
        store.startMonitoring()

        pasteboard.clearContents()
        pasteboard.setString("external while monitoring", forType: .string)
        store.pollPasteboard()
        store.stopMonitoring()

        pasteboard.clearContents()
        pasteboard.setString("replaced while stopped", forType: .string)
        store.startMonitoring()
        store.handleCopyIntentWake()
        let captured = await waitUntil(timeout: 2.0) { !store.items.isEmpty }

        #expect(captured, "restart must discover the external write made while stopped")
        #expect(store.items.map(\.textValue) == ["replaced while stopped"])
    }

    @Test func wakeWhileStoppedDoesNotStartBurstPolling() async {
        let (store, pasteboard) = makeRealTimeStore()
        store.startMonitoring()
        store.stopMonitoring()

        pasteboard.clearContents()
        pasteboard.setString("written while stopped", forType: .string)
        store.handleCopyIntentWake()

        #expect(!store.isBurstPollingActive)
        try? await Task.sleep(nanoseconds: 150_000_000)
        #expect(store.items.isEmpty)
    }

    @Test func stopMonitoringCancelsActiveBurstAndStaleTaskCannotClobberNewerState() async {
        let (store, pasteboard) = makeRealTimeStore()
        store.startMonitoring()

        pasteboard.clearContents()
        pasteboard.setString("first", forType: .string)
        store.handleCopyIntentWake()
        _ = await waitUntil(timeout: 2.0) { !store.items.isEmpty }

        store.stopMonitoring()
        #expect(!store.isBurstPollingActive)

        store.startMonitoring()
        pasteboard.clearContents()
        pasteboard.setString("second", forType: .string)
        store.handleCopyIntentWake()
        let captured = await waitUntil(timeout: 2.0) {
            store.items.map(\.textValue) == ["second", "first"]
        }

        #expect(captured, "a stale canceled burst task must not break the newer burst")
    }

    @Test func selfWriteCancelsPendingObservationAndBurstPolling() async {
        let (store, pasteboard) = makeRealTimeStore()
        store.startMonitoring()

        pasteboard.clearContents()
        pasteboard.setString("pending external", forType: .string)
        store.handleCopyIntentWake()
        #expect(await waitUntil(timeout: 2.0) { store.isBurstPollingActive })

        #expect(store.writeToPasteboard(item(text: "restored text")))
        #expect(!store.isBurstPollingActive, "self-write must cancel burst scheduling")

        store.pollPasteboard()
        #expect(store.items.isEmpty)

        pasteboard.clearContents()
        pasteboard.setString("later external", forType: .string)
        store.handleCopyIntentWake()
        _ = await waitUntil(timeout: 2.0) { store.items.map(\.textValue) == ["later external"] }
        #expect(store.items.map(\.textValue) == ["later external"])
    }

    @Test func burstLoopConfirmsStabilityWithoutExtraPayloadCaptures() async {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        var events: [ClipboardDiagnostics.SourceTimingEvent] = []
        let diagnostics = ClipboardDiagnostics(
            defaults: diagnosticsDefaults(),
            eventSink: { events.append($0) }
        )
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults()),
            sourceTracker: CopySourceTracker(frontmostSourceProvider: { nil }, diagnostics: diagnostics),
            initialItems: [],
            pasteboard: pasteboard,
            diagnostics: diagnostics,
            persistItems: { _ in },
            minimumStabilityInterval: 0.05,
            burstPollInterval: 0.02,
            burstWindow: 0.3
        )
        store.startMonitoring()

        pasteboard.clearContents()
        pasteboard.setString("observed once", forType: .string)
        store.handleCopyIntentWake()
        _ = await waitUntil(timeout: 2.0) { !store.items.isEmpty }

        let changeCount = pasteboard.changeCount
        #expect(store.items.first?.textValue == "observed once")
        #expect(
            events.filter { $0.event == .pasteboardObserved && $0.changeCount == changeCount }.count == 1,
            "the burst loop must create exactly one pending observation"
        )
        #expect(
            events.filter { $0.event == .sourceResolved && $0.changeCount == changeCount }.count == 1,
            "the payload must be read once, only after stability"
        )
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

    private func makeStoreWithVirtualTime() -> (ClipboardStore, NSPasteboard, MutableClock) {
        let clock = MutableClock()
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults()),
            sourceTracker: CopySourceTracker(frontmostSourceProvider: { nil }),
            initialItems: [],
            pasteboard: pasteboard,
            persistItems: { _ in },
            uptimeProvider: { clock.now },
            burstPollInterval: 0.02,
            burstWindow: 0.3
        )
        return (store, pasteboard, clock)
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

    private func item(text: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .text,
            title: text,
            preview: text,
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(),
            isPinned: false,
            pinboardName: nil,
            textValue: text,
            fileURLs: [],
            imageData: nil
        )
    }

    private func diagnosticsDefaults() -> UserDefaults {
        let suiteName = "ClipboardStoreBurstLifecycleTests.diagnostics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: ClipboardDiagnostics.defaultsKey)
        return defaults
    }

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "ClipboardStoreBurstLifecycleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
