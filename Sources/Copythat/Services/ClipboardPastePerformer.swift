import AppKit
import ApplicationServices
import Carbon
import Foundation

@MainActor
final class ClipboardPastePerformer {
    private let store: ClipboardStore

    init(store: ClipboardStore) {
        self.store = store
    }

    func paste(_ item: ClipboardItem, into targetApp: NSRunningApplication?) -> Bool {
        store.clearPermissionMessage()
        guard store.writeToPasteboard(item) else {
            store.permissionMessage = "This clipboard item could not be restored."
            return false
        }
        guard let targetApp else {
            store.permissionMessage = "The item was copied, but no target app was available to paste into."
            return false
        }
        guard AccessibilityService.requestIfNeeded() else {
            store.permissionMessage = "Accessibility permission is off. The item was copied to the clipboard."
            return false
        }

        targetApp.activate(options: [.activateAllWindows])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.sendCommandV()
        }
        return true
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
