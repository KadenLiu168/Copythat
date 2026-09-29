import AppKit
import WebKit

enum LinkPreviewSnapshotEvent {
    case navigationDidFinish
    case navigationDidFail
    case webContentProcessTerminated
}

enum LinkPreviewSnapshotMetrics {
    static let pixelLimit: CGFloat = 640
    static let frame = NSRect(x: 0, y: 0, width: 640, height: 360)
}

/// Seam owning one WKWebView request lifecycle: load, stop, snapshot, cleanup.
/// The snapshot controller drives this interface; tests substitute a fake to
/// exercise every terminal ordering deterministically.
@MainActor
protocol LinkPreviewSnapshotDriving: AnyObject {
    /// Receives lifecycle events from the underlying browser. The controller is
    /// main-actor isolated, so adapters hop to the main actor before invoking.
    var eventHandler: (@MainActor (LinkPreviewSnapshotEvent) -> Void)? { get set }

    func load(url: URL)
    func stopLoading()
    /// Submits the single snapshot request used by the controller. The callback
    /// may arrive on any queue.
    func snapshot(rect: CGRect, completion: @escaping (NSImage?) -> Void)
    /// Terminal cleanup: stops loading, detaches navigation callbacks and
    /// releases the application-owned web view.
    func detach()
}

/// Coordinates a single browser snapshot request on the main actor.
///
/// Phases: loading → (didFinish | 3s navigation deadline) → snapshotting →
/// (callback | additional 2s deadline) → finished. Navigation failure before
/// snapshot submission, and web content process termination in either phase,
/// end the request as a failure. Every terminal path runs the same cleanup
/// (cancel deadlines, `driver.detach`) exactly once; late events can neither
/// resubmit a snapshot, resume the waiter twice, nor touch the result.
@MainActor
final class LinkPreviewSnapshotController {
    private enum Phase {
        case loading
        case snapshotting
        case finished
    }

    private enum WakeSignal {
        case navigation(LinkPreviewSnapshotEvent)
        case navigationDeadlineElapsed
        case snapshotDelivered(NSImage?)
        case snapshotDeadlineElapsed
        case cancelled
    }

    private let driver: any LinkPreviewSnapshotDriving
    private let navigationDeadline: TimeInterval
    private let snapshotDeadline: TimeInterval
    private let waitForDeadline: @MainActor (TimeInterval) async throws -> Void

    private var phase: Phase = .loading
    private var isFinished = false
    private var snapshotSubmitted = false
    private var waiter: CheckedContinuation<WakeSignal, Never>?
    private var bufferedWake: WakeSignal?
    private var terminalWake: WakeSignal?
    private var deadlineTask: Task<Void, Never>?

    init(
        driver: any LinkPreviewSnapshotDriving,
        navigationDeadline: TimeInterval = 3,
        snapshotDeadline: TimeInterval = 2,
        waitForDeadline: @escaping @MainActor (TimeInterval) async throws -> Void = {
            try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
        }
    ) {
        self.driver = driver
        self.navigationDeadline = navigationDeadline
        self.snapshotDeadline = snapshotDeadline
        self.waitForDeadline = waitForDeadline
    }

    /// Runs one snapshot attempt with the production WKWebView adapter. Returns
    /// the final bounded PNG with its content address, or nil on failure,
    /// timeout without usable image, or cancellation.
    static func snapshotData(url: URL) async -> PreparedMedia? {
        let controller = LinkPreviewSnapshotController(driver: LinkPreviewWKWebViewDriver())
        return await controller.run(url: url)
    }

    func run(url: URL) async -> PreparedMedia? {
        guard !Task.isCancelled else { return finish(with: nil) }
        driver.eventHandler = { [weak self] event in
            self?.handleEvent(event)
        }
        driver.load(url: url)
        scheduleDeadline(kind: .navigationDeadlineElapsed, seconds: navigationDeadline)

        let navigationSignal = await nextWake()
        cancelDeadline()
        switch navigationSignal {
        case .navigation(.navigationDidFinish), .navigationDeadlineElapsed:
            bufferedWake = nil
            phase = .snapshotting
            let imageData = await runSnapshotPhase()
            return finish(with: imageData)
        case .navigation(.navigationDidFail), .navigation(.webContentProcessTerminated),
             .cancelled, .snapshotDelivered, .snapshotDeadlineElapsed:
            _ = finish(with: nil)
            return nil
        }
    }

    // MARK: - Snapshot phase

