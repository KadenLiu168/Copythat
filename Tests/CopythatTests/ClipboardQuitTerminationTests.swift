@testable import Copythat
import AppKit
import Foundation
import Testing

/// Normal Quit must await restoration and accepted image work before it
/// resolves saves — including when the save coordinator has nothing pending,
/// which is exactly the case the old fast path got wrong.
@MainActor
@Suite(.serialized)
struct ClipboardQuitTerminationTests {

    // MARK: - 6.3 Detection and resolution

    @Test func quitWaitsForGatedRestoreEvenWithNothingToSave() async {
        let loader = GatedClipboardHistoryLoader([.success([HistoryRestoreFixture.textItem("A")])])
        let worker = TerminationSaveWorker()
        let coordinator = ClipboardHistorySaveCoordinator(worker: worker)
        let model = isolatedRestoringAppModel(loader: loader, coordinator: coordinator)
        #expect(coordinator.hasUnsavedChanges == false, "nothing is pending yet")
        #expect(model.store.isRestoringHistory)

        let replyEvents = LinkPreviewCounter()
        var replies: [Bool] = []
        let delegate = AppDelegate(
            model: model,
            chooseQuitSaveFailure: { .cancelQuit },
            replyToTermination: {
                replies.append($0)
                replyEvents.mark("reply")
            }
        )

        #expect(
            delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater,
            "a loading history is never a reason to terminate now"
        )
        #expect(model.store.isCaptureAdmissionPaused, "admission closes at the first Quit")
        #expect(replies.isEmpty)

