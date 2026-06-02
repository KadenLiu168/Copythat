import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var panelController: PanelWindowController?
    private var hotKeyManager: HotKeyManager?
    private var statusItem: NSStatusItem?
    private var statusMenuController: StatusMenuController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.sourceTracker.start()
        model.store.startMonitoring()

        let panelController = PanelWindowController(model: model)
        self.panelController = panelController
        configureStatusItem()

        hotKeyManager = HotKeyManager {
            Task { @MainActor in panelController.toggle() }
        }
        registerGlobalShortcut(named: model.settings.shortcut)
        bindSettings()

        if ProcessInfo.processInfo.environment["COPYTHAT_OPEN_PANEL_ON_LAUNCH"] == "1" {
            panelController.show()
            DispatchQueue.main.async { [weak panelController] in
                panelController?.show()
            }
        }
    }

    private func bindSettings() {
        model.settings.$shortcut
            .sink { [weak self] shortcutName in
                self?.registerGlobalShortcut(named: shortcutName)
            }
            .store(in: &cancellables)

        model.settings.$appearance
            .sink { mode in
                switch mode {
                case .system:
                    NSApp.appearance = nil
                case .light:
                    NSApp.appearance = NSAppearance(named: .aqua)
                case .dark:
                    NSApp.appearance = NSAppearance(named: .darkAqua)
                }
            }
            .store(in: &cancellables)
    }

    private func registerGlobalShortcut(named shortcutName: String) {
        guard let shortcut = AppSettings.GlobalShortcut(rawValue: shortcutName) else { return }
        let status = hotKeyManager?.register(shortcut: shortcut) ?? OSStatus(paramErr)
        model.settings.setShortcutRegistrationStatus(status)
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = CopythatIcon.statusBarImage()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        let menuController = StatusMenuController(
            showPanel: { [weak self] in self?.showPanel() },
            openSettings: { [weak self] in self?.openSettings() },
            quitApp: { [weak self] in self?.quit() }
        )

        let menu = NSMenu()
        menu.addItem(menuItem("Show Copythat", target: menuController, action: #selector(StatusMenuController.showPanel), keyEquivalent: "v", modifiers: [.command, .shift]))
        menu.addItem(menuItem("Settings...", target: menuController, action: #selector(StatusMenuController.openSettings), keyEquivalent: ",", modifiers: [.command]))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Copythat", target: menuController, action: #selector(StatusMenuController.quitApp), keyEquivalent: "q", modifiers: [.command]))

        menuController.statusItem = statusItem
        menuController.menu = menu
        statusItem.button?.target = menuController
        statusItem.button?.action = #selector(StatusMenuController.pressStatusItem)
        self.statusItem = statusItem
        statusMenuController = menuController
    }

    private func menuItem(
        _ title: String,
        target: AnyObject,
        action: Selector,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    @objc func showPanel() {
        panelController?.show()
    }

    @objc func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }
}

private final class StatusMenuController: NSObject {
    weak var statusItem: NSStatusItem?
    var menu: NSMenu?

    private let showPanelAction: () -> Void
    private let openSettingsAction: () -> Void
    private let quitAppAction: () -> Void

    init(showPanel: @escaping () -> Void, openSettings: @escaping () -> Void, quitApp: @escaping () -> Void) {
        showPanelAction = showPanel
        openSettingsAction = openSettings
        quitAppAction = quitApp
    }

    @objc func pressStatusItem(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp, let menu {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
        } else {
            showPanelAction()
        }
    }

    @objc func showPanel(_ sender: NSMenuItem) {
        showPanelAction()
    }

    @objc func openSettings(_ sender: NSMenuItem) {
        openSettingsAction()
    }

    @objc func quitApp(_ sender: NSMenuItem) {
        quitAppAction()
    }
}
