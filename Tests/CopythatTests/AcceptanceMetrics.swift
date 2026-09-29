import Foundation

/// Machine-readable evidence for the unattended acceptance report.
///
/// The acceptance runner points `COPYTHAT_ACCEPTANCE_METRICS_DIR` at a
/// per-run directory; each scenario appends `{metric, expected, observed}`
/// rows to `<scenario>.jsonl` there, and the runner copies them into
/// `report.json` as the scenario's expected/observed readings. Ordinary test
/// runs never set the variable, so nothing is written outside acceptance runs.
enum AcceptanceMetrics {
    private static let lock = NSLock()

    static func record(
        scenario: String,
        metric: String,
        expected: String,
        observed: String
    ) {
        guard let directory = ProcessInfo.processInfo.environment["COPYTHAT_ACCEPTANCE_METRICS_DIR"],
              !directory.isEmpty else {
            return
        }
        let row: [String: String] = ["metric": metric, "expected": expected, "observed": observed]
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else {
            return
        }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent("\(scenario).jsonl")

        lock.lock()
        defer { lock.unlock() }
        let payload = Data((line + "\n").utf8)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: payload)
                return
            }
            try payload.write(to: url)
        } catch {
            return
        }
    }
}
