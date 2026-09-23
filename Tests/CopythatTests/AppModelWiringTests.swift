@testable import Copythat
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct AppModelWiringTests {
    @Test func trackerWakeReachesStoreAndStartsOrExtendsTheStoreBurst() async {
        let model = AppModel()
        defer { model.store.stopMonitoring() }
        model.store.startMonitoring()

        // Same closure the tracker fires for a recognized copy/cut/screenshot intent.
        model.sourceTracker.onCopyIntentWake?()
        #expect(
            await waitUntil(timeout: 2.0) { model.store.isBurstPollingActive },
            "tracker wake must hop to the main actor and start the store-owned burst"
        )

        model.sourceTracker.onCopyIntentWake?()
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(model.store.isBurstPollingActive, "repeated wake must extend the single burst")
    }

    @Test func storeDeallocatesAfterModelIsReleased() {
        var model: AppModel? = AppModel()
        weak var weakStore = model?.store
        weak var weakTracker = model?.sourceTracker
        #expect(weakStore != nil)
        #expect(weakTracker != nil)

        model = nil

        #expect(weakStore == nil, "the wake wiring must capture the store weakly")
        #expect(weakTracker == nil)
    }

    private func waitUntil(
        timeout seconds: TimeInterval,
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return condition()
    }
}
