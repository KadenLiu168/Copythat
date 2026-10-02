@testable import Copythat
import AppKit
import Foundation
import Testing

/// Normal-Quit admission pause and the accepted-image drain.
///
/// The pause must close new admission without revoking what was already
/// accepted: generation, waiting FIFO and the single physical slot all survive,
/// which is exactly what makes the drain terminate. Every wait here is a
/// handled-transition gate — no sleeps, no polling, no wall-clock thresholds.
@MainActor
@Suite(.serialized)
struct ClipboardQuitAdmissionTests {

    // MARK: - 6.1 Pause and resume boundary

    @Test func pauseBlocksEveryNewAdmissionPathWithoutInvalidatingAcceptedWork() async throws {
        let harness = HistoryRestoreHarness(outcomes: [.success([])])
        defer { harness.cleanUp() }
        let image = ImagePipelineFixture.redImage()
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))

        harness.store.startMonitoring()
        let generationBefore = harness.store.imageCaptureGeneration
        harness.capture(image)
        await harness.encoder.waitForStart(reaching: 1)

        let activeBefore = harness.store.activeImageCapture?.sequence
        harness.store.pauseCaptureAdmission()

        // Every admission path is closed for new work.
        harness.store.pollPasteboard()
        harness.store.handleCopyIntentWake()
        harness.store.admitImageCapture(
            cgImage: cgImage,
            displaySize: image.size,
            source: ClipboardSource(appName: "Preview", iconData: nil, capturedAt: Date()),
            currentChangeCount: 99
        )
        #expect(harness.store.isMonitoring == false, "scheduled observation is suspended")
        #expect(harness.store.isBurstPollingActive == false, "the burst loop is suspended")

        // Accepted work is untouched: not invalidated, not dropped, not freed.
        #expect(harness.store.imageCaptureGeneration == generationBefore, "the pause never invalidates")
        #expect(harness.store.activeImageCapture?.sequence == activeBefore, "the physical slot is intact")
        #expect(harness.encoder.peakConcurrency == 1)

        // A fresh external write is not admitted while paused.
        let waitingBefore = harness.store.waitingImageCaptures.map(\.sequence)
        harness.capture(ImagePipelineFixture.greenImage())
        #expect(harness.store.waitingImageCaptures.map(\.sequence) == waitingBefore)

        harness.store.resumeCaptureAdmission()
        defer { harness.store.stopMonitoring() }
        #expect(harness.store.isMonitoring, "Cancel Quit restores prior scheduled activity")
        #expect(harness.store.imageCaptureGeneration == generationBefore, "resume invalidates nothing")
    }

    @Test func resumeRestoresOnlyMonitoringThatWasActuallyActive() async {
        let idle = HistoryRestoreHarness(outcomes: [.success([])])
        defer { idle.cleanUp() }
        idle.store.pauseCaptureAdmission()
        idle.store.resumeCaptureAdmission()
        #expect(idle.store.isMonitoring == false, "a never-started store stays stopped")

        let active = HistoryRestoreHarness(outcomes: [.success([])])
        defer {
            active.store.stopMonitoring()
            active.cleanUp()
        }
        active.store.startMonitoring()
        active.store.pauseCaptureAdmission()
        #expect(active.store.isMonitoring == false)
        active.store.resumeCaptureAdmission()
        #expect(active.store.isMonitoring, "prior monitoring resumes")
    }

    // MARK: - 6.2 Awaitable drain

    @Test func drainWaitsForActiveAndWaitingCapturesWithoutLeakingWaiters() async throws {
        let harness = HistoryRestoreHarness(outcomes: [.success([])])
        defer { harness.cleanUp() }
        for fixture in [
            ImagePipelineFixture.redImage(),
            ImagePipelineFixture.greenImage(),
            ImagePipelineFixture.blueImage()
        ] {
            harness.capture(fixture)
        }
        await harness.encoder.waitForStart(reaching: 1)
        #expect(harness.store.hasPendingImageCapture)

        let drain = Task { @MainActor in
            await harness.store.drainAdmittedImageCaptures()
        }
        // The drain cannot finish while accepted work is outstanding.
        #expect(harness.store.imageDrainWaiters.isEmpty == false || harness.store.hasPendingImageCapture)

        var handled = 0
        while harness.store.pendingImageCaptureCount > 0 {
            harness.encoder.releaseAll()
            await harness.awaitImageCompletion(handled + 1)
            handled += 1
        }
        await drain.value

        #expect(harness.store.hasPendingImageCapture == false)
        #expect(harness.store.imageDrainWaiters.isEmpty, "no continuation is leaked")
        #expect(harness.encoder.peakConcurrency == 1, "encoders never overlap during a drain")
        #expect(harness.store.items.count == 3, "every accepted capture became a card")
    }

    @Test func drainResolvesWhenAnAdmittedEncodingProducesNoPayload() async throws {
        let harness = HistoryRestoreHarness(outcomes: [.success([])])
        defer { harness.cleanUp() }

        harness.capture(ImagePipelineFixture.redImage())
        await harness.encoder.waitForStart(reaching: 1)
        harness.encoder.failRequest(at: 0)

        let drain = Task { @MainActor in
            await harness.store.drainAdmittedImageCaptures()
        }
        harness.encoder.releaseAll()
        await harness.awaitImageCompletion(1)
        await drain.value

        #expect(harness.store.hasPendingImageCapture == false, "a nil result still releases the slot")
        #expect(harness.store.imageDrainWaiters.isEmpty)
        #expect(harness.store.items.isEmpty, "a failed encoding produces no card")
    }

    @Test func drainReturnsImmediatelyWhenNothingIsAccepted() async {
        let harness = HistoryRestoreHarness(outcomes: [.success([])])
        defer { harness.cleanUp() }

        await harness.store.drainAdmittedImageCaptures()

        #expect(harness.store.imageDrainWaiters.isEmpty)
        #expect(harness.store.hasPendingImageCapture == false)
    }

    // MARK: - 6.4 Either completion order during a Quit

    @Test func imagesFinalizingBeforeRestoreStillReplayAndCommitOnce() async throws {
        let harness = HistoryRestoreHarness(outcomes: [.success([])])
        defer { harness.cleanUp() }

        await harness.beginRestoring()
        harness.capture(ImagePipelineFixture.redImage())
        await harness.encoder.waitForStart(reaching: 1)
        harness.encoder.releaseAll()
        await harness.awaitImageCompletion(1)
        #expect(harness.store.items.isEmpty, "the image is still buffered")

        harness.store.pauseCaptureAdmission()
        await harness.loader.release()
        await harness.store.finishHistoryRestore()

        #expect(harness.store.items.count == 1, "successful encoding is not discarded by the pause")
        #expect(harness.saves.count == 1)
    }

    @Test func imagesFinalizingAfterRestoreUseOrdinarySavesDuringQuit() async throws {
        let harness = HistoryRestoreHarness(outcomes: [.success([])])
        defer { harness.cleanUp() }

        await harness.beginRestoring()
        await harness.loader.release()
        await harness.store.finishHistoryRestore()
        #expect(harness.store.isRestoringHistory == false)

        // Admitted before Quit and still encoding when Quit begins: restoration
        // has already finished, so its completion is ordinary insertion.
        harness.capture(ImagePipelineFixture.redImage())
        await harness.encoder.waitForStart(reaching: 1)
        harness.store.pauseCaptureAdmission()
        harness.encoder.releaseAll()
        await harness.awaitImageCompletion(1)
        await harness.store.drainAdmittedImageCaptures()

        #expect(harness.store.items.count == 1)
        #expect(harness.saves.count == 1, "the post-restore image is its own ordinary save")
    }

    @Test func multipleWaitingImagesDrainInOrdinaryFIFOOrder() async throws {
        let harness = HistoryRestoreHarness(outcomes: [.success([])])
        defer { harness.cleanUp() }
        let fixtures = [
            ImagePipelineFixture.redImage(),
            ImagePipelineFixture.greenImage(),
            ImagePipelineFixture.blueImage(),
            ImagePipelineFixture.amberImage()
        ]
        var expected: [String] = []
        for fixture in fixtures {
            expected.append(try await ImagePipelineFixture.preparedMedia(of: fixture).id)
        }

        await harness.beginRestoring()
        for fixture in fixtures {
            harness.capture(fixture)
        }
        harness.store.pauseCaptureAdmission()
        await harness.loader.release()
        await harness.store.finishHistoryRestore()
        #expect(harness.saves.count == 0, "a clean restore over an empty buffer commits nothing")

        let drain = Task { @MainActor in
            await harness.store.drainAdmittedImageCaptures()
        }
        var handled = 0
        while harness.store.pendingImageCaptureCount > 0 {
            harness.encoder.releaseAll()
            await harness.awaitImageCompletion(handled + 1)
            handled += 1
        }
        await drain.value

        #expect(harness.store.items.count == 4)
        #expect(harness.store.items.map(\.imageBlobID) == expected.reversed(), "ordinary FIFO survives the drain")
        #expect(harness.encoder.peakConcurrency == 1)
        // These encodings finished *after* restoration, so each is an ordinary
        // insertion save rather than an extra baseline/replay bootstrap request.
        #expect(harness.saves.count == fixtures.count)
        #expect(harness.saves.latestTextValues.count == fixtures.count)
    }

    // MARK: - 6.6 Destructive actions are gated during the pause

    @Test func destructiveActionsCannotInvalidateWorkBeingDrained() async throws {
        let harness = HistoryRestoreHarness(outcomes: [.success([])])
        defer { harness.cleanUp() }
        harness.capture(ImagePipelineFixture.redImage())
        await harness.encoder.waitForStart(reaching: 1)

        harness.store.pauseCaptureAdmission()
        let generationBefore = harness.store.imageCaptureGeneration
        let activeBefore = harness.store.activeImageCapture?.sequence
        #expect(harness.store.canMutateHistory == false, "history mutations are unavailable while draining")

        let buffered = HistoryRestoreFixture.textItem("buffered")
        harness.store.add(buffered)
        harness.store.clearHistory(includePinnedAndPinboardItems: true)
        harness.store.togglePin(buffered)
        harness.store.move(buffered, toPinboard: "Work")
        harness.store.remove(buffered)
        harness.store.renamePinboardAssignments(from: "Work", to: "Renamed")
        harness.store.clearPinboardAssignments(named: "Renamed")

        #expect(
            harness.store.imageCaptureGeneration == generationBefore,
            "the drain's accepted work cannot be invalidated"
        )
        #expect(harness.store.activeImageCapture?.sequence == activeBefore, "the physical slot survives")

        harness.encoder.releaseAll()
        await harness.awaitImageCompletion(1)
        await harness.store.drainAdmittedImageCaptures()
        #expect(harness.store.items.count == 2, "the drained image and the injected item both survive")
    }

    @Test func ordinaryMutationsReturnAfterCancelQuit() async {
        let harness = HistoryRestoreHarness(outcomes: [.success([])])
        defer { harness.cleanUp() }

        harness.store.pauseCaptureAdmission()
        #expect(harness.store.canMutateHistory == false)
        harness.store.resumeCaptureAdmission()
        #expect(harness.store.canMutateHistory, "cancelling Quit restores mutation eligibility")

        let item = HistoryRestoreFixture.textItem("A")
        harness.store.add(item)
        harness.store.togglePin(item)
        #expect(harness.store.items.first?.isPinned == true)
    }
}
