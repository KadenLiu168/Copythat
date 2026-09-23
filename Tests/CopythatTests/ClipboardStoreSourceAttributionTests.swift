@testable import Copythat
import AppKit
import Foundation
import Testing

@MainActor
struct ClipboardStoreSourceAttributionTests {
    @Test func capturedItemUsesInjectedPersistence() {
        let orderedSources = OrderedFrontmostSources([
            source(named: "Source A"),
            source(named: "Confirmation B")
        ])
        let clock = MutableClock()
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        var persistedItems: [ClipboardItem] = []
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults()),
            sourceTracker: CopySourceTracker(frontmostSourceProvider: orderedSources.next),
            initialItems: [],
            pasteboard: pasteboard,
            persistItems: { persistedItems = $0 },
            uptimeProvider: { clock.now }
        )

        pasteboard.clearContents()
        pasteboard.setString("copied text", forType: .string)
        store.pollPasteboard()
        clock.advance(by: 1.0)
        store.pollPasteboard()

        #expect(persistedItems.count == 1)
        #expect(persistedItems.first?.textValue == "copied text")
    }

    @Test func firstObservationAndResolutionEmitCorrelatedDiagnostics() {
        let defaults = diagnosticsDefaults()
        var events: [ClipboardDiagnostics.SourceTimingEvent] = []
        let diagnostics = ClipboardDiagnostics(defaults: defaults, eventSink: { events.append($0) })
        let clock = MutableClock()
        let orderedSources = OrderedFrontmostSources([
            source(named: "Source A"),
            source(named: "Confirmation B")
        ])
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let tracker = CopySourceTracker(
            frontmostSourceProvider: orderedSources.next,
            diagnostics: diagnostics
        )
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults()),
            sourceTracker: tracker,
            initialItems: [],
            pasteboard: pasteboard,
            diagnostics: diagnostics,
            persistItems: { _ in },
            uptimeProvider: { clock.now }
        )

        pasteboard.clearContents()
        pasteboard.setString("copied text", forType: .string)
        let capturedChangeCount = pasteboard.changeCount
        store.pollPasteboard()
        clock.advance(by: 1.0)
        store.pollPasteboard()

        #expect(events.map(\.event) == [.pasteboardObserved, .sourceResolved])
        #expect(events.map(\.changeCount) == [capturedChangeCount, capturedChangeCount])
        #expect(events[0].sourceApp == "Source A")
        #expect(events[1].sourceApp == "Source A")
        #expect(events[1].resolutionSlot == "firstObservedForeground")
        #expect(events[0].uptime <= events[1].uptime)
    }

    @Test func firstObservedSourceBeatsConfirmationSource() {
        let orderedSources = OrderedFrontmostSources([
            source(named: "Source A"),
            source(named: "Confirmation B")
        ])
        let (store, pasteboard, clock) = makeStore(orderedSources: orderedSources)

        pasteboard.clearContents()
        pasteboard.setString("copied text", forType: .string)
        store.pollPasteboard()
        clock.advance(by: 1.0)
        store.pollPasteboard()

        #expect(store.items.first?.sourceApp == "Source A")
    }

    @Test func nilFirstObservedSourceFallsBackToConfirmationSource() {
        let orderedSources = OrderedFrontmostSources([
            nil,
            source(named: "Confirmation B")
        ])
        let (store, pasteboard, clock) = makeStore(orderedSources: orderedSources)

        pasteboard.clearContents()
        pasteboard.setString("copied text", forType: .string)
        store.pollPasteboard()
        clock.advance(by: 1.0)
        store.pollPasteboard()

        #expect(store.items.first?.sourceApp == "Confirmation B")
    }

    @Test func newerChangeCountReplacesPendingSourceTogetherWithCount() {
        let orderedSources = OrderedFrontmostSources([
            source(named: "Source A"),
            source(named: "Source B"),
            source(named: "Confirmation C")
        ])
        let (store, pasteboard, clock) = makeStore(orderedSources: orderedSources)

        pasteboard.clearContents()
        pasteboard.setString("transient text", forType: .string)
        store.pollPasteboard()

        pasteboard.clearContents()
        pasteboard.setString("final text", forType: .string)
        store.pollPasteboard()
        clock.advance(by: 1.0)
        store.pollPasteboard()

        #expect(store.items.first?.textValue == "final text")
        #expect(store.items.first?.sourceApp == "Source B")
    }

    @Test func processedPasteboardClearsPendingSourceBeforeLaterCapture() {
        let orderedSources = OrderedFrontmostSources([
            source(named: "Stale A"),
            source(named: "Later B"),
            source(named: "Confirmation C")
        ])
        let (store, pasteboard, clock) = makeStore(orderedSources: orderedSources)

        pasteboard.clearContents()
        pasteboard.setString("pending external text", forType: .string)
        store.pollPasteboard()

        #expect(store.writeToPasteboard(item(text: "restored text")))

        pasteboard.clearContents()
        pasteboard.setString("later external text", forType: .string)
        store.pollPasteboard()
        clock.advance(by: 1.0)
        store.pollPasteboard()

        #expect(store.items.first?.textValue == "later external text")
        #expect(store.items.first?.sourceApp == "Later B")
    }

    @Test func copyThenSwitchWithinOnePollIntervalKeepsCopySource() {
        let frontmostAfterSwitch = source(named: "App B")
        let orderedSources = OrderedFrontmostSources([
            frontmostAfterSwitch,
            frontmostAfterSwitch
        ])
        let clock = MutableClock()
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let tracker = CopySourceTracker(frontmostSourceProvider: orderedSources.next)
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults()),
            sourceTracker: tracker,
            initialItems: [],
            pasteboard: pasteboard,
            persistItems: { _ in },
            uptimeProvider: { clock.now }
        )

        tracker.recordActivatedSource(source(named: "App A"), currentChangeCount: pasteboard.changeCount)
        pasteboard.clearContents()
        pasteboard.setString("copied text", forType: .string)
        tracker.recordActivatedSource(frontmostAfterSwitch, currentChangeCount: pasteboard.changeCount)

        store.pollPasteboard()
        clock.advance(by: 1.0)
        store.pollPasteboard()

        #expect(store.items.first?.textValue == "copied text")
        #expect(store.items.first?.sourceApp == "App A")
    }

    @Test func pendingObservationUptimeIsReplacedTogetherWithCountAndSource() {
        let orderedSources = OrderedFrontmostSources([
            source(named: "Source A"),
            source(named: "Source B"),
            source(named: "Confirmation C")
        ])
        let (store, pasteboard, clock) = makeStore(orderedSources: orderedSources)

        pasteboard.clearContents()
        pasteboard.setString("transient text", forType: .string)
        store.pollPasteboard()

        clock.advance(by: 0.05)
        pasteboard.clearContents()
        pasteboard.setString("final text", forType: .string)
        store.pollPasteboard()

        clock.advance(by: 0.05)
        store.pollPasteboard()
        #expect(store.items.isEmpty, "the replacement count must restart its own quiet time")

        clock.advance(by: 1.0)
        store.pollPasteboard()

        #expect(store.items.first?.textValue == "final text")
        #expect(store.items.first?.sourceApp == "Source B")
    }

    private func makeStore(orderedSources: OrderedFrontmostSources) -> (ClipboardStore, NSPasteboard, MutableClock) {
        let clock = MutableClock()
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let tracker = CopySourceTracker(frontmostSourceProvider: orderedSources.next)
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults()),
            sourceTracker: tracker,
            initialItems: [],
            pasteboard: pasteboard,
            persistItems: { _ in },
            uptimeProvider: { clock.now }
        )
        return (store, pasteboard, clock)
    }

    private func source(named name: String) -> ClipboardSource {
        ClipboardSource(appName: name, iconData: nil, capturedAt: Date())
    }

    private func diagnosticsDefaults() -> UserDefaults {
        let suiteName = "ClipboardStoreSourceAttributionTests.diagnostics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: ClipboardDiagnostics.defaultsKey)
        return defaults
    }

    private func item(text: String) -> ClipboardItem {
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

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "ClipboardStoreSourceAttributionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class OrderedFrontmostSources {
    private var sources: [ClipboardSource?]

    init(_ sources: [ClipboardSource?]) {
        self.sources = sources
    }

    func next() -> ClipboardSource? {
        guard !sources.isEmpty else { return nil }
        return sources.removeFirst()
    }
}
