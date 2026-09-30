@testable import Copythat
import Foundation
import Testing

/// Deterministic coverage for the source-icon cache itself: process-generation
/// identity, loader and identity-hash counts, bounded least-recently-used
/// retention, and successful-only insertion.
struct SourceAppIconCacheTests {
    private let launchDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let laterLaunchDate = Date(timeIntervalSince1970: 1_700_000_600)
    private let bundleURL = URL(fileURLWithPath: "/Applications/Example.app")
    private let otherBundleURL = URL(fileURLWithPath: "/Volumes/Other/Example.app")

    @Test func keySeparatesProcessGenerationsAndInstallationLocations() {
        let key = cacheKey(pid: 501, launchDate: launchDate, bundleURL: bundleURL)

        #expect(key != nil)
        #expect(key == cacheKey(pid: 501, launchDate: launchDate, bundleURL: bundleURL))
        #expect(key != cacheKey(pid: 502, launchDate: launchDate, bundleURL: bundleURL))
        #expect(key != cacheKey(pid: 501, launchDate: laterLaunchDate, bundleURL: bundleURL))
        #expect(key != cacheKey(pid: 501, launchDate: launchDate, bundleURL: otherBundleURL))
        #expect(key != cacheKey(pid: 501, launchDate: launchDate, bundleURL: nil))
    }

    @Test func keyAllowsAValidGenerationWithoutABundleLocation() {
        let key = cacheKey(pid: 501, launchDate: launchDate, bundleURL: nil)

        #expect(key != nil)
        #expect(key == cacheKey(pid: 501, launchDate: launchDate, bundleURL: nil))
    }

    @Test func keyRequiresAPositiveIdentifierAndAKnownLaunchDate() {
        #expect(cacheKey(pid: 501, launchDate: nil, bundleURL: bundleURL) == nil)
        #expect(cacheKey(pid: 0, launchDate: launchDate, bundleURL: bundleURL) == nil)
        #expect(cacheKey(pid: -501, launchDate: launchDate, bundleURL: bundleURL) == nil)
    }

    @Test func repeatedRequestsPrepareAndHashOnceForOneGeneration() async {
        let counters = MediaOperationCounters()
        let icon = Data(repeating: 0x21, count: 64)
        let key = cacheKey(pid: 501, launchDate: launchDate, bundleURL: bundleURL)!
        let log = IconPreparationLog(payloads: [key: icon])
        var cache = SourceAppIconCache(capacity: 4)

        counters.reset()
        let observations = await counters.measure {
            (0..<5).map { _ in cache.prepared(forKey: key, prepare: { log.prepare(key) }) }
        }

        #expect(observations.allSatisfy { $0?.data == icon })
        #expect(observations.allSatisfy { $0?.id == observations[0]?.id })
        #expect(log.attemptCount(for: key) == 1)
        #expect(counters.identityHashCount == 1)
        #expect(cache.count == 1)

        counters.reset()
        let hit = await counters.measure { cache.prepared(forKey: key, prepare: { log.prepare(key) }) }

        #expect(hit?.data == icon)
        #expect(log.attemptCount(for: key) == 1)
        #expect(counters.identityHashCount == 0)
        #expect(counters.mediaHashCount == 0)
    }

    @Test func leastRecentlyUsedGenerationIsEvictedAndPreparedAgain() {
        let (a, b, c) = (generation(601), generation(602), generation(603))
        let payloadA = Data(repeating: 0xA1, count: 32)
        let payloadB = Data(repeating: 0xB2, count: 32)
        let payloadC = Data(repeating: 0xC3, count: 32)
        let log = IconPreparationLog(payloads: [a: payloadA, b: payloadB, c: payloadC])
        var cache = SourceAppIconCache(capacity: 2)

        _ = cache.prepared(forKey: a, prepare: { log.prepare(a) })
        _ = cache.prepared(forKey: b, prepare: { log.prepare(b) })
        _ = cache.prepared(forKey: a, prepare: { log.prepare(a) })
        _ = cache.prepared(forKey: c, prepare: { log.prepare(c) })

        #expect(cache.count == 2)
        #expect(log.attemptCount(for: b) == 1)

        let retainedA = cache.prepared(forKey: a, prepare: { log.prepare(a) })
        #expect(retainedA?.data == payloadA)
        #expect(log.attemptCount(for: a) == 1)

        let repreparedB = cache.prepared(forKey: b, prepare: { log.prepare(b) })
        #expect(repreparedB?.data == payloadB)
        #expect(log.attemptCount(for: b) == 2)
    }

    @Test func repeatedHitsKeepOneRecencyEntryPerGeneration() {
        let (a, b, c) = (generation(611), generation(612), generation(613))
        let payloadA = Data(repeating: 0xD1, count: 32)
        let payloadB = Data(repeating: 0xD2, count: 32)
        let log = IconPreparationLog(payloads: [a: payloadA, b: payloadB, c: Data(repeating: 0xD3, count: 32)])
        var cache = SourceAppIconCache(capacity: 2)

        _ = cache.prepared(forKey: a, prepare: { log.prepare(a) })
        _ = cache.prepared(forKey: b, prepare: { log.prepare(b) })
        for _ in 0..<3 {
            _ = cache.prepared(forKey: a, prepare: { log.prepare(a) })
        }
        _ = cache.prepared(forKey: c, prepare: { log.prepare(c) })

        // Duplicate recency occurrences would have made A the eviction victim.
        let retainedA = cache.prepared(forKey: a, prepare: { log.prepare(a) })
        #expect(retainedA?.data == payloadA)
        #expect(log.attemptCount(for: a) == 1)

        let repreparedB = cache.prepared(forKey: b, prepare: { log.prepare(b) })
        #expect(repreparedB?.data == payloadB)
        #expect(log.attemptCount(for: b) == 2)
    }

