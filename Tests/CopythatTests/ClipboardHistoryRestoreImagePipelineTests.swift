@testable import Copythat
import AppKit
import Foundation
import Testing

/// The bounded image pipeline must survive startup restoration unchanged: a
/// capture admitted before the baseline exists keeps its admission context and
/// its already-finalized bytes, and the single physical encoder and four-capture
/// bound keep applying across the restore boundary.
@MainActor
@Suite(.serialized)
struct ClipboardHistoryRestoreImagePipelineTests {

    // MARK: - 5.1 Real admission finalizing during a blocked restore

    @Test func imageFinalizingDuringBlockedRestoreSurvivesReplayWithoutReEncoding() async throws {
        let icon = try #require(ImagePipelineFixture.greenImage().pngData(maxPixel: 32))
        let harness = HistoryRestoreHarness(outcomes: [.success([])], sourceApp: "Preview", sourceIcon: icon)
        let hashes = MediaHashRecorder()
        defer { harness.cleanUp() }
        let image = ImagePipelineFixture.redImage()
        let expected = try await ImagePipelineFixture.preparedMedia(of: image)

        await MediaHashObservation.$recorder.withValue(hashes) {
            await harness.beginRestoring()
            harness.capture(image)
        }
        await harness.encoder.waitForStart(reaching: 1)
        let admission = try #require(harness.store.activeImageCapture)

        // Finalize while the baseline is still loading. The Store's own
        // admission-time source and time must survive, and the prepared
        // identity is forwarded rather than recomputed.
        harness.encoder.releaseAll()
        await harness.awaitImageCompletion(1)
        #expect(harness.store.items.isEmpty, "the finalized image is buffered, not inserted")
        #expect(harness.encoder.startCount == 1, "the image is encoded exactly once")
        let hashesBeforeReplay = hashes.totalCount
        #expect(hashesBeforeReplay > 0, "the hash recorder observed real finalization")

        await MediaHashObservation.$recorder.withValue(hashes) {
            await harness.finishRestoring()
        }
        #expect(hashes.totalCount == hashesBeforeReplay, "replay never re-hashes prepared media")

        let replayed = try #require(harness.store.items.first)
        #expect(replayed.kind == .image)
        #expect(replayed.sourceApp == "Preview", "admission source context survives replay")
        #expect(replayed.sourceAppIconData == icon)
        #expect(replayed.createdAt == admission.capturedAt)
        #expect(replayed.imageBlobID == expected.id, "prepared media identity is forwarded unchanged")
        #expect(
            replayed.imageData == expected.data,
            "finalized bytes survive replay without another encoding"
        )
        #expect(harness.encoder.startCount == 1, "replay never re-encodes the image")
        #expect(harness.store.startupCaptureBuffer.isEmpty, "the startup buffer releases its ownership")
        #expect(harness.store.pendingImageCaptureCount == 0)
        #expect(harness.encoder.peakConcurrency == 1, "never more than one physical encoder")
        #expect(harness.saves.count == 1, "the buffered image commits once")
        #expect(harness.saves.latestTextValues.count == 1)
    }

    @Test func multipleImagesFinalizingDuringRestoreReplayInArrivalOrder() async throws {
        let harness = HistoryRestoreHarness(outcomes: [.success([])])
        defer { harness.cleanUp() }
        let fixtures = [
            ImagePipelineFixture.redImage(),
            ImagePipelineFixture.greenImage(),
            ImagePipelineFixture.blueImage()
        ]
        var expectedIDs: [String] = []
        for fixture in fixtures {
            expectedIDs.append(try await ImagePipelineFixture.preparedMedia(of: fixture).id)
        }

        await harness.beginRestoring()
        for fixture in fixtures {
            harness.capture(fixture)
        }
        // One encoder runs at a time, so only the first has started. Each
        // release completes one capture and synchronously launches the next.
        await harness.encoder.waitForStart(reaching: 1)
        for index in 1...fixtures.count {
            harness.encoder.releaseAll()
            await harness.awaitImageCompletion(index)
        }
        #expect(harness.store.items.isEmpty, "all three are still buffered")

        await harness.finishRestoring()

        #expect(harness.store.items.count == 3)
        // Last arrival ends up at the head, as ordinary insertion dictates.
        #expect(harness.store.items.map(\.imageBlobID) == [expectedIDs[2], expectedIDs[1], expectedIDs[0]])
        #expect(harness.encoder.startCount == 3, "each image is encoded exactly once")
        #expect(harness.encoder.peakConcurrency == 1, "never more than one physical encoder")
        #expect(harness.saves.count == 1, "three replayed images still commit exactly once")
    }

    // MARK: - 5.2 After ready, and capacity overflow during loading

    @Test func imagesCompletingAfterReadyUseOrdinarySaves() async throws {
        let harness = HistoryRestoreHarness(outcomes: [.success([])])
        defer { harness.cleanUp() }

        await harness.beginRestoring()
        await harness.finishRestoring()
        #expect(harness.saves.count == 0, "a clean restore commits nothing")

        harness.capture(ImagePipelineFixture.redImage())
        await harness.encoder.waitForStart(reaching: 1)
        harness.encoder.releaseAll()
        await harness.awaitImageCompletion(1)

        #expect(harness.store.items.count == 1, "a post-ready image inserts ordinarily")
        #expect(
            harness.saves.count == 1,
            "a post-ready image is its own ordinary save, not an extra bootstrap request"
        )
        #expect(harness.store.restoreState == .ready)
        #expect(harness.store.canMutateHistory)
    }

    @Test func capacityOverflowDuringLoadingKeepsOneEncoderAndFourRawCaptures() async throws {
        let harness = HistoryRestoreHarness(outcomes: [.success([])])
        defer { harness.cleanUp() }
        let fixtures = [
            ImagePipelineFixture.redImage(),
            ImagePipelineFixture.greenImage(),
            ImagePipelineFixture.blueImage(),
            ImagePipelineFixture.amberImage(),
            ImagePipelineFixture.violetImage(),
            ImagePipelineFixture.image(pixelsWide: 40, pixelsHigh: 40)
        ]

        await harness.beginRestoring()
        for fixture in fixtures {
            harness.capture(fixture)
        }

        // The first capture takes the active slot; the rest queue, and the
        // oldest waiting capture is evicted at capacity.
        await harness.encoder.waitForStart(reaching: 1)
        #expect(harness.store.pendingImageCaptureCount == 4, "raw capture depth stays at most four")
        #expect(harness.encoder.peakConcurrency == 1, "still a single physical encoder")

        // Drive the pipeline to idle using the Store's own synchronous state,
        // so the loop terminates on handled transitions rather than a guessed
        // number of completions.
        var handled = 0
        while harness.store.pendingImageCaptureCount > 0 {
            harness.encoder.releaseAll()
            await harness.awaitImageCompletion(handled + 1)
            handled += 1
            #expect(harness.encoder.peakConcurrency == 1, "encoders never overlap")
        }
        #expect(handled < fixtures.count, "the evicted captures never encoded")

        await harness.finishRestoring()

        // The overflowed capture is gone; everything else survived the replay.
        #expect(harness.store.items.count < fixtures.count, "the evicted capture never becomes a card")
        #expect(harness.store.items.count <= 4)
        #expect(harness.store.startupCaptureBuffer.isEmpty)
        #expect(harness.encoder.startCount <= fixtures.count)
        #expect(harness.saves.count == 1, "overflow during loading still commits once")
    }
}
