import CryptoKit
import Foundation
import OSLog

struct ClipboardDiagnostics {
    static let defaultsKey = "clipboardDiagnosticsEnabled"
    static let category = "ClipboardDiagnostics"

    private let defaults: UserDefaults
    private let logger: Logger
    private let eventSink: ((SourceTimingEvent) -> Void)?

    init(
        defaults: UserDefaults = .standard,
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "local.copythat.clipboard",
            category: ClipboardDiagnostics.category
        ),
        eventSink: ((SourceTimingEvent) -> Void)? = nil
    ) {
        self.defaults = defaults
        self.logger = logger
        self.eventSink = eventSink
    }

    var isEnabled: Bool {
        defaults.bool(forKey: Self.defaultsKey)
    }

    func contentSummary(for item: ClipboardItem) -> ContentSummary {
        Self.contentSummary(for: item)
    }

    static func contentSummary(for item: ClipboardItem) -> ContentSummary {
        let digest = SHA256.hash(data: Data(item.contentKey.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()

        return ContentSummary(
            kind: item.kind.rawValue,
            contentLength: contentLength(for: item),
            contentKeyDigest: digest
        )
    }

    static func duplicateMetadata(for item: ClipboardItem, in items: [ClipboardItem]) -> DuplicateMetadata {
        let matches = items.filter { $0.contentKey == item.contentKey }
        return DuplicateMetadata(
            count: matches.count,
            itemIDs: matches.map(\.id),
            pinnedCount: matches.filter(\.isPinned).count
        )
    }

    func logCapture(
        kind: ClipboardKind,
        source: ClipboardSource,
        currentChangeCount: Int,
        changeCountDelta: Int
    ) {
        guard isEnabled else { return }
        logger.info(
            "capture kind=\(kind.rawValue, privacy: .public) source=\(source.appName, privacy: .public) currentChangeCount=\(currentChangeCount, privacy: .public) changeCountDelta=\(changeCountDelta, privacy: .public)"
        )
    }

    func logPasteboardObserved(
        changeCount: Int,
        source: ClipboardSource?,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        emit(SourceTimingEvent(
            event: .pasteboardObserved,
            uptime: uptime,
            changeCount: changeCount,
            sourceApp: source?.appName ?? "none"
        ))
    }

    func logAppActivated(
        source: ClipboardSource,
        currentChangeCount: Int,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        emit(SourceTimingEvent(
            event: .appActivated,
            uptime: uptime,
            changeCount: currentChangeCount,
            sourceApp: source.appName
        ))
    }

    func logCopyShortcutObserved(
        operation: ShortcutOperation,
        source: ClipboardSource,
        baselineChangeCount: Int,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        emit(SourceTimingEvent(
            event: .copyShortcutObserved,
            uptime: uptime,
            changeCount: baselineChangeCount,
            sourceApp: source.appName,
            operation: operation.rawValue
        ))
    }

    func logSourceResolved(
        slot: CopySourceResolutionSlot,
        source: ClipboardSource,
        currentChangeCount: Int?,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        emit(SourceTimingEvent(
            event: .sourceResolved,
            uptime: uptime,
            changeCount: currentChangeCount,
            sourceApp: source.appName,
            resolutionSlot: slot.rawValue
        ))
    }

    func logInsertion(
        item: ClipboardItem,
        beforeCount: Int,
        afterCount: Int,
        duplicateMetadata: DuplicateMetadata
    ) {
        guard isEnabled else { return }
        let summary = contentSummary(for: item)
        logger.info(
            "insert itemID=\(item.id.uuidString, privacy: .public) kind=\(summary.kind, privacy: .public) source=\(item.sourceApp, privacy: .public) contentLength=\(summary.contentLength, privacy: .public) contentKeyDigest=\(summary.contentKeyDigest, privacy: .public) duplicateCount=\(duplicateMetadata.count, privacy: .public) duplicatePinnedCount=\(duplicateMetadata.pinnedCount, privacy: .public) duplicateIDs=\(duplicateMetadata.itemIDList, privacy: .public) beforeCount=\(beforeCount, privacy: .public) afterCount=\(afterCount, privacy: .public)"
        )
    }

    private func emit(_ event: SourceTimingEvent) {
        guard isEnabled else { return }
        if let eventSink {
            eventSink(event)
            return
        }
        guard let message = try? event.jsonLine() else { return }
        logger.info("source_timing \(message, privacy: .public)")
    }

    private static func contentLength(for item: ClipboardItem) -> Int {
        switch item.kind {
        case .text, .url:
            (item.textValue ?? item.preview).count
        case .file:
            item.fileURLs.count
        case .image:
            item.imageData?.count ?? 0
        }
    }
}

extension ClipboardDiagnostics {
    enum ShortcutOperation: String {
        case copy
        case cut
    }

    struct SourceTimingEvent: Codable, Equatable {
        enum Event: String, Codable {
            case pasteboardObserved = "pasteboard_observed"
            case appActivated = "app_activated"
            case copyShortcutObserved = "copy_shortcut_observed"
            case sourceResolved = "source_resolved"
        }

        let event: Event
        let uptime: TimeInterval
        let changeCount: Int?
        let sourceApp: String
        let operation: String?
        let resolutionSlot: String?

        init(
            event: Event,
            uptime: TimeInterval,
            changeCount: Int?,
            sourceApp: String,
            operation: String? = nil,
            resolutionSlot: String? = nil
        ) {
            self.event = event
            self.uptime = uptime
            self.changeCount = changeCount
            self.sourceApp = sourceApp
            self.operation = operation
            self.resolutionSlot = resolutionSlot
        }

        func jsonLine() throws -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return String(decoding: try encoder.encode(self), as: UTF8.self)
        }
    }

    struct ContentSummary: Equatable {
        let kind: String
        let contentLength: Int
        let contentKeyDigest: String
    }

    struct DuplicateMetadata: Equatable {
        let count: Int
        let itemIDs: [UUID]
        let pinnedCount: Int

        var itemIDList: String {
            itemIDs.map(\.uuidString).joined(separator: ",")
        }
    }
}