    @Test func defaultCapacityBoundsRetainedGenerations() {
        let log = IconPreparationLog(payloads: [:])
        var cache = SourceAppIconCache()
        #expect(cache.capacity == 32)

        var keys: [SourceAppIconCacheKey] = []
        for pid in 1...40 {
            let key = generation(pid_t(pid))
            keys.append(key)
            log.provide(key, payload: Data([UInt8(pid)]))
            _ = cache.prepared(forKey: key, prepare: { log.prepare(key) })
        }

        #expect(cache.count == 32)

        _ = cache.prepared(forKey: keys[39], prepare: { log.prepare(keys[39]) })
        #expect(log.attemptCount(for: keys[39]) == 1)

        _ = cache.prepared(forKey: keys[0], prepare: { log.prepare(keys[0]) })
        #expect(log.attemptCount(for: keys[0]) == 2)
    }

    @Test func unsuccessfulPreparationCreatesNoEntryAndIsRetried() async {
        let counters = MediaOperationCounters()
        let icon = Data(repeating: 0x31, count: 48)
        let key = generation(701)
        let log = IconPreparationLog(payloads: [:])
        var cache = SourceAppIconCache(capacity: 4)

        counters.reset()
        let failures = await counters.measure {
            (0..<3).map { _ in cache.prepared(forKey: key, prepare: { log.prepare(key) }) }
        }

        #expect(failures.allSatisfy { $0 == nil })
        #expect(log.attemptCount(for: key) == 3)
        #expect(counters.identityHashCount == 0)
        #expect(cache.count == 0)

        log.provide(key, payload: icon)
        counters.reset()
        let succeeded = await counters.measure { cache.prepared(forKey: key, prepare: { log.prepare(key) }) }

        #expect(succeeded?.data == icon)
        #expect(log.attemptCount(for: key) == 4)
        #expect(counters.identityHashCount == 1)
        #expect(cache.count == 1)
    }

    @Test func unsuccessfulPreparationLeavesRetainedEntriesAndRecencyUnchanged() {
        let (a, b, c, d) = (generation(711), generation(712), generation(713), generation(714))
        let payloadA = Data(repeating: 0xE1, count: 32)
        let payloadB = Data(repeating: 0xE2, count: 32)
        let log = IconPreparationLog(payloads: [a: payloadA, b: payloadB, d: Data(repeating: 0xE4, count: 32)])
        var cache = SourceAppIconCache(capacity: 2)

        _ = cache.prepared(forKey: a, prepare: { log.prepare(a) })
        _ = cache.prepared(forKey: b, prepare: { log.prepare(b) })
        _ = cache.prepared(forKey: c, prepare: { log.prepare(c) })

        #expect(cache.count == 2)
        #expect(log.attemptCount(for: c) == 1)

        _ = cache.prepared(forKey: d, prepare: { log.prepare(d) })

        #expect(cache.count == 2)

        // The failed attempt neither evicted a successful entry nor changed
        // the recency order: B is still retained, and A stayed the least
        // recent entry that D evicted.
        let retainedB = cache.prepared(forKey: b, prepare: { log.prepare(b) })
        #expect(retainedB?.data == payloadB)
        #expect(log.attemptCount(for: b) == 1)

        let repreparedA = cache.prepared(forKey: a, prepare: { log.prepare(a) })
        #expect(repreparedA?.data == payloadA)
        #expect(log.attemptCount(for: a) == 2)
    }

    private func cacheKey(pid: pid_t, launchDate: Date?, bundleURL: URL?) -> SourceAppIconCacheKey? {
        SourceAppIconCacheKey(processIdentifier: pid, launchDate: launchDate, bundleURL: bundleURL)
    }

    private func generation(_ pid: pid_t) -> SourceAppIconCacheKey {
        cacheKey(pid: pid, launchDate: launchDate, bundleURL: bundleURL)!
    }
}

/// Counts preparation attempts per process generation and finalizes a payload
/// through the real identity seam, so hash counting stays honest. A generation
/// without a payload stands for unavailable preparation.
private final class IconPreparationLog {
    private var payloads: [SourceAppIconCacheKey: Data]
    private var attempts: [SourceAppIconCacheKey: Int] = [:]

    init(payloads: [SourceAppIconCacheKey: Data]) {
        self.payloads = payloads
    }

    func provide(_ key: SourceAppIconCacheKey, payload: Data) {
        payloads[key] = payload
    }

    func prepare(_ key: SourceAppIconCacheKey) -> PreparedMedia? {
        attempts[key, default: 0] += 1
        return payloads[key].map { PreparedMedia(hashing: $0) }
    }

    func attemptCount(for key: SourceAppIconCacheKey) -> Int {
        attempts[key] ?? 0
    }
}
