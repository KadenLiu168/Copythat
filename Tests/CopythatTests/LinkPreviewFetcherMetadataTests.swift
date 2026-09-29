@testable import Copythat
import AppKit
import LinkPresentation
import CryptoKit
import Testing
import UniformTypeIdentifiers

@MainActor
@Suite(.serialized)
struct LinkPreviewFetcherMetadataTests {
    @Test func extractPreviewPrefersImageOverIconAndBoundsTo640px() async throws {
        let metadata = LPLinkMetadata()
        metadata.title = " Example Domain "
        metadata.imageProvider = NSItemProvider(object: LinkPreviewFixture.testImage())
        metadata.iconProvider = NSItemProvider(object: LinkPreviewFixture.largeTestImage(red: true))

        let result = try await LinkPreviewFetcher.extractPreview(from: metadata)

        #expect(result.title == "Example Domain")
        let image = try #require(result.image.flatMap { NSImage(data: $0.data) })
        #expect(image.size == NSSize(width: 32, height: 32))
        #expect(max(image.size.width, image.size.height) <= 640)
    }

    @Test func finalizedPreviewCarriesExactlyOneIdentityHash() async throws {
        let counters = MediaOperationCounters()
        let metadata = LPLinkMetadata()
        metadata.imageProvider = NSItemProvider(object: LinkPreviewFixture.largeTestImage(red: true))

        counters.reset()
        let result = try await counters.measure {
            try await LinkPreviewFetcher.extractPreview(from: metadata)
        }

        let image = try #require(result.image)
        #expect(counters.identityHashCount == 1)
        #expect(counters.integrityHashCount == 0)
        #expect(image.id == sha256Hex(image.data))
        let decoded = try #require(NSImage(data: image.data))
        #expect(max(decoded.size.width, decoded.size.height) <= 640)
    }

    @Test func cancelledExtractionDoesNotReturnEmptySuccess() async {
        let metadata = LPLinkMetadata()
        let task = Task { try await LinkPreviewFetcher.extractPreview(from: metadata) }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("cancelled extraction must throw")
        } catch {
            #expect(error is CancellationError)
        }
    }

    @Test func cancelledMetadataRequestDoesNotStartProvider() async {
        let task = Task {
            try await LinkPreviewFetcher.fetchMetadata(url: URL(string: "https://example.com/")!)
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("cancelled metadata must throw")
        } catch {
            #expect(error is CancellationError)
        }
    }

    @Test func cancellationOfPendingItemProviderEndsWithoutCallback() async {
        let counter = LinkPreviewCounter()
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { _ in
            let progress = Progress(totalUnitCount: 1)
            progress.cancellationHandler = { counter.mark("cancelled") }
            counter.mark("loading")
            return progress
        }
        let metadata = LPLinkMetadata()
        metadata.imageProvider = provider
        let task = Task { try await LinkPreviewFetcher.extractPreview(from: metadata) }
        await counter.waitFor("loading", reaching: 1)
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("pending image load must end on cancellation without an Apple callback")
        } catch {
            #expect(error is CancellationError)
        }
        await counter.waitFor("cancelled", reaching: 1)
    }

    @Test func extractPreviewFallsBackToIconWhenImageMissing() async throws {
        let metadata = LPLinkMetadata()
        metadata.title = "Icon only"
        metadata.iconProvider = NSItemProvider(object: LinkPreviewFixture.testImage())

        let result = try await LinkPreviewFetcher.extractPreview(from: metadata)

        #expect(result.title == "Icon only")
        #expect(result.image != nil)
    }

    @Test func extractPreviewAllowsEmptySuccess() async throws {
        let metadata = LPLinkMetadata()

        let result = try await LinkPreviewFetcher.extractPreview(from: metadata)

        #expect(result.title == nil)
        #expect(result.image == nil)
    }

    @Test func extractPreviewTrimsWhitespaceOnlyTitleToNil() async throws {
        let metadata = LPLinkMetadata()
        metadata.title = "   "

        let result = try await LinkPreviewFetcher.extractPreview(from: metadata)

        #expect(result.title == nil)
    }

    @Test func metadataStageContainsNoWebKitUsage() throws {
        // The metadata path must structurally never touch WebKit: the browser
        // snapshot lives in its own stage (LinkPreviewSnapshotController).
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Copythat/Support/LinkPreviewFetcher.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        #expect(!source.contains("import WebKit"))
        #expect(!source.contains("WKWebView"))
        #expect(!source.contains("takeSnapshot"))
    }
}

@Suite(.serialized)
struct LinkPreviewCallbackBridgeTests {
    @Test func bridgeDeliversCallbackValueExactlyOnce() async throws {
        let bridge = LinkPreviewCallbackBridge<Int>()
        let counter = LinkPreviewCounter()

        let task = Task {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
                let startAllowed = bridge.register(continuation)
                #expect(startAllowed)
                counter.mark("registered")
            }
        }
        await counter.waitFor("registered", reaching: 1)
        bridge.finish(.success(7))
        bridge.finish(.success(8))

        let value = try await task.value
        #expect(value == 7)
    }

    @Test func cancelBeforeRegisterPreventsStartAndThrowsCancellation() async throws {
        let bridge = LinkPreviewCallbackBridge<Int>()
        bridge.cancel()

        await #expect(throws: CancellationError.self) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
                let startAllowed = bridge.register(continuation)
                #expect(startAllowed == false)
            }
        }
    }

    @Test func lateCallbackAfterCancelIsIgnored() async throws {
        let bridge = LinkPreviewCallbackBridge<Int>()
        let counter = LinkPreviewCounter()

        let task = Task {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
                _ = bridge.register(continuation)
                counter.mark("registered")
            }
        }
        await counter.waitFor("registered", reaching: 1)
        bridge.cancel()
        bridge.finish(.success(99))

        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch {
            #expect(error is CancellationError)
        }
    }

    @Test func doubleCancelResumesWaiterExactlyOnce() async throws {
        let bridge = LinkPreviewCallbackBridge<Int>()
        let counter = LinkPreviewCounter()

        let task = Task {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
                _ = bridge.register(continuation)
                counter.mark("registered")
            }
        }
        await counter.waitFor("registered", reaching: 1)
        bridge.cancel()
        bridge.cancel()

        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch {
            #expect(error is CancellationError)
        }
    }

    @Test func adoptProgressAfterCancelCancelsProgressImmediately() async {
        let bridge = LinkPreviewCallbackBridge<Int>()
        bridge.cancel()

        let progress = Progress()
        bridge.adopt(progress: progress)

        #expect(progress.isCancelled)
    }

    @Test func adoptProgressThenCancelCancelsRegisteredProgress() async {
        let bridge = LinkPreviewCallbackBridge<Int>()
        let progress = Progress()
        bridge.adopt(progress: progress)

        bridge.cancel()

        #expect(progress.isCancelled)
    }

    @Test func synchronousCallbackDuringStartCompletes() async throws {
        let bridge = LinkPreviewCallbackBridge<String>()

        let value = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let startAllowed = bridge.register(continuation)
            #expect(startAllowed)
            bridge.finish(.success("sync"))
        }

        #expect(value == "sync")
    }
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}
