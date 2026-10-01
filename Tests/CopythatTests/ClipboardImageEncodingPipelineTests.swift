@testable import Copythat
import AppKit
import CryptoKit
import Foundation
import Testing

/// Bounded image-capture pipeline: consecutive observed images survive instead
/// of cancelling one another, the single physical encoder is never overlapped,
/// buffered captures stay inside capacity, and lifecycle invalidation revokes
/// results without freeing a running encoder's slot.
@MainActor
@Suite(.serialized)
struct ClipboardImageEncodingPipelineTests {
    // MARK: - Deterministic regression seam

    @Test func defaultEncoderStillFinalizesRealBoundedPNGOffMainActor() async throws {
        let counters = MediaOperationCounters()
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let clock = MutableClock()
        let saves = LinkPreviewCounter()
        let source = ClipboardSource(appName: "Screenshot", iconData: nil, capturedAt: Date())
        // No encoder injection: this exercises the production pipeline itself.
        let store = ClipboardStore(
            settings: AppSettings(defaults: LinkPreviewFixture.tempDefaults("pipeline-default")),
            sourceTracker: CopySourceTracker(frontmostSourceProvider: { source }),
            initialItems: [],
            pasteboard: pasteboard,
            persistItems: { _ in saves.mark("saved") },
            uptimeProvider: { clock.now },
            fetchLinkMetadata: { _ in throw URLError(.unsupportedURL) },
            fetchLinkSnapshot: { _ in throw URLError(.unsupportedURL) }
        )
        let image = ImagePipelineFixture.image(pixelsWide: 2400, pixelsHigh: 1200, red: 0.9, green: 0.1, blue: 0.1)
        var beforeCompletion = Date.distantFuture

        counters.reset()
        await counters.measure {
            pasteboard.clearContents()
            #expect(pasteboard.writeObjects([image]))
            store.pollPasteboard()
            clock.advance(by: 1)
            store.pollPasteboard()
            beforeCompletion = Date()
            await saves.waitFor("saved", reaching: 1)
        }

        let captured = try #require(store.items.first)
        #expect(captured.kind == .image)
        #expect(counters.identityHashCount == 1, "the finalized payload takes exactly one identity hash")
        #expect(counters.mainThreadIdentityHashCount == 0, "finalization must stay off MainActor")
        // The card exists only after `beforeCompletion`; a completion-time stamp
        // would sit after it, an admission-time stamp before it.
        #expect(captured.createdAt <= beforeCompletion, "a new card uses its admission time, not completion time")
        #expect(captured.preview == "2400 x 1200", "the card reports the original display size")
        let data = try #require(captured.imageData)
        let bitmap = try #require(NSBitmapImageRep(data: data))
        #expect(max(bitmap.pixelsWide, bitmap.pixelsHigh) <= 1_200, "PNG output stays bounded to 1200px")
        #expect(bitmap.pixelsWide == 1_200)
        #expect(bitmap.pixelsHigh == 600)
        #expect(captured.imageBlobID == sha256Hex(data), "carried bytes and content address agree")
        #expect(!store.hasPendingImageCapture)
    }

    @Test func twoConsecutiveImagesBothInsertInFinalizationOrder() async throws {
        let harness = ImagePipelineHarness(capacity: 2)
        let first = ImagePipelineFixture.redImage()
        let second = ImagePipelineFixture.greenImage()
        let firstID = try await ImagePipelineFixture.blobID(of: first)
        let secondID = try await ImagePipelineFixture.blobID(of: second)

        harness.capture(first)
        await harness.encoder.waitForStart(reaching: 1)
        harness.capture(second)

        #expect(harness.store.pendingImageCaptureCount == 2)
        #expect(harness.encoder.startCount == 1, "a waiting capture must launch no encoder")
        #expect(harness.encoder.peakConcurrency == 1)

        harness.encoder.releaseOldest()
        await harness.waitForHandled(1)

        #expect(harness.store.items.map(\.imageBlobID) == [firstID], "a later image must not cancel A")
        await harness.encoder.waitForStart(reaching: 2)
        #expect(harness.encoder.peakConcurrency == 1, "B must start only after A released the slot")

        harness.encoder.releaseOldest()
        await harness.waitForHandled(2)

        #expect(harness.store.items.map(\.imageBlobID) == [secondID, firstID])
        #expect(harness.encoder.peakConcurrency == 1)
        #expect(harness.encoder.launchOrder == [0, 1], "finalization runs A then B")
        #expect(!harness.store.hasPendingImageCapture)
    }