        await loader.release()
        await replyEvents.waitFor("reply", reaching: 1)
        #expect(replies == [true])
        #expect(model.store.items.map(\.textValue) == ["A"], "the baseline was applied before replying")
        // A clean restore requests no save, so there is nothing to commit and
        // termination still resolves. The admission pause stays closed because
        // the application is going away, not because the Quit was cancelled.
        #expect(model.store.isCaptureAdmissionPaused)
        #expect(await coordinator.flush())
        let committed = await worker.state()
        #expect(committed.committedGenerations.isEmpty, "clean restoration commits nothing")
    }

    @Test func quitWaitsForAnAdmittedImageEvenWithNothingToSave() async throws {
        let loader = GatedClipboardHistoryLoader([.success([])])
        let worker = TerminationSaveWorker()
        let coordinator = ClipboardHistorySaveCoordinator(worker: worker)
        let encoder = ControlledImageEncoder()
        let model = isolatedRestoringAppModel(loader: loader, coordinator: coordinator, encoder: encoder)
        await loader.release()
        await model.store.finishHistoryRestore()
        #expect(coordinator.hasUnsavedChanges == false, "an encoding in flight is invisible to the coordinator")

        let image = ImagePipelineFixture.redImage()
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        model.store.admitImageCapture(
            cgImage: cgImage,
            displaySize: image.size,
            source: ClipboardSource(appName: "Preview", iconData: nil, capturedAt: Date()),
            currentChangeCount: 1
        )
        await encoder.waitForStart(reaching: 1)
        #expect(model.store.hasPendingImageCapture)

        let replyEvents = LinkPreviewCounter()
        var replies: [Bool] = []
        let delegate = AppDelegate(
            model: model,
            chooseQuitSaveFailure: { .cancelQuit },
            replyToTermination: {
                replies.append($0)
                replyEvents.mark("reply")
            }
        )
        #expect(
            delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater,
            "accepted image work is never a reason to terminate now"
        )
        #expect(replies.isEmpty)

        encoder.releaseAll()
        await replyEvents.waitFor("reply", reaching: 1)
        #expect(replies == [true])
        #expect(model.store.items.count == 1, "the accepted image became a card before committing")
        #expect(await coordinator.flush())
        let committed = await worker.state()
        #expect(committed.committedGenerations.isEmpty == false, "the card committed before terminating")
    }

    @Test func quitCommitsTheMergedBaselineAndStartupCapture() async {
        let loader = GatedClipboardHistoryLoader([.success([HistoryRestoreFixture.textItem("A")])])
        let worker = TerminationSaveWorker()
        let coordinator = ClipboardHistorySaveCoordinator(worker: worker)
        let model = isolatedRestoringAppModel(loader: loader, coordinator: coordinator)
        model.store.add(HistoryRestoreFixture.textItem("B"))

        let replyEvents = LinkPreviewCounter()
        var replies: [Bool] = []
        let delegate = AppDelegate(
            model: model,
            chooseQuitSaveFailure: { .cancelQuit },
            replyToTermination: {
                replies.append($0)
                replyEvents.mark("reply")
            }
        )
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)

        await loader.release()
        await replyEvents.waitFor("reply", reaching: 1)
        #expect(replies == [true])
        #expect(await coordinator.flush())
        // The committed snapshot is the baseline plus the replayed capture.
        #expect(await worker.state().committedText == "B")
    }

    @Test(arguments: [true, false])
    func quitPersistsBaselineAndWaitingImagesInEitherCompletionOrder(restoreFirst: Bool) async throws {
        let fixture = try HistoryRestoreDiskFixture()
        defer { fixture.cleanUp() }
        let baseline = HistoryRestoreFixture.textItem("saved baseline")
        try fixture.persistence.save([baseline])
        let loader = GatedClipboardHistoryLoader([.success([baseline])])
        let encoder = ControlledImageEncoder()
        let coordinator = ClipboardHistorySaveCoordinator(
            worker: ClipboardHistorySaveWorker(persistence: fixture.persistence)
        )
        let model = AppModel(
            historySaveCoordinator: coordinator,
            pasteboard: NSPasteboard.withUniqueName(),
            settings: fixture.settings,
            mediaLoader: ClipboardHistoryMediaLoader(blobStore: fixture.persistence.blobStore),
            historyLoader: loader,
            encodeImage: { image, recorder in await encoder.encode(image, recorder: recorder) }
        )
        let handled = LinkPreviewCounter()
        model.store.imageCompletionHandledObserver = { handled.mark("image") }
        let images = [ImagePipelineFixture.redImage(), ImagePipelineFixture.greenImage(), ImagePipelineFixture.blueImage()]
        var imageIDs: [String] = []
        for (index, image) in images.enumerated() {
            imageIDs.append(try await ImagePipelineFixture.preparedMedia(of: image).id)
            model.store.admitImageCapture(
                cgImage: try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil)),
                displaySize: image.size,
                source: ClipboardSource(appName: "Preview", iconData: nil, capturedAt: Date()),
                currentChangeCount: index + 1
            )
        }
        await loader.waitUntilStarted()
        await encoder.waitForStart(reaching: 1)
        let replyEvents = LinkPreviewCounter()
        var replies: [Bool] = []
        let delegate = AppDelegate(
            model: model,
            chooseQuitSaveFailure: { .cancelQuit },
            replyToTermination: {
                replies.append($0)
                replyEvents.mark("reply")
            }
        )
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        if restoreFirst {
            await loader.release()
            await model.store.finishHistoryRestore()
            #expect(model.store.items == [baseline])
        }
        #expect(replies.isEmpty)
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        for index in 1...images.count {
            encoder.releaseAll()
            await handled.waitFor("image", reaching: index)
        }
        if !restoreFirst {
            #expect(replies.isEmpty, "images alone cannot resolve Quit before restore")
            #expect(model.store.items.isEmpty)
            await loader.release()
        }
        await replyEvents.waitFor("reply", reaching: 1)
        #expect(replies == [true])
        #expect(!coordinator.hasUnsavedChanges, "reply follows the merged commit")
        #expect(!model.store.hasPendingImageCapture)
        #expect(encoder.peakConcurrency == 1)
        let committed = try fixture.persistence.loadItems()
        #expect(committed.map(\.contentKey) == imageIDs.reversed().map { "image:\($0)" } + [baseline.contentKey])
        #expect(committed.last?.id == baseline.id)
        #expect(await loader.loadCount == 1)
    }

    // MARK: - 6.5 Retry, Quit Anyway, Cancel Quit and repeated Quit

    @Test func cancelQuitKeepsInMemoryHistoryAndResumesPriorMonitoring() async {
        let loader = GatedClipboardHistoryLoader([.success([HistoryRestoreFixture.textItem("A")])])
        let coordinator = ClipboardHistorySaveCoordinator(worker: TerminationSaveWorker(failedGenerations: [1]))
        let model = isolatedRestoringAppModel(loader: loader, coordinator: coordinator)
        model.store.startMonitoring()
        model.store.add(HistoryRestoreFixture.textItem("B"))

        let replyEvents = LinkPreviewCounter()
        var replies: [Bool] = []
        var choices = 0
        let delegate = AppDelegate(
            model: model,
            chooseQuitSaveFailure: {
                choices += 1
                return .cancelQuit
            },
            replyToTermination: {
                replies.append($0)
                replyEvents.mark("reply")
            }
        )
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        await loader.release()
        await replyEvents.waitFor("reply", reaching: 1)
        #expect(replies == [false])
        #expect(choices == 1)

        #expect(model.store.isCaptureAdmissionPaused == false, "Cancel Quit ends the pause")
        #expect(model.store.isMonitoring, "prior monitoring resumes")
        #expect(model.store.canMutateHistory, "normal mutation eligibility returns")
        #expect(
            model.store.items.map(\.textValue) == ["B", "A"],
            "Cancel Quit keeps the current in-memory history"
        )
        model.store.stopMonitoring()
    }

    @Test func quitAnywayKeepsThePreviouslyCommittedHistory() async {
        let loader = GatedClipboardHistoryLoader([.success([HistoryRestoreFixture.textItem("A")])])
        // Generation 1 commits; the bootstrap's save is generation 2 and fails,
        // which is what puts the explicit user choice on screen.
        let worker = TerminationSaveWorker(failedGenerations: [2])
        let coordinator = ClipboardHistorySaveCoordinator(worker: worker)
        let model = isolatedRestoringAppModel(loader: loader, coordinator: coordinator)
        coordinator.requestSave([HistoryRestoreFixture.textItem("previously committed")])
        #expect(await coordinator.flush())
        model.store.add(HistoryRestoreFixture.textItem("B"))

        let replyEvents = LinkPreviewCounter()
        var replies: [Bool] = []
        let delegate = AppDelegate(
            model: model,
            chooseQuitSaveFailure: { .quitAnyway },
            replyToTermination: {
                replies.append($0)
                replyEvents.mark("reply")
            }
        )
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        await loader.release()
        await replyEvents.waitFor("reply", reaching: 1)

        #expect(replies == [true])
        let committed = await worker.state()
        #expect(committed.committedText == "previously committed", "the old committed snapshot stands")
    }

    @Test func retryAfterBootstrapSavesTheLatestState() async {
        let loader = GatedClipboardHistoryLoader([.success([HistoryRestoreFixture.textItem("A")])])
        let worker = TerminationSaveWorker(committedText: "previously committed", failedGenerations: [1])
        let coordinator = ClipboardHistorySaveCoordinator(worker: worker)
        let model = isolatedRestoringAppModel(loader: loader, coordinator: coordinator)
        model.store.add(HistoryRestoreFixture.textItem("B"))

        let replyEvents = LinkPreviewCounter()
        var replies: [Bool] = []
        var choices: [ClipboardHistoryQuitChoice] = [.retry]
        let delegate = AppDelegate(
            model: model,
            chooseQuitSaveFailure: { choices.removeFirst() },
            replyToTermination: {
                replies.append($0)
                replyEvents.mark("reply")
            }
        )
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        await loader.release()
        await replyEvents.waitFor("reply", reaching: 1)

        #expect(replies == [true])
        #expect(choices.isEmpty)
        let committed = await worker.state()
        #expect(committed.committedText == "B", "retry targets the latest state")
    }

    @Test func repeatedQuitRequestsShareOneResolutionAndNeverRestoreTwice() async {
        let loader = GatedClipboardHistoryLoader([.success([HistoryRestoreFixture.textItem("A")])])
        let coordinator = ClipboardHistorySaveCoordinator(worker: TerminationSaveWorker())
        let model = isolatedRestoringAppModel(loader: loader, coordinator: coordinator)

        let replyEvents = LinkPreviewCounter()
        var replies: [Bool] = []
        let delegate = AppDelegate(
            model: model,
            chooseQuitSaveFailure: { .cancelQuit },
            replyToTermination: {
                replies.append($0)
                replyEvents.mark("reply")
            }
        )
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)

        await loader.release()
        await replyEvents.waitFor("reply", reaching: 1)
        #expect(replies == [true], "exactly one reply for repeated Quit requests")
        #expect(await loader.loadCount == 1, "no second restoration is started")
    }

}
