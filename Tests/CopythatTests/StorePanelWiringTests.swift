@testable import Copythat
import AppKit
import Foundation
import Testing

@MainActor
struct StorePanelWiringTests {
    @Test func realPanelControllerShowCloseUpdatesStoreVisibility() {
        let defaultsName = "PanelSmoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(defaultsName)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(
            historySaveCoordinator: ClipboardHistorySaveCoordinator(worker: ClipboardHistorySaveWorker(
                persistence: ClipboardHistoryPersistence(directoryURL: directory, userDefaults: defaults)
            )),
            pasteboard: NSPasteboard.withUniqueName(),
            settings: AppSettings(defaults: defaults), initialItems: []
        )
        _ = NSApplication.shared
        let controller = PanelWindowController(model: model)
        #expect(!model.store.panelVisible)
        controller.show()
        #expect(model.store.panelVisible)
        #expect(NSApp.windows.contains { $0.title == "Copythat" && $0.isVisible })
        controller.close()
        #expect(!model.store.panelVisible)
        #expect(!NSApp.windows.contains { $0.title == "Copythat" && $0.isVisible })
        controller.show()
        #expect(model.store.panelVisible)
        controller.close()
        #expect(!model.store.panelVisible)
    }

    private struct WiringFacts {
        let showCallsPanelDidOpenAfterOrderFront: Bool
        let closeCallsPanelDidCloseBeforeOrderOut: Bool
        let selectionPrecedesVisibility: Bool
    }

    @Test func panelControllerDrivesStoreVisibilityInShowCloseOrder() throws {
        // The window lifecycle boundary lives in PanelWindowController: show()
        // finishes the display order (selection already refreshed) and then
        // authorizes fallback evaluation; close() revokes eligibility before
        // the window is ordered out so NSHostingView retention cannot keep a
        // fallback alive.
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Copythat/Services/PanelWindowController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        guard let showRange = source.range(of: "func show()"),
              let closeRange = source.range(of: "func close()"),
              let orderFrontRange = source.range(of: "panel.orderFrontRegardless()"),
              let panelDidOpenRange = source.range(of: "model.store.panelDidOpen()"),
              let panelDidCloseRange = source.range(of: "model.store.panelDidClose()"),
              let orderOutRange = source.range(of: "panel?.orderOut(nil)"),
              let selectFirstRange = source.range(of: "model.store.selectFirstVisibleItem()") else {
            Issue.record("PanelWindowController is missing its visibility wiring")
            return
        }

        let facts = WiringFacts(
            showCallsPanelDidOpenAfterOrderFront: orderFrontRange.lowerBound < panelDidOpenRange.lowerBound,
            closeCallsPanelDidCloseBeforeOrderOut: panelDidCloseRange.lowerBound < orderOutRange.lowerBound,
            selectionPrecedesVisibility: selectFirstRange.lowerBound < panelDidOpenRange.lowerBound
        )

        #expect(facts.showCallsPanelDidOpenAfterOrderFront)
        #expect(facts.closeCallsPanelDidCloseBeforeOrderOut)
        #expect(facts.selectionPrecedesVisibility)
        #expect(source.contains("func toggle()"))
        #expect(!source.contains("linkPreview"))
    }
}
