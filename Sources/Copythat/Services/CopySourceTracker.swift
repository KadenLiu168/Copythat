import AppKit
import Carbon
import CoreGraphics
import Foundation

struct ClipboardSource {
    let appName: String
    let iconData: Data?
    /// Content address of the icon bytes, established once when the icon is
    /// encoded and forwarded with it afterwards.
    let iconBlobID: String?
    let capturedAt: Date
    let pasteboardChangeCount: Int?

    init(
        appName: String,
        iconData: Data?,
        iconBlobID: String? = nil,
        capturedAt: Date,
        pasteboardChangeCount: Int? = nil
    ) {
        self.appName = appName
        self.iconData = iconData
        self.iconBlobID = iconData.map { iconBlobID ?? PreparedMedia(hashing: $0).id } ?? iconBlobID
        self.capturedAt = capturedAt
        self.pasteboardChangeCount = pasteboardChangeCount
    }

    static func unknown() -> ClipboardSource {
        ClipboardSource(appName: "Unknown", iconData: nil, capturedAt: Date())
    }

    static func system(pasteboardChangeCount: Int? = nil) -> ClipboardSource {
        ClipboardSource(
            appName: "System",
            iconData: NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)?.pngData(maxPixel: 64),
            capturedAt: Date(),
            pasteboardChangeCount: pasteboardChangeCount
        )
    }
}

private extension ClipboardSource {
    var snapshot: CopySourceSnapshot {
        CopySourceSnapshot(
            appName: appName,
            capturedAt: capturedAt,
            pasteboardChangeCount: pasteboardChangeCount
        )
    }
}

/// Identity of one running application process generation. A process
/// identifier alone can be reused by a later launch, so the captured launch
/// date distinguishes generations and the bundle location distinguishes
/// installations; a display name is never part of this identity.
struct SourceAppIconCacheKey: Hashable {
    let processIdentifier: pid_t
    let launchDate: Date
    let bundleURL: URL?

    /// Missing process-generation metadata yields no key, so that observation
    /// stays uncached instead of risking a collision with a later process.
    init?(processIdentifier: pid_t, launchDate: Date?, bundleURL: URL?) {
        guard processIdentifier > 0, let launchDate else { return nil }
        self.processIdentifier = processIdentifier
        self.launchDate = launchDate
        self.bundleURL = bundleURL
    }
}

/// Session-only cache of successfully prepared source icons, bounded to
/// `capacity` entries with least-recently-used eviction. A hit refreshes the
/// entry's recency and returns the retained value without running the loader; a
/// miss runs the loader at most once and retains only a successful result.
struct SourceAppIconCache {
    let capacity: Int
    private var entries: [SourceAppIconCacheKey: PreparedMedia] = [:]
    private var recency: [SourceAppIconCacheKey] = []

    init(capacity: Int = 32) {
        precondition(capacity > 0, "a source icon cache needs a positive capacity")
        self.capacity = capacity
    }

    var count: Int { entries.count }

    mutating func prepared(
        forKey key: SourceAppIconCacheKey,
        prepare: () -> PreparedMedia?
    ) -> PreparedMedia? {
        if let retained = entries[key] {
            markMostRecent(key)
            return retained
        }

        guard let prepared = prepare() else { return nil }
        entries[key] = prepared
        markMostRecent(key)
        if entries.count > capacity, let leastRecent = recency.first {
            recency.removeFirst()
            entries[leastRecent] = nil
        }
        return prepared
    }

    /// Recency holds at most one occurrence per key, so eviction always sees
    /// the true least recently used entry.
    private mutating func markMostRecent(_ key: SourceAppIconCacheKey) {
        if let index = recency.firstIndex(of: key) {
            recency.remove(at: index)
        }
        recency.append(key)
    }
}

final class CopySourceTracker {
    // Narrow copy-intent wake signal; wired by AppModel to the clipboard store.
    var onCopyIntentWake: (() -> Void)?