    @Test func threeConsecutiveImagesFinalizeFIFOWithOneEncoderAtATime() async throws {
        let harness = ImagePipelineHarness(capacity: 4)
        let images = [
            ImagePipelineFixture.redImage(),
            ImagePipelineFixture.greenImage(),
            ImagePipelineFixture.blueImage()
        ]
        var blobIDs: [String] = []
        for image in images {
            blobIDs.append(try await ImagePipelineFixture.blobID(of: image))
        }

        for image in images {
            harness.capture(image)
        }
        await harness.encoder.waitForStart(reaching: 1)
        #expect(harness.store.pendingImageCaptureCount == 3)
        #expect(harness.encoder.startCount == 1)

        await harness.drain(through: 3)

        #expect(harness.store.items.map(\.imageBlobID) == blobIDs.reversed())
        #expect(harness.encoder.peakConcurrency == 1)
        #expect(harness.encoder.launchOrder == [0, 1, 2])
    }

    // MARK: - Admission context

    @Test func cardsUseAdmissionTimeSourceAndDisplaySize() async throws {
        let iconA = Data(repeating: 0x11, count: 48)
        let iconB = Data(repeating: 0x22, count: 48)
        let harness = ImagePipelineHarness(
            capacity: 2,
            source: ClipboardSource(appName: "Preview", iconData: iconA, capturedAt: Date())
        )
        let large = ImagePipelineFixture.image(pixelsWide: 2000, pixelsHigh: 1000, red: 0.9, green: 0.1, blue: 0.1)
        let small = ImagePipelineFixture.image(pixelsWide: 48, pixelsHigh: 24, red: 0.1, green: 0.8, blue: 0.2)

        let firstAdmittedAt = Date()
        harness.capture(large)
        await harness.encoder.waitForStart(reaching: 1)

        // The foreground application switches while A is still encoding.
        harness.sourceBox.source = ClipboardSource(appName: "Editor", iconData: iconB, capturedAt: Date())
        harness.capture(small)

        let beforeCompletion = Date()
        await harness.drain(through: 2)

        let items = harness.store.items
        #expect(items.count == 2)
        let newCard = try #require(items.first)
        let oldCard = try #require(items.last)

        #expect(newCard.sourceApp == "Editor", "B keeps the source resolved at its own admission")
        #expect(newCard.sourceAppIconData == iconB)
        #expect(newCard.sourceAppIconBlobID == sha256Hex(iconB))
        #expect(newCard.preview == "48 x 24")

        #expect(oldCard.sourceApp == "Preview", "A keeps its own source across the queue delay")
        #expect(oldCard.sourceAppIconData == iconA)
        #expect(oldCard.sourceAppIconBlobID == sha256Hex(iconA))
        #expect(oldCard.preview == "2000 x 1000")
        #expect(oldCard.createdAt >= firstAdmittedAt)
        #expect(
            oldCard.createdAt <= beforeCompletion,
            "A's card uses admission time: it predates the moment A actually finished encoding"
        )
    }

    // MARK: - Finalization

    @Test func nilEncodingDiscardsItsRequestWithoutSavingAndUnblocksTheNext() async throws {
        let harness = ImagePipelineHarness(capacity: 2)
        let first = ImagePipelineFixture.redImage()
        let second = ImagePipelineFixture.greenImage()
        let secondID = try await ImagePipelineFixture.blobID(of: second)

        harness.encoder.failRequest(at: 0)
        harness.capture(first)
        await harness.encoder.waitForStart(reaching: 1)
        harness.capture(second)

        harness.encoder.releaseOldest()
        await harness.waitForHandled(1)

        #expect(harness.store.items.isEmpty, "a request with no finalized payload inserts nothing")
        #expect(harness.savedCount == 0, "a failed encoding must not request a save")

        await harness.encoder.waitForStart(reaching: 2)
        harness.encoder.releaseOldest()
        await harness.waitForHandled(2)

        #expect(harness.store.items.map(\.imageBlobID) == [secondID], "B still finalizes and inserts")
        #expect(harness.savedCount == 1)
    }

    // MARK: - Bounded overflow

    @Test func overflowRetainsActiveWorkAndDiscardsTheOldestWaitingCapture() async throws {
        let harness = ImagePipelineHarness(capacity: 2)
        let images = [
            ImagePipelineFixture.redImage(),
            ImagePipelineFixture.greenImage(),
            ImagePipelineFixture.blueImage()
        ]
        var blobIDs: [String] = []
        for image in images {
            blobIDs.append(try await ImagePipelineFixture.blobID(of: image))
        }

        harness.capture(images[0])
        await harness.encoder.waitForStart(reaching: 1)
        harness.capture(images[1])
        harness.capture(images[2])

        #expect(harness.store.pendingImageCaptureCount == 2, "buffered captures stay inside capacity")
        #expect(harness.encoder.startCount == 1)

        harness.encoder.releaseAll()
        await harness.waitForHandled(1)
        await harness.encoder.waitForStart(reaching: 2)
        harness.encoder.releaseOldest()
        await harness.waitForHandled(2)

        #expect(harness.store.items.map(\.imageBlobID) == [blobIDs[2], blobIDs[0]])
        #expect(harness.encoder.launchOrder == [0, 1], "the discarded waiting capture never starts encoding")
        #expect(harness.encoder.peakConcurrency == 1)
    }

    @Test func overflowDiagnosticIsMetadataOnlyAndEmittedOnlyWhenEnabled() async throws {
        let enabled = ImagePipelineHarness(capacity: 2, diagnosticsEnabled: true)
        enabled.capture(ImagePipelineFixture.redImage())
        await enabled.encoder.waitForStart(reaching: 1)
        enabled.capture(ImagePipelineFixture.greenImage())
        enabled.capture(ImagePipelineFixture.blueImage())

        let events = enabled.overflowEvents
        #expect(events.count == 1, "exactly one event per discarded waiting capture")
        #expect(events.first?.event == .imageEncodingOverflow)
        #expect(events.first?.queueDepth == 2, "depth is the buffered total after the replacement")
        #expect(events.first?.sourceApp == "Tests")

        let json = try events.first?.jsonLine() ?? ""
        #expect(!json.isEmpty)
        // The field set is closed: no payload, digest, length or identity slot
        // can be added without this assertion failing.
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let fields = Set(try #require(object as? [String: Any]).keys)
        #expect(fields == ["event", "uptime", "sequence", "changeCount", "queueDepth", "sourceApp"])
        #expect(!json.contains("image:"))
        #expect(!json.lowercased().contains("hash"))

        let disabled = ImagePipelineHarness(capacity: 2, diagnosticsEnabled: false)
        disabled.capture(ImagePipelineFixture.redImage())
        await disabled.encoder.waitForStart(reaching: 1)
        disabled.capture(ImagePipelineFixture.greenImage())
        disabled.capture(ImagePipelineFixture.blueImage())

        #expect(disabled.overflowEvents.isEmpty, "overflow diagnostics stay default off")
        await enabled.drain(through: 2)
        await disabled.drain(through: 2)
    }

    @Test func productionCapacityRetainsActiveAndTheThreeNewestWaitingCaptures() async throws {
        let harness = ImagePipelineHarness(capacity: 4)
        let images = [
            ImagePipelineFixture.redImage(),
            ImagePipelineFixture.greenImage(),
            ImagePipelineFixture.blueImage(),
            ImagePipelineFixture.amberImage(),
            ImagePipelineFixture.violetImage()
        ]
        var blobIDs: [String] = []
        for image in images {
            blobIDs.append(try await ImagePipelineFixture.blobID(of: image))
        }

        for image in images {
            harness.capture(image)
        }
        await harness.encoder.waitForStart(reaching: 1)

        #expect(harness.store.pendingImageCaptureCount == 4, "buffered captures never exceed four")
        await harness.drain(through: 4)

        #expect(harness.store.items.map(\.imageBlobID) == [blobIDs[4], blobIDs[3], blobIDs[2], blobIDs[0]])
        #expect(harness.encoder.peakConcurrency == 1)
    }

}

