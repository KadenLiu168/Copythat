@testable import Copythat
import AppKit
import Carbon
import CoreGraphics
import Foundation
import Testing

struct CopySourceTrackerTests {
    private let launchDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let bundleURL = URL(fileURLWithPath: "/Applications/Example.app")

    @Test func frontmostSnapshotDoesNotUpdateRecentExternalSource() {
        let source = ClipboardSource(
            appName: "First App",
            iconData: nil,
            capturedAt: Date()
        )
        var sources: [ClipboardSource?] = [source, nil]
        let tracker = CopySourceTracker(frontmostSourceProvider: {
            sources.removeFirst()
        })

        let firstObservedSource = tracker.frontmostSourceSnapshot()
        let resolvedSource = tracker.resolveSource()

        #expect(firstObservedSource?.appName == "First App")
        #expect(resolvedSource.appName == "Unknown")
    }

    @Test func activationShortcutAndResolutionEmitCorrelatedDiagnostics() {
        let suiteName = "CopySourceTrackerTests.diagnostics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: ClipboardDiagnostics.defaultsKey)
        var events: [ClipboardDiagnostics.SourceTimingEvent] = []
        let diagnostics = ClipboardDiagnostics(defaults: defaults, eventSink: { events.append($0) })
        let now = Date(timeIntervalSince1970: 100)
        let activatedSource = source(named: "Code", capturedAt: now, changeCount: 40)
        let shortcutSource = source(named: "Google Chrome", capturedAt: now, changeCount: 40)
        let tracker = CopySourceTracker(
            frontmostSourceProvider: { activatedSource },
            diagnostics: diagnostics
        )

        tracker.recordActivatedSource(activatedSource, currentChangeCount: 40, uptime: 9.9)
        tracker.recordShortcutSource(shortcutSource, operation: .copy, uptime: 10)
        let resolved = tracker.resolveSource(
            currentPasteboardChangeCount: 41,
            now: now.addingTimeInterval(0.5),
            uptime: 10.5
        )

        #expect(resolved.appName == "Google Chrome")
        #expect(events.map(\.event) == [
            .appActivated,
            .copyShortcutObserved,
            .sourceResolved
        ])
        #expect(events.map(\.uptime) == [9.9, 10, 10.5])
        #expect(events[0].sourceApp == "Code")
        #expect(events[1].operation == "copy")
        #expect(events[2].changeCount == 41)
        #expect(events[2].sourceApp == "Google Chrome")
        #expect(events[2].resolutionSlot == "shortcut")
    }

    @Test func snapshotReturnsPreviousFrontmostWhenWritePredatesActivation() {
        let currentFrontmost = ClipboardSource(appName: "App B", iconData: nil, capturedAt: Date())
        let tracker = CopySourceTracker(frontmostSourceProvider: { currentFrontmost })

        tracker.recordActivatedSource(
            ClipboardSource(appName: "App A", iconData: nil, capturedAt: Date()),
            currentChangeCount: 9
        )
        tracker.recordActivatedSource(currentFrontmost, currentChangeCount: 10)

        let snapshot = tracker.frontmostSourceSnapshot(pasteboardChangeCount: 10)

        #expect(snapshot?.appName == "App A")
    }

    @Test func snapshotKeepsCurrentFrontmostWhenWriteFollowsActivation() {
        let currentFrontmost = ClipboardSource(appName: "App B", iconData: nil, capturedAt: Date())
        let tracker = CopySourceTracker(frontmostSourceProvider: { currentFrontmost })

        tracker.recordActivatedSource(
            ClipboardSource(appName: "App A", iconData: nil, capturedAt: Date()),
            currentChangeCount: 9
        )
        tracker.recordActivatedSource(currentFrontmost, currentChangeCount: 9)

        let snapshot = tracker.frontmostSourceSnapshot(pasteboardChangeCount: 10)

        #expect(snapshot?.appName == "App B")
    }

    @Test func recognizedCopyAndCutShortcutsDeliverExactlyOneWake() {
        let tracker = CopySourceTracker(frontmostSourceProvider: { nil })
        var wakes = 0
        tracker.onCopyIntentWake = { wakes += 1 }

        tracker.handle(type: .keyDown, event: keyDown(keyCode: kVK_ANSI_C, flags: .maskCommand))
        tracker.handle(type: .keyDown, event: keyDown(keyCode: kVK_ANSI_X, flags: .maskCommand))

        #expect(wakes == 2, "each supported copy/cut intent must deliver exactly one wake")
    }

    @Test func screenshotShortcutDeliversWakeWithSystemSourceQueued() {
        let tracker = CopySourceTracker(frontmostSourceProvider: { nil })
        var wakes = 0
        tracker.onCopyIntentWake = { wakes += 1 }

        tracker.handle(
            type: .keyDown,
            event: keyDown(keyCode: kVK_ANSI_3, flags: [.maskCommand, .maskControl, .maskShift])
        )

        #expect(wakes == 1)
        let baseline = NSPasteboard.general.changeCount
        let resolved = tracker.resolveSource(currentPasteboardChangeCount: baseline + 1)
        #expect(resolved.appName == "System")
    }

    @Test func unrelatedKeyDownDoesNotWake() {
        let tracker = CopySourceTracker(frontmostSourceProvider: { nil })
        var wakes = 0
        tracker.onCopyIntentWake = { wakes += 1 }

        tracker.handle(type: .keyDown, event: keyDown(keyCode: kVK_ANSI_D, flags: .maskCommand))
        tracker.handle(type: .keyDown, event: keyDown(keyCode: kVK_ANSI_C, flags: [.maskCommand, .maskControl]))
        tracker.handle(type: .flagsChanged, event: keyDown(keyCode: kVK_ANSI_C, flags: .maskCommand))

        #expect(wakes == 0)
    }

    @Test func shortcutEvidenceIsQueuedBeforeWakeDelivery() {
        let chromeSource = ClipboardSource(appName: "Chrome", iconData: nil, capturedAt: Date())
        var sources: [ClipboardSource?] = [chromeSource, nil]
        let tracker = CopySourceTracker(frontmostSourceProvider: { sources.removeFirst() })
        var wakes = 0
        tracker.onCopyIntentWake = { wakes += 1 }

        tracker.handle(type: .keyDown, event: keyDown(keyCode: kVK_ANSI_C, flags: .maskCommand))

        #expect(wakes == 1)
        let baseline = NSPasteboard.general.changeCount
        let resolved = tracker.resolveSource(currentPasteboardChangeCount: baseline + 1)
        #expect(
            resolved.appName == "Chrome",
            "the shortcut source queued during wake handling must resolve after the wake"
        )
    }

    @Test func sharedSourceAssemblyPreparesAndHashesOnceForRepeatedObservations() async {
        let counters = MediaOperationCounters()
        let icon = Data(repeating: 0x5A, count: 64)
        let log = TrackerIconPreparationLog()
        log.provide("Example", payload: icon)
        let tracker = CopySourceTracker(frontmostSourceProvider: { nil })
        let key = generation(501, bundleURL: bundleURL)

        counters.reset()
        let observations = await counters.measure {
            (0..<3).map { index in
                tracker.makeSource(
                    appName: "Example",
                    cacheKey: key,
                    capturedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                    pasteboardChangeCount: index,
                    prepareIcon: { log.prepare("Example") }
                )
            }
        }

        #expect(log.attemptCount(for: "Example") == 1)
        #expect(counters.identityHashCount == 1)
        #expect(observations.allSatisfy { $0.iconData == icon })
        #expect(observations.allSatisfy { $0.iconBlobID == observations[0].iconBlobID })
    }

    @Test func cacheHitsKeepEachObservationsOwnNameTimestampAndChangeCount() async {
        let counters = MediaOperationCounters()
        let icon = Data(repeating: 0x66, count: 48)
        let log = TrackerIconPreparationLog()
        log.provide("Example", payload: icon)
        let tracker = CopySourceTracker(frontmostSourceProvider: { nil })
        let key = generation(511, bundleURL: bundleURL)
        let firstCapturedAt = Date(timeIntervalSince1970: 10)
        let secondCapturedAt = Date(timeIntervalSince1970: 20)

        counters.reset()
        let first = await counters.measure {
            tracker.makeSource(
                appName: "Example",
                cacheKey: key,
                capturedAt: firstCapturedAt,
                pasteboardChangeCount: 7,
                prepareIcon: { log.prepare("Example") }
            )
        }
        let second = await counters.measure {
            tracker.makeSource(
                appName: "Renamed Example",
                cacheKey: key,
                capturedAt: secondCapturedAt,
                pasteboardChangeCount: nil,
                prepareIcon: { log.prepare("Example") }
            )
        }

        #expect(log.attemptCount(for: "Example") == 1)
        #expect(counters.identityHashCount == 1)
        #expect(second.iconData == first.iconData)
        #expect(second.iconBlobID == first.iconBlobID)
        #expect(first.appName == "Example")
        #expect(first.capturedAt == firstCapturedAt)
        #expect(first.pasteboardChangeCount == 7)
        // The name and the observation context come from each call, not from
        // the retained icon.
        #expect(second.appName == "Renamed Example")
        #expect(second.capturedAt == secondCapturedAt)
        #expect(second.pasteboardChangeCount == nil)
    }

    @Test func sameDisplayNameAcrossProcessesKeepsSeparateIcons() async {
        let counters = MediaOperationCounters()
        let firstIcon = Data(repeating: 0x71, count: 40)
        let secondIcon = Data(repeating: 0x72, count: 56)
        let log = TrackerIconPreparationLog()
        log.provide("first", payload: firstIcon)
        log.provide("second", payload: secondIcon)
        let tracker = CopySourceTracker(frontmostSourceProvider: { nil })
        let firstKey = generation(801, bundleURL: bundleURL)
        let secondKey = generation(802, bundleURL: bundleURL)

        counters.reset()
        let (first, second, firstAgain) = await counters.measure {
            (
                tracker.makeSource(
                    appName: "Example",
                    cacheKey: firstKey,
                    capturedAt: launchDate,
                    prepareIcon: { log.prepare("first") }
                ),
                tracker.makeSource(
                    appName: "Example",
                    cacheKey: secondKey,
                    capturedAt: launchDate,
                    prepareIcon: { log.prepare("second") }
                ),
                tracker.makeSource(
                    appName: "Example",
                    cacheKey: firstKey,
                    capturedAt: launchDate,
                    prepareIcon: { log.prepare("first") }
                )
            )
        }

        #expect(log.attemptCount(for: "first") == 1)
        #expect(log.attemptCount(for: "second") == 1)
        #expect(counters.identityHashCount == 2)
        #expect(first.iconData == firstIcon)
        #expect(second.iconData == secondIcon)
        #expect(first.iconBlobID == ClipboardHistoryBlobStore.sha256Hex(firstIcon))
        #expect(second.iconBlobID == ClipboardHistoryBlobStore.sha256Hex(secondIcon))
        #expect(firstAgain.iconData == firstIcon)
        #expect(firstAgain.iconBlobID == first.iconBlobID)
    }

    @Test func restartedAndDifferentlyLocatedApplicationsDoNotShareIcons() {
        let icon = Data(repeating: 0x81, count: 32)
        let restartedIcon = Data(repeating: 0x82, count: 32)
        let otherInstallIcon = Data(repeating: 0x83, count: 32)
        let log = TrackerIconPreparationLog()
        log.provide("generation", payload: icon)
        log.provide("restart", payload: restartedIcon)
        log.provide("other-installation", payload: otherInstallIcon)
        let tracker = CopySourceTracker(frontmostSourceProvider: { nil })
        let launched = generation(811, bundleURL: bundleURL)
        // A reused process identifier after a restart, and the same bundle
        // identifier installed somewhere else, are both distinct identities.
        let restarted = SourceAppIconCacheKey(
            processIdentifier: 811,
            launchDate: launchDate.addingTimeInterval(120),
            bundleURL: bundleURL
        )!
        let otherInstallation = generation(811, bundleURL: URL(fileURLWithPath: "/Volumes/Other/Example.app"))

        let observed = [
            ("generation", launched),
            ("restart", restarted),
            ("other-installation", otherInstallation)
        ].map { label, key in
            tracker.makeSource(
                appName: "Example",
                cacheKey: key,
                capturedAt: launchDate,
                prepareIcon: { log.prepare(label) }
            )
        }

        #expect(log.attemptCount(for: "generation") == 1)
        #expect(log.attemptCount(for: "restart") == 1)
        #expect(log.attemptCount(for: "other-installation") == 1)
        #expect(observed.map(\.iconData) == [icon, restartedIcon, otherInstallIcon])
        #expect(Set(observed.compactMap(\.iconBlobID)).count == 3)
    }

    @Test func unavailableProcessGenerationPreparesWithoutCaching() async {
        let counters = MediaOperationCounters()
        let icon = Data(repeating: 0x91, count: 40)
        let log = TrackerIconPreparationLog()
        log.provide("Example", payload: icon)
        let tracker = CopySourceTracker(frontmostSourceProvider: { nil })
        // A reliable generation is also cacheable without a bundle location.
        let key = generation(821, bundleURL: nil)

        counters.reset()
        let uncached = await counters.measure {
            (0..<3).map { index in
                tracker.makeSource(
                    appName: "Example",
                    cacheKey: nil,
                    capturedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                    pasteboardChangeCount: index,
                    prepareIcon: { log.prepare("Example") }
                )
            }
        }

        #expect(log.attemptCount(for: "Example") == 3)
        #expect(counters.identityHashCount == 3)
        #expect(uncached.map(\.appName) == ["Example", "Example", "Example"])
        #expect(uncached.map(\.capturedAt) == (0..<3).map { Date(timeIntervalSince1970: TimeInterval($0)) })
        #expect(uncached.map(\.pasteboardChangeCount) == [0, 1, 2])
        #expect(uncached.allSatisfy { $0.iconData == icon })

        // A later reliable identity prepares once and then hits.
        let cached = tracker.makeSource(
            appName: "Example",
            cacheKey: key,
            capturedAt: launchDate,
            prepareIcon: { log.prepare("Example") }
        )
        let attemptsAfterCaching = log.attemptCount(for: "Example")
        #expect(attemptsAfterCaching == 4)

        // Uncached observations never populate the cache: filling every
        // observation with them would otherwise evict the retained entry.
        for index in 0..<40 {
            _ = tracker.makeSource(
                appName: "Example",
                cacheKey: nil,
                capturedAt: launchDate,
                pasteboardChangeCount: index,
                prepareIcon: { log.prepare("Example") }
            )
        }
        #expect(log.attemptCount(for: "Example") == attemptsAfterCaching + 40)

        let hit = tracker.makeSource(
            appName: "Example",
            cacheKey: key,
            capturedAt: launchDate,
            prepareIcon: { log.prepare("Example") }
        )
        #expect(log.attemptCount(for: "Example") == attemptsAfterCaching + 40)
        #expect(hit.iconData == icon)
        #expect(hit.iconBlobID == cached.iconBlobID)
    }

    @Test func failedPreparationYieldsIconlessNamedSourceAndLaterRetries() async {
        let counters = MediaOperationCounters()
        let icon = Data(repeating: 0xA1, count: 72)
        let log = TrackerIconPreparationLog()
        let tracker = CopySourceTracker(frontmostSourceProvider: { nil })
        let key = generation(831, bundleURL: bundleURL)
        let capturedAt = Date(timeIntervalSince1970: 42)

        counters.reset()
        let failed = await counters.measure {
            tracker.makeSource(
                appName: "Example",
                cacheKey: key,
                capturedAt: capturedAt,
                pasteboardChangeCount: 12,
                prepareIcon: { log.prepare("Example") }
            )
        }

        #expect(failed.appName == "Example")
        #expect(failed.iconData == nil)
        #expect(failed.iconBlobID == nil)
        #expect(failed.capturedAt == capturedAt)
        #expect(failed.pasteboardChangeCount == 12)
        #expect(counters.identityHashCount == 0)

        log.provide("Example", payload: icon)
        let retried = tracker.makeSource(
            appName: "Example",
            cacheKey: key,
            capturedAt: capturedAt,
            prepareIcon: { log.prepare("Example") }
        )
        #expect(retried.iconData == icon)
        #expect(retried.iconBlobID == ClipboardHistoryBlobStore.sha256Hex(icon))

        counters.reset()
        let hit = await counters.measure {
            tracker.makeSource(
                appName: "Example",
                cacheKey: key,
                capturedAt: capturedAt,
                prepareIcon: { log.prepare("Example") }
            )
        }
        #expect(hit.iconBlobID == retried.iconBlobID)
        #expect(log.attemptCount(for: "Example") == 2)
        #expect(counters.identityHashCount == 0)
    }

    @Test func evictionKeepsCreatedSourcesIntactAndAllowsRepreparation() {
        let icon = Data(repeating: 0xB1, count: 24)
        let replacementIcon = Data(repeating: 0xB2, count: 24)
        let log = TrackerIconPreparationLog()
        log.provide(label(1), payload: icon)
        let tracker = CopySourceTracker(frontmostSourceProvider: { nil })

        let first = tracker.makeSource(
            appName: "Example 1",
            cacheKey: generation(1, bundleURL: bundleURL),
            capturedAt: launchDate,
            prepareIcon: { log.prepare(label(1)) }
        )

        // Fill the default bound with newer successful identities.
        for pid in 2...33 {
            let identifier = pid_t(pid)
            log.provide(label(identifier), payload: Data([UInt8(pid)]))
            _ = tracker.makeSource(
                appName: "Example \(pid)",
                cacheKey: generation(identifier, bundleURL: bundleURL),
                capturedAt: launchDate,
                prepareIcon: { log.prepare(label(identifier)) }
            )
        }

        log.provide(label(1), payload: replacementIcon)
        let reprepared = tracker.makeSource(
            appName: "Example 1",
            cacheKey: generation(1, bundleURL: bundleURL),
            capturedAt: launchDate,
            prepareIcon: { log.prepare(label(1)) }
        )

        #expect(log.attemptCount(for: label(1)) == 2)
        #expect(reprepared.iconData == replacementIcon)
        // The earlier observation keeps exactly what it captured.
        #expect(first.iconData == icon)
        #expect(first.iconBlobID == ClipboardHistoryBlobStore.sha256Hex(icon))
        #expect(reprepared.iconBlobID != first.iconBlobID)
    }

    private func keyDown(keyCode: Int, flags: CGEventFlags) -> CGEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true)
        event?.flags = flags
        return event!
    }

    private func generation(_ pid: pid_t, bundleURL: URL?) -> SourceAppIconCacheKey {
        SourceAppIconCacheKey(processIdentifier: pid, launchDate: launchDate, bundleURL: bundleURL)!
    }

    private func label(_ pid: pid_t) -> String {
        "generation-\(pid)"
    }

    private func source(
        named name: String,
        capturedAt: Date,
        changeCount: Int
    ) -> ClipboardSource {
        ClipboardSource(
            appName: name,
            iconData: nil,
            capturedAt: capturedAt,
            pasteboardChangeCount: changeCount
        )
    }
}

/// Counts shared-path icon preparation attempts per observation label and
/// finalizes each payload through the real identity seam, so hash counting
/// stays honest. A label without a payload stands for unavailable preparation.
private final class TrackerIconPreparationLog {
    private var payloads: [String: Data] = [:]
    private var attempts: [String: Int] = [:]

    func provide(_ label: String, payload: Data) {
        payloads[label] = payload
    }

    func prepare(_ label: String) -> PreparedMedia? {
        attempts[label, default: 0] += 1
        return payloads[label].map { PreparedMedia(hashing: $0) }
    }

    func attemptCount(for label: String) -> Int {
        attempts[label] ?? 0
    }
}
