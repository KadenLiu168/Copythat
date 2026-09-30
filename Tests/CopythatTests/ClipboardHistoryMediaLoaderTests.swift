@testable import Copythat
import CryptoKit
import Foundation
import Testing

private final class LoaderReadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var blobNames: [String] = []
    private var mainThreadFlags: [Bool] = []

    func read(_ url: URL) throws -> Data {
        lock.lock()
        blobNames.append(url.lastPathComponent)
        mainThreadFlags.append(Thread.isMainThread)
        lock.unlock()
        return try Data(contentsOf: url)
    }

    func reads() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return blobNames
    }

    func ranOnMainThread() -> [Bool] {
        lock.lock()
        defer { lock.unlock() }
        return mainThreadFlags
    }
}

private final class BlockingLoaderReader: @unchecked Sendable {
    let firstReadStarted = DispatchSemaphore(value: 0)
    let releaseFirstRead = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var count = 0
    private var didBlockFirstRead = false

    func read(_ url: URL) throws -> Data {
        lock.lock()
        count += 1
        let shouldBlock = !didBlockFirstRead
        if shouldBlock {
            didBlockFirstRead = true
        }
        lock.unlock()
        if shouldBlock {
            firstReadStarted.signal()
            _ = releaseFirstRead.wait(timeout: .now() + 5)
        }
        return try Data(contentsOf: url)
    }

    func readCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

struct ClipboardHistoryMediaLoaderTests {
    @Test func verifiedReadReturnsBytesAndRejectsMissingOrCorruptFiles() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let loader = ClipboardHistoryMediaLoader(
            blobStore: ClipboardHistoryBlobStore(
                directoryURL: directory,
                readData: { try Data(contentsOf: $0) }
            )
        )
        let bytes = Data([1, 2, 3, 4])
        let blobID = sha256Hex(bytes)
        try bytes.write(to: directory.appendingPathComponent("\(blobID).blob"))

        #expect(try await loader.load(blobID: blobID) == bytes)

        let missingID = sha256Hex(Data([9, 9]))
        await #expect(throws: (any Error).self) {
            try await loader.load(blobID: missingID)
        }

