@testable import Copythat
import AppKit
import CryptoKit
import Foundation
import Testing

/// Acceptance for metadata persistence over a mixed history: once every blob is
/// present, pinning, organizing, deleting, or renaming must commit metadata with
/// zero media hashes, zero payload reads, zero payload writes, and exactly one
/// manifest commit — both through direct persistence calls and through real
/// Store mutations driven by the save coordinator and worker.
@MainActor
@Suite(.serialized)
struct ClipboardHistoryMetadataSaveAcceptanceTests {
    private static let itemCount = 120

    @Test func directPersistenceMetadataSaveTouchesNoMedia() async throws {
        let environment = try AcceptanceEnvironment()
        defer { environment.cleanup() }
        let items = environment.makeMixedItems(count: Self.itemCount)
        expectPairedMedia(items)
        try environment.persistence.save(items)

        var mutated = items
        mutated[0].isPinned = true
        mutated[1].pinboardName = "Work"
        mutated[2] = mutated[2].withLinkPreview(title: "Renamed", linkImage: nil)

        environment.counters.reset()
        try await environment.counters.measure { try environment.persistence.save(mutated) }

        expectMetadataOnlySave(environment.counters, mutation: "direct-persistence")
        let manifest = try environment.manifest()
        #expect(manifest.version == 2)
        #expect(manifest.items.count == Self.itemCount)
        #expect(manifest.items[0].isPinned)
        #expect(manifest.items[1].pinboardName == "Work")
        #expect(manifest.items[2].linkTitle == "Renamed")
        #expect(manifest.items[0].imageBlob == items[0].imageBlobID)
        expectPairedMedia(mutated)
    }

    @Test func residentStoreMetadataMutationsCommitWithoutMediaWork() async throws {
        try await expectStoreMutationsCommitWithoutMediaWork(source: .resident)
    }

    @Test func lazyRestoredStoreMetadataMutationsCommitWithoutMediaWork() async throws {
        try await expectStoreMutationsCommitWithoutMediaWork(source: .restoredReferenceOnly)
    }

    @Test func durablyReleasedStoreMetadataMutationsCommitWithoutMediaWork() async throws {
        try await expectStoreMutationsCommitWithoutMediaWork(source: .durablyReleased)
    }

    private func expectStoreMutationsCommitWithoutMediaWork(source: MediaSource) async throws {
        let environment = try AcceptanceEnvironment()
        defer { environment.cleanup() }
        let items = environment.makeMixedItems(count: Self.itemCount)
        try environment.persistence.save(items)

        let storeItems: [ClipboardItem]
        switch source {
        case .resident:
            storeItems = items
        case .restoredReferenceOnly:
            storeItems = try environment.persistence.loadItems()
            #expect(storeItems.allSatisfy { $0.imageData == nil && $0.linkImageData == nil })
            #expect(storeItems.contains { $0.imageBlobID != nil })
        case .durablyReleased:
            storeItems = items
        }

        let store = environment.makeStore(
            initialItems: storeItems,
            installsDurableMediaHandler: source == .durablyReleased
        )
        let imageItem = try #require(store.items.first { $0.kind == .image && $0.imageBlobID != nil })
        let previewItem = try #require(store.items.first { $0.linkImageBlobID != nil })
        let textItem = try #require(store.items.first { $0.kind == .text })
        let committedImageBlobID = imageItem.imageBlobID
        let committedPreviewBlobID = previewItem.linkImageBlobID

        if source == .durablyReleased {
            #expect(await environment.commit(store))
            #expect(
                store.items.allSatisfy { $0.imageData == nil && $0.linkImageData == nil },
                "a durable commit releases resident media from history"
            )
            #expect(store.filteredItems.allSatisfy { $0.imageData == nil && $0.linkImageData == nil })
        }

        try await expectMetadataOnlyMutation(environment, mutation: "pin") {
            store.togglePin(imageItem)
        }
        try await expectMetadataOnlyMutation(environment, mutation: "unpin") {
            store.togglePin(store.items.first { $0.id == imageItem.id }!)
        }
        try await expectMetadataOnlyMutation(environment, mutation: "pinboard-assignment") {
            store.move(store.items.first { $0.id == previewItem.id }!, toPinboard: "Work")
        }
        try await expectMetadataOnlyMutation(environment, mutation: "pinboard-rename") {
            store.renamePinboardAssignments(from: "Work", to: "Later")
        }
        try await expectMetadataOnlyMutation(environment, mutation: "other-item-deletion") {
            store.remove(store.items.first { $0.id == textItem.id }!)
        }
        try await expectMetadataOnlyMutation(environment, mutation: "title-only-update") {
            store.applyLinkPreview(itemID: previewItem.id, title: "Renamed preview", linkImage: nil)
        }

