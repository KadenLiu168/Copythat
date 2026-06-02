import CryptoKit
import Foundation

enum ClipboardKind: String {
    case image
}

struct ClipboardItem {
    let kind: ClipboardKind
    let imageData: Data?

    var contentKey: String {
        switch kind {
        case .image:
            return "image:\(imageData?.stableDigest ?? "empty")"
        }
    }
}

private extension Data {
    var stableDigest: String {
        SHA256.hash(data: self)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

let first = ClipboardItem(kind: .image, imageData: Data([0, 1, 2, 3, 4]))
let same = ClipboardItem(kind: .image, imageData: Data([0, 1, 2, 3, 4]))
let different = ClipboardItem(kind: .image, imageData: Data([0, 1, 2, 3, 5]))

precondition(first.contentKey == same.contentKey, "same image data should produce the same content key")
precondition(first.contentKey != different.contentKey, "different image data should produce a different content key")
precondition(first.contentKey == "image:08bb5e5d6eaac1049ede0893d30ed022b1a4d9b5b48db414871f51c9cb35283d", "image content key should use a stable SHA-256 digest")

print("content keys ok")
