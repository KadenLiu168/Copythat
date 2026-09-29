@testable import Copythat
import AppKit
import Foundation
import Testing

@MainActor
private final class FakeLinkPreviewDriver: LinkPreviewSnapshotDriving {
    var eventHandler: (@MainActor (LinkPreviewSnapshotEvent) -> Void)?
    private(set) var loadCalls: [URL] = []
    private(set) var snapshotRequests: [CGRect] = []
    private(set) var detachCalls = 0
    private(set) var stopLoadingCalls = 0
    private let counter: LinkPreviewCounter

    private var pendingSnapshotCompletions: [(NSImage?) -> Void] = []

    init(counter: LinkPreviewCounter) {
        self.counter = counter
    }

    func load(url: URL) {
        loadCalls.append(url)
        counter.mark("load")
    }

    func stopLoading() {
        stopLoadingCalls += 1
    }

    func snapshot(rect: CGRect, completion: @escaping (NSImage?) -> Void) {
        snapshotRequests.append(rect)
        pendingSnapshotCompletions.append(completion)
        counter.mark("snapshotSubmitted")
    }

    func detach() {
        detachCalls += 1
        counter.mark("detached")
    }

    func emit(_ event: LinkPreviewSnapshotEvent) {
        eventHandler?(event)
    }

    func completeSnapshot(_ image: NSImage?) {
        let completions = pendingSnapshotCompletions
        completions.forEach { $0(image) }
    }
}

@MainActor
@Suite(.serialized)
struct LinkPreviewSnapshotControllerTests {
    private let counter = LinkPreviewCounter()
    private let snapshotImage = LinkPreviewFixture.testImage()
    private let navigationGate = LinkPreviewGate()
    private let snapshotGate = LinkPreviewGate()

    private func controlledDeadline(_ seconds: TimeInterval) async throws {
        let key = seconds == 3 ? "navigationDeadline" : "snapshotDeadline"
        counter.mark(key)
        await (seconds == 3 ? navigationGate : snapshotGate).waitOrCancelled()
        try Task.checkCancellation()
    }

    private func makeDriver() -> FakeLinkPreviewDriver {
        FakeLinkPreviewDriver(counter: counter)
    }

    @Test func cancelledBeforeRunDoesNotLoadOrSnapshot() async {
        let driver = makeDriver()
        let controller = LinkPreviewSnapshotController(driver: driver)
        let task = Task { await controller.run(url: fixtureURL()) }
        task.cancel()
        let data = await task.value

        #expect(data == nil)
        #expect(driver.loadCalls.isEmpty)
        #expect(driver.snapshotRequests.isEmpty)
        #expect(driver.detachCalls == 1)
    }

    @Test func cancellationAfterDidFinishBeforeResumptionDoesNotSnapshot() async {
        let driver = makeDriver()
        let controller = LinkPreviewSnapshotController(driver: driver)
        let task = Task { await controller.run(url: fixtureURL()) }
        await counter.waitFor("load", reaching: 1)
        driver.emit(.navigationDidFinish)
        task.cancel()
        let data = await task.value

        #expect(data == nil)
        #expect(driver.snapshotRequests.isEmpty)
        #expect(driver.detachCalls == 1)
    }

    @Test func earlyDidFinishSubmitsSnapshotImmediately() async {
        let driver = makeDriver()
        let controller = LinkPreviewSnapshotController(
            driver: driver,
            waitForDeadline: controlledDeadline
        )

        async let result = controller.run(url: fixtureURL())
        await counter.waitFor("load", reaching: 1)
        driver.emit(.navigationDidFinish)
        await counter.waitFor("snapshotSubmitted", reaching: 1)
        driver.completeSnapshot(snapshotImage)
        let data = await result
        await counter.waitFor("detached", reaching: 1)

        #expect(data != nil)
        #expect(driver.snapshotRequests.count == 1)
        #expect(driver.detachCalls == 1)
        #expect(driver.stopLoadingCalls >= 1)
        #expect(driver.eventHandler == nil)
    }

    @Test func deliveredSnapshotCarriesExactlyOneIdentityHash() async throws {
        let counters = MediaOperationCounters()
        let driver = makeDriver()
        let controller = LinkPreviewSnapshotController(
            driver: driver,
            waitForDeadline: controlledDeadline
        )

        counters.reset()
        async let result = counters.measure {
            await controller.run(url: fixtureURL())
        }
        await counter.waitFor("load", reaching: 1)
        driver.emit(.navigationDidFinish)
        await counter.waitFor("snapshotSubmitted", reaching: 1)
        driver.completeSnapshot(snapshotImage)
        let media = try #require(await result)

        #expect(media.id.count == 64)
        #expect(!media.data.isEmpty)
        #expect(counters.identityHashCount == 1)
        #expect(counters.integrityHashCount == 0)
    }

