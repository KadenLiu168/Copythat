@testable import Copythat
import AppKit
import Testing

/// Deterministic coordination tests for `ClipboardPastePerformer`.
///
/// The seams below replace every system boundary (activation observation,
/// active-state checks, activation requests, fallback scheduling, deferred
/// main-queue delivery, and Command-V posting) so these tests never launch
/// another app, never sleep 350 ms, never write the real pasteboard, and never
/// post CGEvents.
@MainActor
struct ClipboardPastePerformerTests {

    // MARK: - Seam recorder

    private final class Seams {
        private(set) var callOrder: [String] = []

        // Stores every registered callback so tests can fire stale ones.
        private(set) var activationCallbacks: [@MainActor (pid_t) -> Void] = []
        private(set) var observerRemovals = 0
        func observeActivation(_ callback: @escaping @MainActor (pid_t) -> Void) -> () -> Void {
            callOrder.append("observe")
            activationCallbacks.append(callback)
            return { [weak self] in
                guard let self else { return }
                self.observerRemovals += 1
                self.callOrder.append("removeObserver")
            }
        }
        func activateApp(at index: Int, pid: pid_t) {
            MainActor.assumeIsolated { activationCallbacks[index](pid) }
        }
        func activateLatestApp(pid: pid_t) {
            guard let callback = activationCallbacks.last else { return }
            MainActor.assumeIsolated { callback(pid) }
        }

        // Active-state seam, consumed in order: pre-activation, post-activation.
        var activeStates: [Bool] = []
        func isTargetActive(_ application: NSRunningApplication) -> Bool {
            callOrder.append("activeCheck")
            guard !activeStates.isEmpty else { return false }
            return activeStates.removeFirst()
        }

        // Activation request seam; can fire the observer synchronously inside
        // the request to simulate a notification delivered during activate().
        private(set) var activationRequests = 0
        var fireObserverInsideActivation: (() -> Void)?
        func requestActivation(_ application: NSRunningApplication) {
            callOrder.append("activate")
            activationRequests += 1
            fireObserverInsideActivation?()
        }

        // Fallback scheduling seam.
        private(set) var fallbackDelays: [TimeInterval] = []
        private(set) var fallbackCancels = 0
        private(set) var fallbackBlocks: [@MainActor () -> Void] = []
        func scheduleFallback(_ delay: TimeInterval, fire: @escaping @MainActor () -> Void) -> () -> Void {
            callOrder.append("scheduleFallback")
            fallbackDelays.append(delay)
            fallbackBlocks.append(fire)
            return { [weak self] in
                guard let self else { return }
                self.fallbackCancels += 1
                self.callOrder.append("cancelFallback")
            }
        }
        func fireFallback(at index: Int) {
            MainActor.assumeIsolated { fallbackBlocks[index]() }
        }
        func fireLatestFallback() {
            guard let fallback = fallbackBlocks.last else { return }
            MainActor.assumeIsolated { fallback() }
        }

        // Deferred main-queue delivery seam.
        private(set) var queuedSends: [@MainActor () -> Void] = []
        func scheduleSend(_ fire: @escaping @MainActor () -> Void) {
            callOrder.append("queueSend")
            queuedSends.append(fire)
        }
        func runNextQueuedSend() {
            guard !queuedSends.isEmpty else { return }
            let queued = queuedSends.removeFirst()
            MainActor.assumeIsolated { queued() }
        }
        func runAllQueuedSends() {
            while !queuedSends.isEmpty { runNextQueuedSend() }
        }

        // Command-V recording seam (never posts real CGEvents).
        private(set) var commandVCount = 0
        func sendCommandV() {
            callOrder.append("sendCommandV")
            commandVCount += 1
        }
    }

    // MARK: - Fixture

    /// Owns an isolated store/pasteboard/defaults set. The performer is created
    /// on demand via `makePerformer()` so tests can verify weak release.
    @MainActor
    private final class Fixture {
        let seams = Seams()
        let pasteboard: NSPasteboard
        let store: ClipboardStore
        let defaults: UserDefaults
        private let suiteName: String

        init() {
            suiteName = "ClipboardPastePerformerTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            self.defaults = defaults

            let pasteboard = NSPasteboard.withUniqueName()
            pasteboard.clearContents()
            self.pasteboard = pasteboard

            seams.activeStates = [false, false]

            store = ClipboardStore(
                settings: AppSettings(defaults: defaults),
                sourceTracker: CopySourceTracker(),
                initialItems: [],
                pasteboard: pasteboard,
                persistItems: { _ in }
            )
        }

