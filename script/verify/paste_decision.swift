import Foundation

enum PasteDecision: Equatable {
    case showRestoreFailure
    case showMissingTarget
    case showAccessibilityFailure
    case sendPaste
}

func pasteDecision(didWrite: Bool, hasTargetApp: Bool, accessibilityTrusted: Bool) -> PasteDecision {
    guard didWrite else {
        return .showRestoreFailure
    }
    guard hasTargetApp else {
        return .showMissingTarget
    }
    guard accessibilityTrusted else {
        return .showAccessibilityFailure
    }
    return .sendPaste
}

precondition(pasteDecision(didWrite: false, hasTargetApp: false, accessibilityTrusted: false) == .showRestoreFailure)
precondition(pasteDecision(didWrite: true, hasTargetApp: false, accessibilityTrusted: true) == .showMissingTarget)
precondition(pasteDecision(didWrite: true, hasTargetApp: true, accessibilityTrusted: false) == .showAccessibilityFailure)
precondition(pasteDecision(didWrite: true, hasTargetApp: true, accessibilityTrusted: true) == .sendPaste)

print("paste decision ok")
