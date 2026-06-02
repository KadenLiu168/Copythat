import Carbon
import Foundation

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    deinit {
        unregister()
    }

    func register(shortcut: AppSettings.GlobalShortcut) -> OSStatus {
        unregister()

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.action()
            }
            return noErr
        }, 1, &eventType, selfPointer, &eventHandler)
        guard installStatus == noErr else {
            eventHandler = nil
            return installStatus
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x50535445), id: 1)
        let registerStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            unregister()
            return registerStatus
        }

        return noErr
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}

extension AppSettings.GlobalShortcut {
    var keyCode: UInt32 {
        switch self {
        case .commandShiftV:
            UInt32(kVK_ANSI_V)
        case .optionSpace, .controlSpace:
            UInt32(kVK_Space)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .commandShiftV:
            UInt32(cmdKey | shiftKey)
        case .optionSpace:
            UInt32(optionKey)
        case .controlSpace:
            UInt32(controlKey)
        }
    }
}