        var targetPID: pid_t { NSRunningApplication.current.processIdentifier }

        func makePerformer() -> ClipboardPastePerformer {
            let seams = self.seams
            return ClipboardPastePerformer(
                store: store,
                observeActivation: { seams.observeActivation($0) },
                isTargetActive: { seams.isTargetActive($0) },
                requestActivation: { seams.requestActivation($0) },
                scheduleFallback: { delay, fire in seams.scheduleFallback(delay, fire: fire) },
                scheduleSend: { seams.scheduleSend($0) },
                sendCommandV: { seams.sendCommandV() }
            )
        }

        deinit {
            pasteboard.releaseGlobally()
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private func textItem(text: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .text,
            title: "Test item",
            preview: text,
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            isPinned: false,
            pinboardName: nil,
            textValue: text,
            fileURLs: [],
            imageData: nil
        )
    }

    // MARK: - Activation coordination (1.2)

    @Test func targetPIDActivationQueuesSendOnNextMainQueueTurn() {
        let fixture = Fixture()
        let performer = fixture.makePerformer()

        performer.beginPasteAttempt(to: .current)
        #expect(fixture.seams.queuedSends.isEmpty, "no confirmation yet: nothing may be queued")

        fixture.seams.activateLatestApp(pid: fixture.targetPID)

        #expect(fixture.seams.commandVCount == 0, "delivery must be deferred, not inline")
        #expect(fixture.seams.queuedSends.count == 1)
        #expect(fixture.seams.observerRemovals == 1, "completion removes the observer")
        #expect(fixture.seams.fallbackCancels == 1, "completion cancels the fallback")

        fixture.seams.fireLatestFallback()
        #expect(fixture.seams.commandVCount == 0, "fallback must not paste again after confirmation")
        fixture.seams.activateLatestApp(pid: fixture.targetPID)
        #expect(fixture.seams.commandVCount == 0, "later activation must not paste again")

        fixture.seams.runAllQueuedSends()
        #expect(fixture.seams.commandVCount == 1)
    }

    @Test func wrongPIDIgnoredThenTargetPIDSends() {
        let fixture = Fixture()
        let performer = fixture.makePerformer()

        performer.beginPasteAttempt(to: .current)

        fixture.seams.activateLatestApp(pid: fixture.targetPID - 1)
        #expect(fixture.seams.queuedSends.isEmpty, "unrelated activation must not trigger Command-V")
        #expect(fixture.seams.observerRemovals == 0)
        #expect(fixture.seams.fallbackCancels == 0)

        fixture.seams.activateLatestApp(pid: fixture.targetPID)
        #expect(fixture.seams.queuedSends.count == 1, "a later activation of the intended target can still trigger Command-V")

        fixture.seams.runAllQueuedSends()
        #expect(fixture.seams.commandVCount == 1)
    }

    @Test func fallbackDelayIs350msAndPastesWithoutActivationConfirmation() {
        let fixture = Fixture()
        let performer = fixture.makePerformer()

        performer.beginPasteAttempt(to: .current)

        #expect(fixture.seams.fallbackDelays == [0.35], "fallback deadline is 350 ms")
        #expect(fixture.seams.queuedSends.isEmpty, "no confirmation yet: nothing may be queued")

        fixture.seams.fireLatestFallback()
        #expect(fixture.seams.queuedSends.count == 1)

        fixture.seams.runAllQueuedSends()
        #expect(fixture.seams.commandVCount == 1)
        #expect(fixture.seams.observerRemovals == 1, "fallback claim also removes the observer")
        #expect(fixture.seams.fallbackCancels == 1, "fallback claim cancels the timer")
    }

    @Test func alreadyActiveTargetSendsWithoutActivationEvent() {
        let fixture = Fixture()
        let performer = fixture.makePerformer()
        fixture.seams.activeStates = [true, true]

        performer.beginPasteAttempt(to: .current)

        #expect(fixture.seams.activationRequests == 1, "activation is still requested on the already-active path")
        #expect(fixture.seams.commandVCount == 0, "delivery must be deferred, not inline")
        #expect(fixture.seams.queuedSends.count == 1, "already-active target must not wait for a notification or the fallback")
        #expect(fixture.seams.observerRemovals == 1)
        #expect(fixture.seams.fallbackCancels == 1)

        fixture.seams.runAllQueuedSends()
        #expect(fixture.seams.commandVCount == 1)
    }

