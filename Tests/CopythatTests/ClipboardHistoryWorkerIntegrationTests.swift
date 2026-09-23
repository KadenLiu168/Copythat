@testable import Copythat
import AppKit
import Foundation
import Testing

private final class PersistenceWriteProbe: @unchecked Sendable {
    struct Snapshot: Sendable {
        let blobNames: [String]
        let blobBytes: Int
        let writesOnMainThread: [Bool]
        let maximumConcurrentWrites: Int
    }

    private let lock = NSLock()
    private var blobNames: [String] = []
    private var blobBytes = 0
    private var writesOnMainThread: [Bool] = []
    private var activeWrites = 0
    private var maximumConcurrentWrites = 0

    func beginWrite(data: Data, url: URL) {
        lock.lock()
        activeWrites += 1
        maximumConcurrentWrites = max(maximumConcurrentWrites, activeWrites)
        writesOnMainThread.append(Thread.isMainThread)
        if url.pathExtension == "blob" {
            blobNames.append(url.lastPathComponent)
            blobBytes += data.count
        }
        lock.unlock()
    }

    func endWrite() {
        lock.lock()
        activeWrites -= 1
        lock.unlock()
    }

    func reset() {
        lock.lock()
        blobNames.removeAll()
        blobBytes = 0
        writesOnMainThread.removeAll()
        maximumConcurrentWrites = activeWrites
        lock.unlock()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            blobNames: blobNames,
            blobBytes: blobBytes,
            writesOnMainThread: writesOnMainThread,
            maximumConcurrentWrites: maximumConcurrentWrites
        )
    }
}

private final class FirstManifestWriteBarrier: @unchecked Sendable {
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var isArmed = false
    private var didBlock = false
    private var didStart = false
    private var startWaiter: CheckedContinuation<Void, Never>?

    func arm() {
        lock.lock()
        isArmed = true
        didBlock = false
        didStart = false
        lock.unlock()
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if didStart {
                lock.unlock()
                continuation.resume()
            } else {
                startWaiter = continuation
                lock.unlock()
            }
        }
    }

    func blockFirstManifestWrite(at url: URL) throws {
        guard url.lastPathComponent == "clipboard-history.json" else { return }
        lock.lock()
        let shouldBlock = isArmed && !didBlock
        let waiter: CheckedContinuation<Void, Never>?
        if shouldBlock {
            didBlock = true
            didStart = true
            waiter = startWaiter
            startWaiter = nil
        } else {
            waiter = nil
        }
        lock.unlock()
        guard shouldBlock else { return }

        waiter?.resume()
        guard release.wait(timeout: .now() + 5) == .success else {
            throw ClipboardHistoryTestError.writeBarrierTimedOut
        }
    }
}

private final class ManifestReferenceProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var observedItemCounts: [Int] = []

    func record(_ count: Int) {
        lock.lock()
        observedItemCounts.append(count)
        lock.unlock()
    }

    func counts() -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return observedItemCounts
    }
}

private enum ClipboardHistoryTestError: Error {
    case writeBarrierTimedOut
}

@MainActor
@Suite(.serialized)
struct ClipboardHistoryWorkerIntegrationTests {
    @Test func serialWorkerExcludesConcurrentWritersAndRejectsLateOldGeneration() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryWorkerTests-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "ClipboardHistoryWorkerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        let probe = PersistenceWriteProbe()
        let barrier = FirstManifestWriteBarrier()
        let persistence = ClipboardHistoryPersistence(
            directoryURL: directory,
            userDefaults: defaults,
            writeData: { data, url in
                probe.beginWrite(data: data, url: url)
                defer { probe.endWrite() }
                try barrier.blockFirstManifestWrite(at: url)
                try data.write(to: url, options: [.atomic])
            }
        )
        let worker = ClipboardHistorySaveWorker(persistence: persistence)
        let first = historyItem("first")
        let second = historyItem("second")

        barrier.arm()
        let firstSave = Task.detached {
            try await worker.save([first], generation: 1)
        }
        await barrier.waitUntilStarted()

        let secondSave = Task.detached {
            try await worker.save([second], generation: 2)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(probe.snapshot().maximumConcurrentWrites == 1)

        barrier.release.signal()
        try await firstSave.value
        try await secondSave.value
        let probeSnapshot = probe.snapshot()

        #expect(probeSnapshot.maximumConcurrentWrites == 1)
        #expect(probeSnapshot.writesOnMainThread == [false, false])
        #expect(await worker.lastCommittedGeneration == 2)
        #expect(try persistence.loadItems() == [second])

        var staleGenerationRejected = false
        do {
            try await worker.save([first], generation: 1)
        } catch {
            staleGenerationRejected = true
        }
        #expect(staleGenerationRejected)
        #expect(try persistence.loadItems() == [second])
    }