extension ClipboardImageEncodingPipelineTests {
    // MARK: - Lifecycle invalidation

    @Test func clearingHistoryInvalidatesActiveAndWaitingCaptures() async {
        let harness = ImagePipelineHarness(capacity: 3)

        harness.capture(ImagePipelineFixture.redImage())
        await harness.encoder.waitForStart(reaching: 1)
        harness.capture(ImagePipelineFixture.greenImage())
        harness.capture(ImagePipelineFixture.blueImage())
        #expect(harness.store.pendingImageCaptureCount == 3)

        harness.store.clearHistory(includePinnedAndPinboardItems: false)

        #expect(harness.store.pendingImageCaptureCount == 1, "waiting captures are dropped at once")
        #expect(harness.encoder.startCount == 1)

        harness.encoder.releaseAll()
        await harness.waitForHandled(1)

        #expect(harness.store.items.isEmpty, "an invalidated capture cannot repopulate history")
        #expect(harness.savedCount == 0, "an invalidated completion requests no save")
    }

    @Test func clearingEmptyHistoryStillInvalidatesPendingCapturesWithoutSaving() async {
        let harness = ImagePipelineHarness(capacity: 2)
        harness.capture(ImagePipelineFixture.redImage())
        await harness.encoder.waitForStart(reaching: 1)

        #expect(harness.store.clearHistory(includePinnedAndPinboardItems: false) == 0)
        harness.encoder.releaseAll()
        await harness.waitForHandled(1)

        #expect(harness.store.items.isEmpty)
        #expect(harness.savedCount == 0, "a no-op clear requests no history save")
    }

