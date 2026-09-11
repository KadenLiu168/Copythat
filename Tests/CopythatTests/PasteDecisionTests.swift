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
    }
}
