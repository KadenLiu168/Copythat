@testable import Copythat
import AppKit
import CryptoKit
import Foundation
import Testing

/// Platform seams for the paste performer so these tests never post real
/// Command-V events, never activate another app, and never wait out the
/// 350 ms fallback.
@MainActor
private final class PastePlatformSeams {
    private(set) var commandVCount = 0
    private(set) var queuedSends: [@MainActor () -> Void] = []
    private(set) var fallbackBlocks: [@MainActor () -> Void] = []
    private(set) var activationCallbacks: [@MainActor (pid_t) -> Void] = []
    var activeStates: [Bool] = []
    var accessibilityTrusted = true

    func makePerformer(store: ClipboardStore) -> ClipboardPastePerformer {
        ClipboardPastePerformer(
            store: store,
            observeActivation: { [self] callback in
                activationCallbacks.append(callback)
                return {}
            },
            isTargetActive: { [self] _ in
                guard !activeStates.isEmpty else { return false }
                return activeStates.removeFirst()
            },
            requestActivation: { _ in },
            scheduleFallback: { [self] _, fire in
                fallbackBlocks.append(fire)
                return {}
            },
            scheduleSend: { [self] fire in
                queuedSends.append(fire)
            },
            isAccessibilityTrusted: { [self] in
                accessibilityTrusted
            },
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

    func fireLatestFallback() {
        guard let fallback = fallbackBlocks.last else { return }
        MainActor.assumeIsolated { fallback() }
    }
}

@MainActor
private final class PasteMaterializationFixture {
    let seams = PastePlatformSeams()
    let loaderReads = ReadCounter()
    let loader: ClipboardHistoryMediaLoader
    let pasteboard: NSPasteboard
    let defaults: UserDefaults
    let directory: URL
    private let suiteName: String
    private let mediaDirectory: URL
    var gate: DispatchSemaphore?
    private var firstReadStarted: DispatchSemaphore?
    private var didBlockFirstRead = false

    init(blockFirstRead: Bool = false) throws {
        suiteName = "PasteMaterialization.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName)
        mediaDirectory = directory.appendingPathComponent("history-media", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        if blockFirstRead {
            gate = DispatchSemaphore(value: 0)
            firstReadStarted = DispatchSemaphore(value: 0)
        }
        let reads = loaderReads
        let started = firstReadStarted
        let gate = self.gate
        loader = ClipboardHistoryMediaLoader(
            blobStore: ClipboardHistoryBlobStore(
                directoryURL: mediaDirectory,
                readData: { url in
                    let shouldBlock = reads.beginRead(gate: gate, started: started)
                    defer { _ = shouldBlock }
                    return try Data(contentsOf: url)
                }
            )
        )
    }

    func cleanUp() {
        pasteboard.releaseGlobally()
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    func writeBlob(_ data: Data) -> String {
        let blobID = sha256Hex(data)
        try? data.write(to: mediaDirectory.appendingPathComponent("\(blobID).blob"))
        return blobID
    }

    func makeStore(items: [ClipboardItem]) -> ClipboardStore {
        ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: items,
            pasteboard: pasteboard,
            mediaLoader: loader,
            persistItems: { _ in }
        )
    }

    func makeModel(items: [ClipboardItem]) -> AppModel {
        AppModel(
            historySaveCoordinator: ClipboardHistorySaveCoordinator(worker: DiscardPasteSaves()),
            pasteboard: pasteboard,
            settings: AppSettings(defaults: defaults),
            initialItems: items,
            mediaLoader: loader
        )
    }

    func waitForFirstRead() async {
        guard let firstReadStarted else { return }
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                _ = firstReadStarted.wait(timeout: .now() + 5)
                continuation.resume()
            }
        }
    }

    func releaseFirstRead() {
        gate?.signal()
    }

    func imageItem(id: UUID = UUID(), blobID: String) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: .image,
            title: "Image",
            preview: "64 x 64",
            sourceApp: "Preview",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_500),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: nil,
            imageBlobID: blobID
        )
    }

    func textItem(_ text: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .text,
            title: text,
            preview: text,
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_501),
            isPinned: false,
            pinboardName: nil,
            textValue: text,
            fileURLs: [],
            imageData: nil
        )
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func sha256Hex(_ data: Data) -> String {
        Self.sha256Hex(data)
    }

    static func imagePNG(red: Bool) -> Data? {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 32,
            pixelsHigh: 32,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let color = red
            ? NSColor(calibratedRed: 0.85, green: 0.1, blue: 0.1, alpha: 1)
            : NSColor(calibratedRed: 0.1, green: 0.2, blue: 0.85, alpha: 1)
        for x in 0..<32 {
            for y in 0..<32 {
                bitmap.setColor(color, atX: x, y: y)
            }
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return condition()
    }

    func settle(iterations: Int = 8) async {
        for _ in 0..<iterations {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

private final class ReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    private var didBlockFirst = false

    func beginRead(gate: DispatchSemaphore?, started: DispatchSemaphore?) -> Bool {
        lock.lock()
        value += 1
        let shouldBlock = !didBlockFirst && gate != nil
        if shouldBlock {
            didBlockFirst = true
        }
        lock.unlock()
        if shouldBlock, let gate, let started {
            started.signal()
            _ = gate.wait(timeout: .now() + 5)
        }
        return shouldBlock
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private actor DiscardPasteSaves: ClipboardHistorySaving {
    func save(_ items: [ClipboardItem], generation: UInt64) async throws {}
    func collectGarbage() async {}
}

@MainActor
@Suite(.serialized)
struct PanelPasteMaterializationTests {
    // MARK: - Store materialization

    @Test func lazyImageMaterializesIntoATemporaryVerifiedItem() async throws {
        let fixture = try PasteMaterializationFixture()
        defer { fixture.cleanUp() }
        let bytes = try #require(PasteMaterializationFixture.imagePNG(red: true))
        let blobID = fixture.writeBlob(bytes)
        let item = fixture.imageItem(blobID: blobID)
        let store = fixture.makeStore(items: [item])
        let originalItems = store.items
        let originalSelection = store.selectedID

        let materialized = try await store.materializedItemForPaste(item)

        #expect(materialized.imageData == bytes)
        #expect(materialized.imageBlobID == blobID)
        #expect(materialized.id == item.id)
        #expect(materialized.kind == item.kind)
        #expect(materialized.createdAt == item.createdAt)
        #expect(store.items == originalItems)
        #expect(store.items.first?.imageData == nil)
        #expect(store.selectedID == originalSelection)

        #expect(store.writeToPasteboard(materialized))
        let pastedImage = try #require(
            (fixture.pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.first
        )
        #expect(pastedImage.size == NSSize(width: 32, height: 32))
    }

    @Test func materializationFailsForMissingCorruptAndUndecodableMedia() async throws {
        let fixture = try PasteMaterializationFixture()
        defer { fixture.cleanUp() }
        fixture.pasteboard.clearContents()
        fixture.pasteboard.setString("sentinel", forType: .string)
        let store = fixture.makeStore(items: [])
        let bytes = try #require(PasteMaterializationFixture.imagePNG(red: true))

        let missingID = fixture.sha256Hex(Data(repeating: 0x11, count: 64))
        await #expect(throws: (any Error).self) {
            try await store.materializedItemForPaste(fixture.imageItem(blobID: missingID))
        }

        let corruptID = fixture.writeBlob(bytes)
        try Data([0x00]).write(to: fixture.directory
            .appendingPathComponent("history-media", isDirectory: true)
            .appendingPathComponent("\(corruptID).blob"))
        await #expect(throws: (any Error).self) {
            try await store.materializedItemForPaste(fixture.imageItem(blobID: corruptID))
        }

        let undecodableID = fixture.writeBlob(Data(repeating: 0x42, count: 128))
        await #expect(throws: ClipboardPasteMaterializationError.self) {
            try await store.materializedItemForPaste(fixture.imageItem(blobID: undecodableID))
        }

        #expect(fixture.pasteboard.string(forType: .string) == "sentinel")
        #expect(fixture.loaderReads.count == 3)
    }

    @Test func nonImageAndResidentItemsKeepTheSynchronousFastPath() async throws {
        let fixture = try PasteMaterializationFixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore(items: [])
        let text = fixture.textItem("fast path")
        let residentImage = ClipboardItem(
            id: UUID(),
            kind: .image,
            title: "Image",
            preview: "1 x 1",
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_502),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: Data([1, 2, 3])
        )

        #expect(try await store.materializedItemForPaste(text) == text)
        #expect(try await store.materializedItemForPaste(residentImage) == residentImage)
        #expect(fixture.loaderReads.count == 0)
    }

    // MARK: - Controller pending materialization

    @Test func closingThePanelDuringMaterializationWritesNothing() async throws {
        let fixture = try PasteMaterializationFixture(blockFirstRead: true)
        defer { fixture.cleanUp() }
        let bytes = try #require(PasteMaterializationFixture.imagePNG(red: true))
        let blobID = fixture.writeBlob(bytes)
        let model = fixture.makeModel(items: [fixture.imageItem(blobID: blobID)])
        _ = NSApplication.shared
        let controller = PanelWindowController(
            model: model,
            pastePerformer: fixture.seams.makePerformer(store: model.store)
        )
        controller.show()
        let changeCountBefore = fixture.pasteboard.changeCount

        controller.panel?.onPaste?()
        await fixture.waitForFirstRead()

        // Escape / close while media is still loading.
        controller.close()
        fixture.releaseFirstRead()
        await fixture.settle()

        #expect(fixture.pasteboard.changeCount == changeCountBefore)
        #expect(fixture.seams.commandVCount == 0)
        #expect(fixture.seams.queuedSends.isEmpty)

        AcceptanceMetrics.record(
            scenario: "paste-materialization",
            metric: "pasteboardWritesAfterCloseDuringMaterialization",
            expected: "0",
            observed: "\(fixture.pasteboard.changeCount - changeCountBefore)"
        )
        AcceptanceMetrics.record(
            scenario: "paste-materialization",
            metric: "commandVSendsAfterCloseDuringMaterialization",
            expected: "0",
            observed: "\(fixture.seams.commandVCount)"
        )
    }

    @Test func newestPasteWinsEvenWhenTheOlderRequestCompletesLast() async throws {
        let fixture = try PasteMaterializationFixture(blockFirstRead: true)
        defer { fixture.cleanUp() }
        let firstBytes = try #require(PasteMaterializationFixture.imagePNG(red: true))
        let secondBytes = try #require(PasteMaterializationFixture.imagePNG(red: false))
        let firstBlobID = fixture.writeBlob(firstBytes)
        let secondBlobID = fixture.writeBlob(secondBytes)
        let firstItem = fixture.imageItem(blobID: firstBlobID)
        let secondItem = fixture.imageItem(blobID: secondBlobID)
        let model = fixture.makeModel(items: [firstItem, secondItem])
        _ = NSApplication.shared
        let controller = PanelWindowController(
            model: model,
            pastePerformer: fixture.seams.makePerformer(store: model.store)
        )
        controller.pasteTargetOverride = .current
        controller.show()
        // The target confirms activation for whichever request hands off.
        fixture.seams.activeStates = [true, true]

        // Request A blocks in its first read.
        model.store.selectedID = firstItem.id
        controller.panel?.onPaste?()
        await fixture.waitForFirstRead()

        // Request B supersedes A while A is still loading.
        model.store.selectedID = secondItem.id
        controller.panel?.onPaste?()

        fixture.releaseFirstRead()
        await fixture.waitUntil { fixture.seams.queuedSends.count >= 1 }
        fixture.seams.runAllQueuedSends()
        await fixture.settle()

        let pasted = try #require(
            (fixture.pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.first
        )
        #expect(pasted.size == NSSize(width: 32, height: 32))
        #expect(fixture.seams.commandVCount == 1)
        AcceptanceMetrics.record(
            scenario: "paste-materialization",
            metric: "commandVSendsForNewestRequestOnly",
            expected: "1",
            observed: "\(fixture.seams.commandVCount)"
        )
    }

    @Test func releasingTheControllerWhileLoadingStopsDelivery() async throws {
        let fixture = try PasteMaterializationFixture(blockFirstRead: true)
        defer { fixture.cleanUp() }
        let bytes = try #require(PasteMaterializationFixture.imagePNG(red: true))
        let blobID = fixture.writeBlob(bytes)
        let model = fixture.makeModel(items: [fixture.imageItem(blobID: blobID)])
        _ = NSApplication.shared
        var controller: PanelWindowController? = PanelWindowController(
            model: model,
            pastePerformer: fixture.seams.makePerformer(store: model.store)
        )
        weak var weakController = controller
        controller?.show()
        let changeCountBefore = fixture.pasteboard.changeCount

        controller?.panel?.onPaste?()
        await fixture.waitForFirstRead()

        controller = nil
        #expect(weakController == nil, "the pending task must not keep the controller alive")

        fixture.releaseFirstRead()
        await fixture.settle()

        #expect(fixture.pasteboard.changeCount == changeCountBefore)
        #expect(fixture.seams.commandVCount == 0)
        #expect(fixture.seams.queuedSends.isEmpty)
    }

    @Test func currentFailureKeepsTheExistingRestoreMessage() async throws {
        let fixture = try PasteMaterializationFixture()
        defer { fixture.cleanUp() }
        let missingID = fixture.sha256Hex(Data(repeating: 0x22, count: 64))
        let model = fixture.makeModel(items: [fixture.imageItem(blobID: missingID)])
        _ = NSApplication.shared
        let controller = PanelWindowController(
            model: model,
            pastePerformer: fixture.seams.makePerformer(store: model.store)
        )
        controller.show()
        let changeCountBefore = fixture.pasteboard.changeCount

        controller.panel?.onPaste?()
        #expect(await fixture.waitUntil { model.store.permissionMessage != nil })

        #expect(model.store.permissionMessage == "This clipboard item could not be restored.")
        #expect(model.store.panelVisible)
        #expect(fixture.pasteboard.changeCount == changeCountBefore)
        #expect(fixture.seams.commandVCount == 0)
    }

    // MARK: - Injected permission and target acceptance

    @Test func injectedTrustCheckDrivesTheRealPasteDecisionWithoutPrompting() async throws {
        let fixture = try PasteMaterializationFixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore(items: [])
        let item = fixture.textItem("permission probe")

        // Denied: the item is restored but nothing may be sent.
        fixture.seams.accessibilityTrusted = false
        let deniedPerformer = fixture.seams.makePerformer(store: store)
        #expect(deniedPerformer.paste(item, into: .current) == false)
        #expect(store.permissionMessage == "Accessibility permission is off. The item was copied to the clipboard.")
        #expect(fixture.pasteboard.string(forType: .string) == "permission probe")
        fixture.seams.runAllQueuedSends()
        #expect(fixture.seams.commandVCount == 0)

        // Allowed: at most one send, and no extra feedback.
        fixture.seams.accessibilityTrusted = true
        fixture.seams.activeStates = [true, true]
        store.clearPermissionMessage()
        let allowedPerformer = fixture.seams.makePerformer(store: store)
        #expect(allowedPerformer.paste(item, into: .current))
        fixture.seams.runAllQueuedSends()
        #expect(fixture.seams.commandVCount == 1)
        #expect(store.permissionMessage == nil)
    }

    @Test func missingTargetRestoresButNeverSends() async throws {
        let fixture = try PasteMaterializationFixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore(items: [])
        let item = fixture.textItem("no target")
        let performer = fixture.seams.makePerformer(store: store)

        #expect(performer.paste(item, into: nil) == false)

        #expect(store.permissionMessage == "The item was copied, but no target app was available to paste into.")
        #expect(fixture.pasteboard.string(forType: .string) == "no target")
        fixture.seams.runAllQueuedSends()
        #expect(fixture.seams.commandVCount == 0)
    }

    @Test func unrestorableItemKeepsTheExistingRestoreFailure() async throws {
        let fixture = try PasteMaterializationFixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore(items: [])
        fixture.seams.activeStates = [true, true]
        let performer = fixture.seams.makePerformer(store: store)

        #expect(performer.paste(fixture.textItem(""), into: .current) == false)
        #expect(store.permissionMessage == "This clipboard item could not be restored.")
        fixture.seams.runAllQueuedSends()
        #expect(fixture.seams.commandVCount == 0)
    }

    @Test func acceptedHandoffSurvivesTheInternalCloseAndStillSends() async throws {
        let fixture = try PasteMaterializationFixture()
        defer { fixture.cleanUp() }
        let model = fixture.makeModel(items: [fixture.textItem("paste me")])
        _ = NSApplication.shared
        fixture.seams.activeStates = [true, true]
        let controller = PanelWindowController(
            model: model,
            pastePerformer: fixture.seams.makePerformer(store: model.store)
        )
        controller.pasteTargetOverride = .current
        controller.show()
        #expect(model.store.panelVisible)

        // Text stays on the synchronous path: the pasteboard is written and the
        // panel closes before any asynchronous work exists.
        controller.panel?.onPaste?()

        #expect(fixture.pasteboard.string(forType: .string) == "paste me")
        #expect(!model.store.panelVisible)

        // The internal close must not cancel the accepted attempt.
        fixture.seams.runAllQueuedSends()
        #expect(fixture.seams.commandVCount == 1)
    }
}
