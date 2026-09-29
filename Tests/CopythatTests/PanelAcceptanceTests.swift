@testable import Copythat
import AppKit
import Carbon
import Foundation
import Testing

/// Unattended native-AppKit acceptance for the panel. Everything here drives
/// the production `CopythatPanel`, its real key routing, the real
/// `NSHostingView` hierarchy and the production `PanelWindowController`; only
/// platform boundaries (activation, trust check, Command-V) are injected.
@MainActor
@Suite(.serialized)
struct PanelAcceptanceTests {
    @Test func escapeClosesAndReturnPastesThroughRealKeyRouting() async throws {
        let fixture = try PanelAcceptanceFixture(items: [
            PanelAcceptanceFixture.textItem("routing paste")
        ])
        defer { fixture.cleanUp() }
        let (controller, model) = fixture.makeController()
        defer { controller.close() }
        controller.show()
        #expect(model.store.panelVisible)

        controller.panel?.sendEvent(fixture.keyEvent(keyCode: kVK_Escape, characters: "\u{1b}"))
        #expect(!model.store.panelVisible, "Escape must close the real panel")

        controller.show()
        #expect(model.store.panelVisible)
        controller.panel?.sendEvent(fixture.keyEvent(keyCode: kVK_Return, characters: "\r"))

        #expect(fixture.pasteboard.string(forType: .string) == "routing paste")
        #expect(!model.store.panelVisible, "an accepted Return paste closes the panel")
        fixture.seams.runAllQueuedSends()
        #expect(fixture.seams.commandVCount == 1)

        AcceptanceMetrics.record(
            scenario: "panel-key-routing",
            metric: "commandVSendsForAcceptedReturn",
            expected: "1",
            observed: "\(fixture.seams.commandVCount)"
        )
        AcceptanceMetrics.record(
            scenario: "panel-key-routing",
            metric: "pasteboardTextAfterReturn",
            expected: "routing paste",
            observed: fixture.pasteboard.string(forType: .string) ?? "nil"
        )
    }

    @Test func arrowKeysMoveSelectionThroughRealKeyRouting() async throws {
        let fixture = try PanelAcceptanceFixture(items: [
            PanelAcceptanceFixture.textItem("first"),
            PanelAcceptanceFixture.textItem("second"),
            PanelAcceptanceFixture.textItem("third")
        ])
        defer { fixture.cleanUp() }
        let (controller, model) = fixture.makeController()
        defer { controller.close() }
        controller.show()
        let firstID = try #require(model.store.filteredItems.first?.id)

        controller.panel?.sendEvent(fixture.keyEvent(keyCode: kVK_RightArrow, characters: "\u{f703}"))
        #expect(model.store.selectedID != firstID)
        let afterRight = model.store.selectedID

        controller.panel?.sendEvent(fixture.keyEvent(keyCode: kVK_LeftArrow, characters: "\u{f702}"))
        #expect(model.store.selectedID == firstID)
        #expect(afterRight != firstID)
    }

    @Test func doubleClickOnTheFirstCardPastesThroughTheRealGesture() async throws {
        let fixture = try PanelAcceptanceFixture(items: [
            PanelAcceptanceFixture.textItem("double click paste")
        ])
        defer { fixture.cleanUp() }
        let (controller, model) = fixture.makeController()
        defer { controller.close() }
        controller.show()
        // Let SwiftUI lay the timeline out before hit testing.
        try? await Task.sleep(nanoseconds: 150_000_000)
        let panel = try #require(controller.panel)
        panel.contentView?.layoutSubtreeIfNeeded()

        let firstCardID = try #require(model.store.filteredItems.first?.id)
        model.store.selectedID = firstCardID

        // Double-click the first card's center through the panel's normal event
        // routing so the card's production gesture wiring runs.
        let point = NSPoint(x: 140, y: panel.frame.height / 2)
        for clickCount in [1, 2] {
            panel.sendEvent(fixture.mouseEvent(.leftMouseDown, clickCount: clickCount, at: point, in: panel))
            panel.sendEvent(fixture.mouseEvent(.leftMouseUp, clickCount: clickCount, at: point, in: panel))
        }
        #expect(await fixture.waitUntil { !model.store.panelVisible })

        #expect(fixture.pasteboard.string(forType: .string) == "double click paste")
        AcceptanceMetrics.record(
            scenario: "panel-key-routing",
            metric: "pasteboardTextAfterDoubleClickGesture",
            expected: "double click paste",
            observed: fixture.pasteboard.string(forType: .string) ?? "nil"
        )
    }

