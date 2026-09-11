@testable import Copythat
import Foundation
import Testing

@MainActor
struct PasteTargetTests {
    @Test func excludesCopythatAndSystemProcessesButAcceptsUserApps() {
        let copythatBundleIdentifier = "local.copythat.clipboard"

        #expect(!PanelWindowController.isPasteTargetCandidate(
            processIdentifier: 100,
            currentProcessIdentifier: 100,
            bundleIdentifier: "com.example.other",
            copythatBundleIdentifier: copythatBundleIdentifier
        ))
        #expect(!PanelWindowController.isPasteTargetCandidate(
            processIdentifier: 200,
            currentProcessIdentifier: 100,
            bundleIdentifier: copythatBundleIdentifier,
            copythatBundleIdentifier: copythatBundleIdentifier
        ))
        #expect(!PanelWindowController.isPasteTargetCandidate(
            processIdentifier: 300,
            currentProcessIdentifier: 100,
            bundleIdentifier: "com.apple.systemuiserver",
            copythatBundleIdentifier: copythatBundleIdentifier
        ))
        #expect(PanelWindowController.isPasteTargetCandidate(
            processIdentifier: 400,
            currentProcessIdentifier: 100,
            bundleIdentifier: "com.apple.TextEdit",
            copythatBundleIdentifier: copythatBundleIdentifier
        ))
    }
}