    @Test func coordinatorDefersGarbageCollectionUntilLatestPendingSnapshotCommits() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryWorkerTests-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "ClipboardHistoryWorkerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        let barrier = FirstManifestWriteBarrier()
        let manifestProbe = ManifestReferenceProbe()
        let manifestURL = directory.appendingPathComponent("clipboard-history.json")
        let persistence = ClipboardHistoryPersistence(
            directoryURL: directory,
            userDefaults: defaults,
            writeData: { data, url in
                try barrier.blockFirstManifestWrite(at: url)
                try data.write(to: url, options: [.atomic])
            },
            removeItem: { url in
                let data = try Data(contentsOf: manifestURL)
                let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let items = object?["items"] as? [[String: Any]] ?? []
                manifestProbe.record(items.count)
                try FileManager.default.removeItem(at: url)
            }
        )
        let coordinator = ClipboardHistorySaveCoordinator(worker: ClipboardHistorySaveWorker(persistence: persistence))
        let image = ClipboardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000a1")!,
            kind: .image,
            title: "Image",
            preview: "Image",
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_101),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: Data(repeating: 0xa1, count: 1_024)
        )

        barrier.arm()
        coordinator.requestSave([image])
        await barrier.waitUntilStarted()
        coordinator.requestSave([])
        barrier.release.signal()

        #expect(await coordinator.flush())
        let mediaDirectory = directory.appendingPathComponent("history-media", isDirectory: true)
        #expect(manifestProbe.counts() == [0])
        #expect(try persistence.loadItems().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(at: mediaDirectory, includingPropertiesForKeys: nil).isEmpty)
    }

    @Test func imageHeavyPinMutationRunsWorkerWritesOffMainAndReusesEveryBlob() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardHistoryWorkerTests-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "ClipboardHistoryWorkerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }

        let probe = PersistenceWriteProbe()
        let barrier = FirstManifestWriteBarrier()
        let persistence = ClipboardHistoryPersistence(
            directoryURL: directory,
            userDefaults: defaults,
            writeData: { data, url in
                probe.beginWrite(data: data, url: url)
                defer { probe.endWrite() }
                try barrier.blockFirstManifestWrite(at: url)
                try data.write(to: url, options: [.atomic])
            }
        )
        let media = Data(repeating: 0xa2, count: 2 * 1_024 * 1_024)
        let icon = Data(repeating: 0xa3, count: 512)
        let linkPreview = Data(repeating: 0xa4, count: 4_096)
        let item = ClipboardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000a2")!,
            kind: .image,
            title: "Image-heavy history item",
            preview: "2 MB",
            sourceApp: "Tests",
            sourceAppIconData: icon,
            createdAt: Date(timeIntervalSince1970: 1_700_000_102),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: media,
            linkImageData: linkPreview
        )
        try persistence.save([item])
        let mediaDirectory = directory.appendingPathComponent("history-media", isDirectory: true)
        let originalBlobs = try blobSnapshot(in: mediaDirectory)
        probe.reset()

        let coordinator = ClipboardHistorySaveCoordinator(worker: ClipboardHistorySaveWorker(persistence: persistence))
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: [item],
            pasteboard: NSPasteboard.withUniqueName(),
            persistItems: { coordinator.requestSave($0) }
        )
        barrier.arm()
        store.togglePin(item)
        await barrier.waitUntilStarted()
        #expect(store.items.first?.isPinned == true)
        #expect(probe.snapshot().writesOnMainThread == [false])
        barrier.release.signal()

        #expect(await coordinator.flush())
        let latestProbe = probe.snapshot()
        let newBlobs = try blobSnapshot(in: mediaDirectory)
        let manifest = try Data(contentsOf: persistence.historyURL)
        let manifestText = try #require(String(data: manifest, encoding: .utf8))

        #expect(latestProbe.blobNames.isEmpty)
        #expect(latestProbe.blobBytes == 0)
        #expect(latestProbe.writesOnMainThread == [false])
        #expect(newBlobs == originalBlobs)
        #expect(!manifestText.contains(media.base64EncodedString()))
        #expect(!manifestText.contains(icon.base64EncodedString()))
        #expect(!manifestText.contains(linkPreview.base64EncodedString()))
        #expect(try persistence.loadItems().first?.isPinned == true)
    }

    private func historyItem(_ value: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000a0")!,
            kind: .text,
            title: value,
            preview: value,
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            isPinned: false,
            pinboardName: nil,
            textValue: value,
            fileURLs: [],
            imageData: nil
        )
    }

    private func blobSnapshot(in directory: URL) throws -> [String: Data] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .reduce(into: [:]) { snapshot, url in
                snapshot[url.lastPathComponent] = try Data(contentsOf: url)
            }
    }
}
