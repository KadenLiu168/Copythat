@testable import Copythat
import Foundation
import Testing

struct ClipboardDiagnosticsTests {
    @Test func diagnosticsAreDisabledByDefault() {
        let suiteName = "ClipboardDiagnosticsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let diagnostics = ClipboardDiagnostics(defaults: defaults)

        #expect(!diagnostics.isEnabled)
    }

    @Test func contentSummaryDoesNotExposeRawTextPayload() {
        let payload = "secret launch token from chat"
        let item = textItem(text: payload, sourceApp: "ChatGPT")

        let summary = ClipboardDiagnostics.contentSummary(for: item)

        #expect(summary.kind == ClipboardKind.text.rawValue)
        #expect(summary.contentLength == payload.count)
        #expect(summary.contentKeyDigest.count == 16)
        #expect(summary.contentKeyDigest != payload)
        #expect(!summary.contentKeyDigest.contains("secret"))
        #expect(!summary.contentKeyDigest.contains("chat"))
    }

    @Test func contentSummaryDoesNotExposeRawURLOrFilePathPayloads() {
        let url = "https://example.com/private/path?token=secret"
        let urlSummary = ClipboardDiagnostics.contentSummary(for: urlItem(url))
        let fileURL = URL(fileURLWithPath: "/Users/kaden/private/secret.txt")
        let fileSummary = ClipboardDiagnostics.contentSummary(for: fileItem(fileURL))

        #expect(urlSummary.contentLength == url.count)
        #expect(!urlSummary.contentKeyDigest.contains("example"))
        #expect(!urlSummary.contentKeyDigest.contains("secret"))
        #expect(fileSummary.contentLength == 1)
        #expect(!fileSummary.contentKeyDigest.contains("Users"))
        #expect(!fileSummary.contentKeyDigest.contains("secret"))
    }

    @Test func duplicateMetadataReportsMatchingItemsAndPinnedStatus() {
        let duplicateID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let pinnedDuplicateID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let differentID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let pending = textItem(text: "same", sourceApp: "ChatGPT")
        let duplicate = textItem(id: duplicateID, text: "same", sourceApp: "Doubao")
        let pinnedDuplicate = textItem(id: pinnedDuplicateID, text: "same", sourceApp: "Safari", isPinned: true)
        let different = textItem(id: differentID, text: "different", sourceApp: "ChatGPT")

        let metadata = ClipboardDiagnostics.duplicateMetadata(
            for: pending,
            in: [duplicate, pinnedDuplicate, different]
        )

        #expect(metadata.count == 2)
        #expect(metadata.itemIDs == [duplicateID, pinnedDuplicateID])
        #expect(metadata.pinnedCount == 1)
        #expect(metadata.itemIDList.contains(duplicateID.uuidString))
        #expect(metadata.itemIDList.contains(pinnedDuplicateID.uuidString))
        #expect(!metadata.itemIDList.contains(differentID.uuidString))
    }

    @Test func sourceTimingEventsExposeAuditableMetadata() {
        let defaults = enabledDefaults()
        var events: [ClipboardDiagnostics.SourceTimingEvent] = []
        let diagnostics = ClipboardDiagnostics(defaults: defaults, eventSink: { events.append($0) })
        let firstSource = source(named: "Google Chrome", capturedAt: 10)
        let activatedSource = source(named: "Code", capturedAt: 10.2)

        diagnostics.logPasteboardObserved(
            changeCount: 41,
            source: firstSource,
            uptime: 10
        )
        diagnostics.logAppActivated(
            source: activatedSource,
            currentChangeCount: 41,
            uptime: 10.2
        )
        diagnostics.logCopyShortcutObserved(
            operation: .copy,
            source: firstSource,
            baselineChangeCount: 41,
            uptime: 10.3
        )
        diagnostics.logSourceResolved(
            slot: .firstObservedForeground,
            source: firstSource,
            currentChangeCount: 41,
            uptime: 10.45
        )

        #expect(events == [
            .init(
                event: .pasteboardObserved,
                uptime: 10,
                changeCount: 41,
                sourceApp: "Google Chrome"
            ),
            .init(
                event: .appActivated,
                uptime: 10.2,
                changeCount: 41,
                sourceApp: "Code"
            ),
            .init(
                event: .copyShortcutObserved,
                uptime: 10.3,
                changeCount: 41,
                sourceApp: "Google Chrome",
                operation: "copy"
            ),
            .init(
                event: .sourceResolved,
                uptime: 10.45,
                changeCount: 41,
                sourceApp: "Google Chrome",
                resolutionSlot: "firstObservedForeground"
            )
        ])
    }

    @Test func disabledDiagnosticsEmitNoSourceTimingEvents() {
        let suiteName = "ClipboardDiagnosticsTests.disabled.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        var events: [ClipboardDiagnostics.SourceTimingEvent] = []
        let diagnostics = ClipboardDiagnostics(defaults: defaults, eventSink: { events.append($0) })
        let source = source(named: "Google Chrome", capturedAt: 10)

        diagnostics.logPasteboardObserved(changeCount: 41, source: source, uptime: 10)
        diagnostics.logAppActivated(source: source, currentChangeCount: 41, uptime: 10.1)
        diagnostics.logCopyShortcutObserved(
            operation: .copy,
            source: source,
            baselineChangeCount: 41,
            uptime: 10.2
        )
        diagnostics.logSourceResolved(
            slot: .shortcut,
            source: source,
            currentChangeCount: 42,
            uptime: 10.3
        )

        #expect(events.isEmpty)
    }

    @Test func sourceTimingEventSerializationContainsNoClipboardPayload() throws {
        let event = ClipboardDiagnostics.SourceTimingEvent(
            event: .sourceResolved,
            uptime: 12.5,
            changeCount: 99,
            sourceApp: "Google Chrome",
            resolutionSlot: "shortcut"
        )
        let serialized = try event.jsonLine()

        #expect(serialized.contains("source_resolved"))
        #expect(serialized.contains("Google Chrome"))
        #expect(serialized.contains("12.5"))
        #expect(!serialized.contains("secret-marker-123"))
        #expect(!serialized.contains("https://example.com/private"))
        #expect(!serialized.contains("/Users/kaden/private.txt"))
    }

    private func textItem(
        id: UUID = UUID(),
        text: String,
        sourceApp: String,
        isPinned: Bool = false
    ) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: .text,
            title: text,
            preview: text,
            sourceApp: sourceApp,
            sourceAppIconData: nil,
            createdAt: Date(),
            isPinned: isPinned,
            pinboardName: nil,
            textValue: text,
            fileURLs: [],
            imageData: nil
        )
    }

    private func enabledDefaults() -> UserDefaults {
        let suiteName = "ClipboardDiagnosticsTests.enabled.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: ClipboardDiagnostics.defaultsKey)
        return defaults
    }

    private func source(named name: String, capturedAt: TimeInterval) -> ClipboardSource {
        ClipboardSource(
            appName: name,
            iconData: nil,
            capturedAt: Date(timeIntervalSince1970: capturedAt)
        )
    }

    private func urlItem(_ url: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .url,
            title: "example.com",
            preview: url,
            sourceApp: "Safari",
            sourceAppIconData: nil,
            createdAt: Date(),
            isPinned: false,
            pinboardName: nil,
            textValue: url,
            fileURLs: [],
            imageData: nil
        )
    }

    private func fileItem(_ url: URL) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .file,
            title: url.lastPathComponent,
            preview: url.path,
            sourceApp: "Finder",
            sourceAppIconData: nil,
            createdAt: Date(),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [url],
            imageData: nil
        )
    }
}
