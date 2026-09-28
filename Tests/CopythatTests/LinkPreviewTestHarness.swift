@testable import Copythat
import AppKit
import Foundation

/// Thread-safe event counter with awaitable thresholds. All waits are
/// continuation-based so tests never sleep.
final class LinkPreviewCounter: @unchecked Sendable {
    private final class ThresholdWaiter {
        let key: String
        let threshold: Int
        var continuation: CheckedContinuation<Void, Never>?

        init(key: String, threshold: Int) {
            self.key = key
            self.threshold = threshold
        }
    }

    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var waiters: [ThresholdWaiter] = []
    private var concurrent = 0
    private var peakConcurrent = 0

    /// Records a loader start; also tracks in-flight concurrency for assertions.
    func begin(_ key: String) {
        lock.lock()
        counts[key, default: 0] += 1
        concurrent += 1
        peakConcurrent = max(peakConcurrent, concurrent)
        let reached = collectReached(forKey: key)
        lock.unlock()
        reached.forEach { $0.continuation?.resume() }
    }

    /// Records a plain event (no concurrency bookkeeping); resolves waiters.
    func mark(_ key: String) {
        lock.lock()
        counts[key, default: 0] += 1
        let reached = collectReached(forKey: key)
        lock.unlock()
        reached.forEach { $0.continuation?.resume() }
    }

    /// Records a loader end.
    func end(_ key: String) {
        lock.lock()
        concurrent -= 1
        counts["ended:\(key)", default: 0] += 1
        let reached = collectReached(forKey: "ended:\(key)")
        lock.unlock()
        reached.forEach { $0.continuation?.resume() }
    }

    func value(_ key: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[key] ?? 0
    }

    func endedValue(_ key: String) -> Int {
        value("ended:\(key)")
    }

    func peakConcurrency() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return peakConcurrent
    }

    func waitForEnd(_ key: String, reaching threshold: Int) async {
        await waitFor("ended:\(key)", reaching: threshold)
    }

    func waitFor(_ key: String, reaching threshold: Int) async {
        lock.lock()
        if (counts[key] ?? 0) >= threshold {
            lock.unlock()
            return
        }
        lock.unlock()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if (counts[key] ?? 0) >= threshold {
                lock.unlock()
                continuation.resume()
                return
            }
            let waiter = ThresholdWaiter(key: key, threshold: threshold)
            waiter.continuation = continuation
            waiters.append(waiter)
            lock.unlock()
        }
    }

    private func collectReached(forKey key: String) -> [ThresholdWaiter] {
        var reached: [ThresholdWaiter] = []
        waiters.removeAll { waiter in
            guard waiter.key == key, waiter.continuation != nil else { return false }
            if (counts[key] ?? 0) >= waiter.threshold {
                reached.append(waiter)
                return true
            }
            return false
        }
        return reached
    }
}
/// Gate for test loaders. `waitOrCancelled` returns when released OR when the
/// enclosing task is cancelled; `waitUntilReleased` ignores cancellation so a
/// deliberately late result can be delivered after a Store-side cancel.
final class LinkPreviewGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isReleased = false
    private var cancellationObserved = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func waitOrCancelled() async {
        lock.lock()
        if isReleased || cancellationObserved {
            lock.unlock()
            return
        }
        lock.unlock()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                if isReleased || cancellationObserved {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                waiters.append(continuation)
                lock.unlock()
            }
        } onCancel: {
            observeCancellation()
        }
    }

    func waitUntilReleased() async {
        lock.lock()
        if isReleased {
            lock.unlock()
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            lock.unlock()
        }
    }

    func release() {
        lock.lock()
        isReleased = true
        let pending = waiters
        waiters = []
        lock.unlock()
        pending.forEach { $0.resume() }
    }

    private func observeCancellation() {
        lock.lock()
        cancellationObserved = true
        let pending = waiters
        waiters = []
        lock.unlock()
        pending.forEach { $0.resume() }
    }
}

/// MainActor save recorder with awaitable save counts.
@MainActor
final class LinkPreviewSaveRecorder {
    private final class ThresholdWaiter {
        let threshold: Int
        var continuation: CheckedContinuation<Void, Never>?

        init(threshold: Int) {
            self.threshold = threshold
        }
    }

    private var saves: [[ClipboardItem]] = []
    private var waiters: [ThresholdWaiter] = []

    func record(_ items: [ClipboardItem]) {
        saves.append(items)
        let reached = waiters.filter { saves.count >= $0.threshold }
        let reachedIDs = Set(reached.map(ObjectIdentifier.init))
        waiters.removeAll { reachedIDs.contains(ObjectIdentifier($0)) }
        reached.forEach { $0.continuation?.resume() }
    }

    var count: Int { saves.count }

    var last: [ClipboardItem]? { saves.last }

    func recordedSaves() -> [[ClipboardItem]] {
        saves
    }

    func waitForSaveCount(_ count: Int) async {
        if saves.count >= count { return }
        let waiter = ThresholdWaiter(threshold: count)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiter.continuation = continuation
            waiters.append(waiter)
        }
    }
}

// MARK: - Test fixtures

@MainActor
enum LinkPreviewFixture {
    static func tempDefaults(_ label: String) -> UserDefaults {
        let suiteName = "LinkPreview.\(label).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    static func uniquePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        return pasteboard
    }

    static func urlItem(
        id: UUID = UUID(),
        urlString: String,
        linkTitle: String? = nil,
        linkImageData: Data? = nil,
        isPinned: Bool = false,
        pinboardName: String? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: .url,
            title: URL(string: urlString)?.host(percentEncoded: false) ?? urlString,
            preview: urlString,
            sourceApp: "Safari",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            isPinned: isPinned,
            pinboardName: pinboardName,
            textValue: urlString,
            fileURLs: [],
            imageData: nil,
            linkTitle: linkTitle,
            linkImageData: linkImageData
        )
    }

    static func textItem(id: UUID = UUID(), text: String) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: .text,
            title: text,
            preview: text,
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            isPinned: false,
            pinboardName: nil,
            textValue: text,
            fileURLs: [],
            imageData: nil
        )
    }

    static func testImage(red: Bool = false) -> NSImage {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 32,
            pixelsHigh: 32,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let color = red
            ? NSColor(calibratedRed: 0.9, green: 0.1, blue: 0.1, alpha: 1)
            : NSColor(calibratedRed: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        for pixelX in 0..<32 {
            for pixelY in 0..<32 {
                bitmap.setColor(color, atX: pixelX, y: pixelY)
            }
        }
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.addRepresentation(bitmap)
        return image
    }

    /// Bounded sample image (1280×1280) to exercise 640px processing.
    static func largeTestImage(red: Bool = false) -> NSImage {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1280,
            pixelsHigh: 1280,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let color = red
            ? NSColor(calibratedRed: 0.9, green: 0.1, blue: 0.1, alpha: 1)
            : NSColor(calibratedRed: 0.3, green: 0.6, blue: 0.2, alpha: 1)
        bitmap.setColor(color, atX: 0, y: 0)
        bitmap.setColor(color, atX: 1279, y: 1279)
        let image = NSImage(size: NSSize(width: 1280, height: 1280))
        image.addRepresentation(bitmap)
        return image
    }
}
