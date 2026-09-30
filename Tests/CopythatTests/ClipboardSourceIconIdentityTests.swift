@testable import Copythat
import AppKit
import CryptoKit
import Foundation
import Testing

/// Source icons are finalized once per prepared payload: the tracker cache
/// reuses those bytes and their established address, and the address travels
/// with the icon through copied sources, every item creation path, and
/// persistence, so no later capture, save, or restore hashes or re-encodes an
/// icon.
@MainActor
struct ClipboardSourceIconIdentityTests {
    @Test func cachedPreparedIconIsForwardedToEveryItemKindAndPersisted() async throws {
        let counters = MediaOperationCounters()
        let icon = Data(repeating: 0x41, count: 160)
        let clock = MutableClock()
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let counter = LinkPreviewCounter()
        let key = SourceAppIconCacheKey(
            processIdentifier: 501,
            launchDate: Date(timeIntervalSince1970: 1_700_000_000),
            bundleURL: URL(fileURLWithPath: "/Applications/Example.app")
        )!
        var preparations = 0
        let sourceTracker = CopySourceTracker()
        let prepareIcon = {
            preparations += 1
            return PreparedMedia(hashing: icon)
        }

        // Fixture: the first observation prepares the icon and establishes its
        // address before any measurement window opens; the next one reuses it.
        let source = sourceTracker.makeSource(
            appName: "Tests",
            cacheKey: key,
            capturedAt: Date(),
            prepareIcon: prepareIcon
        )
        let cachedSource = sourceTracker.makeSource(
            appName: "Tests",
            cacheKey: key,
            capturedAt: Date(),
            prepareIcon: prepareIcon
        )
        #expect(preparations == 1)
        #expect(source.iconData == icon)
        #expect(cachedSource.iconBlobID == sha256Hex(icon))

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardSourceIconIdentityTests-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "ClipboardSourceIconIdentityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: defaultsName)
        }
        let persistence = counters.makePersistence(directoryURL: directory, userDefaults: defaults)

        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults()),
            sourceTracker: CopySourceTracker(frontmostSourceProvider: { cachedSource }),
            initialItems: [],
            pasteboard: pasteboard,
            persistItems: { items in
                try? persistence.save(items)
                counter.mark("saved")
            },
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
        #expect(preparations == 1)
        #expect(store.items.allSatisfy { $0.sourceAppIconData == icon })
        #expect(store.items.allSatisfy { $0.sourceAppIconBlobID == sha256Hex(icon) })
        // Only the captured image payload was finalized in this window; no
        // capture path re-hashed or re-encoded the prepared source icon.
        #expect(counters.identityHashCount == 1)

        // The saved source-icon blob holds exactly the prepared payload at its
        // established address.
        #expect(try persistence.blobStore.read(blobID: sha256Hex(icon)) == icon)

        counters.reset()
        let reloaded = try await counters.measure { try persistence.loadItems() }

        #expect(reloaded.count == 4)
        #expect(reloaded.map(\.kind) == [.image, .file, .url, .text])
        #expect(reloaded.allSatisfy { $0.sourceAppIconData == icon })
        #expect(reloaded.allSatisfy { $0.sourceAppIconBlobID == sha256Hex(icon) })
        // Restore keeps its integrity verification: the shared icon is read and
        // verified once, and no address is recomputed.
        #expect(counters.identityHashCount == 0)
        #expect(counters.integrityHashCount == 1)
        #expect(counters.blobReadCount == 1)

        // Eviction stays local to preparation: the captured items keep the bytes
        // and the address they were given.
        for pid in 2...33 {
            _ = sourceTracker.makeSource(
                appName: "Other \(pid)",
                cacheKey: SourceAppIconCacheKey(
                    processIdentifier: pid_t(pid),
                    launchDate: Date(timeIntervalSince1970: TimeInterval(pid)),
                    bundleURL: nil
                )!,
                capturedAt: Date(),
                prepareIcon: { PreparedMedia(hashing: Data([UInt8(pid)])) }
            )
        }
        _ = sourceTracker.makeSource(
            appName: "Tests",
            cacheKey: key,
            capturedAt: Date(),
            prepareIcon: prepareIcon
        )

        #expect(preparations == 2)
        #expect(store.items.allSatisfy { $0.sourceAppIconData == icon })
        #expect(store.items.allSatisfy { $0.sourceAppIconBlobID == sha256Hex(icon) })
        #expect(try persistence.blobStore.read(blobID: sha256Hex(icon)) == icon)
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
