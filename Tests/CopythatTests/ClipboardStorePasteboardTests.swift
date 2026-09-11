@testable import Copythat
import AppKit
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct ClipboardStorePasteboardTests {
    @Test func captureUsesTheStableSecondPoll() {
        let (store, pasteboard) = makeStore()
        pasteboard.clearContents()
        pasteboard.setString("stable text", forType: .string)

        store.pollPasteboard()
        #expect(store.items.isEmpty)

        store.pollPasteboard()

        #expect(store.items.count == 1)
        #expect(store.items.first?.kind == .text)
        #expect(store.items.first?.textValue == "stable text")
    }

    @Test func capturesHTTPAndHTTPSURLs() {
        let (store, pasteboard) = makeStore()

        pollStable(store, pasteboard) { pasteboard in
            pasteboard.setString("http://127.0.0.1:1/http", forType: .string)
        }
        pollStable(store, pasteboard) { pasteboard in
            pasteboard.setString("HTTPS://127.0.0.1:1/https", forType: .string)
        }

        #expect(store.items.map(\.kind) == [.url, .url])
        #expect(store.items.map(\.textValue) == [
            "HTTPS://127.0.0.1:1/https",
            "http://127.0.0.1:1/http"
        ])
    }

    @Test func capturesExistingFileURLString() throws {
        let (store, pasteboard) = makeStore()
        let fileURL = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        pollStable(store, pasteboard) { pasteboard in
            pasteboard.setString(fileURL.path, forType: .string)
        }

        let item = try #require(store.items.first)
        #expect(item.kind == .file)
        #expect(item.fileURLs == [fileURL])
        #expect(item.title == fileURL.lastPathComponent)
    }

    @Test func capturesFileObjects() throws {
        let (store, pasteboard) = makeStore()
        let fileURL = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var didWrite = false
        pollStable(store, pasteboard) { pasteboard in
            didWrite = pasteboard.writeObjects([fileURL as NSURL])
        }

        #expect(didWrite)
        let item = try #require(store.items.first)
        #expect(item.kind == .file)
        #expect(item.fileURLs == [fileURL])
    }

    @Test func ignoresEmptyAndUnsupportedPasteboardContent() {
        let (store, pasteboard) = makeStore()

        pollStable(store, pasteboard) { pasteboard in
            _ = pasteboard.setString("", forType: .string)
        }
        #expect(store.items.isEmpty)

        pollStable(store, pasteboard) { pasteboard in
            _ = pasteboard.setData(
                Data([1, 2, 3]),
                forType: NSPasteboard.PasteboardType("com.copythat.tests.unsupported")
            )
        }
        #expect(store.items.isEmpty)
    }

    @Test func restoresSupportedItemsAndRejectsInvalidInputs() throws {
        let (store, pasteboard) = makeStore()
        pasteboard.setString("keep me", forType: .string)

        let emptyText = item(kind: .text, textValue: "", preview: "")
        let emptyURL = item(kind: .url, textValue: "", preview: "")
        let missingFileURL = URL(fileURLWithPath: "/tmp/copythat-missing-\(UUID().uuidString)")
        let missingFile = item(kind: .file, fileURLs: [missingFileURL])
        let invalidImage = item(kind: .image)

        #expect(!store.writeToPasteboard(emptyText))
        #expect(!store.writeToPasteboard(emptyURL))
        #expect(!store.writeToPasteboard(missingFile))
        #expect(!store.writeToPasteboard(invalidImage))
        #expect(pasteboard.string(forType: .string) == "keep me")

        let fileURL = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let existingFile = item(kind: .file, fileURLs: [missingFileURL, fileURL])
        #expect(store.writeToPasteboard(existingFile))
        #expect(pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] == [fileURL])

        let text = item(kind: .text, textValue: "restore me")
        #expect(store.writeToPasteboard(text))
        #expect(pasteboard.string(forType: .string) == "restore me")

        let image = item(kind: .image, imageData: testImage().pngData(maxPixel: 10))
        #expect(store.writeToPasteboard(image))
        #expect(pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.isEmpty == false)
    }

    @Test func capturesImageThroughTheAsynchronousEncodingPath() async throws {
        let (store, pasteboard) = makeStore()
        let image = testImage()
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([image]))

        store.pollPasteboard()
        #expect(store.items.isEmpty)
        store.pollPasteboard()
        #expect(store.items.isEmpty)

        for _ in 0..<200 where store.items.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let item = try #require(store.items.first)
        #expect(item.kind == .image)
        #expect(item.imageData?.isEmpty == false)
    }

    private func makeStore() -> (ClipboardStore, NSPasteboard) {
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let source = ClipboardSource(appName: "Tests", iconData: nil, capturedAt: Date())
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults()),
            sourceTracker: CopySourceTracker(frontmostSourceProvider: { source }),
            initialItems: [],
            pasteboard: pasteboard,
            persistItems: { _ in }
        )
        return (store, pasteboard)
    }

    private func pollStable(
        _ store: ClipboardStore,
        _ pasteboard: NSPasteboard,
        write: (NSPasteboard) -> Void
    ) {
        pasteboard.clearContents()
        write(pasteboard)
        store.pollPasteboard()
        store.pollPasteboard()
    }

    private func item(
        kind: ClipboardKind,
        textValue: String? = nil,
        preview: String = "",
        fileURLs: [URL] = [],
        imageData: Data? = nil
    ) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: kind,
            title: "Test item",
            preview: preview,
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            isPinned: false,
            pinboardName: nil,
            textValue: textValue,
            fileURLs: fileURLs,
            imageData: imageData
        )
    }

    private func temporaryFile() throws -> URL {
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("copythat-pasteboard-\(UUID().uuidString).txt")
        try Data("fixture".utf8).write(to: fileURL)
        return fileURL
    }

    private func testImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        image.unlockFocus()
        return image
    }

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "ClipboardStorePasteboardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