    @Test func navigationDeadlineAttemptsSnapshotOnceWithoutDidFinish() async {
        let driver = makeDriver()
        let controller = LinkPreviewSnapshotController(
            driver: driver,
            waitForDeadline: controlledDeadline
        )

        async let result = controller.run(url: fixtureURL())
        await counter.waitFor("navigationDeadline", reaching: 1)
        navigationGate.release()
        await counter.waitFor("snapshotSubmitted", reaching: 1)
        driver.completeSnapshot(snapshotImage)
        let data = await result

        #expect(data != nil)
        #expect(driver.snapshotRequests.count == 1)
        #expect(driver.loadCalls.count == 1)
        #expect(driver.detachCalls == 1)
    }

    @Test func navigationFailureBeforeSubmissionFailsWithoutSnapshot() async {
        let driver = makeDriver()
        let controller = LinkPreviewSnapshotController(
            driver: driver,
            waitForDeadline: controlledDeadline
        )

        async let result = controller.run(url: fixtureURL())
        await counter.waitFor("load", reaching: 1)
        driver.emit(.navigationDidFail)
        let data = await result

        #expect(data == nil)
        #expect(driver.snapshotRequests.isEmpty)
        #expect(driver.detachCalls == 1)
    }

    @Test func processTerminationDuringLoadingFailsWithoutSnapshot() async {
        let driver = makeDriver()
        let controller = LinkPreviewSnapshotController(
            driver: driver,
            waitForDeadline: controlledDeadline
        )

        async let result = controller.run(url: fixtureURL())
        await counter.waitFor("load", reaching: 1)
        driver.emit(.webContentProcessTerminated)
        let data = await result

        #expect(data == nil)
        #expect(driver.snapshotRequests.isEmpty)
        #expect(driver.detachCalls == 1)
    }

    @Test func processTerminationDuringSnapshottingFails() async {
        let driver = makeDriver()
        let controller = LinkPreviewSnapshotController(
            driver: driver,
            waitForDeadline: controlledDeadline
        )

        async let result = controller.run(url: fixtureURL())
        await counter.waitFor("load", reaching: 1)
        driver.emit(.navigationDidFinish)
        await counter.waitFor("snapshotSubmitted", reaching: 1)
        driver.emit(.webContentProcessTerminated)
        let data = await result

        #expect(data == nil)
        #expect(driver.snapshotRequests.count == 1)
        #expect(driver.detachCalls == 1)

        // Late callback after termination must not resurrect the result.
        driver.completeSnapshot(snapshotImage)
    }

    @Test func lateNavigationFailureAfterSubmissionIsIgnored() async {
        let driver = makeDriver()
        let controller = LinkPreviewSnapshotController(
            driver: driver,
            waitForDeadline: controlledDeadline
        )

        async let result = controller.run(url: fixtureURL())
        await counter.waitFor("load", reaching: 1)
        driver.emit(.navigationDidFinish)
        await counter.waitFor("snapshotSubmitted", reaching: 1)
        driver.emit(.navigationDidFail)
        driver.completeSnapshot(snapshotImage)
        let data = await result

        #expect(data != nil)
        #expect(driver.snapshotRequests.count == 1)
    }

    @Test func missingSnapshotCallbackFailsAtSnapshotDeadline() async {
        let driver = makeDriver()
        let controller = LinkPreviewSnapshotController(
            driver: driver,
            waitForDeadline: controlledDeadline
        )

        async let result = controller.run(url: fixtureURL())
        await counter.waitFor("navigationDeadline", reaching: 1)
        navigationGate.release()
        await counter.waitFor("snapshotSubmitted", reaching: 1)
        await counter.waitFor("snapshotDeadline", reaching: 1)
        snapshotGate.release()
        let data = await result

        #expect(data == nil)
        #expect(driver.snapshotRequests.count == 1)
        #expect(driver.detachCalls == 1)
    }

    @Test func cancelBeforeSnapshotSubmissionSendsNoSnapshot() async {
        let driver = makeDriver()
        let controller = LinkPreviewSnapshotController(
            driver: driver,
            waitForDeadline: controlledDeadline
        )

        let task = Task { await controller.run(url: fixtureURL()) }
        await counter.waitFor("load", reaching: 1)
        task.cancel()
        let data = await task.value

        #expect(data == nil)
        #expect(driver.snapshotRequests.isEmpty)
        #expect(driver.detachCalls == 1)
    }

    @Test func cancelAfterSubmissionDiscardsCallback() async {
        let driver = makeDriver()
        let controller = LinkPreviewSnapshotController(
            driver: driver,
            waitForDeadline: controlledDeadline
        )

        let task = Task { await controller.run(url: fixtureURL()) }
        await counter.waitFor("navigationDeadline", reaching: 1)
        navigationGate.release()
        await counter.waitFor("snapshotSubmitted", reaching: 1)
        task.cancel()
        let data = await task.value

        #expect(data == nil)
        #expect(driver.snapshotRequests.count == 1)
        #expect(driver.detachCalls == 1)

        // Late callback after terminal state must be discarded without effect.
        driver.completeSnapshot(snapshotImage)
    }

