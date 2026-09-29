@testable import Copythat
import AppKit
import Foundation
import Testing

/// The captured image path finalizes its payload once, in the background, and
/// every later consumer — duplicate/content-key checks, the initial save, and
/// metadata saves — reuses that identity instead of hashing the bytes again.
@MainActor
@Suite(.serialized)
struct ClipboardStoreImageCaptureIdentityTests {
    @Test func capturedImageHashesOnceThroughContentKeysAndSaves() async throws {
        let counters = MediaOperationCounters()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureIdentity-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultsName = "CaptureIdentity.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let persistence = counters.makePersistence(directoryURL: directory, userDefaults: defaults)
        let coordinator = ClipboardHistorySaveCoordinator(
            worker: ClipboardHistorySaveWorker(persistence: persistence)
        )
        let counter = LinkPreviewCounter()
        let clock = MutableClock()
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let source = ClipboardSource(appName: "Tests", iconData: nil, capturedAt: Date())
        let store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(frontmostSourceProvider: { source }),
            initialItems: [],
            pasteboard: pasteboard,
            mediaLoader: ClipboardHistoryMediaLoader(blobStore: persistence.blobStore),
            persistItems: {
                counter.mark("requested")
                coordinator.requestSave($0)
            },
            uptimeProvider: { clock.now },
            fetchLinkMetadata: { _ in throw URLError(.unsupportedURL) },
            fetchLinkSnapshot: { _ in throw URLError(.unsupportedURL) }
        )
        let image = LinkPreviewFixture.testImage()

        counters.reset()
        await counters.measure {
            pasteboard.clearContents()
            #expect(pasteboard.writeObjects([image]))
            store.pollPasteboard()
            clock.advance(by: 1)
            store.pollPasteboard()
            await counter.waitFor("requested", reaching: 1)
            #expect(await coordinator.flush())
        }

        let captured = try #require(store.items.first)
        #expect(captured.kind == .image)
        #expect(counters.identityHashCount == 1)
        #expect(counters.mainThreadIdentityHashCount == 0)
        #expect(counters.integrityHashCount == 0)
        let captureIdentityHashes = counters.identityHashCount
        let mainThreadIdentityHashes = counters.mainThreadIdentityHashCount

        let mediaDirectory = directory.appendingPathComponent("history-media", isDirectory: true)
        let blobName = "\(try #require(captured.imageBlobID)).blob"
        let blobURL = mediaDirectory.appendingPathComponent(blobName)
        #expect(FileManager.default.fileExists(atPath: blobURL.path))
        #expect(try Data(contentsOf: blobURL) == captured.imageData)

        // A later metadata mutation reuses the stored identity: no media hash,
        // no payload read, no payload write, and exactly one manifest commit.
        counters.reset()
        await counters.measure {
            store.togglePin(captured)
            #expect(await coordinator.flush())
        }

        #expect(store.items.first?.isPinned == true)
        #expect(counters.identityHashCount == 0)
        #expect(counters.integrityHashCount == 0)
        #expect(counters.blobReadCount == 0)
        #expect(counters.blobWriteCount == 0)
        #expect(counters.manifestWriteCount == 1)
        #expect(try Data(contentsOf: blobURL) == captured.imageData)

        let restored = try persistence.loadItems()
        #expect(restored.first?.imageBlobID == captured.imageBlobID)
        #expect(restored.first?.isPinned == true)

        AcceptanceMetrics.record(
            scenario: "capture-identity",
            metric: "identityHashesForCapturedImageThroughMetadataSave",
            expected: "1",
            observed: "\(captureIdentityHashes)"
        )
        AcceptanceMetrics.record(
            scenario: "capture-identity",
            metric: "mainThreadIdentityHashes",
            expected: "0",
            observed: "\(mainThreadIdentityHashes)"
        )
    }
}
