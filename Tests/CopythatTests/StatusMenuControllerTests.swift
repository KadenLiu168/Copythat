@testable import Copythat
import AppKit
import Testing

@MainActor
struct StatusMenuControllerTests {
    @Test func settingsMenuItemInvokesOpenSettingsAction() {
        var openSettingsCount = 0
        let controller = StatusMenuController(
            showPanel: {},
            openSettings: { openSettingsCount += 1 },
            quitApp: {}
        )

        controller.openSettings(NSMenuItem())

        #expect(openSettingsCount == 1)
    }

    @Test func settingsWindowControllerCreatesSettingsWindow() {
        let controller = SettingsWindowController(settings: AppSettings())
        let window = controller.window

        #expect(window?.title == "Settings")
        #expect(window?.contentLayoutRect.width == 520)
        #expect(window?.contentLayoutRect.height == 420)
        #expect(window?.contentView != nil)
    }
}
