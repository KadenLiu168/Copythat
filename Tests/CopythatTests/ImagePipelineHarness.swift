@testable import Copythat
import AppKit
import Foundation
import Testing

/// Mutable foreground source so a test can switch the frontmost application
/// between admissions and prove a queued card keeps its admission-time context.
final class MutableSourceBox {
    var source: ClipboardSource?
}

/// Collector for image-pipeline diagnostic events. The Store is built inside an
/// initializer, so the sink owns its own storage rather than capturing `self`.
final class ImagePipelineEventBox {
    private let lock = NSLock()
    private var events: [ClipboardDiagnostics.ImagePipelineEvent] = []

    func append(_ event: ClipboardDiagnostics.ImagePipelineEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    var recorded: [ClipboardDiagnostics.ImagePipelineEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

/// One Store wired for deterministic pipeline observation: virtual uptime for
/// stability gating, a parked encoder for physical-slot control, an injected
/// capacity, and counted saves and handled completions.
@MainActor
final class ImagePipelineHarness {
    let store: ClipboardStore
    let pasteboard: NSPasteboard
    let clock: MutableClock
    let encoder: ControlledImageEncoder
    let saves: LinkPreviewCounter
    let handled: LinkPreviewCounter
    let sourceBox: MutableSourceBox
    let eventBox: ImagePipelineEventBox

    init(
        capacity: Int,
        diagnosticsEnabled: Bool = false,
        ignoredApplications: String = "",
        source: ClipboardSource? = ClipboardSource(appName: "Tests", iconData: nil, capturedAt: Date())
    ) {
        let label = "ImagePipeline.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: label)!
        defaults.removePersistentDomain(forName: label)
        defaults.set(ignoredApplications, forKey: "ignoredApplications")

        let diagnosticsDefaults = UserDefaults(suiteName: "\(label).diagnostics")!
        diagnosticsDefaults.removePersistentDomain(forName: "\(label).diagnostics")
        diagnosticsDefaults.set(diagnosticsEnabled, forKey: ClipboardDiagnostics.defaultsKey)

        let sourceBox = MutableSourceBox()
        sourceBox.source = source
        self.sourceBox = sourceBox
        let eventBox = ImagePipelineEventBox()
        self.eventBox = eventBox

        let diagnostics = ClipboardDiagnostics(
            defaults: diagnosticsDefaults,
            imagePipelineEventSink: { event in eventBox.append(event) }
        )
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        self.pasteboard = pasteboard

        let saves = LinkPreviewCounter()
        self.saves = saves
        let clock = MutableClock()
        self.clock = clock
        let encoder = ControlledImageEncoder()
        self.encoder = encoder
        let handled = LinkPreviewCounter()
        self.handled = handled

        self.store = ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(
                frontmostSourceProvider: { sourceBox.source },
                diagnostics: diagnostics
            ),
            initialItems: [],
            pasteboard: pasteboard,
            diagnostics: diagnostics,
            persistItems: { _ in saves.mark("saved") },
            uptimeProvider: { clock.now },
            fetchLinkMetadata: { _ in throw URLError(.unsupportedURL) },
            fetchLinkSnapshot: { _ in throw URLError(.unsupportedURL) },
            imageCaptureCapacity: capacity,
            encodeImage: { cgImage, recorder in
                await encoder.encode(cgImage, recorder: recorder)
            }
        )
        // Captures the counter directly: a closure naming `self` here would keep
        // the harness — and through it the Store — alive for the whole test.
        store.imageCompletionHandledObserver = { handled.mark("handled") }
    }

    /// Drives one image through the real admission path: an external write, a
    /// first observation, then a poll past the stability interval.
    func capture(_ image: NSImage) {
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([image]))
        store.pollPasteboard()
        clock.advance(by: 1)
        store.pollPasteboard()
    }

    func waitForHandled(_ threshold: Int) async {
        await handled.waitFor("handled", reaching: threshold)
    }

    /// Drains the whole buffer: releases whatever is parked, waits for that
    /// completion to be handled, then waits for the next encoder to start before
    /// releasing it. A plain `releaseAll()` would miss encoders that the
    /// previous completion had not launched yet.
    func drain(through handledCount: Int) async {
        for step in 1...handledCount {
            encoder.releaseAll()
            await waitForHandled(step)
            if step < handledCount {
                await encoder.waitForStart(reaching: step + 1)
            }
        }
    }

    var savedCount: Int { saves.value("saved") }
    var historyCount: Int { store.items.count }
    var overflowEvents: [ClipboardDiagnostics.ImagePipelineEvent] { eventBox.recorded }
}

enum ImagePipelineFixture {
    /// Solid-colour bitmap. Distinct colours yield distinct PNG payloads, so
    /// each fixture stands for distinct clipboard content.
    static func image(
        pixelsWide: Int = 32,
        pixelsHigh: Int = 32,
        red: CGFloat = 0.2,
        green: CGFloat = 0.4,
        blue: CGFloat = 0.8
    ) -> NSImage {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let color = NSColor(calibratedRed: red, green: green, blue: blue, alpha: 1)
        for pixelX in 0..<pixelsWide {
            for pixelY in 0..<pixelsHigh {
                bitmap.setColor(color, atX: pixelX, y: pixelY)
            }
        }
        let image = NSImage(size: NSSize(width: pixelsWide, height: pixelsHigh))
        image.addRepresentation(bitmap)
        return image
    }

    static func redImage() -> NSImage { image(red: 0.9, green: 0.1, blue: 0.1) }
    static func greenImage() -> NSImage { image(red: 0.1, green: 0.8, blue: 0.2) }
    static func blueImage() -> NSImage { image(red: 0.1, green: 0.2, blue: 0.9) }
    static func amberImage() -> NSImage { image(red: 0.9, green: 0.7, blue: 0.1) }
    static func violetImage() -> NSImage { image(red: 0.5, green: 0.2, blue: 0.8) }

    /// Content address the production finalizer produces for an image.
    static func blobID(of image: NSImage) async throws -> String {
        try await preparedMedia(of: image).id
    }

    /// The finalized payload production produces, for fixtures that need a card
    /// whose resident bytes and advertised address genuinely agree.
    static func preparedMedia(of image: NSImage) async throws -> PreparedMedia {
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        return try #require(await ClipboardStore.defaultImageEncoder(cgImage, nil))
    }

    static func textItem(_ text: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .text,
            title: text,
            preview: text,
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(),
            isPinned: false,
            pinboardName: nil,
            textValue: text,
            fileURLs: [],
            imageData: nil
        )
    }
}