        #expect(store.items.first { $0.id == imageItem.id }?.isPinned == false)
        #expect(store.items.first { $0.id == previewItem.id }?.pinboardName == "Later")
        #expect(store.items.first { $0.id == textItem.id } == nil)
        #expect(store.items.first { $0.id == previewItem.id }?.linkTitle == "Renamed preview")
        // Blob references and content identity survive release and mutation.
        #expect(store.items.first { $0.id == imageItem.id }?.imageBlobID == committedImageBlobID)
        #expect(store.items.first { $0.id == previewItem.id }?.linkImageBlobID == committedPreviewBlobID)
        if source == .durablyReleased {
            #expect(try environment.manifest().version == 2, "release keeps the V2 schema")
            #expect(store.items.first { $0.id == imageItem.id }?.imageData == nil)
            #expect(store.items.first { $0.id == previewItem.id }?.linkImageData == nil)
        }
        expectPairedMedia(store.items)
        let restored = try environment.persistence.loadItems()
        #expect(restored.count == Self.itemCount - 1)
        expectPairedMedia(restored)
    }

    private func expectMetadataOnlyMutation(
        _ environment: AcceptanceEnvironment,
        mutation: String,
        _ body: () -> Void
    ) async throws {
        environment.counters.reset()
        try await environment.counters.measure {
            body()
            #expect(await environment.flush())
        }

        expectMetadataOnlySave(environment.counters, mutation: mutation)
    }

    private func expectMetadataOnlySave(_ counters: MediaOperationCounters, mutation: String) {
        #expect(counters.mediaHashCount == 0, "\(mutation) hashed media")
        #expect(counters.blobReadCount == 0, "\(mutation) read a media payload")
        #expect(counters.blobWriteCount == 0, "\(mutation) wrote a media payload")
        #expect(counters.manifestWriteCount == 1, "\(mutation) committed \(counters.manifestWriteCount) manifests")
        AcceptanceMetrics.record(
            scenario: "metadata-save",
            metric: "mediaHashCount",
            expected: "0",
            observed: "\(counters.mediaHashCount)"
        )
        AcceptanceMetrics.record(
            scenario: "metadata-save",
            metric: "blobReadCountDuringSave",
            expected: "0",
            observed: "\(counters.blobReadCount)"
        )
        AcceptanceMetrics.record(
            scenario: "metadata-save",
            metric: "blobWriteCount",
            expected: "0",
            observed: "\(counters.blobWriteCount)"
        )
        AcceptanceMetrics.record(
            scenario: "metadata-save",
            metric: "manifestWriteCount",
            expected: "1",
            observed: "\(counters.manifestWriteCount)"
        )
    }

    /// Resident bytes always carry the address of those exact bytes, so no
    /// producer can hand the save a payload it would have to identify itself.
    private func expectPairedMedia(
        _ items: [ClipboardItem],
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        for item in items {
            if let data = item.imageData {
                #expect(item.imageBlobID == sha256Hex(data), sourceLocation: sourceLocation)
            }
            if let data = item.linkImageData {
                #expect(item.linkImageBlobID == sha256Hex(data), sourceLocation: sourceLocation)
            }
            if let data = item.sourceAppIconData {
                #expect(item.sourceAppIconBlobID == sha256Hex(data), sourceLocation: sourceLocation)
            }
        }
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// Isolated history root, defaults, persistence, and Store wiring for the
/// acceptance scenarios. Fixture preparation and media access stay outside the
/// measurement windows the scenarios open.
@MainActor
private final class AcceptanceEnvironment {
    let counters = MediaOperationCounters()
    let persistence: ClipboardHistoryPersistence
    let coordinator: ClipboardHistorySaveCoordinator

    private let directory: URL
    private let defaultsName: String
    private let defaults: UserDefaults

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MetadataSaveAcceptance-\(UUID().uuidString)", isDirectory: true)
        defaultsName = "MetadataSaveAcceptance.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsName)!
        defaults.removePersistentDomain(forName: defaultsName)
        let counters = self.counters
        persistence = counters.makePersistence(directoryURL: directory, userDefaults: defaults)
        coordinator = ClipboardHistorySaveCoordinator(
            worker: ClipboardHistorySaveWorker(persistence: persistence)
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: defaultsName)
    }

    func makeStore(
        initialItems: [ClipboardItem],
        installsDurableMediaHandler: Bool = false
    ) -> ClipboardStore {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: initialItems,
            pasteboard: pasteboard,
            mediaLoader: ClipboardHistoryMediaLoader(blobStore: persistence.blobStore),
            persistItems: { [coordinator] in coordinator.requestSave($0) },
            fetchLinkMetadata: { _ in throw URLError(.unsupportedURL) },
            fetchLinkSnapshot: { _ in throw URLError(.unsupportedURL) }
        )
        if installsDurableMediaHandler {
            coordinator.setDurableMediaHandler { [weak store] commit in
                await store?.handleDurableMediaCommit(commit)
            }
        }
        return store
    }

    /// Persists the store's current history, as a metadata mutation would.
    func commit(_ store: ClipboardStore) async -> Bool {
        coordinator.requestSave(store.items)
        return await coordinator.flush()
    }

    func flush() async -> Bool {
        await coordinator.flush()
    }

    func manifest() throws -> Manifest {
        let data = try Data(contentsOf: persistence.historyURL)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    func makeMixedItems(count: Int) -> [ClipboardItem] {
        let icons = (0..<4).map { index in Data(repeating: UInt8(0x30 + index), count: 96 + index) }
        let images = (0..<3).map { index in NSImagePixels(seed: index).png }
        let previews = (0..<3).map { index in NSImagePixels(seed: index + 8).png }

        return (0..<count).map { index in
            let icon = icons[index % icons.count]
            let base = ClipboardItem(
                id: UUID(),
                kind: .text,
                title: "Item \(index)",
                preview: "Preview \(index)",
                sourceApp: "App \(index % 5)",
                sourceAppIconData: icon,
                createdAt: Date(timeIntervalSince1970: 1_700_100_000 + Double(index)),
                isPinned: false,
                pinboardName: nil,
                textValue: "Text \(index)",
                fileURLs: [],
                imageData: nil
            )
            switch index % 4 {
            case 0:
                return base.replaced(kind: .image, imageData: images[index % images.count])
            case 1:
                return base.replaced(
                    kind: .url,
                    textValue: "https://item\(index).example.com/",
                    linkImageData: previews[index % previews.count]
                )
            case 2:
                return base
            default:
                return base.replaced(kind: .url, textValue: "https://item\(index).example.com/")
            }
        }
    }
}

