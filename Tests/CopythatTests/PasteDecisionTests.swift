@testable import Copythat
import Testing

struct PasteDecisionTests {
    @Test func restoreFailureTakesPrecedence() {
        #expect(pasteDecision(didWrite: false, hasTargetApp: false, accessibilityTrusted: false) == .showRestoreFailure)
    }

    @Test func missingTargetIsReportedAfterRestore() {
        #expect(pasteDecision(didWrite: true, hasTargetApp: false, accessibilityTrusted: true) == .showMissingTarget)
    }

    @Test func accessibilityFailureIsReportedBeforeSendingPaste() {
        #expect(pasteDecision(didWrite: true, hasTargetApp: true, accessibilityTrusted: false) == .showAccessibilityFailure)
    }

    @Test func pasteIsSentOnlyWhenEveryPreconditionPasses() {
        #expect(pasteDecision(didWrite: true, hasTargetApp: true, accessibilityTrusted: true) == .sendPaste)
        AcceptanceMetrics.record(
            scenario: "paste-decision-and-target",
            metric: "decisionWhenEveryPreconditionPasses",
            expected: "sendPaste",
            observed: "\(pasteDecision(didWrite: true, hasTargetApp: true, accessibilityTrusted: true))"
        )
        AcceptanceMetrics.record(
            scenario: "paste-decision-and-target",
            metric: "decisionForFailedRestore",
            expected: "showRestoreFailure",
            observed: "\(pasteDecision(didWrite: false, hasTargetApp: false, accessibilityTrusted: false))"
        )
        AcceptanceMetrics.record(
            scenario: "paste-decision-and-target",
            metric: "decisionForMissingTarget",
            expected: "showMissingTarget",
            observed: "\(pasteDecision(didWrite: true, hasTargetApp: false, accessibilityTrusted: true))"
        )
        AcceptanceMetrics.record(
            scenario: "paste-decision-and-target",
            metric: "decisionForUntrustedAccessibility",
            expected: "showAccessibilityFailure",
            observed: "\(pasteDecision(didWrite: true, hasTargetApp: true, accessibilityTrusted: false))"
        )
    }
}