    // Verification-only seam (D3/D4): when set, its result replaces the real
    // CGEvent.tapCreate call. Production code leaves it nil; only the live
    // verification driver injects a failure to exercise the idle fallback.
    var eventTapFactory: (() -> CFMachPort?)?

    // Metadata-only observation (D3): whether the copy-intent event tap was
    // created successfully. Never drives capture; observation only.
    private(set) var isEventTapActive = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activationObserver: NSObjectProtocol?
    private var pendingShortcutSources: [ClipboardSource] = []
    private var recentExternalSource: ClipboardSource?
    private var lastActivation: (source: ClipboardSource, pasteboardChangeCount: Int)?
    private var frontmostBeforeLastActivation: ClipboardSource?
    private var sourceIconCache = SourceAppIconCache()
    private let frontmostSourceProvider: (() -> ClipboardSource?)?
    private let diagnostics: ClipboardDiagnostics

    init(
        frontmostSourceProvider: (() -> ClipboardSource?)? = nil,
        diagnostics: ClipboardDiagnostics = ClipboardDiagnostics()
    ) {
        self.frontmostSourceProvider = frontmostSourceProvider
        self.diagnostics = diagnostics
    }

    func start() {
        observeExternalAppActivations()
        updateRecentExternalSource(from: NSWorkspace.shared.frontmostApplication, capturedAt: Date())

        guard eventTap == nil else { return }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let tap: CFMachPort?
        if let eventTapFactory {
            tap = eventTapFactory()
        } else {
            tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else {
                        return Unmanaged.passUnretained(event)
                    }
                    let tracker = Unmanaged<CopySourceTracker>.fromOpaque(userInfo).takeUnretainedValue()
                    tracker.handle(type: type, event: event)
                    return Unmanaged.passUnretained(event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        }
        guard let tap else {
            isEventTapActive = false
            return
        }

        eventTap = tap
        isEventTapActive = true
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func resolveSource(
        isSystemGeneratedContent: Bool = false,
        firstObservedSource: ClipboardSource? = nil,
        pasteboardChangeCountDelta: Int = 1,
        currentPasteboardChangeCount: Int? = nil,
        now: Date = Date(),
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> ClipboardSource {
        let shortcutSource = consumeRecentShortcutSource(
            pasteboardChangeCountDelta: pasteboardChangeCountDelta,
            currentPasteboardChangeCount: currentPasteboardChangeCount,
            now: now
        )
        let currentForegroundSource = currentFrontmostSource(capturedAt: now)
        if let currentForegroundSource {
            recentExternalSource = currentForegroundSource
        }

        let slot = CopySourceResolution.resolveSlot(
            shortcut: shortcutSource?.snapshot,
            firstObservedForeground: firstObservedSource?.snapshot,
            currentForeground: currentForegroundSource?.snapshot,
            recentForeground: recentExternalSource?.snapshot,
            isSystemGeneratedContent: isSystemGeneratedContent,
            now: now
        )

        let resolvedSource: ClipboardSource
        switch slot {
        case .shortcut:
            resolvedSource = shortcutSource ?? .unknown()
        case .firstObservedForeground:
            resolvedSource = firstObservedSource ?? .unknown()
        case .currentForeground:
            resolvedSource = currentForegroundSource ?? .unknown()
        case .recentForeground:
            resolvedSource = recentExternalSource ?? .unknown()
        case .system:
            resolvedSource = .system()
        case .unknown:
            resolvedSource = .unknown()
        }
        diagnostics.logSourceResolved(
            slot: slot,
            source: resolvedSource,
            currentChangeCount: currentPasteboardChangeCount,
            uptime: uptime
        )
        return resolvedSource
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CFRunLoopRunInMode(.defaultMode, 0, true)
    }

    func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }
        guard type == .keyDown else { return }

        let flags = event.flags
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let pasteboardChangeCount = NSPasteboard.general.changeCount

        if isScreenshotToClipboardShortcut(keyCode: keyCode, flags: flags) {
            appendPendingShortcutSource(.system(pasteboardChangeCount: pasteboardChangeCount))
            deliverCopyIntentWake()
            return
        }

        guard isCopyOrCutShortcut(keyCode: keyCode, flags: flags) else { return }
        let operation: ClipboardDiagnostics.ShortcutOperation = keyCode == kVK_ANSI_C ? .copy : .cut
        // D2: queue available shortcut evidence before the wake so immediate polling
        // cannot resolve ahead of its source evidence; a missing source still wakes.
        if let source = currentFrontmostSource(
            capturedAt: Date(),
            pasteboardChangeCount: pasteboardChangeCount
        ) {
            recordShortcutSource(source, operation: operation)
        }
        deliverCopyIntentWake()
    }

    private func deliverCopyIntentWake() {
        onCopyIntentWake?()
    }

    private func isCopyOrCutShortcut(keyCode: Int, flags: CGEventFlags) -> Bool {
        guard flags.contains(.maskCommand), !flags.contains(.maskControl) else {
            return false
        }
        return keyCode == kVK_ANSI_C || keyCode == kVK_ANSI_X
    }

    private func isScreenshotToClipboardShortcut(keyCode: Int, flags: CGEventFlags) -> Bool {
        guard flags.contains(.maskCommand),
              flags.contains(.maskControl),
              flags.contains(.maskShift) else {
            return false
        }
        return keyCode == kVK_ANSI_3 || keyCode == kVK_ANSI_4 || keyCode == kVK_ANSI_5
    }

    func frontmostSourceSnapshot(pasteboardChangeCount observedChangeCount: Int? = nil) -> ClipboardSource? {
        let current = currentFrontmostSource(
            capturedAt: Date(),
            pasteboardChangeCount: observedChangeCount
        )
        guard let current,
              let observedChangeCount,
              let lastActivation,
              lastActivation.source.appName == current.appName,
              lastActivation.pasteboardChangeCount >= observedChangeCount,
              let previous = frontmostBeforeLastActivation,
              previous.appName != current.appName else {
            return current
        }
        return ClipboardSource(
            appName: previous.appName,
            iconData: previous.iconData,
            iconBlobID: previous.iconBlobID,
            capturedAt: Date(),
            pasteboardChangeCount: observedChangeCount
        )
    }

    private func currentFrontmostSource(capturedAt: Date, pasteboardChangeCount: Int? = nil) -> ClipboardSource? {
        if let frontmostSourceProvider {
            return frontmostSourceProvider()
        }

        guard let app = NSWorkspace.shared.frontmostApplication,
              let source = source(
                for: app,
                capturedAt: capturedAt,
                pasteboardChangeCount: pasteboardChangeCount
              ) else {
            return nil
        }

        return source
    }

    private static func isSourceCandidate(_ app: NSRunningApplication) -> Bool {
        CopySourceResolution.isSourceCandidate(
            processIdentifier: app.processIdentifier,
            currentProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
            bundleIdentifier: app.bundleIdentifier,
            localizedName: app.localizedName,
            copythatBundleIdentifier: Bundle.main.bundleIdentifier
        )
    }

    private func appendPendingShortcutSource(_ source: ClipboardSource) {
        pendingShortcutSources.append(source)
        if pendingShortcutSources.count > 8 {
            pendingShortcutSources.removeFirst(pendingShortcutSources.count - 8)
        }
    }

    private func consumeRecentShortcutSource(
        pasteboardChangeCountDelta: Int,
        currentPasteboardChangeCount: Int?,
        now: Date
    ) -> ClipboardSource? {
        pendingShortcutSources.removeAll {
            now.timeIntervalSince($0.capturedAt) > CopySourceResolution.shortcutMaxAge
        }

        let snapshots = pendingShortcutSources.map(\.snapshot)
        guard let index = CopySourceResolution.pendingShortcutIndex(
            snapshots: snapshots,
            pasteboardChangeCountDelta: pasteboardChangeCountDelta,
            currentPasteboardChangeCount: currentPasteboardChangeCount,
            now: now
        ) else {
            return nil
        }

        let source = pendingShortcutSources[index]
        pendingShortcutSources.removeSubrange(...index)
        return source
    }

    private func observeExternalAppActivations() {
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            self?.updateRecentExternalSource(from: app, capturedAt: Date(), logActivation: true)
        }
    }