/// Where a scenario's heavy media came from, so resident, lazily restored, and
/// durably released coverage stay separate cases.
private enum MediaSource {
    case resident
    case restoredReferenceOnly
    case durablyReleased
}

private struct Manifest: Decodable {    struct Item: Decodable {
        let id: UUID
        let isPinned: Bool
        let pinboardName: String?
        let linkTitle: String?
        let imageBlob: String?
        let linkImageBlob: String?
        let sourceAppIconBlob: String?
    }

    let version: Int
    let items: [Item]
}

/// Small deterministic PNG payloads so the fixture carries real final media.
private struct NSImagePixels {
    let png: Data

    init(seed: Int) {
        let size = 24 + seed
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let color = NSColor(
            calibratedRed: CGFloat((seed % 7) + 1) / 8,
            green: CGFloat((seed % 5) + 1) / 6,
            blue: CGFloat((seed % 3) + 1) / 4,
            alpha: 1
        )
        for column in 0..<size {
            for row in 0..<size {
                bitmap.setColor(color, atX: column, y: row)
            }
        }
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(bitmap)
        png = image.pngData(maxPixel: 1_200) ?? Data()
    }
}

private extension ClipboardItem {
    func replaced(
        kind: ClipboardKind? = nil,
        textValue: String? = nil,
        imageData: Data? = nil,
        linkImageData: Data? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: kind ?? self.kind,
            title: title,
            preview: preview,
            sourceApp: sourceApp,
            sourceAppIconData: sourceAppIconData,
            sourceAppIconBlobID: sourceAppIconBlobID,
            createdAt: createdAt,
            isPinned: isPinned,
            pinboardName: pinboardName,
            textValue: textValue ?? self.textValue,
            fileURLs: fileURLs,
            imageData: imageData,
            imageBlobID: imageData == nil ? imageBlobID : nil,
            linkTitle: linkTitle,
            linkImageData: linkImageData,
            linkImageBlobID: linkImageData == nil ? linkImageBlobID : nil
        )
    }
}
