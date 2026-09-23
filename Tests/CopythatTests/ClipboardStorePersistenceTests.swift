@testable import Copythat
import AppKit
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
        for x in 0..<32 {
            for y in 0..<32 {
                bitmap.setColor(color, atX: x, y: y)
            }
        }
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.addRepresentation(bitmap)
        return image
    }
}