    private func runSnapshotPhase() async -> PreparedMedia? {
        guard !Task.isCancelled, terminalWake == nil, !snapshotSubmitted else { return nil }
        snapshotSubmitted = true

        driver.snapshot(rect: LinkPreviewSnapshotMetrics.frame) { [weak self] image in
            Task { @MainActor [weak self] in
                self?.handleSnapshotCallback(image)
            }
        }
        scheduleDeadline(kind: .snapshotDeadlineElapsed, seconds: snapshotDeadline)

        let snapshotSignal = await nextWake()
        cancelDeadline()
        let snapshotImage: NSImage?
        switch snapshotSignal {
        case .snapshotDelivered(let image):
            snapshotImage = image
        case .snapshotDeadlineElapsed, .navigation(.webContentProcessTerminated), .cancelled,
             .navigationDeadlineElapsed:
            snapshotImage = nil
        case .navigation(.navigationDidFinish), .navigation(.navigationDidFail):
            // Filtered stale wakes; treat defensively as a boundary failure.
            snapshotImage = nil
        }
        guard !Task.isCancelled, terminalWake == nil else { return nil }
        // The final bounded PNG and its content address are produced together
        // here, before any consumer can apply or store the payload.
        return snapshotImage?.pngData(maxPixel: LinkPreviewSnapshotMetrics.pixelLimit)
            .map { PreparedMedia(hashing: $0) }
    }

    private func handleSnapshotCallback(_ image: NSImage?) {
        guard phase == .snapshotting else { return }
        dispatch(.snapshotDelivered(image))
    }

    // MARK: - Events and termination

    private func handleEvent(_ event: LinkPreviewSnapshotEvent) {
        switch (phase, event) {
        case (.loading, let event):
            if event != .navigationDidFinish { terminalWake = .navigation(event) }
            dispatch(.navigation(event))
        case (.snapshotting, .webContentProcessTerminated):
            // Process termination still ends a submitted snapshot as a failure.
            terminalWake = .navigation(.webContentProcessTerminated)
            dispatch(.navigation(.webContentProcessTerminated))
        case (.snapshotting, .navigationDidFinish), (.snapshotting, .navigationDidFail),
             (.finished, _):
            // Late navigation events after submission are ignored.
            break
        }
    }

    private func dispatch(_ signal: WakeSignal) {
        guard !isFinished else { return }
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: signal)
        } else {
            // The first wake wins; terminal events are tracked separately.
            if bufferedWake == nil { bufferedWake = signal }
        }
    }

    private func nextWake() async -> WakeSignal {
        if Task.isCancelled { return .cancelled }
        if let terminalWake { return terminalWake }
        if let buffered = bufferedWake {
            bufferedWake = nil
            return buffered
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiter = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.dispatch(.cancelled)
            }
        }
    }

    // MARK: - Terminal state

    /// Marks the terminal state, cancels deadlines, stops loading, detaches the
    /// driver's navigation delegate and releases the application-owned web view.
    /// Runs at most once per request.
    private func finish(with media: PreparedMedia?) -> PreparedMedia? {
        guard !isFinished else { return nil }
        isFinished = true
        phase = .finished
        cancelDeadline()
        bufferedWake = nil
        waiter = nil
        driver.eventHandler = nil
        driver.stopLoading()
        driver.detach()
        return media
    }

    // MARK: - Deadlines

    private func scheduleDeadline(kind: WakeSignal, seconds: TimeInterval) {
        cancelDeadline()
        let waitForDeadline = self.waitForDeadline
        let scheduledPhase = phase
        deadlineTask = Task { [weak self, kind, seconds] in
            do {
                try await waitForDeadline(seconds)
            } catch {
                // The deadline task itself was cancelled (phase transition or
                // terminal cleanup); that is internal lifecycle, not request
                // cancellation. Request cancellation is observed by the waiter
                // via its own cancellation handler.
                return
            }
            guard !Task.isCancelled, let self, self.phase == scheduledPhase else { return }
            self.dispatch(kind)
        }
    }

    private func cancelDeadline() {
        deadlineTask?.cancel()
        deadlineTask = nil
    }
}

/// Production adapter: owns one non-persistent WKWebView per request and maps
/// navigation delegate callbacks onto the driving seam.
@MainActor
final class LinkPreviewWKWebViewDriver: NSObject, LinkPreviewSnapshotDriving {
    private var webView: WKWebView?
    var eventHandler: (@MainActor (LinkPreviewSnapshotEvent) -> Void)?

    /// Call counters (also used by tests to assert the production wiring).
    private(set) var loadCallCount = 0
    private(set) var stopLoadingCallCount = 0
    private(set) var detachCallCount = 0

    var hasReleasedWebView: Bool { webView == nil }

    func load(url: URL) {
        loadCallCount += 1
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.suppressesIncrementalRendering = false

        let webView = WKWebView(frame: LinkPreviewSnapshotMetrics.frame, configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView
        webView.load(URLRequest(url: url, timeoutInterval: 8))
    }

    func stopLoading() {
        stopLoadingCallCount += 1
        webView?.stopLoading()
    }

    func snapshot(rect: CGRect, completion: @escaping (NSImage?) -> Void) {
        guard let webView else {
            completion(nil)
            return
        }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = rect
        webView.takeSnapshot(with: configuration) { image, _ in
            completion(image)
        }
    }

    func detach() {
        detachCallCount += 1
        if let webView {
            webView.navigationDelegate = nil
            webView.stopLoading()
        }
        webView = nil
    }
}

extension LinkPreviewWKWebViewDriver: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        eventHandler?(.navigationDidFinish)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        eventHandler?(.navigationDidFail)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        eventHandler?(.navigationDidFail)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        eventHandler?(.webContentProcessTerminated)
    }
}
