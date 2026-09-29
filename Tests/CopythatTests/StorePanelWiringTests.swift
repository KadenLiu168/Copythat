@testable import Copythat
import AppKit
import CryptoKit
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
        let panel = controller.panel
        #expect(panel?.isVisible == true)
        controller.close()
        #expect(!model.store.panelVisible)
        #expect(panel?.isVisible == false)
        controller.show()
        #expect(model.store.panelVisible)
        #expect(panel?.isVisible == true)
        controller.close()
        #expect(!model.store.panelVisible)
        #expect(panel?.isVisible == false)
    }

    @Test func appModelFeedsTheStoreMediaLoaderBoundToTheFixtureDirectory() async throws {
        let defaultsName = "PanelMedia.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(defaultsName)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = ClipboardHistoryPersistence(directoryURL: directory, userDefaults: defaults)
        let model = AppModel(
            historySaveCoordinator: ClipboardHistorySaveCoordinator(worker: ClipboardHistorySaveWorker(
                persistence: persistence
            )),
            pasteboard: NSPasteboard.withUniqueName(),
            settings: AppSettings(defaults: defaults), initialItems: [],
            mediaLoader: ClipboardHistoryMediaLoader(blobStore: persistence.blobStore)
        )
        let bytes = Data(repeating: 0x71, count: 512)
        let blobID = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let mediaDirectory = directory.appendingPathComponent("history-media", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        try bytes.write(to: mediaDirectory.appendingPathComponent("\(blobID).blob"))

        _ = NSApplication.shared
        let controller = PanelWindowController(model: model)
        controller.show()
        controller.close()

        // Resolves only in the fixture directory; the shared history loader
        // could never return these bytes.
        #expect(try await model.store.mediaLoader.load(blobID: blobID) == bytes)
    }

    private final class BlobReadCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func record() {
            lock.lock()
            value += 1
            lock.unlock()
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private func waitUntil(
        timeout seconds: TimeInterval,
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return condition()
    }

    @Test func retainedPanelVisibilityDrivesAndRevokesRealCardMediaTasks() async throws {
        let defaultsName = "PanelLazyMedia.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(defaultsName)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = ClipboardHistoryPersistence(directoryURL: directory, userDefaults: defaults)
        let reads = BlobReadCounter()
        let mediaDirectory = directory.appendingPathComponent("history-media", isDirectory: true)
        let loader = ClipboardHistoryMediaLoader(
            blobStore: ClipboardHistoryBlobStore(
                directoryURL: mediaDirectory,
                readData: { url in
                    reads.record()
                    return try Data(contentsOf: url)
                }
            )
        )
        let bytes = Data(repeating: 0x81, count: 1_024)
        let blobID = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        try bytes.write(to: mediaDirectory.appendingPathComponent("\(blobID).blob"))
        let item = ClipboardItem(
            id: UUID(),
            kind: .image,
            title: "Image",
            preview: "64 x 64",
            sourceApp: "Preview",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_400),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: nil,
            imageBlobID: blobID
        )
        let model = AppModel(
            historySaveCoordinator: ClipboardHistorySaveCoordinator(worker: ClipboardHistorySaveWorker(
                persistence: persistence
            )),
            pasteboard: NSPasteboard.withUniqueName(),
            settings: AppSettings(defaults: defaults),
            initialItems: [item],
            mediaLoader: loader
        )
        _ = NSApplication.shared
        let controller = PanelWindowController(model: model)
        defer { controller.close() }

        controller.show()
        #expect(await waitUntil(timeout: 3) { reads.count >= 1 })
        let readsWhileVisible = reads.count

        // The hosting view stays retained across close: no further loads may
        // start while the panel is hidden.
        controller.close()
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(reads.count == readsWhileVisible)
        AcceptanceMetrics.record(
            scenario: "panel-wiring",
            metric: "mediaReadsWhileRetainedPanelHidden",
            expected: "0",
            observed: "\(reads.count - readsWhileVisible)"
        )
        AcceptanceMetrics.record(
            scenario: "panel-wiring",
            metric: "mediaReadsForVisibleCard",
            expected: ">=1",
            observed: "\(readsWhileVisible)"
        )

        // Reopening under a newer authorization generation loads again, but a
        // cached blob means the count may stay put; what matters is that the
        // first visible card task ran and the hidden panel added nothing.
        controller.show()
        #expect(model.store.panelVisible)
        #expect(await waitUntil(timeout: 3) { reads.count >= 1 })
        #expect(reads.count >= readsWhileVisible)
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
