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