    @Test func activeStateRightAfterActivationQueuesSendWithoutNotification() {
        let fixture = Fixture()
        let performer = fixture.makePerformer()
        fixture.seams.activeStates = [false, true]

        performer.beginPasteAttempt(to: .current)

        #expect(fixture.seams.queuedSends.count == 1, "active-state confirmation after activation must not wait for a notification")
        #expect(fixture.seams.commandVCount == 0)

        fixture.seams.runAllQueuedSends()
        #expect(fixture.seams.commandVCount == 1)
    }

    @Test func synchronousNotificationInsideActivationRequest() {
        let fixture = Fixture()
        let performer = fixture.makePerformer()
        fixture.seams.fireObserverInsideActivation = {
            fixture.seams.activateLatestApp(pid: fixture.targetPID)
        }

        performer.beginPasteAttempt(to: .current)

        #expect(fixture.seams.observerRemovals == 1, "synchronous claim finds both cleanup handles installed")
        #expect(fixture.seams.fallbackCancels == 1)
        #expect(fixture.seams.queuedSends.count == 1)
        #expect(fixture.seams.commandVCount == 0, "must not send inline before the synchronous call returns")

        fixture.seams.fireLatestFallback()
        fixture.seams.activateLatestApp(pid: fixture.targetPID)
        #expect(fixture.seams.queuedSends.count == 1, "post-activation check must not rearm a completed attempt")

        fixture.seams.runAllQueuedSends()
        #expect(fixture.seams.commandVCount == 1)
    }