    private func updateRecentExternalSource(
        from app: NSRunningApplication?,
        capturedAt: Date,
        logActivation: Bool = false
    ) {
        guard let app,
              let source = source(for: app, capturedAt: capturedAt) else {
            return
        }

        if logActivation {
            recordActivatedSource(
                source,
                currentChangeCount: NSPasteboard.general.changeCount
            )
        } else {
            recentExternalSource = source
        }
    }

    func recordActivatedSource(
        _ source: ClipboardSource,
        currentChangeCount: Int,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        if let recentExternalSource, recentExternalSource.appName != source.appName {
            frontmostBeforeLastActivation = recentExternalSource
        }
        lastActivation = (source, currentChangeCount)
        recentExternalSource = source
        diagnostics.logAppActivated(
            source: source,
            currentChangeCount: currentChangeCount,
            uptime: uptime
        )
    }

    func recordShortcutSource(
        _ source: ClipboardSource,
        operation: ClipboardDiagnostics.ShortcutOperation,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        appendPendingShortcutSource(source)
        recentExternalSource = source
        diagnostics.logCopyShortcutObserved(
            operation: operation,
            source: source,
            baselineChangeCount: source.pasteboardChangeCount ?? NSPasteboard.general.changeCount,
            uptime: uptime
        )
    }

