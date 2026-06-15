import AppKit
import Carbon
import SwiftUI

@MainActor
final class PanelWindowController {
    private let model: AppModel
    private let pastePerformer: ClipboardPastePerformer
    private var panel: CopythatPanel?
    private var targetApp: NSRunningApplication?

    init(model: AppModel) {
        self.model = model
        pastePerformer = ClipboardPastePerformer(store: model.store)
    }

    func toggle() {
        if panel?.isVisible == true {
            close()
        } else {
            show()
        }
    }

    func show() {
        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
           isPasteTargetCandidate(frontmostApplication) {
            targetApp = frontmostApplication
        }
        model.store.clearPermissionMessage()
        model.store.pollPasteboard()
        model.store.selectFirstVisibleItem()

        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func pasteSelected() {
        guard let selected = model.store.selectedItem else { return }
        if pastePerformer.paste(selected, into: targetApp) {
            close()
        }
    }

    private func makePanel() -> CopythatPanel {
        let panel = CopythatPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 342),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.title = "Copythat"
        panel.onPaste = { [weak self] in self?.pasteSelected() }
        panel.onClosePanel = { [weak self] in self?.close() }
        panel.onMoveSelection = { [weak self] delta in self?.model.store.moveSelection(delta) }

        let view = BottomPanelView(
            model: model,
            onClose: { [weak self] in self?.close() },
            onPaste: { [weak self] in self?.pasteSelected() }
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        panel.contentView = hostingView
        return panel
    }

    private func position(_ panel: NSPanel) {
        let screen = screenContainingMouse() ?? NSScreen.main
        guard let screen else { return }
        panel.setFrame(
            PanelFrameCalculator.frame(
                screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame,
                prefersScreenBottomAnchor: targetAppTouchesScreenBottom(on: screen)
            ),
            display: true
        )
    }

    private func targetAppTouchesScreenBottom(on screen: NSScreen) -> Bool {
        guard let targetApp else { return false }

        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == targetApp.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"],
                  let y = bounds["Y"],
                  let width = bounds["Width"],
                  let height = bounds["Height"] else {
                return false
            }

            let frame = CGRect(
                x: x,
                y: screen.frame.maxY - y - height,
                width: width,
                height: height
            )

            return frame.intersects(screen.frame) &&
                frame.minY <= screen.frame.minY + 1 &&
                frame.width >= screen.frame.width * 0.6 &&
                frame.height >= screen.frame.height * 0.5
        }
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
    }

    private func isPasteTargetCandidate(_ application: NSRunningApplication) -> Bool {
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return false
        }
        switch application.bundleIdentifier {
        case Bundle.main.bundleIdentifier, "com.apple.systemuiserver":
            return false
        default:
            return true
        }
    }
}

final class CopythatPanel: NSPanel {
    var onPaste: (() -> Void)?
    var onClosePanel: (() -> Void)?
    var onMoveSelection: ((Int) -> Void)?

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        isMovable = false
        isMovableByWindowBackground = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleKeyEvent(event) {
            return
        }
        super.sendEvent(event)
    }

    override func keyDown(with event: NSEvent) {
        if handleKeyEvent(event) {
            return
        }
        super.keyDown(with: event)
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            onPaste?()
            return true
        case kVK_Escape:
            onClosePanel?()
            return true
        case kVK_LeftArrow:
            onMoveSelection?(-1)
            return true
        case kVK_RightArrow:
            onMoveSelection?(1)
            return true
        default:
            return false
        }
    }
}
