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

    // MARK: - Consecutive real production-encoder captures

    /// Every capture finalizes with the real bounded PNG pipeline: exactly one
    /// identity hash each, always off MainActor, even while earlier captures are
    /// still queued behind the single encoder.
    @MainActor
    @Test func queuedRealEncoderCapturesHashOnceEachOutsideMainActor() async throws {
        let counters = MediaOperationCounters()
        let icon = Data(repeating: 0x5a, count: 72)
        let harness = ImagePipelineHarness(
            capacity: 4,
            source: ClipboardSource(appName: "Screenshot", iconData: icon, capturedAt: Date())
        )
        let images = [
            ImagePipelineFixture.redImage(),
            ImagePipelineFixture.greenImage(),
            ImagePipelineFixture.blueImage()
        ]

        counters.reset()
        await counters.measure {
            for image in images {
                harness.capture(image)
            }
            await harness.encoder.waitForStart(reaching: 1)
            #expect(harness.encoder.peakConcurrency == 1)
            await harness.drain(through: 3)
        }

        #expect(counters.identityHashCount == 3, "one identity hash per finalized image, and no more")
        #expect(counters.mainThreadIdentityHashCount == 0, "PNG and hashing stay off MainActor")
        #expect(counters.integrityHashCount == 0)
        #expect(harness.store.items.count == 3)
        for item in harness.store.items {
            #expect(item.imageBlobID == item.imageData.map(sha256Hex))
            #expect(item.sourceAppIconBlobID == sha256Hex(icon), "a prepared icon adds no identity hash")
        }

        // A metadata mutation reuses the established identities.
        counters.reset()
        let pinned = try #require(harness.store.items.first)
        await counters.measure { harness.store.togglePin(pinned) }

        #expect(counters.mediaHashCount == 0, "metadata saves neither rehash nor re-encode image payloads")
        #expect(harness.store.items.first?.isPinned == true)
    }

    /// Recorder attribution belongs to the admission that captured it: a
    /// capture admitted after a measurement window closes is not counted inside
    /// it, so a later request cannot inherit an earlier one's context.
    @MainActor
    @Test func eachCaptureUsesTheRecorderInstalledAtItsOwnAdmission() async throws {
        let firstCounters = MediaOperationCounters()
        let secondCounters = MediaOperationCounters()
        let harness = ImagePipelineHarness(capacity: 3)

        await firstCounters.measure {
            harness.capture(ImagePipelineFixture.redImage())
            await harness.encoder.waitForStart(reaching: 1)
        }
        await secondCounters.measure {
            harness.capture(ImagePipelineFixture.greenImage())
        }
        #expect(firstCounters.identityHashCount == 0)
        #expect(secondCounters.identityHashCount == 0)

        // Finalize after both measurement scopes have ended. Each queued
        // request must retain its own admission recorder, not the launch one.
        await harness.drain(through: 2)
        #expect(firstCounters.identityHashCount == 1)
        #expect(secondCounters.identityHashCount == 1)
        #expect(firstCounters.mainThreadIdentityHashCount == 0)
        #expect(secondCounters.mainThreadIdentityHashCount == 0)

        harness.capture(ImagePipelineFixture.blueImage())
        await harness.encoder.waitForStart(reaching: 3)
        await harness.drain(through: 3)
        #expect(firstCounters.identityHashCount == 1, "a later worker must not reuse an earlier recorder")
        #expect(secondCounters.identityHashCount == 1)
        #expect(harness.store.items.count == 3)
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
