@testable import Copythat
import AppKit
import CryptoKit
import Foundation
import Testing
import UniformTypeIdentifiers

@MainActor
struct ClipboardImageDragCancellationTests {
    @Test func cancelledReceiverNeverGetsLateImageBytes() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DragCancellation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        image.setColor(.red, atX: 0, y: 0)
        let bytes = try #require(image.representation(using: .png, properties: [:]))
        let blobID = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        try bytes.write(to: directory.appendingPathComponent("\(blobID).blob"))

        let started = DispatchSemaphore(value: 0)
        let gate = DispatchSemaphore(value: 0)
        let loader = ClipboardHistoryMediaLoader(blobStore: ClipboardHistoryBlobStore(
            directoryURL: directory,
            readData: { url in
                started.signal()
                _ = gate.wait(timeout: .now() + 5)
                return try Data(contentsOf: url)
            }
        ))
        let item = ClipboardItem(
            id: UUID(), kind: .image, title: "image", preview: "image",
            sourceApp: "Tests", sourceAppIconData: nil, createdAt: Date(),
            isPinned: false, pinboardName: nil, textValue: nil, fileURLs: [],
            imageData: nil, imageBlobID: blobID
        )
        let provider = ClipboardImageDragProvider.provider(for: item, mediaLoader: loader)
        let received = DragResultRecorder()
        let progress = provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, _ in
            received.record(data)
        }
        let didStart = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: started.wait(timeout: .now() + 5) == .success)
            }
        }
        defer { gate.signal() }
        #expect(didStart)
        progress.cancel()
        gate.signal()
        #expect(await received.waitForCompletion())
        #expect(received.count == 1)
        #expect(received.deliveredBytes == false)
        AcceptanceMetrics.record(
            scenario: "image-drag-cancellation",
            metric: "receiverCompletionsAfterCancel",
            expected: "1",
            observed: "\(received.count)"
        )
        AcceptanceMetrics.record(
            scenario: "image-drag-cancellation",
            metric: "lateImageBytesDeliveredAfterCancel",
            expected: "false",
            observed: "\(received.deliveredBytes)"
        )
    }
}

private final class DragResultRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Bool] = []
    var count: Int { lock.lock(); defer { lock.unlock() }; return results.count }
    var deliveredBytes: Bool { lock.lock(); defer { lock.unlock() }; return results.contains(true) }
    func record(_ data: Data?) {
        lock.lock()
        results.append(data != nil)
        lock.unlock()
    }
    func waitForCompletion() async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while count == 0 && Date() < deadline {
            await Task.yield()
        }
        return count > 0
    }
}
