import AppKit
import Foundation

enum ClipboardKind {
    case text
    case file
    case image
}

struct ClipboardItem {
    let kind: ClipboardKind
    let textValue: String?
    let preview: String
    let fileURLs: [URL]
    let imageData: Data?

    var image: NSImage? {
        imageData.flatMap(NSImage.init(data:))
    }
}

func writeToPasteboard(_ item: ClipboardItem, pasteboard: NSPasteboard) -> Bool {
    switch item.kind {
    case .text:
        let string = item.textValue ?? item.preview
        guard !string.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(string, forType: .string)
    case .file:
        let existingFileURLs = item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existingFileURLs.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects(existingFileURLs as [NSURL])
    case .image:
        guard let image = item.image else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects([image])
    }
}

let pasteboard = NSPasteboard.withUniqueName()
pasteboard.clearContents()
pasteboard.setString("keep me", forType: .string)

let invalidImage = ClipboardItem(kind: .image, textValue: nil, preview: "Image", fileURLs: [], imageData: nil)
precondition(writeToPasteboard(invalidImage, pasteboard: pasteboard) == false, "invalid image should not write")
precondition(pasteboard.string(forType: .string) == "keep me", "invalid item should not clear existing pasteboard contents")

let missingFile = ClipboardItem(kind: .file, textValue: nil, preview: "Missing", fileURLs: [URL(fileURLWithPath: "/tmp/paste-missing-file-\(UUID().uuidString)")], imageData: nil)
precondition(writeToPasteboard(missingFile, pasteboard: pasteboard) == false, "missing file should not write")
precondition(pasteboard.string(forType: .string) == "keep me", "missing file should not clear existing pasteboard contents")

let existingFileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("paste-existing-file-\(UUID().uuidString)")
try "file".write(to: existingFileURL, atomically: true, encoding: .utf8)
defer { try? FileManager.default.removeItem(at: existingFileURL) }
let existingFile = ClipboardItem(kind: .file, textValue: nil, preview: "Existing", fileURLs: [missingFile.fileURLs[0], existingFileURL], imageData: nil)
precondition(writeToPasteboard(existingFile, pasteboard: pasteboard), "existing file should write")
let writtenFiles = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
precondition(writtenFiles == [existingFileURL], "only existing files should be written")

let text = ClipboardItem(kind: .text, textValue: "restore me", preview: "", fileURLs: [], imageData: nil)
precondition(writeToPasteboard(text, pasteboard: pasteboard), "text item should write")
precondition(pasteboard.string(forType: .string) == "restore me", "text item should replace pasteboard contents")

print("pasteboard write ok")
