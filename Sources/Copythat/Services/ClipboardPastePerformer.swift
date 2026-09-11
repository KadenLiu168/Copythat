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
    private let store: ClipboardStore

    init(store: ClipboardStore) {
        self.store = store
    }

    func paste(_ item: ClipboardItem, into targetApp: NSRunningApplication?) -> Bool {
        store.clearPermissionMessage()
        let didWrite = store.writeToPasteboard(item)
        let hasTargetApp = targetApp != nil
        let accessibilityTrusted = didWrite && hasTargetApp && AccessibilityService.requestIfNeeded()

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
            targetApp.activate(options: [.activateAllWindows])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.sendCommandV()
            }
            return true
        }
    }

    private func sendCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