        let corruptBytes = Data([5, 5, 5])
        let corruptID = sha256Hex(corruptBytes)
        try Data([0x00]).write(to: directory.appendingPathComponent("\(corruptID).blob"))
        await #expect(throws: (any Error).self) {
            try await loader.load(blobID: corruptID)
        }
    }

    @Test func invalidIDsFailWithoutReadingDisk() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = LoaderReadRecorder()
        let loader = ClipboardHistoryMediaLoader(
            blobStore: ClipboardHistoryBlobStore(directoryURL: directory, readData: recorder.read)
        )

        for invalidID in [
            String(repeating: "a", count: 63),
            String(repeating: "A", count: 64),
            String(repeating: "Z", count: 64),
            String(repeating: "./", count: 32)
        ] {
            await #expect(throws: (any Error).self) {
                try await loader.load(blobID: invalidID)
            }
        }

        #expect(recorder.reads().isEmpty)
    }

    @Test func loadsRunOffMainThread() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = LoaderReadRecorder()
        let loader = ClipboardHistoryMediaLoader(
            blobStore: ClipboardHistoryBlobStore(directoryURL: directory, readData: recorder.read)
        )
        let bytes = Data(repeating: 0x01, count: 32)
        let blobID = sha256Hex(bytes)
        try bytes.write(to: directory.appendingPathComponent("\(blobID).blob"))

        _ = try await loader.load(blobID: blobID)

        #expect(!recorder.ranOnMainThread().isEmpty)
        #expect(recorder.ranOnMainThread().allSatisfy { !$0 })
    }

    @Test func repeatedLoadReadsDiskOnceAndRefreshesRecency() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = LoaderReadRecorder()
        let loader = ClipboardHistoryMediaLoader(
            blobStore: ClipboardHistoryBlobStore(directoryURL: directory, readData: recorder.read),
            byteBudget: 10_000
        )
        let bytes = Data(repeating: 0x11, count: 100)
        let blobID = sha256Hex(bytes)
        try bytes.write(to: directory.appendingPathComponent("\(blobID).blob"))

        #expect(try await loader.load(blobID: blobID) == bytes)
        #expect(try await loader.load(blobID: blobID) == bytes)

        #expect(recorder.reads().count == 1)
        AcceptanceMetrics.record(
            scenario: "media-loader",
            metric: "diskReadsForRepeatedLoad",
            expected: "1",
            observed: "\(recorder.reads().count)"
        )
    }

    @Test func byteCostLRUEvictsLeastRecentlyUsedEntries() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = LoaderReadRecorder()
        let loader = ClipboardHistoryMediaLoader(
            blobStore: ClipboardHistoryBlobStore(directoryURL: directory, readData: recorder.read),
            byteBudget: 250
        )
        let blobs = [
            Data(repeating: 0x21, count: 100),
            Data(repeating: 0x22, count: 100),
            Data(repeating: 0x23, count: 100)
        ]
        let ids = blobs.map { blobID in
            sha256Hex(blobID)
        }
        for (bytes, blobID) in zip(blobs, ids) {
            try bytes.write(to: directory.appendingPathComponent("\(blobID).blob"))
        }

        _ = try await loader.load(blobID: ids[0])
        _ = try await loader.load(blobID: ids[1])
        _ = try await loader.load(blobID: ids[0])
        _ = try await loader.load(blobID: ids[2])
        let readsAfterEviction = recorder.reads().count
        #expect(readsAfterEviction == 3)

        _ = try await loader.load(blobID: ids[0])
        #expect(recorder.reads().count == readsAfterEviction)
        _ = try await loader.load(blobID: ids[1])
        #expect(recorder.reads().count == readsAfterEviction + 1)
    }

    @Test func oversizedBlobIsReturnedWithoutBeingCached() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = LoaderReadRecorder()
        let loader = ClipboardHistoryMediaLoader(
            blobStore: ClipboardHistoryBlobStore(directoryURL: directory, readData: recorder.read),
            byteBudget: 100
        )
        let bytes = Data(repeating: 0x31, count: 500)
        let blobID = sha256Hex(bytes)
        try bytes.write(to: directory.appendingPathComponent("\(blobID).blob"))

        #expect(try await loader.load(blobID: blobID) == bytes)
        #expect(try await loader.load(blobID: blobID) == bytes)

        #expect(recorder.reads().count == 2)
        AcceptanceMetrics.record(
            scenario: "media-loader",
            metric: "diskReadsForOversizedBlobTwice",
            expected: "2",
            observed: "\(recorder.reads().count)"
        )
    }

    @Test func failedLoadIsNotCachedAndSucceedsAfterRepair() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = LoaderReadRecorder()
        let loader = ClipboardHistoryMediaLoader(
            blobStore: ClipboardHistoryBlobStore(directoryURL: directory, readData: recorder.read),
            byteBudget: 10_000
        )
        let bytes = Data(repeating: 0x41, count: 64)
        let blobID = sha256Hex(bytes)
        let blobURL = directory.appendingPathComponent("\(blobID).blob")
        try Data([0x00]).write(to: blobURL)

        await #expect(throws: (any Error).self) {
            try await loader.load(blobID: blobID)
        }

        try bytes.write(to: blobURL)
        #expect(try await loader.load(blobID: blobID) == bytes)
        #expect(try await loader.load(blobID: blobID) == bytes)
        #expect(recorder.reads().count == 2)
    }

    @Test func cancelledQueuedRequestDoesNotStartARead() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = BlockingLoaderReader()
        let loader = ClipboardHistoryMediaLoader(
            blobStore: ClipboardHistoryBlobStore(directoryURL: directory, readData: reader.read),
            byteBudget: 10_000
        )
        let firstBytes = Data(repeating: 0x51, count: 64)
        let secondBytes = Data(repeating: 0x52, count: 64)
        let firstID = sha256Hex(firstBytes)
        let secondID = sha256Hex(secondBytes)
        try firstBytes.write(to: directory.appendingPathComponent("\(firstID).blob"))
        try secondBytes.write(to: directory.appendingPathComponent("\(secondID).blob"))

        let firstTask = Task { try await loader.load(blobID: firstID) }
        #expect(reader.firstReadStarted.wait(timeout: .now() + 5) == .success)

        let secondTask = Task { try await loader.load(blobID: secondID) }
        secondTask.cancel()

        reader.releaseFirstRead.signal()
        #expect(try await firstTask.value == firstBytes)

        var secondFailed = false
        do {
            _ = try await secondTask.value
        } catch {
            secondFailed = true
        }
        #expect(secondFailed)
        #expect(reader.readCount() == 1)
        AcceptanceMetrics.record(
            scenario: "media-loader",
            metric: "diskReadsAfterQueuedCancellation",
            expected: "1",
            observed: "\(reader.readCount())"
        )
    }

    @Test func seededCommittedMediaIsReusedWithoutDiskReadsOrHashes() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = LoaderReadRecorder()
        let loader = ClipboardHistoryMediaLoader(
            blobStore: ClipboardHistoryBlobStore(directoryURL: directory, readData: recorder.read),
            byteBudget: 10_000
        )
        let prepared = PreparedMedia(hashing: Data(repeating: 0x61, count: 256))
        try prepared.data.write(to: directory.appendingPathComponent("\(prepared.id).blob"))

        let counters = MediaOperationCounters()
        await counters.measure { await loader.seedCommitted([prepared]) }
        #expect(counters.mediaHashCount == 0, "seeding must not hash committed bytes")

        counters.reset()
        let loaded = try await counters.measure { try await loader.load(blobID: prepared.id) }

        #expect(loaded == prepared.data)
        #expect(recorder.reads().isEmpty, "a seeded hit must not read disk")
        #expect(counters.mediaHashCount == 0, "a seeded hit must not verify or re-identify bytes")
        #expect(await loader.retainedByteCost == prepared.data.count)
        AcceptanceMetrics.record(
            scenario: "media-loader",
            metric: "diskReadsForSeededCommittedMedia",
            expected: "0",
            observed: "\(recorder.reads().count)"
        )
    }

    @Test func seedingAccountsRepeatedIdentitiesOnce() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = LoaderReadRecorder()
        let loader = ClipboardHistoryMediaLoader(
            blobStore: ClipboardHistoryBlobStore(directoryURL: directory, readData: recorder.read),
            byteBudget: 250
        )
        let first = PreparedMedia(hashing: Data(repeating: 0x62, count: 100))
        let second = PreparedMedia(hashing: Data(repeating: 0x63, count: 100))
        for prepared in [first, second] {
            try prepared.data.write(to: directory.appendingPathComponent("\(prepared.id).blob"))
        }

        await loader.seedCommitted([first, first, second])

        #expect(await loader.retainedByteCost == 200, "a repeated identity must cost its bytes once")
        #expect(try await loader.load(blobID: first.id) == first.data)
        #expect(try await loader.load(blobID: second.id) == second.data)
        #expect(recorder.reads().isEmpty)
    }

    @Test func seedingEvictsLeastRecentlySeededEntriesWithinBudget() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = LoaderReadRecorder()
        let loader = ClipboardHistoryMediaLoader(
            blobStore: ClipboardHistoryBlobStore(directoryURL: directory, readData: recorder.read),
            byteBudget: 250
        )
        let oldest = PreparedMedia(hashing: Data(repeating: 0x64, count: 100))
        let middle = PreparedMedia(hashing: Data(repeating: 0x65, count: 100))
        let newest = PreparedMedia(hashing: Data(repeating: 0x66, count: 100))
        for prepared in [oldest, middle, newest] {
            try prepared.data.write(to: directory.appendingPathComponent("\(prepared.id).blob"))
        }

        await loader.seedCommitted([oldest, middle, newest])

        #expect(await loader.retainedByteCost == 200)
        #expect(await loader.retainedByteCost <= 250, "byte accounting must stay within budget")
        // The newest entries were seeded last, so the oldest one is the eviction
        // candidate and a release of it can still be read back from disk.
        #expect(try await loader.load(blobID: newest.id) == newest.data)
        #expect(try await loader.load(blobID: middle.id) == middle.data)
        #expect(recorder.reads().isEmpty)
        #expect(try await loader.load(blobID: oldest.id) == oldest.data)
        #expect(recorder.reads() == ["\(oldest.id).blob"])
    }

    @Test func oversizedSeedIsSkippedAndItsAccessStaysAVerifiedDiskRead() async throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = LoaderReadRecorder()
        let loader = ClipboardHistoryMediaLoader(
            blobStore: ClipboardHistoryBlobStore(directoryURL: directory, readData: recorder.read),
            byteBudget: 250
        )
        let first = PreparedMedia(hashing: Data(repeating: 0x67, count: 100))
        let second = PreparedMedia(hashing: Data(repeating: 0x68, count: 100))
        let oversized = PreparedMedia(hashing: Data(repeating: 0x69, count: 500))
        for prepared in [first, second, oversized] {
            try prepared.data.write(to: directory.appendingPathComponent("\(prepared.id).blob"))
        }

        await loader.seedCommitted([first, second, oversized])

        #expect(await loader.retainedByteCost == 200, "an impossible insertion must not displace useful entries")
        #expect(try await loader.load(blobID: first.id) == first.data)
        #expect(try await loader.load(blobID: second.id) == second.data)
        #expect(recorder.reads().isEmpty)

        let counters = MediaOperationCounters()
        let loaded = try await counters.measure { try await loader.load(blobID: oversized.id) }
        #expect(loaded == oversized.data)
        #expect(recorder.reads() == ["\(oversized.id).blob"])
        #expect(counters.integrityHashCount == 1, "an uncached oversized payload is verified on read")
        #expect(await loader.retainedByteCost == 200)

        try Data([0x00]).write(to: directory.appendingPathComponent("\(oversized.id).blob"))
        await #expect(throws: (any Error).self) {
            try await loader.load(blobID: oversized.id)
        }
    }

    private func makeDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryMediaLoaderTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
