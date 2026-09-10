import AppKit
import Carbon
import CoreGraphics
import Foundation

struct ClipboardSource {
    let appName: String
    let iconData: Data?
    let capturedAt: Date
    let pasteboardChangeCount: Int?

    init(appName: String, iconData: Data?, capturedAt: Date, pasteboardChangeCount: Int? = nil) {
        self.appName = appName
        self.iconData = iconData
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

final class CopySourceTracker {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activationObserver: NSObjectProtocol?
    private var pendingShortcutSources: [ClipboardSource] = []
    private var recentExternalSource: ClipboardSource?
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
        guard let tap = CGEvent.tapCreate(
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
        ) else {
            return
        }

        eventTap = tap
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

    private func handle(type: CGEventType, event: CGEvent) {
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
            return
        }

        guard isCopyOrCutShortcut(keyCode: keyCode, flags: flags),
              let source = currentFrontmostSource(
                capturedAt: Date(),
                pasteboardChangeCount: pasteboardChangeCount
              ) else {
            return
        }
        recordShortcutSource(
            source,
            operation: keyCode == kVK_ANSI_C ? .copy : .cut
        )
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

    func frontmostSourceSnapshot() -> ClipboardSource? {
        currentFrontmostSource(capturedAt: Date())
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

        let iconData: Data?
        if let bundlePath = app.bundleURL?.path {
            iconData = NSWorkspace.shared.icon(forFile: bundlePath).pngData(maxPixel: 160)
        } else {
            iconData = app.icon?.pngData(maxPixel: 160)
        }

        return ClipboardSource(
            appName: name,
            iconData: iconData,
            capturedAt: capturedAt,
            pasteboardChangeCount: pasteboardChangeCount
        )
    }
}
