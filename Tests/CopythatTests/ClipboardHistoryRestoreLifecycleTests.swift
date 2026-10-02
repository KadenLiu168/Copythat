@testable import Copythat
import AppKit
import Foundation
import Testing

/// Restore-lifecycle edges: the Store must not be retained across the loader
/// await, and a loader that finishes after the Store is gone must neither
/// publish nor save anything.
@MainActor
@Suite(.serialized)
struct ClipboardHistoryRestoreLifecycleTests {

    @Test func restoreTaskHoldsTheStoreWeaklyAcrossTheLoaderAwait() async throws {
        let loader = GatedClipboardHistoryLoader([.success([HistoryRestoreFixture.textItem("A")])])
        let saves = HistorySaveRecorder()
        var store: ClipboardStore? = ClipboardStore(
            settings: isolatedAppSettings(),
            sourceTracker: CopySourceTracker(),
            initialItems: [],
            pasteboard: NSPasteboard.withUniqueName(),
            persistItems: { saves.record($0) }
        )
        weak var weakStore = store
        #expect(weakStore != nil)

        store?.beginHistoryRestore(with: loader)
        await loader.waitUntilStarted()

        let restoreTask = try #require(store?.historyRestoreTask)
        store = nil

        #expect(
            weakStore == nil,
            "no restore task may hold the Store strongly across the loader await"
        )

        // The late completion resolves against a deallocated Store: it can
        // neither publish nor save.
        await loader.release()
        await restoreTask.value
        #expect(saves.count == 0, "a late completion publishes nothing and saves nothing")
    }

    @Test func waitingClientsCompleteAfterRepeatedFinishCalls() async throws {
        let harness = HistoryRestoreHarness(outcomes: [.success([HistoryRestoreFixture.textItem("A")])])
        defer { harness.cleanUp() }

        await harness.beginRestoring()
        // Several clients await the same restoration; none restarts or cancels it.
        async let first = harness.store.finishHistoryRestore()
        async let second = harness.store.finishHistoryRestore()
        await harness.loader.release()
        _ = await first
        _ = await second
        await harness.store.finishHistoryRestore()

        #expect(await harness.loader.loadCount == 1)
        #expect(harness.store.restoreState == .ready)
        #expect(harness.store.items.map(\.textValue) == ["A"])
        #expect(harness.saves.count == 0, "a clean restore still commits nothing")
    }

    @Test func repeatedBeginAndFinishAcrossSuccessAndErrorStayOneShot() async throws {
        let harness = HistoryRestoreHarness(outcomes: [
            .success([HistoryRestoreFixture.textItem("A")]),
            .failure
        ])
        defer { harness.cleanUp() }

        await harness.beginRestoring()
        // Let the gated load finish; the clients below then observe real
        // completion rather than a still-parked loader.
        await harness.loader.release()
        await harness.store.finishHistoryRestore()
        #expect(harness.store.items.map(\.textValue) == ["A"])
        #expect(harness.store.restoreState == .ready)

        // Further begins are refused even after the handle was cleared, so the
        // second prepared outcome and failure are never consumed.
        harness.store.beginHistoryRestore(with: harness.loader)
        await harness.store.finishHistoryRestore()

        #expect(await harness.loader.loadCount == 1)
        #expect(harness.store.items.map(\.textValue) == ["A"], "a refused begin changes nothing")
        #expect(harness.store.restoreState == .ready)
        #expect(harness.saves.count == 0)
    }

    @Test func aStoreThatNeverRestoredStaysReadyThroughRepeatedFinishCalls() async {
        let harness = HistoryRestoreHarness(outcomes: [])
        defer { harness.cleanUp() }

        await harness.store.finishHistoryRestore()
        await harness.store.finishHistoryRestore()

        #expect(await harness.loader.loadCount == 0)
        #expect(harness.store.restoreState == .ready)
        #expect(harness.store.canMutateHistory)
    }
}