// preview_live_driver.swift - in-process live verification host for the link
// preview pipeline (8.2). Hosts the production ClipboardStore with isolated
// settings/persistence and named NSPasteboard, the REAL LinkPreviewFetcher
// (LPMetadataProvider + WebKit) against local fixture pages, and an injected
// LinkPreviewEvent sink.
// Results carry item IDs, outcome kinds, and timing only - never URLs or
// clipboard payloads. Evidence level: automated-real-providers.

import AppKit
import CryptoKit
import Foundation

struct PreviewAssertion: Codable {
    let name: String
    let expected: String
    let observed: String
    let passed: Bool
}

struct PreviewScenarioResult: Codable {
    let scenario: String
    // passed | failed | blocked
    let verdict: String
    // automated-real-providers (real store, real providers, real WebKit)
    let evidenceLevel: String
    let reason: String
    let assertions: [PreviewAssertion]
    let timings: [String: Double]
}

struct PreviewReport: Codable {
    let generatedAt: String
    let evidenceLevel: String
    let inputMechanism: String
    let payloadSafety: String
    let boundaries: [String]
    let events: [ClipboardDiagnostics.LinkPreviewEvent]
    let scenarios: [PreviewScenarioResult]
}

enum PreviewVerdict {
    static let passed = "passed"
    static let failed = "failed"
    static let blocked = "blocked"
}

enum PreviewEvidence {
    static let automatedRealDesktop = "automated-real-providers"
}

func previewDigest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
}

/// In-memory collector for the diagnostics link-preview event stream.
@MainActor
final class PreviewEventLog {
    private(set) var events: [ClipboardDiagnostics.LinkPreviewEvent] = []

    func record(_ event: ClipboardDiagnostics.LinkPreviewEvent) {
        events.append(event)
    }

    func reset() {
        events.removeAll()
    }

    func count(_ outcome: ClipboardDiagnostics.LinkPreviewOutcome) -> Int {
        events.filter { $0.outcome == outcome.rawValue }.count
    }

    func count(_ outcome: ClipboardDiagnostics.LinkPreviewOutcome, itemID: UUID) -> Int {
        events.filter { $0.outcome == outcome.rawValue && $0.itemID == itemID.uuidString }.count
    }

    func anyEvent(itemID: UUID) -> Bool {
        events.contains { $0.itemID == itemID.uuidString }
    }

    var jsonLines: [String] {
        events.map { (try? $0.jsonLine()) ?? "{}" }
    }
}

