import Foundation

struct Candidate {
    let processIdentifier: Int32
    let bundleIdentifier: String?
}

func isPasteTargetCandidate(_ application: Candidate, currentPID: Int32, bundleIdentifier: String?) -> Bool {
    guard application.processIdentifier != currentPID else {
        return false
    }
    switch application.bundleIdentifier {
    case bundleIdentifier, "com.apple.systemuiserver":
        return false
    default:
        return true
    }
}

let currentPID: Int32 = 100
let bundleIdentifier = "local.copythat.clipboard"

precondition(!isPasteTargetCandidate(Candidate(processIdentifier: currentPID, bundleIdentifier: bundleIdentifier), currentPID: currentPID, bundleIdentifier: bundleIdentifier), "Copythat should not paste into itself")
precondition(!isPasteTargetCandidate(Candidate(processIdentifier: 200, bundleIdentifier: bundleIdentifier), currentPID: currentPID, bundleIdentifier: bundleIdentifier), "same bundle id should not be a paste target")
precondition(!isPasteTargetCandidate(Candidate(processIdentifier: 300, bundleIdentifier: "com.apple.systemuiserver"), currentPID: currentPID, bundleIdentifier: bundleIdentifier), "SystemUIServer should not be a paste target")
precondition(isPasteTargetCandidate(Candidate(processIdentifier: 400, bundleIdentifier: "com.apple.TextEdit"), currentPID: currentPID, bundleIdentifier: bundleIdentifier), "user app should be a paste target")

print("paste target ok")
