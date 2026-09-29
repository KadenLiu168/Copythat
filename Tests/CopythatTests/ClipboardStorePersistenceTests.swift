// Link preview seam
@testable import Copythat
import AppKit
import CryptoKit
import Foundation
import Testing

private struct RecordedStoreItem: Equatable, Sendable {
    let id: UUID
    let textValue: String?
    let isPinned: Bool
    let pinboardName: String?
    let linkTitle: String?
    let linkImageData: Data?
}

private struct RecordedStoreSave: Equatable, Sendable {
    let generation: UInt64
    let items: [RecordedStoreItem]
}

private actor StorePersistenceRecorder: ClipboardHistorySaving {
    private var saves: [RecordedStoreSave] = []

    func save(_ items: [ClipboardItem], generation: UInt64) async throws {
        saves.append(
            RecordedStoreSave(
                generation: generation,
                items: items.map {
                    RecordedStoreItem(
                        id: $0.id,
                        textValue: $0.textValue,
                        isPinned: $0.isPinned,
                        pinboardName: $0.pinboardName,
                        linkTitle: $0.linkTitle,
                        linkImageData: $0.linkImageData
                    )
                }
            )
        )
    }

    func collectGarbage() async {}

    func recordedSaves() -> [RecordedStoreSave] {
        saves
    }
}

private final class BlobReadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []

    func record(_ url: URL) {
        lock.lock()
        names.append(url.lastPathComponent)
        lock.unlock()
    }

    func reset() {
        lock.lock()
        names.removeAll()
        lock.unlock()
    }

    func blobReads() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return names.filter { $0.hasSuffix(".blob") }
    }
}

