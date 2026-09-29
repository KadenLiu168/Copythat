import AppKit
import ApplicationServices
import Carbon
import Foundation

enum PasteDecision: Equatable {
    case showRestoreFailure
    case showMissingTarget
    case showAccessibilityFailure
    case sendPaste
}

func pasteDecision(didWrite: Bool, hasTargetApp: Bool, accessibilityTrusted: Bool) -> PasteDecision {
    guard didWrite else {
        return .showRestoreFailure
    }
    guard hasTargetApp else {
        return .showMissingTarget
    }
    guard accessibilityTrusted else {
        return .showAccessibilityFailure
    }
    return .sendPaste
}

@MainActor
final class ClipboardPastePerformer {
    /// Compatibility fallback: attempts Command-V without activation
    /// confirmation, matching the pre-coordination behavior.
    static let fallbackDelay: TimeInterval = 0.35

    private let store: ClipboardStore
    private let observeActivation: (@escaping @MainActor (pid_t) -> Void) -> () -> Void
    private let isTargetActive: (NSRunningApplication) -> Bool
    private let requestActivation: (NSRunningApplication) -> Void
    private let scheduleFallback: (TimeInterval, @escaping @MainActor () -> Void) -> () -> Void
    private let scheduleSend: (@escaping @MainActor () -> Void) -> Void
    private let isAccessibilityTrusted: () -> Bool
    private let sendCommandV: () -> Void

    private struct PendingAttempt {
        let token: Int
        let removeObserver: () -> Void
        let cancelFallback: () -> Void
    }

    /// At most one pending paste attempt; a new `paste()` request supersedes it.
    private var pendingAttempt: PendingAttempt?
    /// Monotonic attempt tokens; also invalidates queued-but-unsent deliveries.
    private var attemptGeneration = 0

    init(
        store: ClipboardStore,
        observeActivation: @escaping (@escaping @MainActor (pid_t) -> Void) -> () -> Void = ClipboardPastePerformer.defaultObserveActivation,
        isTargetActive: @escaping (NSRunningApplication) -> Bool = { $0.isActive },
        requestActivation: @escaping (NSRunningApplication) -> Void = { $0.activate(options: [.activateAllWindows]) },
        scheduleFallback: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> () -> Void = ClipboardPastePerformer.defaultScheduleFallback,
        scheduleSend: @escaping (@escaping @MainActor () -> Void) -> Void = ClipboardPastePerformer.defaultScheduleSend,
        isAccessibilityTrusted: @escaping () -> Bool = AccessibilityService.requestIfNeeded,
        sendCommandV: @escaping () -> Void = ClipboardPastePerformer.defaultSendCommandV
    ) {
        self.store = store
        self.observeActivation = observeActivation
        self.isTargetActive = isTargetActive
        self.requestActivation = requestActivation
        self.scheduleFallback = scheduleFallback
        self.scheduleSend = scheduleSend
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.sendCommandV = sendCommandV
    }

    func paste(_ item: ClipboardItem, into targetApp: NSRunningApplication?) -> Bool {
        supersedePendingAttempt()
        store.clearPermissionMessage()
        let didWrite = store.writeToPasteboard(item)
        let hasTargetApp = targetApp != nil
        let accessibilityTrusted = didWrite && hasTargetApp && isAccessibilityTrusted()

        switch pasteDecision(
            didWrite: didWrite,
            hasTargetApp: hasTargetApp,
            accessibilityTrusted: accessibilityTrusted
        ) {
        case .showRestoreFailure:
            store.permissionMessage = "This clipboard item could not be restored."
            return false
        case .showMissingTarget:
            store.permissionMessage = "The item was copied, but no target app was available to paste into."
            return false
        case .showAccessibilityFailure:
            store.permissionMessage = "Accessibility permission is off. The item was copied to the clipboard."
            return false
        case .sendPaste:
            guard let targetApp else { return false }
            beginPasteAttempt(to: targetApp)
            return true
        }
    }

    /// Coordinates activation confirmation and the 350 ms fallback for one
    /// paste attempt. Shared by `paste()` and by deterministic tests, which
    /// exercise successful coordination without the restore/Accessibility gates.
    func beginPasteAttempt(to targetApp: NSRunningApplication) {
        supersedePendingAttempt()
        attemptGeneration += 1
        let token = attemptGeneration
        let targetPID = targetApp.processIdentifier

        // Records pre-activation readiness so an already-active target does not
        // wait for a notification edge that will never arrive.
        let wasActive = isTargetActive(targetApp)

        // Install both cleanup handles before requesting activation so a
        // notification delivered synchronously inside activate() finds them.
        let removeObserver = observeActivation { [weak self] activatedPID in
            guard let self, activatedPID == targetPID else { return }
            self.completeAttempt(token: token)
        }
        let cancelFallback = scheduleFallback(Self.fallbackDelay) { [weak self] in
            self?.completeAttempt(token: token)
        }
        pendingAttempt = PendingAttempt(
            token: token,
            removeObserver: removeObserver,
            cancelFallback: cancelFallback
        )

        // Keep the activation request even on the already-active path.
        requestActivation(targetApp)

        // Delivery is claimed only after the activation request was made: an
        // already-active or synchronously activated target must not wait out
        // the fallback, and a completed attempt must not be rearmed.
        let activeAfterActivation = isTargetActive(targetApp)
        if wasActive || activeAfterActivation {
            completeAttempt(token: token)
        }
    }

    /// Single token-checked completion: atomically claims the attempt, cleans
    /// up observer and fallback, then queues one deferred key event.
    private func completeAttempt(token: Int) {
        guard let attempt = pendingAttempt, attempt.token == token else { return }
        pendingAttempt = nil
        attempt.removeObserver()
        attempt.cancelFallback()
        scheduleSend { [weak self] in
            // Recheck at delivery: a newer paste() request invalidates this.
            guard let self, self.attemptGeneration == token else { return }
            self.sendCommandV()
        }
    }

    /// Cancels any pending activation/fallback coordination without sending.
    /// A new paste request calls this as it starts, so an attempt queued by an
    /// older request cannot fire while the newer one still materializes media.
    func supersedePendingAttempt() {
        attemptGeneration += 1
        guard let attempt = pendingAttempt else { return }
        pendingAttempt = nil
        attempt.removeObserver()
        attempt.cancelFallback()
    }

    deinit {
        pendingAttempt?.removeObserver()
        pendingAttempt?.cancelFallback()
        pendingAttempt = nil
    }

    // MARK: - Production seams

    private nonisolated static func defaultObserveActivation(
        _ callback: @escaping @MainActor (pid_t) -> Void
    ) -> () -> Void {
        let center = NSWorkspace.shared.notificationCenter
        let observer = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let activatedPID = application?.processIdentifier ?? 0
            MainActor.assumeIsolated {
                callback(activatedPID)
            }
        }
        return { center.removeObserver(observer) }
    }

    private nonisolated static func defaultScheduleFallback(
        _ delay: TimeInterval,
        _ fire: @escaping @MainActor () -> Void
    ) -> () -> Void {
        let workItem = DispatchWorkItem {
            MainActor.assumeIsolated {
                fire()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        return { workItem.cancel() }
    }

    private nonisolated static func defaultScheduleSend(
        _ fire: @escaping @MainActor () -> Void
    ) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                fire()
            }
        }
    }

    private nonisolated static func defaultSendCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