    @Test func clearingProtectedOnlyHistoryInvalidatesWithoutSaving() async throws {
        let harness = ImagePipelineHarness(capacity: 2)
        let pinned = ClipboardItem(
            id: UUID(),
            kind: .text,
            title: "pinned",
            preview: "pinned",
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(),
            isPinned: true,
            pinboardName: nil,
            textValue: "pinned",
            fileURLs: [],
            imageData: nil
        )
        harness.store.add(pinned)
        let savesAfterAdd = harness.savedCount

        harness.capture(ImagePipelineFixture.redImage())
        await harness.encoder.waitForStart(reaching: 1)

        #expect(harness.store.clearHistory(includePinnedAndPinboardItems: false) == 0)
        harness.encoder.releaseAll()
        await harness.waitForHandled(1)

        #expect(harness.store.items.map(\.id) == [pinned.id], "protected cards and their selection survive")
        #expect(harness.store.selectedID == pinned.id, "a no-op clear leaves the visible selection alone")
        #expect(harness.savedCount == savesAfterAdd, "no history save is requested solely for invalidation")
    }

    @Test func newCaptureAfterClearWaitsForTheInvalidatedEncoderToFinish() async throws {
        let harness = ImagePipelineHarness(capacity: 3)
        let old = ImagePipelineFixture.redImage()
        let new = ImagePipelineFixture.greenImage()
        let newID = try await ImagePipelineFixture.blobID(of: new)

        harness.capture(old)
        await harness.encoder.waitForStart(reaching: 1)
        harness.store.clearHistory(includePinnedAndPinboardItems: false)

        harness.capture(new)
        #expect(harness.encoder.startCount == 1, "the new capture waits for the invalidated encoder")
        #expect(harness.store.pendingImageCaptureCount == 2)

        await harness.drain(through: 2)

        #expect(harness.store.items.map(\.imageBlobID) == [newID])
        #expect(harness.encoder.peakConcurrency == 1, "invalidated work never overlaps a new encoder")
    }

    @Test func stoppingMonitoringInvalidatesWithoutFreeingThePhysicalSlot() async throws {
        let harness = ImagePipelineHarness(capacity: 3)
        let old = ImagePipelineFixture.redImage()
        let new = ImagePipelineFixture.greenImage()
        let newID = try await ImagePipelineFixture.blobID(of: new)

        harness.capture(old)
        await harness.encoder.waitForStart(reaching: 1)

        harness.store.stopMonitoring()
        harness.capture(new)

        #expect(harness.encoder.startCount == 1, "restart does not erase the old physical slot")
        #expect(harness.store.pendingImageCaptureCount == 2)

        await harness.drain(through: 2)

        #expect(harness.store.items.map(\.imageBlobID) == [newID], "the old capture cannot insert")
        #expect(harness.savedCount == 1)
    }