private actor BlockingStoreSaveWorker: ClipboardHistorySaving {
    private var hasStarted = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func save(_ items: [ClipboardItem], generation: UInt64) async throws {
        hasStarted = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { continuation in
            releaseWaiter = continuation
        }
    }

    func collectGarbage() async {}

    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { continuation in
            startWaiter = continuation
        }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private actor RapidMutationSaveWorker: ClipboardHistorySaving {
    private var firstGenerationStarted = false
    private var firstStartWaiter: CheckedContinuation<Void, Never>?
    private var firstReleaseWaiter: CheckedContinuation<Void, Never>?
    private var committedSnapshots: [RecordedStoreSave] = []

    func save(_ items: [ClipboardItem], generation: UInt64) async throws {
        if generation == 1 {
            firstGenerationStarted = true
            firstStartWaiter?.resume()
            firstStartWaiter = nil
            await withCheckedContinuation { continuation in
                firstReleaseWaiter = continuation
            }
        }
        committedSnapshots.append(
            RecordedStoreSave(
                generation: generation,
                items: items.map {
                    RecordedStoreItem(
                        id: $0.id,
                        textValue: $0.textValue,
                        isPinned: $0.isPinned,
                        pinboardName: $0.pinboardName,
                        linkTitle: $0.linkTitle,
                        linkImageData: $0.linkImageData
                    )
                }
            )
        )
    }

    func collectGarbage() async {}

    func waitForFirstGeneration() async {
        if firstGenerationStarted { return }
        await withCheckedContinuation { continuation in
            firstStartWaiter = continuation
        }
    }

    func releaseFirstGeneration() {
        firstReleaseWaiter?.resume()
        firstReleaseWaiter = nil
    }

    func saves() -> [RecordedStoreSave] {
        committedSnapshots
    }
}

@MainActor
@Suite(.serialized)
struct ClipboardStorePersistenceTests {
    @Test func previewSavedToDiskRestoresIntoNewStoreAndRetainsURLBehavior() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreviewRestore-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "PreviewRestore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }
        let persistence = ClipboardHistoryPersistence(directoryURL: directory, userDefaults: defaults)
        let coordinator = ClipboardHistorySaveCoordinator(worker: ClipboardHistorySaveWorker(persistence: persistence))
        let original = urlItemForPersistence(
            id: "00000000-0000-0000-0000-000000000082",
            title: "Original", preview: "https://restore.example.com/path?query=1"
        )
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults), sourceTracker: CopySourceTracker(),
            initialItems: [original], pasteboard: NSPasteboard.withUniqueName(),
            persistItems: { coordinator.requestSave($0) }
        )
        let png = try #require(testImage().pngData(maxPixel: 32))
        store.applyLinkPreview(itemID: original.id, title: "Searchable preview title", imageData: png)
        store.togglePin(original)
        store.move(original, toPinboard: "Work")
        #expect(await coordinator.flush())
        #expect(FileManager.default.fileExists(atPath: persistence.historyURL.path))
        let reader = ClipboardHistoryPersistence(directoryURL: directory, userDefaults: defaults)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let requests = LinkPreviewCounter()
        let restored = ClipboardStore(
            settings: AppSettings(defaults: defaults), sourceTracker: CopySourceTracker(),
            initialItems: try reader.loadItems(), pasteboard: pasteboard, persistItems: { _ in },
            fetchLinkMetadata: { _ in
                requests.mark("metadata")
                throw URLError(.unsupportedURL)
            }
        )
        let item = try #require(restored.items.first)
        #expect(item.id == original.id)
        #expect(item.kind == .url)
        #expect(item.textValue == original.textValue)
        #expect(item.sourceApp == original.sourceApp)
        #expect(item.linkTitle == "Searchable preview title")
        #expect(item.linkImageData == nil)
        #expect(item.persistedLinkImageBlobID == sha256Hex(png))
        let materializedPreview = try reader.blobStore.read(
            blobID: try #require(item.persistedLinkImageBlobID)
        )
        #expect(materializedPreview == png)
        #expect(NSImage(data: materializedPreview)?.size == NSSize(width: 32, height: 32))
        #expect(item.isPinned)
        #expect(item.pinboardName == "Work")
        restored.searchText = "Searchable preview"
        #expect(restored.filteredItems.map(\.id) == [original.id])
        restored.selectedBoardID = Pinboard.pinned.id
        #expect(restored.filteredItems.map(\.id) == [original.id])
        restored.selectedBoardID = Pinboard.custom("Work").id
        #expect(restored.filteredItems.map(\.id) == [original.id])
        restored.panelDidOpen()
        #expect(restored.metadataTasks.isEmpty)
        #expect(restored.activeFallback == nil)
        #expect(requests.value("metadata") == 0)
        #expect(restored.writeToPasteboard(item))
        #expect(pasteboard.string(forType: .string) == original.textValue)
        restored.remove(item)
        #expect(restored.items.isEmpty)
        #expect(restored.filteredItems.isEmpty)
        #expect(restored.selectedID == nil)
        restored.panelDidClose()
    }

    @Test func metadataMutationsPreserveUnloadedMediaReferencesWithoutHeavyReads() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LazyMetadata-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "ClipboardStorePersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        let reads = BlobReadRecorder()
        let persistence = ClipboardHistoryPersistence(
            directoryURL: directory,
            userDefaults: defaults,
            readData: { url in
                reads.record(url)
                return try Data(contentsOf: url)
            }
        )
        let imageBytes = Data(repeating: 0xc1, count: 4_096)
        let linkImageBytes = Data(repeating: 0xc2, count: 2_048)
        let urlItem = ClipboardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000c1")!,
            kind: .url,
            title: "Restored link",
            preview: "https://restored.example.com/",
            sourceApp: "Safari",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_200),
            isPinned: false,
            pinboardName: nil,
            textValue: "https://restored.example.com/",
            fileURLs: [],
            imageData: nil,
            linkTitle: "Restored link",
            linkImageData: linkImageBytes
        )
        let imageItem = ClipboardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000c2")!,
            kind: .image,
            title: "Restored image",
            preview: "64 x 64",
            sourceApp: "Preview",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_201),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: imageBytes
        )
        try persistence.save([urlItem, imageItem])
        reads.reset()

        let restored = try persistence.loadItems()
        #expect(restored.allSatisfy { $0.imageData == nil && $0.linkImageData == nil })

        let coordinator = ClipboardHistorySaveCoordinator(
            worker: ClipboardHistorySaveWorker(persistence: persistence)
        )
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: restored,
            pasteboard: NSPasteboard.withUniqueName(),
            persistItems: { coordinator.requestSave($0) }
        )
        let restoredImage = try #require(store.items.first { $0.id == imageItem.id })
        let restoredURL = try #require(store.items.first { $0.id == urlItem.id })

        store.togglePin(restoredImage)
        store.move(restoredURL, toPinboard: "Work")
        store.add(textItem("00000000-0000-0000-0000-0000000000c3", text: "unrelated"))
        store.renamePinboardAssignments(from: "Work", to: "Ideas")
        // The quit path flushes the same coordinator before replying to
        // termination, so a successful flush here proves the snapshot carries
        // unloaded references all the way to disk.
        #expect(await coordinator.flush())

        #expect(reads.blobReads().isEmpty)
        let reloaded = try persistence.loadItems()
        let reloadedURL = try #require(reloaded.first { $0.id == urlItem.id })
        #expect(reloadedURL.linkImageData == nil)
        #expect(reloadedURL.persistedLinkImageBlobID == sha256Hex(linkImageBytes))
        #expect(reloadedURL.linkTitle == "Restored link")
        #expect(reloadedURL.pinboardName == "Ideas")
        let reloadedImage = try #require(reloaded.first { $0.id == imageItem.id })
        #expect(reloadedImage.imageData == nil)
        #expect(reloadedImage.persistedImageBlobID == sha256Hex(imageBytes))
        #expect(reloadedImage.isPinned)
        #expect(reloaded.contains { $0.textValue == "unrelated" })

        AcceptanceMetrics.record(
            scenario: "history-gc-and-mutations",
            metric: "heavyBlobReadsAcrossMetadataMutations",
            expected: "0",
            observed: "\(reads.blobReads().count)"
        )
        AcceptanceMetrics.record(
            scenario: "history-gc-and-mutations",
            metric: "heavyReferencesPreservedAfterFlush",
            expected: "2",
            observed: "\([reloadedURL.persistedLinkImageBlobID != nil, reloadedImage.persistedImageBlobID != nil].filter { $0 }.count)"
        )
    }

    @Test func deletingARestoredItemWithoutDisplayingItNeverReadsOrKeepsItsMedia() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeleteUnseen-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "ClipboardStorePersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        let reads = BlobReadRecorder()
        let persistence = ClipboardHistoryPersistence(
            directoryURL: directory,
            userDefaults: defaults,
            readData: { url in
                reads.record(url)
                return try Data(contentsOf: url)
            }
        )
        let imageBytes = Data(repeating: 0xd1, count: 2_048)
        let item = ClipboardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000e1")!,
            kind: .image,
            title: "Unseen image",
            preview: "64 x 64",
            sourceApp: "Preview",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_210),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: imageBytes
        )
        try persistence.save([item])
        reads.reset()

        let restored = try persistence.loadItems()
        #expect(restored.first?.imageData == nil)
        #expect(restored.first?.persistedImageBlobID == sha256Hex(imageBytes))

        let coordinator = ClipboardHistorySaveCoordinator(
            worker: ClipboardHistorySaveWorker(persistence: persistence)
        )
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: restored,
            pasteboard: NSPasteboard.withUniqueName(),
            persistItems: { coordinator.requestSave($0) }
        )
        let restoredItem = try #require(store.items.first)

        // Deleted before it was ever displayed or materialized.
        store.remove(restoredItem)
        #expect(await coordinator.flush())

        #expect(reads.blobReads().isEmpty)
        #expect(try persistence.loadItems().isEmpty)
        let mediaDirectory = directory.appendingPathComponent("history-media", isDirectory: true)
        let remaining = try FileManager.default.contentsOfDirectory(
            at: mediaDirectory,
            includingPropertiesForKeys: nil
        )
        #expect(remaining.isEmpty, "its blob is collected only after the new manifest commits")

        AcceptanceMetrics.record(
            scenario: "history-gc-and-mutations",
            metric: "blobReadsForDeleteWithoutDisplay",
            expected: "0",
            observed: "\(reads.blobReads().count)"
        )
        AcceptanceMetrics.record(
            scenario: "history-gc-and-mutations",
            metric: "blobsRemainingAfterGC",
            expected: "0",
            observed: "\(remaining.count)"
        )
    }

    @Test func rapidMutationsAndPreviewArrivalCommitOnlyLatestSnapshot() async throws {
        let defaultsName = "ClipboardStorePersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let worker = RapidMutationSaveWorker()
        let coordinator = ClipboardHistorySaveCoordinator(worker: worker)
        let seed = textItem("00000000-0000-0000-0000-000000000076", text: "seed")
        let url = ClipboardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000077")!,
            kind: .url,
            title: "Example",
            preview: "https://example.com",
            sourceApp: "Safari",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_077),
            isPinned: false,
            pinboardName: nil,
            textValue: "https://example.com",
            fileURLs: [],
            imageData: nil
        )
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [seed, url],
            pasteboard: NSPasteboard.withUniqueName(),
            persistItems: { coordinator.requestSave($0) }
        )
        let transient = textItem("00000000-0000-0000-0000-000000000078", text: "transient")
        let final = textItem("00000000-0000-0000-0000-000000000079", text: "final")

        store.add(transient)
        await worker.waitForFirstGeneration()
        store.togglePin(seed)
        store.remove(transient)
        store.add(final)
        let preview = try #require(testImage().pngData(maxPixel: 32))
        store.applyLinkPreview(itemID: url.id, title: "Latest preview", imageData: preview)

        await worker.releaseFirstGeneration()
        #expect(await coordinator.flush())
        let saves = await worker.saves()
        let latest = try #require(saves.last)

        #expect(saves.map(\.generation) == [1, 5])
        #expect(latest.items.first(where: { $0.id == seed.id })?.isPinned == true)
        #expect(latest.items.contains(where: { $0.id == transient.id }) == false)
        #expect(latest.items.contains(where: { $0.id == final.id }))
        #expect(latest.items.first(where: { $0.id == url.id })?.linkTitle == "Latest preview")
        #expect(latest.items.first(where: { $0.id == url.id })?.linkImageData != nil)
    }

    @Test func storeMutationReturnsWhilePersistenceWorkerIsBlocked() async {
        let defaultsName = "ClipboardStorePersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let worker = BlockingStoreSaveWorker()
        let coordinator = ClipboardHistorySaveCoordinator(worker: worker)
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [],
            pasteboard: NSPasteboard.withUniqueName(),
            persistItems: { coordinator.requestSave($0) }
        )
        let item = textItem("00000000-0000-0000-0000-000000000075", text: "visible immediately")

        store.add(item)
        await worker.waitUntilStarted()

        #expect(store.items == [item])
        await worker.release()
        #expect(await coordinator.flush())
    }

    @Test func mutationsAndPreviewEnrichmentSubmitCurrentSnapshots() async throws {
        let defaultsName = "ClipboardStorePersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let worker = StorePersistenceRecorder()
        let coordinator = ClipboardHistorySaveCoordinator(worker: worker)
        let seed = textItem("00000000-0000-0000-0000-000000000071", text: "seed")
        let removed = textItem("00000000-0000-0000-0000-000000000072", text: "removed")
        let url = ClipboardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000073")!,
            kind: .url,
            title: "Example",
            preview: "https://example.com",
            sourceApp: "Safari",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_073),
            isPinned: false,
            pinboardName: nil,
            textValue: "https://example.com",
            fileURLs: [],
            imageData: nil
        )
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [seed, removed, url],
            pasteboard: NSPasteboard.withUniqueName(),
            persistItems: { coordinator.requestSave($0) }
        )
        let added = textItem("00000000-0000-0000-0000-000000000074", text: "added")

        store.add(added)
        #expect(await coordinator.flush())
        #expect(await worker.recordedSaves().last?.items.count == 4)

        store.togglePin(added)
        #expect(await coordinator.flush())
        #expect(await worker.recordedSaves().last?.items.first(where: { $0.id == added.id })?.isPinned == true)

        store.togglePin(added)
        #expect(await coordinator.flush())
        #expect(await worker.recordedSaves().last?.items.first(where: { $0.id == added.id })?.isPinned == false)

        store.move(added, toPinboard: "Work")
        #expect(await coordinator.flush())
        #expect(await worker.recordedSaves().last?.items.first(where: { $0.id == added.id })?.pinboardName == "Work")

        store.renamePinboardAssignments(from: "Work", to: "Ideas")
        #expect(await coordinator.flush())
        #expect(await worker.recordedSaves().last?.items.first(where: { $0.id == added.id })?.pinboardName == "Ideas")

        store.remove(removed)
        #expect(await coordinator.flush())
        #expect(await worker.recordedSaves().last?.items.contains(where: { $0.id == removed.id }) == false)

        let previewImage = try #require(testImage().pngData(maxPixel: 32))
        store.applyLinkPreview(itemID: url.id, title: "Loaded preview", imageData: previewImage)
        #expect(await coordinator.flush())
        let savedURL = await worker.recordedSaves().last?.items.first(where: { $0.id == url.id })
        #expect(savedURL?.linkTitle == "Loaded preview")
        #expect(savedURL?.linkImageData.flatMap(NSImage.init(data:))?.size == NSSize(width: 32, height: 32))

        #expect(store.clearHistory(includePinnedAndPinboardItems: true) == 3)
        #expect(await coordinator.flush())
        #expect(await worker.recordedSaves().last?.items.isEmpty == true)
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func urlItemForPersistence(
        id: String,
        title: String,
        preview: String
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(uuidString: id)!,
            kind: .url,
            title: title,
            preview: preview,
            sourceApp: "Safari",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_080),
            isPinned: false,
            pinboardName: nil,
            textValue: preview,
            fileURLs: [],
            imageData: nil
        )
    }

    private func makeOrchestrationPersistenceStack() -> (
        ClipboardStore,
        StorePersistenceRecorder,
        ClipboardHistorySaveCoordinator,
        LinkPreviewCounter,
        LinkPreviewGate,
        ClipboardItem,
        ClipboardItem
    ) {
        let defaultsName = "ClipboardStorePersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        let worker = StorePersistenceRecorder()
        let coordinator = ClipboardHistorySaveCoordinator(worker: worker)
        let counter = LinkPreviewCounter()
        let gate = LinkPreviewGate()
        let url = "https://orchestrated.example.com/"
        let urlItem = urlItemForPersistence(id: "00000000-0000-0000-0000-000000000080", title: "Orchestrated", preview: url)
        let removedItem = urlItemForPersistence(id: "00000000-0000-0000-0000-000000000081", title: "Removed", preview: "https://removed.example.com/")
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [],
            pasteboard: NSPasteboard.withUniqueName(),
            persistItems: { coordinator.requestSave($0) },
            fetchLinkMetadata: { requestURL in
                counter.begin("metadata:\(requestURL.absoluteString)")
                defer { counter.end("metadata:\(requestURL.absoluteString)") }
                if requestURL.absoluteString == url {
                    // Empty metadata success: eligible, no data change, no save.
                    return LinkPreviewMetadata(title: nil, imageData: nil)
                }
                return try await LinkPreviewMetadataScript
                    .lateAfterCancel(gate, then: .titleOnly("Late"))
                    .evaluate(counter: counter, key: "removed")
            },
            fetchLinkSnapshot: { _ in throw URLError(.badServerResponse) }
        )
        store.linkPreviewHandledObserver = { counter.mark("handled") }
        return (store, worker, coordinator, counter, gate, urlItem, removedItem)
    }

    @Test func orchestratedPreviewCompletionDoesNotAddExtraSaves() async throws {
        let (store, worker, coordinator, counter, gate, urlItem, removedItem) =
            makeOrchestrationPersistenceStack()

        store.add(urlItem)
        store.add(removedItem)
        store.remove(removedItem)
        await counter.waitFor("metadata:https://removed.example.com/", reaching: 1)
        gate.release()
        await counter.waitFor("handled", reaching: 1)
        #expect(await coordinator.flush())

        let savesAfterLateCompletions = await worker.recordedSaves().count
        // Empty metadata and the removed item's late completion created no save.
        let previewImage = try #require(testImage().pngData(maxPixel: 32))
        store.applyLinkPreview(itemID: urlItem.id, title: "Valid preview", imageData: previewImage)
        #expect(await coordinator.flush())
        let saves = await worker.recordedSaves()
        let latest = try #require(saves.last)

        #expect(saves.count >= savesAfterLateCompletions + 1)
        #expect(latest.items.first(where: { $0.id == urlItem.id })?.linkTitle == "Valid preview")
        #expect(latest.items.first(where: { $0.id == urlItem.id })?.linkImageData != nil)
        #expect(saves.allSatisfy { snapshot in
            snapshot.items.first { $0.id == removedItem.id }?.linkTitle == nil
        })
    }

    private func textItem(_ id: String, text: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(uuidString: id)!,
            kind: .text,
            title: text,
            preview: text,
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_074),
            isPinned: false,
            pinboardName: nil,
            textValue: text,
            fileURLs: [],
            imageData: nil
        )
    }

    private func testImage() -> NSImage {
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
        let color = NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        for pixelX in 0..<32 {
            for pixelY in 0..<32 {
                bitmap.setColor(color, atX: pixelX, y: pixelY)
            }
        }
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.addRepresentation(bitmap)
        return image
    }
}