    @Test func doubleDidFinishSubmitsSnapshotOnce() async {
        let driver = makeDriver()
        let controller = LinkPreviewSnapshotController(
            driver: driver,
            waitForDeadline: controlledDeadline
        )

        async let result = controller.run(url: fixtureURL())
        await counter.waitFor("load", reaching: 1)
        driver.emit(.navigationDidFinish)
        driver.emit(.navigationDidFinish)
        await counter.waitFor("snapshotSubmitted", reaching: 1)
        driver.completeSnapshot(snapshotImage)
        let data = await result

        #expect(data != nil)
        #expect(driver.snapshotRequests.count == 1)
    }

    @Test func eventsBufferedBeforeWaitingStillWakeTheRequest() async {
        let driver = BufferedLoadDriver(image: snapshotImage)
        let controller = LinkPreviewSnapshotController(
            driver: driver,
            waitForDeadline: controlledDeadline
        )

        let data = await controller.run(url: fixtureURL())

        #expect(data != nil)
        #expect(driver.snapshotRequests.count == 1)
        #expect(driver.detachCalls == 1)
    }

    @Test func failureAfterDidFinishBeforeSubmissionPreventsSnapshot() async {
        let driver = makeDriver()
        let controller = LinkPreviewSnapshotController(driver: driver, waitForDeadline: controlledDeadline)
        let task = Task { await controller.run(url: fixtureURL()) }
        await counter.waitFor("load", reaching: 1)
        driver.emit(.navigationDidFinish)
        driver.emit(.navigationDidFail)
        let data = await task.value
        #expect(data == nil)
        #expect(driver.snapshotRequests.isEmpty)
        #expect(driver.detachCalls == 1)
    }

    @Test func duplicateSnapshotCallbacksKeepFirstResult() async {
        let driver = makeDriver()
        let controller = LinkPreviewSnapshotController(driver: driver, waitForDeadline: controlledDeadline)
        let task = Task { await controller.run(url: fixtureURL()) }
        await counter.waitFor("load", reaching: 1)
        driver.emit(.navigationDidFinish)
        await counter.waitFor("snapshotSubmitted", reaching: 1)
        driver.completeSnapshot(snapshotImage)
        driver.completeSnapshot(nil)
        let data = await task.value
        #expect(data != nil)
        #expect(driver.detachCalls == 1)
    }

    @Test func productionAdapterCancellationReleasesRealWebView() async {
        let driver = LinkPreviewWKWebViewDriver()
        let controller = LinkPreviewSnapshotController(driver: driver, waitForDeadline: controlledDeadline)
        let task = Task { await controller.run(url: URL(string: "about:blank")!) }
        await counter.waitFor("navigationDeadline", reaching: 1)
        task.cancel()
        let data = await task.value
        #expect(data == nil)
        #expect(driver.loadCallCount == 1)
        #expect(driver.detachCallCount == 1)
        #expect(driver.stopLoadingCallCount >= 1)
        #expect(driver.eventHandler == nil)
        #expect(driver.hasReleasedWebView)
    }

    @Test func productionAdapterRunsAboutBlankLifecycleWithRealWebKit() async {
        let driver = LinkPreviewWKWebViewDriver()
        let controller = LinkPreviewSnapshotController(
            driver: driver,
            navigationDeadline: 5,
            snapshotDeadline: 5
        )

        let data = await controller.run(url: URL(string: "about:blank")!)

        #expect(data != nil)
        #expect(driver.loadCallCount == 1)
        #expect(driver.stopLoadingCallCount >= 1)
        #expect(driver.detachCallCount == 1)
        #expect(driver.hasReleasedWebView)
    }

    private func fixtureURL() -> URL {
        URL(string: "https://example.com/")!
    }
}

/// Driver that fires didFinish synchronously inside load, exercising the
/// controller's event buffering before the waiter registers.
@MainActor
private final class BufferedLoadDriver: LinkPreviewSnapshotDriving {
    var eventHandler: (@MainActor (LinkPreviewSnapshotEvent) -> Void)?
    private(set) var snapshotRequests: [CGRect] = []
    private(set) var detachCalls = 0
    private let image: NSImage

    init(image: NSImage) {
        self.image = image
    }

    func load(url: URL) {
        eventHandler?(.navigationDidFinish)
    }

    func stopLoading() {}

    func snapshot(rect: CGRect, completion: @escaping (NSImage?) -> Void) {
        snapshotRequests.append(rect)
        completion(image)
    }

    func detach() {
        detachCalls += 1
    }
}