    private func source(
        for app: NSRunningApplication,
        capturedAt: Date,
        pasteboardChangeCount: Int? = nil
    ) -> ClipboardSource? {
        guard Self.isSourceCandidate(app),
              let name = app.localizedName else {
            return nil
        }

        return makeSource(
            appName: name,
            cacheKey: SourceAppIconCacheKey(
                processIdentifier: app.processIdentifier,
                launchDate: app.launchDate,
                bundleURL: app.bundleURL
            ),
            capturedAt: capturedAt,
            pasteboardChangeCount: pasteboardChangeCount,
            prepareIcon: { Self.preparedIcon(for: app) }
        )
    }

    /// Assembles one source observation from validated application metadata.
    /// The icon is prepared lazily, at most once per uncached observation, and
    /// a retained prepared value contributes both its bytes and its established
    /// content address, so a hit hashes nothing. An unreliable process
    /// generation prepares normally without touching the cache.
    func makeSource(
        appName: String,
        cacheKey: SourceAppIconCacheKey?,
        capturedAt: Date,
        pasteboardChangeCount: Int? = nil,
        prepareIcon: () -> PreparedMedia?
    ) -> ClipboardSource {
        let prepared: PreparedMedia?
        if let cacheKey {
            prepared = sourceIconCache.prepared(forKey: cacheKey, prepare: prepareIcon)
        } else {
            prepared = prepareIcon()
        }

        return ClipboardSource(
            appName: appName,
            iconData: prepared?.data,
            iconBlobID: prepared?.id,
            capturedAt: capturedAt,
            pasteboardChangeCount: pasteboardChangeCount
        )
    }

    /// Existing icon selection and bounded PNG preparation: a bundle location
    /// uses the workspace icon, and an unavailable application icon yields no
    /// icon.
    private static func preparedIcon(for app: NSRunningApplication) -> PreparedMedia? {
        let pngData: Data?
        if let bundlePath = app.bundleURL?.path {
            pngData = NSWorkspace.shared.icon(forFile: bundlePath).appIconPNGData(maxPixel: 160)
        } else {
            pngData = app.icon?.appIconPNGData(maxPixel: 160)
        }

        return pngData.map { PreparedMedia(hashing: $0) }
    }
}