    @Test func repeatedInvalidationAndOverflowKeepOneEncoderAndStayInsideCapacity() async throws {
        let harness = ImagePipelineHarness(capacity: 2)
        let images = [
            ImagePipelineFixture.redImage(),
            ImagePipelineFixture.greenImage(),
            ImagePipelineFixture.blueImage(),
            ImagePipelineFixture.amberImage()
        ]
        let survivorID = try await ImagePipelineFixture.blobID(of: images[3])

        harness.capture(images[0])
        await harness.encoder.waitForStart(reaching: 1)
        harness.capture(images[1])
        harness.store.clearHistory(includePinnedAndPinboardItems: false)
        harness.store.stopMonitoring()
        harness.store.clearHistory(includePinnedAndPinboardItems: false)

        harness.store.startMonitoring()
        defer { harness.store.stopMonitoring() }
        for image in images[2...] {
            harness.capture(image)
        }

        #expect(harness.store.pendingImageCaptureCount == 2)
        #expect(harness.encoder.startCount == 1)

        harness.encoder.releaseOldest()
        await harness.waitForHandled(1)
        await harness.encoder.waitForStart(reaching: 2)
        harness.encoder.releaseOldest()
        await harness.waitForHandled(2)

        #expect(harness.encoder.peakConcurrency == 1, "repeated invalidation never overlaps encoders")
        #expect(harness.store.items.map(\.imageBlobID) == [survivorID])
    }

    @Test func nilInvalidatedCompletionReleasesItsSlotAndAllowsNewCapture() async throws {
        let harness = ImagePipelineHarness(capacity: 2)
        harness.encoder.failRequest(at: 0)
        harness.capture(ImagePipelineFixture.redImage())
        await harness.encoder.waitForStart(reaching: 1)
        harness.store.stopMonitoring()
        harness.capture(ImagePipelineFixture.greenImage())

        harness.encoder.releaseOldest()
        await harness.waitForHandled(1)
        #expect(harness.savedCount == 0)
        #expect(harness.store.items.isEmpty)
        await harness.encoder.waitForStart(reaching: 2)
        harness.encoder.releaseOldest()
        await harness.waitForHandled(2)

        #expect(harness.savedCount == 1)
        #expect(harness.store.items.count == 1)
        #expect(harness.encoder.peakConcurrency == 1)
        #expect(!harness.store.hasPendingImageCapture)
    }

    @Test func invalidatedEncoderReleasingItsSlotCannotClearNewerRequestState() async throws {
        let harness = ImagePipelineHarness(capacity: 3)
        harness.capture(ImagePipelineFixture.redImage())
        await harness.encoder.waitForStart(reaching: 1)

        harness.store.clearHistory(includePinnedAndPinboardItems: false)
        harness.capture(ImagePipelineFixture.greenImage())

        harness.encoder.releaseOldest()
        await harness.waitForHandled(1)
        await harness.encoder.waitForStart(reaching: 2)

        #expect(harness.store.pendingImageCaptureCount == 1, "A's completion released only A's own slot")
        harness.encoder.releaseOldest()
        await harness.waitForHandled(2)
        #expect(harness.store.items.count == 1, "the newer request still finalizes normally")
    }

    // MARK: - Store lifetime

    @Test func aReleasedStoreIsNotUpdatedByALateCompletion() async throws {
        let encoder = ControlledImageEncoder()
        let saves = LinkPreviewCounter()
        let clock = MutableClock()
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        weak var weakStore: ClipboardStore?

        do {
            let store = ClipboardStore(
                settings: AppSettings(defaults: LinkPreviewFixture.tempDefaults("pipeline-lifetime")),
                sourceTracker: CopySourceTracker(frontmostSourceProvider: { nil }),
                initialItems: [],
                pasteboard: pasteboard,
                persistItems: { _ in saves.mark("saved") },
                uptimeProvider: { clock.now },
                fetchLinkMetadata: { _ in throw URLError(.unsupportedURL) },
                fetchLinkSnapshot: { _ in throw URLError(.unsupportedURL) },
                encodeImage: { cgImage, recorder in
                    await encoder.encode(cgImage, recorder: recorder)
                }
            )
            weakStore = store
            pasteboard.clearContents()
            #expect(pasteboard.writeObjects([ImagePipelineFixture.redImage()]))
            store.pollPasteboard()
            clock.advance(by: 1)
            store.pollPasteboard()
            await encoder.waitForStart(reaching: 1)
        }

        #expect(weakStore == nil, "pending encoding must not strongly retain the Store")
        encoder.releaseAll()
        await encoder.waitForFinish(reaching: 1)
        #expect(saves.value("saved") == 0, "a released Store is never updated by its late completion")
    }