/// Bounded RunLoop pump for event-driven waits (never a success sleep).
@MainActor
func previewWait(_ seconds: TimeInterval, until predicate: () -> Bool) -> Bool {
    let start = Date()
    while Date().timeIntervalSince(start) < seconds {
        if predicate() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    return predicate()
}

@MainActor
final class PreviewHost {
    let store: ClipboardStore
    let log: PreviewEventLog
    private let pasteboard = NSPasteboard(
        name: NSPasteboard.Name("local.copythat.preview-live.\(UUID().uuidString)")
    )

    init(port: Int) {
        log = PreviewEventLog()
        let suiteName = "local.copythat.preview-live-verify.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: ClipboardDiagnostics.defaultsKey)
        let settings = AppSettings(defaults: defaults)
        let eventLog = log
        store = ClipboardStore(
            settings: settings,
            sourceTracker: CopySourceTracker(),
            initialItems: [],
            pasteboard: pasteboard,
            diagnostics: ClipboardDiagnostics(
            defaults: defaults,
            linkPreviewEventSink: { event in
                MainActor.assumeIsolated {
                    eventLog.record(event)
                    ReportEventsStorage.all.append(event)
                }
            }
            ),
            persistItems: { _ in }
        )
    }

    /// Captures a URL through an isolated NSPasteboard + burst stability path,
    /// returning the new item's id without changing the user's clipboard.
    func capture(urlString: String) -> UUID? {
        pasteboard.clearContents()
        pasteboard.setString(urlString, forType: .string)
        store.pollPasteboard()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        store.pollPasteboard()
        return store.items.first?.id
    }

    /// The controller boundary: selection first, then visibility.
    func openPanel() {
        store.selectFirstVisibleItem()
        store.panelDidOpen()
    }

    func closePanel() {
        store.panelDidClose()
    }
}

// MARK: - CLI (report assembly + exit codes)

private struct PreviewRunOutcome {
    let scenarios: [PreviewScenarioResult]
    let failures: Int
    let blocks: Int
}

@MainActor
private func runPreviewScenarios(port: Int) async -> PreviewRunOutcome {
    var results: [PreviewScenarioResult] = []

    results.append(await PreviewScenarios.metadataImageClosedPanel(port: port))
    results.append(await PreviewScenarios.titleOnlyBatch(port: port))
    results.append(await PreviewScenarios.openSelectAppliesSelectedOnly(port: port))
    results.append(await PreviewScenarios.rapidSwitchOverlap(port: port))
    results.append(await PreviewScenarios.closeCancelReopenRetry(port: port))
    results.append(await PreviewScenarios.refusedPageFailure(port: port))
    results.append(await PreviewScenarios.pinnedDuplicateReusesCache(port: port))
    results.append(PreviewScenarios.eventPayloadSafety())

    let failures = results.filter { $0.verdict == PreviewVerdict.failed }.count
    let blocks = results.filter { $0.verdict == PreviewVerdict.blocked }.count
    return PreviewRunOutcome(scenarios: results, failures: failures, blocks: blocks)
}

@MainActor
private func previewMain() async -> Int32 {
    let arguments = CommandLine.arguments
    guard arguments.count >= 2, arguments[1] == "preview" else {
        FileHandle.standardError.write(Data("usage: preview_live_driver preview --port <n> --report <path>\n".utf8))
        return 2
    }
    var port = 8765
    var reportPath = ""
    var index = 2
    while index + 1 < arguments.count {
        switch arguments[index] {
        case "--port":
            port = Int(arguments[index + 1]) ?? 8765
        case "--report":
            reportPath = arguments[index + 1]
        default:
            break
        }
        index += 2
    }
    guard !reportPath.isEmpty else {
        FileHandle.standardError.write(Data("missing --report path\n".utf8))
        return 2
    }

    let outcome = await runPreviewScenarios(port: port)
    let report = PreviewReport(
        generatedAt: ISO8601DateFormatter().string(from: Date()),
        evidenceLevel: PreviewEvidence.automatedRealDesktop,
        inputMechanism: "in-process production ClipboardStore; isolated named NSPasteboard capture via burst polling",
        payloadSafety: "report events carry item ids, outcome kinds, and uptime only; runner re-validates",
        boundaries: [
            "does not prove physical HID behavior or the accessibility-grant flow",
            "card pixels and visual aesthetics are not covered by this in-process runner",
            "multi-display physical behavior remains unverified",
        ],
        events: ReportEventsStorage.all,
        scenarios: outcome.scenarios
    )
    let encoded = try? JSONEncoder().encode(report)
    if let encoded, let data = try? JSONSerialization.jsonObject(with: encoded) {
        let pretty = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
        FileManager.default.createFile(atPath: reportPath, contents: pretty ?? encoded)
    } else {
        FileManager.default.createFile(atPath: reportPath, contents: Data("{}".utf8))
    }

    for scenario in outcome.scenarios {
        let line = "\(scenario.verdict.uppercased())  \(scenario.scenario)  \(scenario.reason)"
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
    if outcome.failures > 0 { return 1 }
    if outcome.scenarios.isEmpty || outcome.blocks > 0 { return 2 }
    return 0
}


@main
struct PreviewLiveDriverMain {
    static func main() async {
        let status = await previewMain()
        exit(status)
    }
}
