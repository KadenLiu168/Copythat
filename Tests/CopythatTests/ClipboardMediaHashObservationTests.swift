@testable import Copythat
import AppKit
import CryptoKit
import Foundation
import Testing

/// Observation seam contracts: the two media digest operations are counted
/// where they actually run, across detached preparation and actor hops, and
/// only inside the measurement window that installed the recorder.
struct ClipboardMediaHashObservationTests {
    @Test func identityCreationAndBlobVerificationAreObservedSeparately() async throws {
        let counters = MediaOperationCounters()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaHashObservation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blobStore = ClipboardHistoryBlobStore(
            directoryURL: directory,
            readData: { try Data(contentsOf: $0) }
        )
        let media = Data(repeating: 0xab, count: 128)

        counters.reset()
        let prepared = await counters.measure { PreparedMedia(hashing: media) }
        #expect(counters.identityHashCount == 1)
        #expect(counters.integrityHashCount == 0)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try media.write(to: try blobStore.blobURL(for: prepared.id))

        counters.reset()
        let verified = try await counters.measure { try blobStore.read(blobID: prepared.id) }
        #expect(verified == media)
        #expect(counters.identityHashCount == 0)
        #expect(counters.integrityHashCount == 1)
        #expect(counters.mediaHashCount == 1)
    }

    @Test func workOutsideTheMeasurementWindowIsNotCounted() async {
        let counters = MediaOperationCounters()
        let media = Data(repeating: 0xcd, count: 64)

        let measured = await counters.measure { PreparedMedia(hashing: media).id }
        let unmeasured = PreparedMedia(hashing: media).id

        #expect(measured == unmeasured)
        #expect(counters.identityHashCount == 1)
    }

    @MainActor
    @Test func detachedPreparationPropagatesTheRecorder() async throws {
        let counters = MediaOperationCounters()
        let counter = LinkPreviewCounter()
        let icon = Data(repeating: 0x31, count: 96)
        let source = ClipboardSource(appName: "Tests", iconData: icon, capturedAt: Date())
        let clock = MutableClock()
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults()),
            sourceTracker: CopySourceTracker(frontmostSourceProvider: { source }),
            initialItems: [],
            pasteboard: pasteboard,
            persistItems: { _ in counter.mark("saved") },
            uptimeProvider: { clock.now },
            fetchLinkMetadata: { _ in throw URLError(.unsupportedURL) },
            fetchLinkSnapshot: { _ in throw URLError(.unsupportedURL) }
        )
        let image = LinkPreviewFixture.testImage()

        counters.reset()
        try await counters.measure {
            pasteboard.clearContents()
            #expect(pasteboard.writeObjects([image]))
            store.pollPasteboard()
            clock.advance(by: 1)
            store.pollPasteboard()
            await counter.waitFor("saved", reaching: 1)
        }

        let captured = try #require(store.items.first)
        #expect(captured.kind == .image)
        // The payload was prepared once inside the detached encoding task, and
        // the source snapshot prepared above the window contributed no further
        // identity hash when the item was created.
        #expect(counters.identityHashCount == 1)
        #expect(captured.imageBlobID == captured.imageData.map(sha256Hex))
        #expect(captured.sourceAppIconBlobID == sha256Hex(icon))
    }

    @Test func actorReadsPropagateTheRecorder() async throws {
        let counters = MediaOperationCounters()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaHashObservation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blobStore = ClipboardHistoryBlobStore(
            directoryURL: directory,
            readData: { try Data(contentsOf: $0) }
        )
        let media = Data(repeating: 0xef, count: 256)
        let prepared = PreparedMedia(hashing: media)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try media.write(to: try blobStore.blobURL(for: prepared.id))
        let loader = ClipboardHistoryMediaLoader(blobStore: blobStore)

        counters.reset()
        let loaded = try await counters.measure { try await loader.load(blobID: prepared.id) }

        #expect(loaded == media)
        #expect(counters.integrityHashCount == 1)
        #expect(counters.identityHashCount == 0)
    }

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "MediaHashObservation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