    // MARK: - Duplicate compatibility

    @Test func recopyingAnUnpinnedImageMovesTheExistingCardInsteadOfAddingOne() async throws {
        let harness = ImagePipelineHarness(capacity: 3)
        let image = ImagePipelineFixture.redImage()
        let blobID = try await ImagePipelineFixture.blobID(of: image)

        harness.capture(image)
        await harness.encoder.waitForStart(reaching: 1)
        await harness.drain(through: 1)
        let original = try #require(harness.store.items.first)
        #expect(original.sourceApp == "Tests")

        harness.sourceBox.source = ClipboardSource(appName: "Later", iconData: nil, capturedAt: Date())
        harness.capture(image)
        await harness.encoder.waitForStart(reaching: 2)
        await harness.drain(through: 2)

        #expect(harness.store.items.count == 1, "an unpinned duplicate keeps exactly one card")
        let moved = try #require(harness.store.items.first)
        #expect(moved.id == original.id, "the existing card identity survives the recopy")
        #expect(moved.createdAt == original.createdAt)
        #expect(moved.sourceApp == "Tests", "preserved metadata is not rewritten by a recopy")
        #expect(moved.imageBlobID == blobID)
        #expect(harness.store.selectedID == original.id, "the moved duplicate is what gets selected")
    }

    @Test func recopyingAPinnedImageAddsANewCardAboveIt() async throws {
        let harness = ImagePipelineHarness(capacity: 3)
        let image = ImagePipelineFixture.redImage()
        let blobID = try await ImagePipelineFixture.blobID(of: image)

        harness.capture(image)
        await harness.encoder.waitForStart(reaching: 1)
        await harness.drain(through: 1)
        let pinned = try #require(harness.store.items.first)
        harness.store.togglePin(pinned)

        harness.sourceBox.source = ClipboardSource(appName: "Later", iconData: nil, capturedAt: Date())
        harness.capture(image)
        await harness.encoder.waitForStart(reaching: 2)
        await harness.drain(through: 2)

        #expect(harness.store.items.count == 2, "a pinned duplicate keeps both cards")
        let head = try #require(harness.store.items.first)
        let retained = try #require(harness.store.items.last)
        #expect(head.id != retained.id)
        #expect(!head.isPinned)
        #expect(head.sourceApp == "Later", "the new card uses its own admission-time source")
        #expect(head.imageBlobID == blobID)
        #expect(retained.id == pinned.id && retained.isPinned)
        #expect(harness.store.selectedID == head.id, "the newly retained copy is what gets selected")
    }

    // MARK: - Ignored sources

    @Test func ignoredSourceImageIsRejectedBeforeBuffering() async throws {
        let allowedID = try await ImagePipelineFixture.blobID(of: ImagePipelineFixture.greenImage())
        let harness = ImagePipelineHarness(
            capacity: 2,
            ignoredApplications: "PasswordManager\n  SecretApp  \n",
            source: ClipboardSource(appName: "PasswordManager", iconData: nil, capturedAt: Date())
        )

        harness.capture(ImagePipelineFixture.redImage())

        #expect(harness.store.pendingImageCaptureCount == 0, "an ignored image is never buffered")
        #expect(harness.encoder.startCount == 0, "an ignored image starts no capture encoding")
        #expect(harness.store.items.isEmpty)
        #expect(harness.savedCount == 0)

        // A padded configured line still matches: existing trimming is unchanged.
        harness.sourceBox.source = ClipboardSource(appName: "SecretApp", iconData: nil, capturedAt: Date())
        harness.capture(ImagePipelineFixture.blueImage())

        #expect(harness.store.pendingImageCaptureCount == 0, "configured entries are trimmed before matching")
        #expect(harness.encoder.startCount == 0)

        harness.sourceBox.source = ClipboardSource(appName: "Preview", iconData: nil, capturedAt: Date())
        harness.capture(ImagePipelineFixture.greenImage())
        await harness.encoder.waitForStart(reaching: 1)
        harness.encoder.releaseAll()
        await harness.waitForHandled(1)

        #expect(harness.store.items.map(\.imageBlobID) == [allowedID], "an allowed image still captures")
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}