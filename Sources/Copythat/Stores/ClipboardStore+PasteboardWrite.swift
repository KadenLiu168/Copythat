import AppKit
import Foundation

// Pasteboard writes and the content match that decides whether a removal must
// clear the system pasteboard. It shares the polling path's pasteboard and
// processed-count bookkeeping, so it lives beside it rather than duplicating it.
extension ClipboardStore {
    func writeToPasteboard(_ item: ClipboardItem) -> Bool {
        let didWrite: Bool
        switch item.kind {
        case .text, .url:
            let string = item.textValue ?? item.preview
            guard !string.isEmpty else { return false }
            pasteboard.clearContents()
            didWrite = pasteboard.setString(string, forType: .string)
        case .file:
            let existingFileURLs = item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !existingFileURLs.isEmpty else { return false }
            pasteboard.clearContents()
            didWrite = pasteboard.writeObjects(existingFileURLs as [NSURL])
        case .image:
            guard let image = item.image else { return false }
            pasteboard.clearContents()
            didWrite = pasteboard.writeObjects([image])
        }
        markPasteboardProcessed()
        return didWrite
    }

    func pasteboardMatches(_ item: ClipboardItem) -> Bool {
        switch item.kind {
        case .text, .url:
            return pasteboard.string(forType: .string) == (item.textValue ?? item.preview)
        case .file:
            guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL] else {
                return false
            }
            let currentPaths = urls.filter(\.isFileURL).map(\.path)
            return currentPaths == item.fileURLs.map(\.path)
        case .image:
            guard let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
                  let image = images.first,
                  let currentContentKey = imageContentKey(for: image) else {
                return false
            }
            return currentContentKey == item.contentKey
        }
    }
}
