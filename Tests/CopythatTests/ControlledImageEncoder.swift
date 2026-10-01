@testable import Copythat
import AppKit
import Foundation

/// Test image encoder that parks every admitted request until the test releases
/// it, then finalizes with the production 1200px PNG pipeline. Only *when*
/// finalization happens is controlled here, so queue order, physical-slot
/// ownership and eligibility are observable without sleeps or yields.
final class ControlledImageEncoder: @unchecked Sendable {
    /// Checkpoints: "encode" counts starts, "finished:encode" counts finishes,
    /// and both track in-flight concurrency for the single-encoder bound.
    let events = LinkPreviewCounter()

    private let lock = NSLock()
    private var parked: [CheckedContinuation<Void, Never>] = []
    private var unclaimedReleases = 0
    private var failingIndices: Set<Int> = []
    private var launchedIndices: [Int] = []
    private var nextIndex = 0

    /// Marks the request that will launch at `index` as producing no payload,
    /// modelling an encoder that cannot produce a finalized image.
    func failRequest(at index: Int) {
        lock.lock()
        failingIndices.insert(index)
        lock.unlock()
    }

    func encode(_ cgImage: CGImage, recorder: MediaHashRecorder?) async -> PreparedMedia? {
        let index = beginRequest()
        await park()
        let payload: PreparedMedia? = isFailing(index)
            ? nil
            : await ClipboardStore.defaultImageEncoder(cgImage, recorder)
        endRequest()
        return payload
    }

    /// Finalizes the oldest parked request, releasing exactly one slot.
    func releaseOldest() {
        releaseAll()
    }

    /// Releases every parked request. A release issued before its request has
    /// actually parked is held as a credit, so a start checkpoint can never race
    /// a release and strand an encoder.
    func releaseAll() {
        lock.lock()
        if parked.isEmpty {
            unclaimedReleases += 1
        }
        let pending = parked
        parked = []
        lock.unlock()
        pending.forEach { $0.resume() }
    }

    func waitForStart(reaching threshold: Int) async {
        await events.waitFor("encode", reaching: threshold)
    }

    func waitForFinish(reaching threshold: Int) async {
        await events.waitForEnd("encode", reaching: threshold)
    }

    var startCount: Int { events.value("encode") }
    var finishCount: Int { events.endedValue("encode") }

    /// Maximum requests this encoder ever had in flight. The pipeline promises
    /// it never exceeds one.
    var peakConcurrency: Int { events.peakConcurrency() }

    /// Indices in the order the Store launched them, which is finalization order.
    var launchOrder: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return launchedIndices
    }

    private func beginRequest() -> Int {
        lock.lock()
        let index = nextIndex
        nextIndex += 1
        launchedIndices.append(index)
        lock.unlock()
        events.begin("encode")
        return index
    }

    private func endRequest() {
        events.end("encode")
    }

    private func isFailing(_ index: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return failingIndices.contains(index)
    }

    private func park() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if unclaimedReleases > 0 {
                unclaimedReleases -= 1
                lock.unlock()
                continuation.resume()
                return
            }
            parked.append(continuation)
            lock.unlock()
        }
    }
}