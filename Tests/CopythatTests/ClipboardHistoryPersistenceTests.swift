@testable import Copythat
import Foundation
import Testing

private struct LegacyHistoryFixture: Encodable {
    let version: Int
    let items: [ClipboardItem]
}

private enum PersistenceTestFailure: Error {
    case injectedWriteFailure
}

struct ClipboardHistoryPersistenceTests {
    @Test func saveRepairsAnExistingBlobWhoseContentsDoNotMatchItsHash() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "ClipboardHistoryPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        var blobWriteCount = 0
        let persistence = ClipboardHistoryPersistence(
            directoryURL: directory,
            userDefaults: defaults,
            writeData: { data, url in
                if url.pathExtension == "blob" {
                    blobWriteCount += 1
                }
                try data.write(to: url, options: [.atomic])
            }
        )
        let media = Data([0x21, 0x22, 0x23])
        let item = persistenceTestItem(
            id: "00000000-0000-0000-0000-000000000038",
            sourceIcon: nil,
            image: media
        )

        try persistence.save([item])
        let mediaDirectory = directory.appendingPathComponent("history-media", isDirectory: true)
        let blobURL = try #require(
            FileManager.default.contentsOfDirectory(at: mediaDirectory, includingPropertiesForKeys: nil).first
        )
        try Data([0xff]).write(to: blobURL, options: [.atomic])
        #expect(try Data(contentsOf: blobURL) == Data([0xff]))

        try persistence.save([item])

        #expect(blobWriteCount == 2)
        #expect(try Data(contentsOf: blobURL) == media)
        #expect(try persistence.loadItems() == [item])
    }

    @Test func failedVersionOneMigrationKeepsTheLegacyFileReadable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "ClipboardHistoryPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        let persistence = ClipboardHistoryPersistence(
            directoryURL: directory,
            userDefaults: defaults,
            writeData: { data, url in
                if url.lastPathComponent == "clipboard-history.json" {
                    throw PersistenceTestFailure.injectedWriteFailure
                }
                try data.write(to: url, options: [.atomic])
            }
        )
        let legacyItem = persistenceTestItem(
            id: "00000000-0000-0000-0000-000000000039",
            sourceIcon: Data([0x39]),
            image: Data([0x3a])
        )
        let originalLegacyFile = try JSONEncoder().encode(LegacyHistoryFixture(version: 1, items: [legacyItem]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try originalLegacyFile.write(to: persistence.historyURL)

        #expect(try persistence.loadItems() == [legacyItem])

        var migrationFailed = false
        do {
            try persistence.save([legacyItem])
        } catch {
            migrationFailed = true
        }

        let reloadedPersistence = ClipboardHistoryPersistence(directoryURL: directory, userDefaults: defaults)
        #expect(migrationFailed)
        #expect(try Data(contentsOf: persistence.historyURL) == originalLegacyFile)
        #expect(try reloadedPersistence.loadItems() == [legacyItem])
    }

    @Test func garbageCollectionRemovesUnusedBlobsAfterCommitAndKeepsSharedBlobs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "ClipboardHistoryPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        var events: [String] = []
        let persistence = ClipboardHistoryPersistence(
            directoryURL: directory,
            userDefaults: defaults,
            writeData: { data, url in
                events.append("write:\(url.lastPathComponent)")
                try data.write(to: url, options: [.atomic])
            },
            removeItem: { url in
                events.append("remove:\(url.lastPathComponent)")
                try FileManager.default.removeItem(at: url)
            }
        )
        let sharedIcon = Data(repeating: 0x51, count: 128)
        let retainedItem = persistenceTestItem(
            id: "00000000-0000-0000-0000-000000000051",
            sourceIcon: sharedIcon
        )
        let removedItem = persistenceTestItem(
            id: "00000000-0000-0000-0000-000000000052",
            sourceIcon: sharedIcon,
            image: Data(repeating: 0x52, count: 512)
        )
        try persistence.save([retainedItem, removedItem])

        let mediaDirectory = directory.appendingPathComponent("history-media", isDirectory: true)
        let before = try blobSnapshot(in: mediaDirectory)
        events.removeAll()
        try persistence.save([retainedItem])

        let after = try blobSnapshot(in: mediaDirectory)
        let manifestWriteIndex = try #require(events.firstIndex(of: "write:clipboard-history.json"))
        let deletionIndices = events.indices.filter { events[$0].hasPrefix("remove:") }

        #expect(before.count == 2)
        #expect(after.count == 1)
        #expect(before.keys.contains { after[$0] != nil })
        #expect(events.count == 2)
        #expect(!deletionIndices.isEmpty)
        #expect(deletionIndices.allSatisfy { $0 > manifestWriteIndex })
        #expect(try persistence.loadItems() == [retainedItem])
    }

    @Test func garbageCollectionFailureDoesNotFailCommittedSave() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "ClipboardHistoryPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        var failRemoval = false
        let persistence = ClipboardHistoryPersistence(
            directoryURL: directory,
            userDefaults: defaults,
            removeItem: { url in
                if failRemoval {
                    throw PersistenceTestFailure.injectedWriteFailure
                }
                try FileManager.default.removeItem(at: url)
            }
        )
        let item = persistenceTestItem(
            id: "00000000-0000-0000-0000-000000000053",
            sourceIcon: nil,
            image: Data([0x53, 0x54])
        )
        try persistence.save([item])
        failRemoval = true

        var saveSucceeded = false
        do {
            try persistence.save([])
            saveSucceeded = true
        } catch {
            saveSucceeded = false
        }

        let mediaDirectory = directory.appendingPathComponent("history-media", isDirectory: true)
        #expect(saveSucceeded)
        #expect(try persistence.loadItems().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(at: mediaDirectory, includingPropertiesForKeys: nil).count == 1)

        failRemoval = false
        persistence.collectGarbage()
        #expect(try FileManager.default.contentsOfDirectory(at: mediaDirectory, includingPropertiesForKeys: nil).isEmpty)
    }

    @Test func blobAndManifestFailuresLeaveLastCommittedHistoryReadable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "ClipboardHistoryPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        var failBlobWrite = false
        var failManifestWrite = false
        let persistence = ClipboardHistoryPersistence(
            directoryURL: directory,
            userDefaults: defaults,
            writeData: { data, url in
                if failBlobWrite && url.pathExtension == "blob" {
                    throw PersistenceTestFailure.injectedWriteFailure
                }
                if failManifestWrite && url.lastPathComponent == "clipboard-history.json" {
                    throw PersistenceTestFailure.injectedWriteFailure
                }
                try data.write(to: url, options: [.atomic])
            }
        )
        let committedItem = persistenceTestItem(
            id: "00000000-0000-0000-0000-000000000041",
            sourceIcon: Data(repeating: 0x41, count: 128),
            image: Data(repeating: 0x42, count: 2_048)
        )
        try persistence.save([committedItem])
        let committedManifest = try Data(contentsOf: persistence.historyURL)
        let committedBlobs = try blobSnapshot(
            in: directory.appendingPathComponent("history-media", isDirectory: true)
        )
        let updatedItem = committedItem.withLinkPreview(
            title: "Preview",
            linkImageData: Data(repeating: 0x43, count: 4_096)
        )

        failBlobWrite = true
        var blobSaveFailed = false
        do {
            try persistence.save([updatedItem])
        } catch {
            blobSaveFailed = true
        }

        #expect(blobSaveFailed)
        #expect(try Data(contentsOf: persistence.historyURL) == committedManifest)
        #expect(try persistence.loadItems() == [committedItem])

        failBlobWrite = false
        failManifestWrite = true
        var manifestSaveFailed = false
        do {
            try persistence.save([updatedItem])
        } catch {
            manifestSaveFailed = true
        }

        let currentBlobs = try blobSnapshot(
            in: directory.appendingPathComponent("history-media", isDirectory: true)
        )
        #expect(manifestSaveFailed)
        #expect(try Data(contentsOf: persistence.historyURL) == committedManifest)
        #expect(committedBlobs.allSatisfy { currentBlobs[$0.key] == $0.value })
        #expect(try persistence.loadItems() == [committedItem])
    }

    @Test func missingReferencedBlobFailsHistoryLoad() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "ClipboardHistoryPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        let persistence = ClipboardHistoryPersistence(directoryURL: directory, userDefaults: defaults)
        let item = persistenceTestItem(
            id: "00000000-0000-0000-0000-000000000042",
            sourceIcon: nil,
            image: Data(repeating: 0x44, count: 256)
        )
        try persistence.save([item])
        let mediaDirectory = directory.appendingPathComponent("history-media", isDirectory: true)
        let blob = try #require(FileManager.default.contentsOfDirectory(
            at: mediaDirectory,
            includingPropertiesForKeys: nil
        ).first)
        try FileManager.default.removeItem(at: blob)

        var failedToLoad = false
        do {
            _ = try persistence.loadItems()
        } catch {
            failedToLoad = true
        }

        #expect(failedToLoad)
    }

    @Test func failedMigrationKeepsLegacyPreferencesUntilManifestCommit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "ClipboardHistoryPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        var failManifestWrite = true
        let persistence = ClipboardHistoryPersistence(
            directoryURL: directory,
            userDefaults: defaults,
            writeData: { data, url in
                if failManifestWrite && url.lastPathComponent == "clipboard-history.json" {
                    throw PersistenceTestFailure.injectedWriteFailure
                }
                try data.write(to: url, options: [.atomic])
            }
        )
        let item = persistenceTestItem(
            id: "00000000-0000-0000-0000-000000000043",
            sourceIcon: nil,
            image: Data([0x45, 0x46])
        )
        let legacyData = try JSONEncoder().encode([item])
        defaults.set(legacyData, forKey: "clipboardItems")
        #expect(try persistence.loadItems() == [item])

        var saveFailed = false
        do {
            try persistence.save([item])
        } catch {
            saveFailed = true
        }

        #expect(saveFailed)
        #expect(defaults.data(forKey: "clipboardItems") == legacyData)
        #expect(!FileManager.default.fileExists(atPath: persistence.historyURL.path))

        failManifestWrite = false
        try persistence.save([item])

        #expect(defaults.data(forKey: "clipboardItems") == nil)
        #expect(try persistence.loadItems() == [item])
    }

    @Test func loadsVersionOneWrapperAndRawArrayWithoutMigrationWrites() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "ClipboardHistoryPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        let persistence = ClipboardHistoryPersistence(directoryURL: directory, userDefaults: defaults)
        let legacyItem = persistenceTestItem(
            id: "00000000-0000-0000-0000-000000000031",
            sourceIcon: Data([0x31, 0x32]),
            image: Data([0x33, 0x34])
        )
        let wrapperData = try JSONEncoder().encode(LegacyHistoryFixture(version: 1, items: [legacyItem]))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try wrapperData.write(to: persistence.historyURL)

        #expect(try persistence.loadItems() == [legacyItem])
        #expect(try Data(contentsOf: persistence.historyURL) == wrapperData)

        let rawData = try JSONEncoder().encode([legacyItem])
        try rawData.write(to: persistence.historyURL)

        #expect(try persistence.loadItems() == [legacyItem])
        #expect(try Data(contentsOf: persistence.historyURL) == rawData)
    }

    @Test func legacyPreferencesRemainAvailableUntilSuccessfulSave() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "ClipboardHistoryPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        let persistence = ClipboardHistoryPersistence(directoryURL: directory, userDefaults: defaults)
        let legacyItem = persistenceTestItem(
            id: "00000000-0000-0000-0000-000000000032",
            sourceIcon: Data([0x35]),
            image: Data([0x36])
        )
        let legacyData = try JSONEncoder().encode([legacyItem])
        defaults.set(legacyData, forKey: "clipboardItems")

        #expect(try persistence.loadItems() == [legacyItem])
        #expect(defaults.data(forKey: "clipboardItems") == legacyData)
        #expect(!FileManager.default.fileExists(atPath: persistence.historyURL.path))

        try persistence.save([legacyItem])

        #expect(defaults.data(forKey: "clipboardItems") == nil)
        #expect(try persistence.loadItems() == [legacyItem])
    }

    @Test func loadReadsSharedBlobOnlyOncePerLoad() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "ClipboardHistoryPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        var blobReads: [String] = []
        let persistence = ClipboardHistoryPersistence(
            directoryURL: directory,
            userDefaults: defaults,
            readData: { url in
                if url.pathExtension == "blob" {
                    blobReads.append(url.lastPathComponent)
                }
                return try Data(contentsOf: url)
            }
        )
        let sharedMedia = Data(repeating: 0x37, count: 512)
        let expected = [
            persistenceTestItem(
                id: "00000000-0000-0000-0000-000000000033",
                sourceIcon: sharedMedia,
                image: sharedMedia
            ),
            persistenceTestItem(
                id: "00000000-0000-0000-0000-000000000034",
                sourceIcon: sharedMedia,
                linkImage: sharedMedia
            )
        ]
        try persistence.save(expected)

        let actual = try persistence.loadItems()

        #expect(actual == expected)
        #expect(blobReads.count == 1)
        #expect(Set(blobReads).count == 1)
    }

    @Test func linkPreviewAddsOnlyItsBlobAndWritesManifestAfterBlob() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "ClipboardHistoryPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        var writes: [URL] = []
        let persistence = ClipboardHistoryPersistence(
            directoryURL: directory,
            userDefaults: defaults,
            writeData: { data, url in
                writes.append(url)
                try data.write(to: url, options: [.atomic])
            }
        )
        let icon = Data(repeating: 0x41, count: 128)
        let unrelatedImage = Data(repeating: 0x42, count: 2_048)
        let urlItem = ClipboardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
            kind: .url,
            title: "Example",
            preview: "https://example.com",
            sourceApp: "Safari",
            sourceAppIconData: icon,
            createdAt: Date(timeIntervalSince1970: 1_700_000_021),
            isPinned: false,
            pinboardName: nil,
            textValue: "https://example.com",
            fileURLs: [],
            imageData: nil
        )
        let otherItem = persistenceTestItem(
            id: "00000000-0000-0000-0000-000000000022",
            sourceIcon: nil,
            image: unrelatedImage
        )

        try persistence.save([urlItem, otherItem])

        let mediaDirectory = directory.appendingPathComponent("history-media", isDirectory: true)
        let existingBlobs = try blobSnapshot(in: mediaDirectory)
        let existingWriteCount = writes.count
        let preview = Data(repeating: 0x43, count: 4_096)
        let updatedURLItem = urlItem.withLinkPreview(title: "Loaded title", linkImageData: preview)
        try persistence.save([updatedURLItem, otherItem])

        let newWrites = Array(writes.dropFirst(existingWriteCount))
        let currentBlobs = try blobSnapshot(in: mediaDirectory)
        let loadedItems = try persistence.loadItems()

        #expect(newWrites.count == 2)
        #expect(newWrites[0].pathExtension == "blob")
        #expect(newWrites[1] == persistence.historyURL)
        #expect(currentBlobs.count == existingBlobs.count + 1)
        #expect(existingBlobs.allSatisfy { currentBlobs[$0.key] == $0.value })
        #expect(loadedItems == [updatedURLItem, otherItem])
    }

    @Test func sharedMediaIsWrittenOnceAndPinChangesWriteNoBlobBytes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "ClipboardHistoryPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        var blobWrites: [String] = []
        var blobBytesWritten = 0
        let persistence = ClipboardHistoryPersistence(
            directoryURL: directory,
            userDefaults: defaults,
            writeData: { data, url in
                if url.pathExtension == "blob" {
                    blobWrites.append(url.lastPathComponent)
                    blobBytesWritten += data.count
                }
                try data.write(to: url, options: [.atomic])
            }
        )
        let sharedIcon = Data(repeating: 0x11, count: 128)
        let image = Data(repeating: 0x22, count: 2 * 1_024 * 1_024)
        let preview = Data(repeating: 0x33, count: 256)
        let items = [
            persistenceTestItem(
                id: "00000000-0000-0000-0000-000000000011",
                sourceIcon: sharedIcon,
                image: image
            ),
            persistenceTestItem(
                id: "00000000-0000-0000-0000-000000000012",
                sourceIcon: sharedIcon,
                linkImage: preview
            )
        ]

        try persistence.save(items)

        let mediaDirectory = directory.appendingPathComponent("history-media", isDirectory: true)
        let originalBlobURLs = try FileManager.default.contentsOfDirectory(
            at: mediaDirectory,
            includingPropertiesForKeys: nil
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        let originalContents = try originalBlobURLs.map { try Data(contentsOf: $0) }
        let originalNames = originalBlobURLs.map(\.lastPathComponent)
        let expectedUniqueBytes = sharedIcon.count + image.count + preview.count

        #expect(blobWrites.count == 3)
        #expect(Set(blobWrites).count == 3)
        #expect(blobBytesWritten == expectedUniqueBytes)
        #expect(originalNames.count == 3)
        #expect(originalContents.sorted { $0.count < $1.count }.map(\.count) == [128, 256, 2 * 1_024 * 1_024])

        var pinnedItems = items
        pinnedItems[0].isPinned = true
        try persistence.save(pinnedItems)

        let rewrittenBlobURLs = try FileManager.default.contentsOfDirectory(
            at: mediaDirectory,
            includingPropertiesForKeys: nil
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        let rewrittenContents = try rewrittenBlobURLs.map { try Data(contentsOf: $0) }

        #expect(blobWrites.count == 3)
        #expect(blobBytesWritten == expectedUniqueBytes)
        #expect(rewrittenBlobURLs.map(\.lastPathComponent) == originalNames)
        #expect(rewrittenContents == originalContents)
    }

    @Test func writesMediaToBlobAndKeepsV2ManifestMetadataOnly() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "ClipboardHistoryPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        let persistence = ClipboardHistoryPersistence(directoryURL: directory, userDefaults: defaults)
        let media = Data(repeating: 0x6d, count: 128)
        let item = ClipboardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
            kind: .image,
            title: "Image",
            preview: "Image preview",
            sourceApp: "Preview",
            sourceAppIconData: media,
            createdAt: Date(timeIntervalSince1970: 1_700_000_005),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: media
        )

        try persistence.save([item])

        let manifest = try Data(contentsOf: persistence.historyURL)
        let manifestObject = try #require(JSONSerialization.jsonObject(with: manifest) as? [String: Any])
        let manifestText = try #require(String(data: manifest, encoding: .utf8))
        let mediaDirectory = directory.appendingPathComponent("history-media", isDirectory: true)
        let blobURLs = try FileManager.default.contentsOfDirectory(
            at: mediaDirectory,
            includingPropertiesForKeys: nil
        )

        #expect(manifestObject["version"] as? Int == 2)
        #expect(!manifestText.contains(media.base64EncodedString()))
        #expect(blobURLs.count == 1)
        #expect(try Data(contentsOf: try #require(blobURLs.first)) == media)
    }

    @Test func savesAndReloadsEveryRuntimeVisibleClipboardField() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "ClipboardHistoryPersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        let persistence = ClipboardHistoryPersistence(directoryURL: directory, userDefaults: defaults)
        let iconData = Data([0x89, 0x50, 0x4e, 0x47, 0x01])
        let imageData = Data([0x89, 0x50, 0x4e, 0x47, 0x02])
        let linkImageData = Data([0x89, 0x50, 0x4e, 0x47, 0x03])
        let expected = [
            ClipboardItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                kind: .text,
                title: "Text title",
                preview: "Text preview",
                sourceApp: "Notes",
                sourceAppIconData: iconData,
                createdAt: Date(timeIntervalSince1970: 1_700_000_001),
                isPinned: true,
                pinboardName: "Work",
                textValue: "Exact text value",
                fileURLs: [],
                imageData: nil,
                linkTitle: nil,
                linkImageData: nil
            ),
            ClipboardItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                kind: .url,
                title: "Example",
                preview: "https://example.com/item",
                sourceApp: "Safari",
                sourceAppIconData: iconData,
                createdAt: Date(timeIntervalSince1970: 1_700_000_002),
                isPinned: false,
                pinboardName: nil,
                textValue: "https://example.com/item",
                fileURLs: [],
                imageData: nil,
                linkTitle: "Example link title",
                linkImageData: linkImageData
            ),
            ClipboardItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                kind: .image,
                title: "Image title",
                preview: "640 x 480",
                sourceApp: "Preview",
                sourceAppIconData: nil,
                createdAt: Date(timeIntervalSince1970: 1_700_000_003),
                isPinned: false,
                pinboardName: "Design",
                textValue: nil,
                fileURLs: [],
                imageData: imageData
            ),
            ClipboardItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
                kind: .file,
                title: "report.pdf",
                preview: "/tmp/report.pdf",
                sourceApp: "Finder",
                sourceAppIconData: nil,
                createdAt: Date(timeIntervalSince1970: 1_700_000_004),
                isPinned: true,
                pinboardName: "Work",
                textValue: nil,
                fileURLs: [URL(fileURLWithPath: "/tmp/report.pdf")],
                imageData: nil
            )
        ]

        try persistence.save(expected)
        let actual = try persistence.loadItems()

        #expect(actual == expected)
    }

    private func persistenceTestItem(
        id: String,
        sourceIcon: Data?,
        image: Data? = nil,
        linkImage: Data? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(uuidString: id)!,
            kind: .image,
            title: "Image",
            preview: "Image preview",
            sourceApp: "Preview",
            sourceAppIconData: sourceIcon,
            createdAt: Date(timeIntervalSince1970: 1_700_000_011),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: image,
            linkImageData: linkImage
        )
    }

    private func blobSnapshot(in directory: URL) throws -> [String: Data] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .reduce(into: [:]) { snapshot, url in
                snapshot[url.lastPathComponent] = try Data(contentsOf: url)
            }
    }
}
