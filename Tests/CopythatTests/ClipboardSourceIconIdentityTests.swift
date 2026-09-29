@testable import Copythat
import AppKit
import CryptoKit
import Foundation
import Testing

/// Source icons are finalized once per prepared payload: their address travels
/// with the icon through copied sources and every item creation path, so no
/// later capture or save hashes an icon again.
@MainActor
struct ClipboardSourceIconIdentityTests {
    @Test func preparedIconHashesOnceAndIsForwardedToEveryItemKind() async throws {
        let counters = MediaOperationCounters()
        let icon = Data(repeating: 0x41, count: 160)
        let clock = MutableClock()
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let counter = LinkPreviewCounter()

        counters.reset()
        let source = await counters.measure {
            ClipboardSource(appName: "Tests", iconData: icon, capturedAt: Date())
        }
        #expect(counters.identityHashCount == 1)
        #expect(source.iconBlobID == sha256Hex(icon))

        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults()),
            sourceTracker: CopySourceTracker(frontmostSourceProvider: { source }),
            initialItems: [],
            pasteboard: pasteboard,
            persistItems: { _ in counter.mark("saved") },
            uptimeProvider: { clock.now },
            fetchLinkMetadata: { _ in throw URLError(.unsupportedURL) },
            fetchLinkSnapshot: { _ in throw URLError(.unsupportedURL) }
        )

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceIconIdentity-\(UUID().uuidString).txt")
        try "file".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        counters.reset()
        await counters.measure {
            pasteboard.clearContents()
            pasteboard.setString("plain text", forType: .string)
            store.pollPasteboard()
            clock.advance(by: 1)
            store.pollPasteboard()
            await counter.waitFor("saved", reaching: 1)

            pasteboard.clearContents()
            pasteboard.setString("https://icon-identity.example.com/", forType: .string)
            store.pollPasteboard()
            clock.advance(by: 1)
            store.pollPasteboard()
            await counter.waitFor("saved", reaching: 2)

            pasteboard.clearContents()
            pasteboard.setString(fileURL.path, forType: .string)
            store.pollPasteboard()
            clock.advance(by: 1)
            store.pollPasteboard()
            await counter.waitFor("saved", reaching: 3)

            pasteboard.clearContents()
            #expect(pasteboard.writeObjects([LinkPreviewFixture.testImage()]))
            store.pollPasteboard()
            clock.advance(by: 1)
            store.pollPasteboard()
            await counter.waitFor("saved", reaching: 4)
        }

        #expect(store.items.count == 4)
        #expect(store.items.map(\.kind) == [.image, .file, .url, .text])
        #expect(store.items.allSatisfy { $0.sourceAppIconData == icon })
        #expect(store.items.allSatisfy { $0.sourceAppIconBlobID == sha256Hex(icon) })
        // Only the captured image payload was finalized here; no item creation
        // path re-hashed the prepared icon.
        #expect(counters.identityHashCount == 1)
    }

    @Test func copiedSourceSnapshotForwardsThePreparedIconIdentity() async {
        let counters = MediaOperationCounters()
        let icon = Data(repeating: 0x42, count: 96)
        let first = ClipboardSource(
            appName: "First App",
            iconData: icon,
            capturedAt: Date(),
            pasteboardChangeCount: 7
        )
        let second = ClipboardSource(appName: "Second App", iconData: nil, capturedAt: Date())
        let next: ClipboardSource? = second
        let tracker = CopySourceTracker(frontmostSourceProvider: { next })

        tracker.recordActivatedSource(first, currentChangeCount: 7)
        tracker.recordActivatedSource(second, currentChangeCount: 7)

        counters.reset()
        let snapshot = await counters.measure { tracker.frontmostSourceSnapshot(pasteboardChangeCount: 7) }

        #expect(snapshot?.appName == "First App")
        #expect(snapshot?.iconData == icon)
        #expect(snapshot?.iconBlobID == first.iconBlobID)
        #expect(counters.mediaHashCount == 0)
    }

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "ClipboardSourceIconIdentityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
