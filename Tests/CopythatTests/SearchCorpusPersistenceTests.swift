@testable import Copythat
import AppKit
import Foundation
import Testing

/// Persistence contracts for the runtime corpus: V2 history stores metadata
/// only, and restoring builds each corpus from that metadata exactly once
/// without reading heavy media or rewriting the manifest.
@MainActor
struct SearchCorpusPersistenceTests {
    @Test func versionTwoRestoreRebuildsEachCorpusOnceWithoutBlobsOrMigration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SearchCorpusPersistence-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "SearchCorpusPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        let pasteboard = NSPasteboard.withUniqueName()
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
            pasteboard.releaseGlobally()
        }

        let linkImage = PreparedMedia(hashing: testImageData())
        let enriched = enrichedItem(linkImage: linkImage)
        let text = textItem()
        let writer = ClipboardHistoryPersistence(directoryURL: directory, userDefaults: defaults)
        try writer.save([enriched, text])

        let manifestData = try assertPersistedHistoryIsCorpusFree(
            writer: writer,
            linkImageID: linkImage.id,
            mediaDirectory: directory.appendingPathComponent("history-media")
        )

        var blobReads: [String] = []
        let reader = ClipboardHistoryPersistence(
            directoryURL: directory,
            userDefaults: defaults,
            readData: { url in
                if url.pathExtension == "blob" {
                    blobReads.append(url.lastPathComponent)
                }
                return try Data(contentsOf: url)
            }
        )

        let corpusRecorder = SearchCorpusRecorder()
        let restored = try restoreAndExerciseQueries(
            reader: reader,
            defaults: defaults,
            pasteboard: pasteboard,
            enrichedID: enriched.id,
            textID: text.id,
            recorder: corpusRecorder
        )

        #expect(blobReads.isEmpty, "restore must not read a heavy media blob")
        #expect(restored.items.first { $0.id == enriched.id }?.linkImageData == nil)
        #expect(try Data(contentsOf: writer.historyURL) == manifestData, "restore never rewrites the manifest")
    }

    /// The manifest stays version 2 and corpus-free, and only media bytes become
    /// blobs: the cache never reaches disk. Returns the saved manifest bytes.
    private func assertPersistedHistoryIsCorpusFree(
        writer: ClipboardHistoryPersistence,
        linkImageID: String,
        mediaDirectory: URL
    ) throws -> Data {
        let manifestData = try Data(contentsOf: writer.historyURL)
        let manifest = try #require(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        #expect(manifest["version"] as? Int == 2)
        #expect(manifest["searchText"] == nil)
        #expect(manifest["searchCorpus"] == nil)
        let records = try #require(manifest["items"] as? [[String: Any]])
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0["searchText"] == nil && $0["searchCorpus"] == nil })

        let blobNames = try FileManager.default
            .contentsOfDirectory(atPath: mediaDirectory.path)
            .filter { $0.hasSuffix(".blob") }
        #expect(blobNames == ["\(linkImageID).blob"])

        return manifestData
    }

    /// Restores through a window spanning Store initialization and every query,
    /// so a rebuild during either phase cannot happen silently outside it.
    private func restoreAndExerciseQueries(
        reader: ClipboardHistoryPersistence,
        defaults: UserDefaults,
        pasteboard: NSPasteboard,
        enrichedID: UUID,
        textID: UUID,
        recorder: SearchCorpusRecorder
    ) throws -> ClipboardStore {
        try SearchCorpusObservation.$recorder.withValue(recorder) {
            let restored = ClipboardStore(
                settings: AppSettings(defaults: defaults),
                sourceTracker: CopySourceTracker(),
                initialItems: try reader.loadItems(),
                pasteboard: pasteboard,
                persistItems: { _ in }
            )

            #expect(restored.items.count == 2)
            #expect(recorder.count == 2, "each restored item builds its corpus exactly once")

            restored.searchText = "Searchable preview title"
            #expect(restored.filteredItems.map(\.id) == [enrichedID])
            restored.searchText = "plain text"
            #expect(restored.filteredItems.map(\.id) == [textID])
            restored.searchText = "missing"
            #expect(restored.filteredItems.isEmpty)
            restored.searchText = ""
            restored.selectedBoardID = Pinboard.custom("Work").id
            #expect(restored.filteredItems.map(\.id) == [enrichedID])
            restored.selectedBoardID = Pinboard.pinned.id
            #expect(restored.filteredItems.map(\.id) == [enrichedID])

            #expect(recorder.count == 2, "Store initialization and queries never rebuild a corpus")
            return restored
        }
    }

    private func enrichedItem(linkImage: PreparedMedia) -> ClipboardItem {
        let url = "https://restore.example.com/path?query=1"
        return ClipboardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000090")!,
            kind: .url,
            title: "Original",
            preview: url,
            sourceApp: "Safari",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_080),
            isPinned: true,
            pinboardName: "Work",
            textValue: url,
            fileURLs: [],
            imageData: nil,
            linkTitle: "Searchable preview title",
            linkImageData: linkImage.data,
            linkImageBlobID: linkImage.id
        )
    }

    private func textItem() -> ClipboardItem {
        ClipboardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000091")!,
            kind: .text,
            title: "Text item",
            preview: "Plain text",
            sourceApp: "Notes",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_081),
            isPinned: false,
            pinboardName: nil,
            textValue: "Plain text",
            fileURLs: [],
            imageData: nil
        )
    }

    private func testImageData() -> Data {
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
        return image.pngData(maxPixel: 32) ?? Data()
    }
}
