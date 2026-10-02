@testable import Copythat
import AppKit
import Foundation
import Testing

/// History-destructive entry points must reject before *any* side effect while
/// startup restoration owns history — including on an otherwise empty history,
/// where Clear History would otherwise still revoke admitted images.
@MainActor
@Suite(.serialized)
struct ClipboardHistoryRestoreGuardTests {

    @Test func destructiveMutationsAreRejectedBeforeEverySideEffect() async throws {
        let harness = HistoryRestoreHarness(outcomes: [.success([])])
        defer { harness.cleanUp() }
        let image = ImagePipelineFixture.redImage()
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let source = ClipboardSource(appName: "Preview", iconData: nil, capturedAt: Date())

        await harness.beginRestoring()
        harness.store.admitImageCapture(
            cgImage: cgImage,
            displaySize: image.size,
            source: source,
            currentChangeCount: 7
        )
        await harness.encoder.waitForStart(reaching: 1)
        let buffered = HistoryRestoreFixture.textItem("buffered")
        harness.store.add(buffered)

        // Match the system pasteboard so a stray clear would be observable.
        harness.pasteboard.clearContents()
        #expect(harness.pasteboard.setString("buffered", forType: .string))
        let pasteboardTypesBefore = harness.pasteboard.types

        let generationBefore = harness.store.imageCaptureGeneration
        let waitingBefore = harness.store.waitingImageCaptures.map(\.sequence)
        let activeBefore = harness.store.activeImageCapture?.sequence
        #expect(harness.store.canMutateHistory == false)

        harness.store.clearHistory(includePinnedAndPinboardItems: true)
        harness.store.clearHistory(includePinnedAndPinboardItems: false)
        harness.store.togglePin(buffered)
        harness.store.move(buffered, toPinboard: "Work")
        harness.store.remove(buffered)
        harness.store.clearPinboardAssignments(named: "Work")
        harness.store.renamePinboardAssignments(from: "Work", to: "Renamed")

        // Nothing moved, nothing persisted, nothing invalidated, nothing cleared.
        #expect(harness.store.items.isEmpty, "rejected actions change no history")
        #expect(harness.saves.count == 0, "rejected actions request no save")
        #expect(harness.store.imageCaptureGeneration == generationBefore, "no image invalidation")
        #expect(harness.store.waitingImageCaptures.map(\.sequence) == waitingBefore, "waiting captures are untouched")
        #expect(harness.store.activeImageCapture?.sequence == activeBefore, "the active slot is untouched")
        #expect(harness.pasteboard.types == pasteboardTypesBefore, "the system pasteboard is untouched")
        #expect(harness.pasteboard.string(forType: .string) == "buffered")
    }

    @Test func rejectedDestructiveIntentIsNotAppliedAfterLoadingFinishes() async {
        let harness = HistoryRestoreHarness(outcomes: [.success([])])
        defer { harness.cleanUp() }

        await harness.beginRestoring()
        let buffered = HistoryRestoreFixture.textItem("buffered")
        harness.store.add(buffered)

        // A destructive request arrives mid-restore and is dropped outright.
        harness.store.clearHistory(includePinnedAndPinboardItems: true)
        await harness.finishRestoring()

        #expect(
            harness.store.items.map(\.textValue) == ["buffered"],
            "a rejected clear is not queued for later execution"
        )
        #expect(harness.store.canMutateHistory)
        #expect(harness.saves.count == 1, "only the buffered capture is committed")
    }

    @Test func mutationsReturnToOrdinaryBehaviorOnceHistoryIsReady() async throws {
        let harness = HistoryRestoreHarness(outcomes: [.success([HistoryRestoreFixture.textItem("A")])])
        defer { harness.cleanUp() }

        await harness.beginRestoring()
        await harness.finishRestoring()
        let item = try #require(harness.store.items.first)
        #expect(harness.store.canMutateHistory)

        harness.store.togglePin(item)
        #expect(harness.store.items.first?.isPinned == true)

        harness.store.move(item, toPinboard: "Work")
        #expect(harness.store.items.first?.pinboardName == "Work")

        harness.store.renamePinboardAssignments(from: "Work", to: "Renamed")
        #expect(harness.store.items.first?.pinboardName == "Renamed")

        harness.store.clearPinboardAssignments(named: "Renamed")
        #expect(harness.store.items.first?.pinboardName == nil)

        harness.store.clearHistory(includePinnedAndPinboardItems: true)
        #expect(harness.store.items.isEmpty)
    }

    @Test func clearOnAnOtherwiseEmptyHistoryIsStillRejectedDuringRestore() async throws {
        let harness = HistoryRestoreHarness(outcomes: [.success([])])
        defer { harness.cleanUp() }
        let image = ImagePipelineFixture.greenImage()
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))

        await harness.beginRestoring()
        harness.store.admitImageCapture(
            cgImage: cgImage,
            displaySize: image.size,
            source: ClipboardSource(appName: "Preview", iconData: nil, capturedAt: Date()),
            currentChangeCount: 3
        )
        await harness.encoder.waitForStart(reaching: 1)
        let generationBefore = harness.store.imageCaptureGeneration

        let removed = harness.store.clearHistory(includePinnedAndPinboardItems: false)

        #expect(removed == 0)
        #expect(harness.store.items.isEmpty)
        #expect(harness.saves.count == 0)
        #expect(
            harness.store.imageCaptureGeneration == generationBefore,
            "the clear rejection precedes image invalidation even with nothing stored"
        )
    }
}