    @Test func observerAndFallbackAreInstalledBeforeActivation() {
        let fixture = Fixture()
        let performer = fixture.makePerformer()

        performer.beginPasteAttempt(to: .current)
        fixture.seams.activateLatestApp(pid: fixture.targetPID)
        fixture.seams.runAllQueuedSends()

        #expect(fixture.seams.callOrder == [
            "activeCheck",
            "observe",
            "scheduleFallback",
            "activate",
            "activeCheck",
            "removeObserver",
            "cancelFallback",
            "queueSend",
            "sendCommandV"
        ])
    }

    // MARK: - Competing callbacks and supersession (1.3)

    @Test func activationAndTimeoutCompeteSendsAtMostOnce() {
        let fixture = Fixture()
        let performer = fixture.makePerformer()

        // Activation confirms first; the later timeout must not paste again.
        performer.beginPasteAttempt(to: .current)
        fixture.seams.activateLatestApp(pid: fixture.targetPID)
        fixture.seams.fireLatestFallback()
        #expect(fixture.seams.queuedSends.count == 1, "competing callbacks queue exactly one delivery")
        fixture.seams.runAllQueuedSends()
        #expect(fixture.seams.commandVCount == 1)

        // Reverse order: the fallback claims first, a late activation is ignored.
        performer.beginPasteAttempt(to: .current)
        fixture.seams.fireLatestFallback()
        fixture.seams.activateLatestApp(pid: fixture.targetPID)
        #expect(fixture.seams.queuedSends.count == 1)
        fixture.seams.runAllQueuedSends()
        #expect(fixture.seams.commandVCount == 2, "exactly one send per attempt, at most once")
    }

    @Test func supersedingAttemptInvalidatesPendingAttempt() {
        let fixture = Fixture()
        let performer = fixture.makePerformer()
        fixture.seams.activeStates = [false, false, false, false]

        performer.beginPasteAttempt(to: .current)
        performer.beginPasteAttempt(to: .current)

        #expect(fixture.seams.observerRemovals == 1, "supersession removes the older observer")
        #expect(fixture.seams.fallbackCancels == 1, "supersession cancels the older fallback")

        fixture.seams.activateApp(at: 0, pid: fixture.targetPID)
        fixture.seams.fireFallback(at: 0)
        #expect(fixture.seams.queuedSends.isEmpty, "stale callbacks of the older attempt must not queue delivery")

        fixture.seams.activateApp(at: 1, pid: fixture.targetPID)
        #expect(fixture.seams.queuedSends.count == 1)

        fixture.seams.runAllQueuedSends()
        #expect(fixture.seams.commandVCount == 1, "only the surviving attempt sends")
    }

    @Test func supersedingAttemptInvalidatesQueuedSend() {
        let fixture = Fixture()
        let performer = fixture.makePerformer()
        fixture.seams.activeStates = [false, false, false, false]

        performer.beginPasteAttempt(to: .current)
        fixture.seams.activateLatestApp(pid: fixture.targetPID)
        performer.beginPasteAttempt(to: .current)
        fixture.seams.activateLatestApp(pid: fixture.targetPID)

        #expect(fixture.seams.queuedSends.count == 2)

        fixture.seams.runNextQueuedSend()
        #expect(fixture.seams.commandVCount == 0, "the superseded queued send must not fire")

        fixture.seams.runNextQueuedSend()
        #expect(fixture.seams.commandVCount == 1)
    }

    @Test func failedNewerRestoreSupersedesQueuedSend() {
        let fixture = Fixture()
        let performer = fixture.makePerformer()

        performer.beginPasteAttempt(to: .current)
        fixture.seams.activateLatestApp(pid: fixture.targetPID)
        #expect(fixture.seams.queuedSends.count == 1)

        let result = performer.paste(textItem(text: ""), into: .current)

        #expect(result == false)
        #expect(fixture.store.permissionMessage == "This clipboard item could not be restored.")
        #expect(fixture.seams.queuedSends.count == 1, "a failed newer request must not queue its own delivery")

        fixture.seams.runNextQueuedSend()
        #expect(fixture.seams.commandVCount == 0, "the superseded queued send must not fire")
        fixture.seams.activateLatestApp(pid: fixture.targetPID)
        fixture.seams.fireLatestFallback()
        fixture.seams.runAllQueuedSends()
        #expect(fixture.seams.commandVCount == 0, "no stale event may reach Command-V")
    }

    @Test func missingTargetFailureSupersedesPendingAttempt() {
        let fixture = Fixture()
        let performer = fixture.makePerformer()

        performer.beginPasteAttempt(to: .current)

        let result = performer.paste(textItem(text: "missing-target"), into: nil)

        #expect(result == false)
        #expect(fixture.store.permissionMessage == "The item was copied, but no target app was available to paste into.")
        #expect(fixture.pasteboard.string(forType: .string) == "missing-target", "restore happens before the missing-target failure")
        #expect(fixture.seams.observerRemovals == 1, "request entry removes the older observer")
        #expect(fixture.seams.fallbackCancels == 1, "request entry cancels the older fallback")
        #expect(fixture.seams.queuedSends.isEmpty, "the failed request must not start automatic paste")

        fixture.seams.activateLatestApp(pid: fixture.targetPID)
        fixture.seams.fireLatestFallback()
        fixture.seams.runAllQueuedSends()
        #expect(fixture.seams.commandVCount == 0)
    }

    // MARK: - Release cleanup (1.3)

    @Test func releasedPerformerCleansUpPendingAttempt() {
        let fixture = Fixture()
        weak var weakPerformer: ClipboardPastePerformer?

        do {
            let performer = fixture.makePerformer()
            weakPerformer = performer
            performer.beginPasteAttempt(to: .current)
            #expect(weakPerformer != nil)
        }

        #expect(weakPerformer == nil, "a pending attempt must not retain the performer")
        #expect(fixture.seams.observerRemovals == 1, "deinit removes the observer")
        #expect(fixture.seams.fallbackCancels == 1, "deinit cancels the fallback")

        fixture.seams.activateLatestApp(pid: fixture.targetPID)
        fixture.seams.fireLatestFallback()
        fixture.seams.runAllQueuedSends()
        #expect(fixture.seams.commandVCount == 0, "no callback from a released performer sends Command-V")
    }

    @Test func releasedPerformerCannotSendQueuedDelivery() {
        let fixture = Fixture()
        weak var weakPerformer: ClipboardPastePerformer?

        do {
            let performer = fixture.makePerformer()
            weakPerformer = performer
            performer.beginPasteAttempt(to: .current)
            fixture.seams.activateLatestApp(pid: fixture.targetPID)
            #expect(fixture.seams.queuedSends.count == 1)
        }

        #expect(weakPerformer == nil, "a queued delivery must not retain the performer")
        #expect(fixture.seams.observerRemovals == 1, "deinit removes the observer")
        #expect(fixture.seams.fallbackCancels == 1, "deinit cancels the fallback")

        fixture.seams.runAllQueuedSends()
        #expect(fixture.seams.commandVCount == 0, "the queued delivery of a released performer must not fire")
    }
}