    @Test func selectionSearchAndPinboardFilteringFollowTheVisibleTimeline() throws {
        let fixture = try PanelAcceptanceFixture(items: [
            PanelAcceptanceFixture.textItem("alpha"),
            PanelAcceptanceFixture.textItem("beta"),
            PanelAcceptanceFixture.pinnedItem("gamma")
        ])
        defer { fixture.cleanUp() }
        let model = fixture.makeModel()

        #expect(model.store.filteredItems.count == 3)
        model.store.searchText = "beta"
        #expect(model.store.filteredItems.map(\.textValue) == ["beta"])
        model.store.searchText = ""
        model.store.selectedBoardID = Pinboard.pinned.id
        #expect(model.store.filteredItems.map(\.textValue) == ["gamma"])
        model.store.selectedBoardID = Pinboard.all.id
        #expect(model.store.filteredItems.count == 3)
    }

    @Test func retainedPanelReopensAndInjectsTheLazyMediaLoader() async throws {
        let fixture = try PanelAcceptanceFixture(items: [
            PanelAcceptanceFixture.textItem("retained")
        ])
        defer { fixture.cleanUp() }
        let (controller, model) = fixture.makeController()
        defer { controller.close() }
        controller.show()
        let firstPanel = try #require(controller.panel)
        controller.close()
        controller.show()

        #expect(controller.panel === firstPanel, "the hosting view is retained across close")
        #expect(model.store.panelVisible)
        #expect(model.store.mediaLoader === fixture.loader)
    }

    private func keyEventUnused() {}
}

@MainActor
private final class PanelAcceptanceFixture {
    let seams = PanelAcceptanceSeams()
    let pasteboard: NSPasteboard
    let loader: ClipboardHistoryMediaLoader
    let defaults: UserDefaults
    private let suiteName: String
    private let directory: URL

    init(items: [ClipboardItem]) throws {
        suiteName = "PanelAcceptance.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("history-media", isDirectory: true),
            withIntermediateDirectories: true
        )
        loader = ClipboardHistoryMediaLoader(
            blobStore: ClipboardHistoryBlobStore(
                directoryURL: directory.appendingPathComponent("history-media", isDirectory: true),
                readData: { try Data(contentsOf: $0) }
            )
        )
        self.items = items
    }

    private let items: [ClipboardItem]

    func cleanUp() {
        pasteboard.releaseGlobally()
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    func makeModel() -> AppModel {
        AppModel(
            historySaveCoordinator: ClipboardHistorySaveCoordinator(worker: AcceptDiscardSaves()),
            pasteboard: pasteboard,
            settings: AppSettings(defaults: defaults),
            initialItems: items,
            mediaLoader: loader
        )
    }

    func makeController() -> (PanelWindowController, AppModel) {
        let model = makeModel()
        _ = NSApplication.shared
        let controller = PanelWindowController(
            model: model,
            pastePerformer: seams.makePerformer(store: model.store)
        )
        controller.pasteTargetOverride = .current
        return (controller, model)
    }

    func keyEvent(keyCode: Int, characters: String) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: UInt16(keyCode)
        )!
    }

    func mouseEvent(
        _ type: NSEvent.EventType,
        clickCount: Int,
        at point: NSPoint,
        in window: NSWindow
    ) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 1
        )!
    }

    func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return condition()
    }

    static func textItem(_ text: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .text,
            title: text,
            preview: text,
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_600),
            isPinned: false,
            pinboardName: nil,
            textValue: text,
            fileURLs: [],
            imageData: nil
        )
    }

    static func pinnedItem(_ text: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .text,
            title: text,
            preview: text,
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_601),
            isPinned: true,
            pinboardName: nil,
            textValue: text,
            fileURLs: [],
            imageData: nil
        )
    }
}

@MainActor
private final class PanelAcceptanceSeams {
    private(set) var commandVCount = 0
    private(set) var queuedSends: [@MainActor () -> Void] = []

    func makePerformer(store: ClipboardStore) -> ClipboardPastePerformer {
        ClipboardPastePerformer(
            store: store,
            observeActivation: { _ in {} },
            isTargetActive: { _ in true },
            requestActivation: { _ in },
            scheduleFallback: { _, _ in {} },
            scheduleSend: { [self] fire in
                queuedSends.append(fire)
            },
            isAccessibilityTrusted: { true },
            sendCommandV: { [self] in
                commandVCount += 1
            }
        )
    }

    func runAllQueuedSends() {
        while !queuedSends.isEmpty {
            let send = queuedSends.removeFirst()
            MainActor.assumeIsolated { send() }
        }
    }
}

private actor AcceptDiscardSaves: ClipboardHistorySaving {
    func save(_ items: [ClipboardItem], generation: UInt64) async throws {}
    func collectGarbage() async {}
}
