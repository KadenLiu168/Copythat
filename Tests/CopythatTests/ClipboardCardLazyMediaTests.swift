@testable import Copythat
import AppKit
import CryptoKit
import SwiftUI
import Testing
import UniformTypeIdentifiers

private final class MediaReadRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var blobNames: [String] = []
    private var firstReadStarted: DispatchSemaphore?
    private var firstReadGate: DispatchSemaphore?
    private var didBlockFirstRead = false
    private var countWaiters: [(threshold: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(blockFirstRead: Bool = false) {
        if blockFirstRead {
            firstReadStarted = DispatchSemaphore(value: 0)
            firstReadGate = DispatchSemaphore(value: 0)
        }
    }

    func read(_ url: URL) throws -> Data {
        lock.lock()
        blobNames.append(url.lastPathComponent)
        let shouldBlock = !didBlockFirstRead && firstReadGate != nil
        if shouldBlock {
            didBlockFirstRead = true
        }
        let started = firstReadStarted
        let gate = firstReadGate
        let reached = countWaiters.filter { blobNames.count >= $0.threshold }
        countWaiters.removeAll { blobNames.count >= $0.threshold }
        lock.unlock()
        reached.forEach { $0.continuation.resume() }

        if shouldBlock, let started, let gate {
            started.signal()
            _ = gate.wait(timeout: .now() + 5)
        }
        return try Data(contentsOf: url)
    }

    func waitForFirstRead() async {
        guard let firstReadStarted else { return }
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                _ = firstReadStarted.wait(timeout: .now() + 5)
                continuation.resume()
            }
        }
    }

    func releaseFirstRead() {
        firstReadGate?.signal()
    }

    func waitForReads(reaching threshold: Int) async {
        lock.lock()
        if blobNames.count >= threshold {
            lock.unlock()
            return
        }
        lock.unlock()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if blobNames.count >= threshold {
                lock.unlock()
                continuation.resume()
                return
            }
            countWaiters.append((threshold: threshold, continuation: continuation))
            lock.unlock()
        }
    }

    func readCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return blobNames.count
    }

    func readNames() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return blobNames
    }
}

@MainActor
@Suite(.serialized)
struct ClipboardCardLazyMediaTests {
    // MARK: - Visible / hidden eligibility
    @Test func visibleImageCardLoadsMediaAndSwapsPlaceholderForContent() async throws {
        let fixture = try CardMediaFixture()
        defer { fixture.cleanUp() }
        let bytes = try #require(CardMediaFixture.imagePNG(red: true))
        let blobID = fixture.writeBlob(bytes)

        let state = ClipboardCardMediaState()
        let store = fixture.makeStore(items: [fixture.imageItem(blobID: blobID)])
        store.panelDidOpen()
        let (hosting, window) = fixture.host(
            fixture.card(
                item: store.items[0],
                store: store,
                panelVisible: true,
                authorizationGeneration: store.panelAuthorizationGeneration,
                mediaState: state
            )
        )
        defer { fixture.dismiss(window) }
        await fixture.waitUntil { state.image != nil }
        await fixture.waitUntil { !fixture.containsProgressIndicator(hosting) }
        #expect(state.image != nil)
        #expect(!state.imageLoadFailed)
        #expect(hosting.fittingSize == NSSize(width: 236, height: 236))
        #expect(!fixture.containsProgressIndicator(hosting))

        AcceptanceMetrics.record(
            scenario: "card-lazy-media",
            metric: "mediaReadsForVisibleCard",
            expected: "1",
            observed: "\(fixture.reader.readCount())"
        )
        AcceptanceMetrics.record(
            scenario: "card-lazy-media",
            metric: "cardLayoutSize",
            expected: "236x236",
            observed: "\(Int(hosting.fittingSize.width))x\(Int(hosting.fittingSize.height))"
        )
    }
    @Test func pendingImageCardShowsPlaceholderInsideTheCardGeometry() async throws {
        let fixture = try CardMediaFixture(blockFirstRead: true)
        defer { fixture.cleanUp() }
        let bytes = try #require(CardMediaFixture.imagePNG(red: false))
        let blobID = fixture.writeBlob(bytes)

        let state = ClipboardCardMediaState()
        let store = fixture.makeStore(items: [fixture.imageItem(blobID: blobID)])
        store.panelDidOpen()
        let (hosting, window) = fixture.host(
            fixture.card(
                item: store.items[0],
                store: store,
                panelVisible: true,
                authorizationGeneration: store.panelAuthorizationGeneration,
                mediaState: state
            )
        )
        defer { fixture.dismiss(window) }
        await fixture.reader.waitForFirstRead()
        await fixture.waitUntil { fixture.containsProgressIndicator(hosting) }
        #expect(fixture.containsProgressIndicator(hosting))
        #expect(state.image == nil)
        #expect(hosting.fittingSize == NSSize(width: 236, height: 236))

        fixture.reader.releaseFirstRead()
        await fixture.waitUntil { state.image != nil }
        await fixture.waitUntil { !fixture.containsProgressIndicator(hosting) }
        #expect(state.image != nil)
        #expect(!fixture.containsProgressIndicator(hosting))
    }
    @Test func hiddenPanelAndHiddenPreviewsNeverStartReads() async throws {
        let fixture = try CardMediaFixture()
        defer { fixture.cleanUp() }
        let bytes = try #require(CardMediaFixture.imagePNG(red: true))
        let blobID = fixture.writeBlob(bytes)

        let hiddenPanelState = ClipboardCardMediaState()
        let store = fixture.makeStore(items: [fixture.imageItem(blobID: blobID)])
        let (hiddenPanelHosting, hiddenWindow) = fixture.host(
            fixture.card(
                item: store.items[0],
                store: store,
                panelVisible: false,
                authorizationGeneration: store.panelAuthorizationGeneration,
                mediaState: hiddenPanelState
            )
        )
        defer { fixture.dismiss(hiddenWindow) }

        let hiddenPreviewState = ClipboardCardMediaState()
        let (hiddenPreviewHosting, previewWindow) = fixture.host(
            fixture.card(
                item: store.items[0],
                store: store,
                panelVisible: true,
                hidesPreview: true,
                authorizationGeneration: store.panelAuthorizationGeneration,
                mediaState: hiddenPreviewState
            )
        )
        defer { fixture.dismiss(previewWindow) }
        await fixture.settle()
        #expect(fixture.reader.readCount() == 0)
        #expect(hiddenPanelState.image == nil)
        #expect(hiddenPreviewState.image == nil)
        #expect(hiddenPanelHosting.fittingSize == NSSize(width: 236, height: 236))
        #expect(hiddenPreviewHosting.fittingSize == NSSize(width: 236, height: 236))

        AcceptanceMetrics.record(
            scenario: "card-lazy-media",
            metric: "mediaReadsWhileHiddenOrConcealed",
            expected: "0",
            observed: "\(fixture.reader.readCount())"
        )
    }
    @Test func urlCardReservesThePreviewRegionBeforeCompletion() async throws {
        let fixture = try CardMediaFixture(blockFirstRead: true)
        defer { fixture.cleanUp() }
        let bytes = try #require(CardMediaFixture.imagePNG(red: false))
        let blobID = fixture.writeBlob(bytes)

        let state = ClipboardCardMediaState()
        let store = fixture.makeStore(items: [fixture.urlItem(blobID: blobID)])
        store.panelDidOpen()
        let (hosting, window) = fixture.host(
            fixture.card(
                item: store.items[0],
                store: store,
                panelVisible: true,
                authorizationGeneration: store.panelAuthorizationGeneration,
                mediaState: state
            )
        )
        defer { fixture.dismiss(window) }
        await fixture.reader.waitForFirstRead()
        await fixture.waitUntil { fixture.containsProgressIndicator(hosting) }

        // The 105pt region sits directly below the 52pt header, so the pending
        // indicator centers inside it while the card keeps its geometry.
        let indicator = try #require(fixture.firstProgressIndicator(hosting))
        let center = indicator.convert(
            NSPoint(x: indicator.bounds.midX, y: indicator.bounds.midY),
            to: hosting
        )
        #expect(center.y > 236 - 157)
        #expect(center.y < 236 - 52)
        #expect(hosting.fittingSize == NSSize(width: 236, height: 236))
        AcceptanceMetrics.record(
            scenario: "card-lazy-media",
            metric: "pendingIndicatorInsidePreviewRegion",
            expected: "true",
            observed: "\(center.y > 236 - 157 && center.y < 236 - 52)"
        )
        AcceptanceMetrics.record(
            scenario: "card-lazy-media",
            metric: "urlCardLayoutSizeWhilePending",
            expected: "236x236",
            observed: "\(Int(hosting.fittingSize.width))x\(Int(hosting.fittingSize.height))"
        )

        fixture.reader.releaseFirstRead()
        await fixture.waitUntil { state.linkImage != nil }
        await fixture.waitUntil { !fixture.containsProgressIndicator(hosting) }
        #expect(state.linkImage != nil)
        #expect(!fixture.containsProgressIndicator(hosting))
        #expect(hosting.fittingSize == NSSize(width: 236, height: 236))
    }
    @Test func failedLinkPreviewSwitchesToStableFallbackWithoutSpinner() async throws {
        let fixture = try CardMediaFixture()
        defer { fixture.cleanUp() }
        // The reference names no stored blob, so access fails locally.
        let missingBlobID = CardMediaFixture.sha256Hex(Data(repeating: 0x77, count: 64))

        let state = ClipboardCardMediaState()
        let store = fixture.makeStore(items: [fixture.urlItem(blobID: missingBlobID)])
        store.panelDidOpen()
        let (hosting, window) = fixture.host(
            fixture.card(
                item: store.items[0],
                store: store,
                panelVisible: true,
                authorizationGeneration: store.panelAuthorizationGeneration,
                mediaState: state
            )
        )
        defer { fixture.dismiss(window) }
        await fixture.waitUntil { state.linkImageLoadFailed }
        await fixture.waitUntil { !fixture.containsProgressIndicator(hosting) }
        #expect(state.linkImage == nil)
        #expect(state.linkImageLoadFailed)
        #expect(!fixture.containsProgressIndicator(hosting))
        #expect(hosting.fittingSize == NSSize(width: 236, height: 236))
    }
    @Test func ultraWideLinkImageKeepsCardGeometryAndHeader() async throws {
        let fixture = try CardMediaFixture()
        defer { fixture.cleanUp() }
        let bytes = try #require(CardMediaFixture.wideImagePNG())
        let blobID = fixture.writeBlob(bytes)

        let state = ClipboardCardMediaState()
        let store = fixture.makeStore(items: [fixture.urlItem(blobID: blobID)])
        store.panelDidOpen()
        let (hosting, window) = fixture.host(
            fixture.card(
                item: store.items[0],
                store: store,
                panelVisible: true,
                authorizationGeneration: store.panelAuthorizationGeneration,
                mediaState: state
            )
        )
        defer { fixture.dismiss(window) }
        await fixture.waitUntil { state.linkImage != nil }
        await fixture.waitUntil { !fixture.containsProgressIndicator(hosting) }
        #expect(hosting.fittingSize == NSSize(width: 236, height: 236))
        #expect(!fixture.containsProgressIndicator(hosting))
    }

}

@MainActor
extension ClipboardCardLazyMediaTests {
    // MARK: - Late completion rejection
    @Test func closeReopenWithoutIntermediateRenderRejectsTheLateCompletion() async throws {
        let fixture = try CardMediaFixture(blockFirstRead: true)
        defer { fixture.cleanUp() }
        let bytes = try #require(CardMediaFixture.imagePNG(red: true))
        let blobID = fixture.writeBlob(bytes)

        let state = ClipboardCardMediaState()
        let store = fixture.makeStore(items: [fixture.imageItem(blobID: blobID)])
        store.panelDidOpen()
        let generation = store.panelAuthorizationGeneration
        let (hosting, window) = fixture.host(
            fixture.card(
                item: store.items[0],
                store: store,
                panelVisible: true,
                authorizationGeneration: generation,
                mediaState: state
            )
        )
        defer { fixture.dismiss(window) }
        await fixture.reader.waitForFirstRead()

        // Close and reopen in one synchronous step: SwiftUI never renders the
        // hidden state, yet the newer generation must still win.
        store.panelDidClose()
        store.panelDidOpen()
        #expect(store.panelAuthorizationGeneration > generation)

        fixture.reader.releaseFirstRead()
        await fixture.settle()
        #expect(state.image == nil)
        #expect(fixture.reader.readCount() == 1)
        _ = hosting
    }
    @Test func replacedReferenceOnTheSameCardRejectsThePriorCompletion() async throws {
        let fixture = try CardMediaFixture(blockFirstRead: true)
        defer { fixture.cleanUp() }
        let firstBytes = try #require(CardMediaFixture.imagePNG(red: true))
        let secondBytes = try #require(CardMediaFixture.imagePNG(red: false))
        let firstBlobID = fixture.writeBlob(firstBytes)
        let secondBlobID = fixture.writeBlob(secondBytes)
        let itemID = UUID()

        let state = ClipboardCardMediaState()
        let store = fixture.makeStore(items: [
            fixture.imageItem(id: itemID, blobID: firstBlobID)
        ])
        store.panelDidOpen()
        let (hosting, window) = fixture.host(
            EquatableCardHost(
                card: fixture.card(
                    item: store.items[0],
                    store: store,
                    panelVisible: true,
                    authorizationGeneration: store.panelAuthorizationGeneration,
                    mediaState: state
                )
            )
        )
        defer { fixture.dismiss(window) }
        await fixture.reader.waitForFirstRead()

        // Same item ID, different media reference: the identity change must
        // invalidate the first request.
        hosting.rootView = EquatableCardHost(
            card: fixture.card(
                item: fixture.imageItem(id: itemID, blobID: secondBlobID),
                store: store,
                panelVisible: true,
                authorizationGeneration: store.panelAuthorizationGeneration,
                mediaState: state
            )
        )
        // Let the reference replacement supersede the pending request before the
        // superseded read is released: the loader serializes reads, so which of
        // the two wins an update cycle must not decide the outcome.
        await fixture.settle()
        fixture.reader.releaseFirstRead()
        await fixture.waitUntil { state.image != nil }

        let displayed = try #require(state.image)
        #expect(fixture.centerIsRed(displayed) == false)
        #expect(fixture.reader.readCount() >= 2)
    }
    @Test func cardRemovalRejectsThePendingCompletion() async throws {
        let fixture = try CardMediaFixture(blockFirstRead: true)
        defer { fixture.cleanUp() }
        let bytes = try #require(CardMediaFixture.imagePNG(red: true))
        let blobID = fixture.writeBlob(bytes)

        let state = ClipboardCardMediaState()
        let store = fixture.makeStore(items: [fixture.imageItem(blobID: blobID)])
        store.panelDidOpen()
        let card = fixture.card(
            item: store.items[0],
            store: store,
            panelVisible: true,
            authorizationGeneration: store.panelAuthorizationGeneration,
            mediaState: state
        )
        let (hosting, window) = fixture.host(ConditionalCardHost(showsCard: true, card: card))
        defer { fixture.dismiss(window) }
        await fixture.reader.waitForFirstRead()

        // The card leaves the display path (filter out or eviction) and its
        // completion arrives afterwards.
        hosting.rootView = ConditionalCardHost(showsCard: false, card: card)
        await fixture.settle()
        fixture.reader.releaseFirstRead()
        await fixture.settle()
        #expect(state.image == nil)

        // Returning under the same eligibility starts a fresh request that the
        // shared cache can satisfy.
        hosting.rootView = ConditionalCardHost(showsCard: true, card: card)
        await fixture.waitUntil { state.image != nil }
        #expect(state.image != nil)
    }
    @Test func disappearingLoadedCardReleasesItsDecodedMedia() async throws {
        let fixture = try CardMediaFixture()
        defer { fixture.cleanUp() }
        let bytes = try #require(CardMediaFixture.imagePNG(red: true))
        let blobID = fixture.writeBlob(bytes)
        let state = ClipboardCardMediaState()
        let store = fixture.makeStore(items: [fixture.imageItem(blobID: blobID)])
        store.panelDidOpen()
        let card = fixture.card(
            item: store.items[0], store: store, panelVisible: true,
            authorizationGeneration: store.panelAuthorizationGeneration, mediaState: state
        )
        let (hosting, window) = fixture.host(ConditionalCardHost(showsCard: true, card: card))
        defer { fixture.dismiss(window) }
        await fixture.waitUntil { state.image != nil }
        #expect(state.image != nil)

        hosting.rootView = ConditionalCardHost(showsCard: false, card: card)
        await fixture.waitUntil { state.image == nil }
        #expect(state.image == nil)
    }
    @Test func inlineBytesReplacementOnTheSameCardRejectsThePriorCompletion() async throws {
        let fixture = try CardMediaFixture(blockFirstRead: true)
        defer { fixture.cleanUp() }
        let bytes = try #require(CardMediaFixture.imagePNG(red: true))
        let blobID = fixture.writeBlob(bytes)
        let inlineBytes = try #require(CardMediaFixture.imagePNG(red: false))
        let itemID = UUID()

        let state = ClipboardCardMediaState()
        let store = fixture.makeStore(items: [fixture.imageItem(id: itemID, blobID: blobID)])
        store.panelDidOpen()
        let (hosting, window) = fixture.host(
            EquatableCardHost(
                card: fixture.card(
                    item: store.items[0],
                    store: store,
                    panelVisible: true,
                    authorizationGeneration: store.panelAuthorizationGeneration,
                    mediaState: state
                )
            )
        )
        defer { fixture.dismiss(window) }
        await fixture.reader.waitForFirstRead()

        // Same item ID, but the persisted reference is replaced by resident
        // bytes, so the earlier request can no longer apply.
        hosting.rootView = EquatableCardHost(
            card: fixture.card(
                item: fixture.imageItem(id: itemID, inlineData: inlineBytes),
                store: store,
                panelVisible: true,
                authorizationGeneration: store.panelAuthorizationGeneration,
                mediaState: state
            )
        )
        fixture.reader.releaseFirstRead()
        await fixture.settle()
        #expect(state.image == nil)
        #expect(!state.imageLoadFailed)
    }
    @Test func residentBytesReplacedByOtherResidentBytesDisplayTheCurrentPayload() async throws {
        let fixture = try CardMediaFixture(blockFirstRead: true)
        defer { fixture.cleanUp() }
        let firstBytes = try #require(CardMediaFixture.imagePNG(red: true))
        let secondBytes = try #require(CardMediaFixture.imagePNG(red: false))
        _ = fixture.writeBlob(firstBytes)
        _ = fixture.writeBlob(secondBytes)
        let itemID = UUID()
        let residentA = fixture.imageItem(id: itemID, inlineData: firstBytes)
        let residentB = fixture.imageItem(id: itemID, inlineData: secondBytes)
        // The replacement carries a different content address, which is what
        // invalidates the display request the previous payload owned.
        #expect(residentB.imageBlobID != residentA.imageBlobID)

        let state = ClipboardCardMediaState()
        let store = fixture.makeStore(items: [residentA])
        store.panelDidOpen()
        let generation = store.panelAuthorizationGeneration
        let (hosting, window) = fixture.host(
            EquatableCardHost(
                card: fixture.card(
                    item: residentA,
                    store: store,
                    panelVisible: true,
                    authorizationGeneration: generation,
                    mediaState: state
                )
            )
        )
        defer { fixture.dismiss(window) }
        await fixture.settle()
        #expect(fixture.reader.readCount() == 0)
        #expect(state.image == nil)
        let initialColor = try #require(fixture.renderedPreviewColor(hosting))
        #expect(initialColor.redComponent > initialColor.blueComponent)

        hosting.rootView = EquatableCardHost(
            card: fixture.card(
                item: residentB,
                store: store,
                panelVisible: true,
                authorizationGeneration: generation,
                mediaState: state
            )
        )
        await fixture.settle()
        // Both payloads are resident, so the replacement is displayed from the
        // item itself: no lazy state, no blob read, no spinner.
        let replacementColor = try #require(fixture.renderedPreviewColor(hosting))
        #expect(replacementColor.blueComponent > replacementColor.redComponent)
        #expect(state.image == nil)
        #expect(!state.imageLoadFailed)
        #expect(fixture.reader.readCount() == 0)
        #expect(!fixture.containsProgressIndicator(hosting))
        #expect(hosting.fittingSize == NSSize(width: 236, height: 236))
    }
    @Test func reopenedGenerationStartsAnAuthorizedRequestForTheCurrentPayload() async throws {
        let fixture = try CardMediaFixture(blockFirstRead: true)
        defer { fixture.cleanUp() }
        let bytes = try #require(CardMediaFixture.imagePNG(red: true))
        let blobID = fixture.writeBlob(bytes)
        let item = fixture.imageItem(blobID: blobID)

        let state = ClipboardCardMediaState()
        let store = fixture.makeStore(items: [item])
        store.panelDidOpen()
        let firstGeneration = store.panelAuthorizationGeneration
        let (hosting, window) = fixture.host(
            EquatableCardHost(
                card: fixture.card(
                    item: item,
                    store: store,
                    panelVisible: true,
                    authorizationGeneration: firstGeneration,
                    mediaState: state
                )
            )
        )
        defer { fixture.dismiss(window) }
        await fixture.reader.waitForFirstRead()

        // Close and reopen without an intermediate render, then actually render
        // the reopened generation: unlike the late-completion regression, this
        // one must start a new authorized request and succeed.
        store.panelDidClose()
        store.panelDidOpen()
        let reopenedGeneration = store.panelAuthorizationGeneration
        #expect(reopenedGeneration > firstGeneration)

        hosting.rootView = EquatableCardHost(
            card: fixture.card(
                item: item,
                store: store,
                panelVisible: true,
                authorizationGeneration: reopenedGeneration,
                mediaState: state
            )
        )
        fixture.reader.releaseFirstRead()
        await fixture.waitUntil { state.image != nil }
        await fixture.waitUntil { !fixture.containsProgressIndicator(hosting) }
        #expect(state.image != nil)
        #expect(fixture.centerIsRed(try #require(state.image)))
        #expect(!state.imageLoadFailed)
        // The first read already verified these bytes, so the authorized
        // request is served from the loader cache without another disk read.
        #expect(fixture.reader.readCount() == 1)
        #expect(!fixture.containsProgressIndicator(hosting))
        #expect(hosting.fittingSize == NSSize(width: 236, height: 236))
    }
    @Test func residencyTransitionsStartNoReadsWhileThePanelIsHidden() async throws {
        let fixture = try CardMediaFixture()
        defer { fixture.cleanUp() }
        let bytes = try #require(CardMediaFixture.imagePNG(red: true))
        let blobID = fixture.writeBlob(bytes)
        let itemID = UUID()
        let residentItem = fixture.imageItem(id: itemID, inlineData: bytes)
        let referenceItem = try #require(
            residentItem.releasingResidentMedia(
                durableImageBlobID: blobID,
                durableLinkImageBlobID: nil
            )
        )

        let state = ClipboardCardMediaState()
        // A hidden panel never opened, so the card is not eligible at all.
        let store = fixture.makeStore(items: [residentItem])
        let (hosting, window) = fixture.host(
            EquatableCardHost(
                card: fixture.card(
                    item: residentItem,
                    store: store,
                    panelVisible: false,
                    authorizationGeneration: store.panelAuthorizationGeneration,
                    mediaState: state
                )
            )
        )
        defer { fixture.dismiss(window) }
        await fixture.settle()

        hosting.rootView = EquatableCardHost(
            card: fixture.card(
                item: referenceItem,
                store: store,
                panelVisible: false,
                authorizationGeneration: store.panelAuthorizationGeneration,
                mediaState: state
            )
        )
        await fixture.settle()
        #expect(fixture.reader.readCount() == 0)
        #expect(state.image == nil)

        hosting.rootView = EquatableCardHost(
            card: fixture.card(
                item: residentItem,
                store: store,
                panelVisible: false,
                authorizationGeneration: store.panelAuthorizationGeneration,
                mediaState: state
            )
        )
        await fixture.settle()
        #expect(fixture.reader.readCount() == 0)
        #expect(state.image == nil)
        #expect(!fixture.containsProgressIndicator(hosting))
        #expect(hosting.fittingSize == NSSize(width: 236, height: 236))
    }
    @Test func residencyTransitionsStartNoReadsWhilePreviewsAreConcealed() async throws {
        let fixture = try CardMediaFixture()
        defer { fixture.cleanUp() }
        let bytes = try #require(CardMediaFixture.imagePNG(red: true))
        let blobID = fixture.writeBlob(bytes)
        let itemID = UUID()
        let residentItem = fixture.imageItem(id: itemID, inlineData: bytes)
        let referenceItem = try #require(
            residentItem.releasingResidentMedia(
                durableImageBlobID: blobID,
                durableLinkImageBlobID: nil
            )
        )

        let state = ClipboardCardMediaState()
        let store = fixture.makeStore(items: [residentItem])
        store.panelDidOpen()
        let (hosting, window) = fixture.host(
            EquatableCardHost(
                card: fixture.card(
                    item: residentItem,
                    store: store,
                    panelVisible: true,
                    hidesPreview: true,
                    authorizationGeneration: store.panelAuthorizationGeneration,
                    mediaState: state
                )
            )
        )
        defer { fixture.dismiss(window) }
        await fixture.settle()

        hosting.rootView = EquatableCardHost(
            card: fixture.card(
                item: referenceItem,
                store: store,
                panelVisible: true,
                hidesPreview: true,
                authorizationGeneration: store.panelAuthorizationGeneration,
                mediaState: state
            )
        )
        await fixture.settle()
        #expect(fixture.reader.readCount() == 0)
        #expect(state.image == nil)

        hosting.rootView = EquatableCardHost(
            card: fixture.card(
                item: residentItem,
                store: store,
                panelVisible: true,
                hidesPreview: true,
                authorizationGeneration: store.panelAuthorizationGeneration,
                mediaState: state
            )
        )
        await fixture.settle()
        #expect(fixture.reader.readCount() == 0)
        #expect(state.image == nil)
        #expect(!fixture.containsProgressIndicator(hosting))
        #expect(hosting.fittingSize == NSSize(width: 236, height: 236))
    }
    @Test func scrollingHundredImagesWithPreviewsHiddenReadsNothing() async throws {
        let fixture = try CardMediaFixture()
        defer { fixture.cleanUp() }
        var items: [ClipboardItem] = []
        for index in 0..<100 {
            let bytes = try #require(CardMediaFixture.imagePNG(red: index.isMultiple(of: 2), seed: UInt8(index)))
            let blobID = fixture.writeBlob(bytes)
            items.append(fixture.imageItem(blobID: blobID))
        }

        let store = fixture.makeStore(items: items)
        let driver = CardScrollDriver()
        let (hosting, window) = fixture.host(
            CardScrollHarness(
                items: items,
                store: store,
                mediaLoader: fixture.loader,
                hidesPreview: true,
                driver: driver
            )
        )
        defer { fixture.dismiss(window) }
        await fixture.settle()

        for item in items {
            driver.target = item.id
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        await fixture.settle()
        #expect(fixture.reader.readCount() == 0)
        AcceptanceMetrics.record(
            scenario: "card-lazy-media",
            metric: "mediaReadsScrolling100WithPreviewsHidden",
            expected: "0",
            observed: "\(fixture.reader.readCount())"
        )
        _ = hosting
    }

    // MARK: - Image drag
    @Test func dragProviderCreationReadsNothingAndDeliversVerifiedPNG() async throws {
        let fixture = try CardMediaFixture()
        defer { fixture.cleanUp() }
        let bytes = try #require(CardMediaFixture.imagePNG(red: true))
        let blobID = fixture.writeBlob(bytes)
        let item = fixture.imageItem(blobID: blobID)
        let store = fixture.makeStore(items: [item])
        let card = fixture.card(
            item: item,
            store: store,
            panelVisible: true,
            authorizationGeneration: store.panelAuthorizationGeneration,
            mediaState: ClipboardCardMediaState()
        )

        let provider = card.dragProvider(for: item)
        #expect(fixture.reader.readCount() == 0, "provider creation must not read the heavy blob")

        let result = await requestPNG(from: provider)
        let data = try result.get()
        #expect(data == bytes)
        #expect(fixture.reader.readCount() == 1)
        AcceptanceMetrics.record(
            scenario: "card-lazy-media",
            metric: "dragReadsOnProviderRequest",
            expected: "1",
            observed: "\(fixture.reader.readCount())"
        )
    }
    @Test func legacyNonPNGDragPayloadIsConvertedToPNG() async throws {
        let fixture = try CardMediaFixture()
        defer { fixture.cleanUp() }
        let png = try #require(CardMediaFixture.imagePNG(red: false))
        let image = try #require(NSImage(data: png))
        let tiff = try #require(image.tiffRepresentation)
        #expect(!tiff.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        let blobID = fixture.writeBlob(tiff)
        let item = fixture.imageItem(blobID: blobID)

        let provider = ClipboardImageDragProvider.provider(for: item, mediaLoader: fixture.loader)
        let result = await requestPNG(from: provider)
        let data = try result.get()
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(NSImage(data: data) != nil)
    }
    @Test func failedDragPayloadReportsErrorWithoutTextFallback() async throws {
        let fixture = try CardMediaFixture()
        defer { fixture.cleanUp() }
        let missingID = CardMediaFixture.sha256Hex(Data(repeating: 0x31, count: 64))
        let item = fixture.imageItem(blobID: missingID)

        let provider = ClipboardImageDragProvider.provider(for: item, mediaLoader: fixture.loader)
        let result = await requestPNG(from: provider)

        guard case .failure = result else {
            Issue.record("a missing image payload must fail the drag")
            return
        }
        #expect(!provider.canLoadObject(ofClass: NSString.self), "an image must not fall back to text")
    }
    @Test func textAndFileItemsKeepTheirExistingDragProviders() async throws {
        let fixture = try CardMediaFixture()
        defer { fixture.cleanUp() }
        let store = fixture.makeStore(items: [])
        let textItem = fixture.textItem("drag text")
        let fileItem = fixture.fileItem()

        let textProvider = ClipboardImageDragProvider.provider(for: textItem, mediaLoader: fixture.loader)
        #expect(textProvider.canLoadObject(ofClass: NSString.self))

        let card = fixture.card(
            item: fileItem,
            store: store,
            panelVisible: true,
            authorizationGeneration: store.panelAuthorizationGeneration,
            mediaState: ClipboardCardMediaState()
        )
        let fileProvider = card.dragProvider(for: fileItem)
        #expect(fileProvider.canLoadObject(ofClass: NSURL.self))
        #expect(fixture.reader.readCount() == 0)
    }
    @Test func hiddenPreviewsStillAllowExplicitImageDrag() async throws {
        let fixture = try CardMediaFixture()
        defer { fixture.cleanUp() }
        let bytes = try #require(CardMediaFixture.imagePNG(red: true))
        let blobID = fixture.writeBlob(bytes)
        let item = fixture.imageItem(blobID: blobID)
        let store = fixture.makeStore(items: [item])
        let card = fixture.card(
            item: item,
            store: store,
            panelVisible: true,
            hidesPreview: true,
            authorizationGeneration: store.panelAuthorizationGeneration,
            mediaState: ClipboardCardMediaState()
        )

        let provider = card.dragProvider(for: item)
        let result = await requestPNG(from: provider)
        #expect(try result.get() == bytes)
    }

    // MARK: - Same-address residency transitions
    @Test func residentImageReleasedToItsOwnAddressLoadsThroughTheOnDemandPath() async throws {
        let fixture = try CardMediaFixture()
        defer { fixture.cleanUp() }
        let bytes = try #require(CardMediaFixture.imagePNG(red: true))
        let blobID = fixture.writeBlob(bytes)
        let itemID = UUID()
        let residentItem = fixture.imageItem(id: itemID, inlineData: bytes)
        #expect(residentItem.imageBlobID == blobID)

        let state = ClipboardCardMediaState()
        let store = fixture.makeStore(items: [residentItem])
        store.panelDidOpen()
        let generation = store.panelAuthorizationGeneration
        let (hosting, window) = fixture.host(
            EquatableCardHost(
                card: fixture.card(
                    item: residentItem,
                    store: store,
                    panelVisible: true,
                    authorizationGeneration: generation,
                    mediaState: state
                )
            )
        )
        defer { fixture.dismiss(window) }
        await fixture.settle()
        // Resident bytes are already in hand, so no read may happen yet.
        #expect(fixture.reader.readCount() == 0)
        #expect(state.image == nil)

        // The durable commit released the bytes. The address, item ID and all
        // metadata are untouched, so only residency changed.
        let referenceItem = try #require(
            residentItem.releasingResidentMedia(
                durableImageBlobID: blobID,
                durableLinkImageBlobID: nil
            )
        )
        #expect(referenceItem.imageBlobID == residentItem.imageBlobID)
        #expect(referenceItem.imageData == nil)
        #expect(referenceItem.id == residentItem.id)
        #expect(referenceItem.createdAt == residentItem.createdAt)
        #expect(referenceItem.title == residentItem.title)
        let hostingIdentity = ObjectIdentifier(hosting)
        #expect(hosting.window?.contentView === hosting)

        hosting.rootView = EquatableCardHost(
            card: fixture.card(
                item: referenceItem,
                store: store,
                panelVisible: true,
                authorizationGeneration: generation,
                mediaState: state
            )
        )
        // The update re-rendered in place: same hosting view, same item ID, same
        // metadata, same authorization generation, same injected media state.
        #expect(ObjectIdentifier(hosting) == hostingIdentity)
        #expect(hosting.window?.contentView === hosting)

        await fixture.waitUntil { state.image != nil }
        await fixture.waitUntil { !fixture.containsProgressIndicator(hosting) }
        let displayed = try #require(state.image)
        #expect(fixture.centerIsRed(displayed))
        #expect(fixture.reader.readCount() == 1)
        #expect(fixture.reader.readNames() == ["\(blobID).blob"])
        #expect(!state.imageLoadFailed)
        #expect(!fixture.containsProgressIndicator(hosting))
        #expect(hosting.fittingSize == NSSize(width: 236, height: 236))
    }
    @Test func sameAddressBecomingResidentClearsLoadedLazyMediaWithoutReadingAgain() async throws {
        let fixture = try CardMediaFixture()
        defer { fixture.cleanUp() }
        let bytes = try #require(CardMediaFixture.imagePNG(red: true))
        let blobID = fixture.writeBlob(bytes)
        let itemID = UUID()
        let referenceItem = fixture.imageItem(id: itemID, blobID: blobID)
        let residentItem = fixture.imageItem(id: itemID, inlineData: bytes)
        #expect(referenceItem.imageBlobID == residentItem.imageBlobID)

        let state = ClipboardCardMediaState()
        let store = fixture.makeStore(items: [referenceItem])
        store.panelDidOpen()
        let generation = store.panelAuthorizationGeneration
        let (hosting, window) = fixture.host(
            EquatableCardHost(
                card: fixture.card(
                    item: referenceItem,
                    store: store,
                    panelVisible: true,
                    authorizationGeneration: generation,
                    mediaState: state
                )
            )
        )
        defer { fixture.dismiss(window) }
        await fixture.waitUntil { state.image != nil }
        #expect(fixture.centerIsRed(try #require(state.image)))
        #expect(fixture.reader.readCount() == 1)

        hosting.rootView = EquatableCardHost(
            card: fixture.card(
                item: residentItem,
                store: store,
                panelVisible: true,
                authorizationGeneration: generation,
                mediaState: state
            )
        )
        await fixture.waitUntil { state.image == nil }
        // The card now displays its own bytes: the lazy state is dropped, no
        // further read runs and the card keeps its geometry without a spinner.
        #expect(state.image == nil)
        #expect(!state.imageLoadFailed)
        #expect(fixture.reader.readCount() == 1)
        #expect(!fixture.containsProgressIndicator(hosting))
        #expect(hosting.fittingSize == NSSize(width: 236, height: 236))
    }
    @Test func sameAddressBecomingResidentRejectsTheBlockedLazyCompletion() async throws {
        let fixture = try CardMediaFixture(blockFirstRead: true)
        defer { fixture.cleanUp() }
        let bytes = try #require(CardMediaFixture.imagePNG(red: true))
        let blobID = fixture.writeBlob(bytes)
        let itemID = UUID()
        let referenceItem = fixture.imageItem(id: itemID, blobID: blobID)
        let residentItem = fixture.imageItem(id: itemID, inlineData: bytes)

        let state = ClipboardCardMediaState()
        let store = fixture.makeStore(items: [referenceItem])
        store.panelDidOpen()
        let generation = store.panelAuthorizationGeneration
        let (hosting, window) = fixture.host(
            EquatableCardHost(
                card: fixture.card(
                    item: referenceItem,
                    store: store,
                    panelVisible: true,
                    authorizationGeneration: generation,
                    mediaState: state
                )
            )
        )
        defer { fixture.dismiss(window) }
        await fixture.reader.waitForFirstRead()
        #expect(state.image == nil)

        hosting.rootView = EquatableCardHost(
            card: fixture.card(
                item: residentItem,
                store: store,
                panelVisible: true,
                authorizationGeneration: generation,
                mediaState: state
            )
        )
        // Let the resident path supersede the pending request before the blocked
        // read is released, so which request wins the update cycle cannot decide
        // the outcome.
        await fixture.settle()
        fixture.reader.releaseFirstRead()
        await fixture.settle()
        #expect(state.image == nil)
        #expect(!state.imageLoadFailed)
        #expect(fixture.reader.readCount() == 1)
        #expect(!fixture.containsProgressIndicator(hosting))
        #expect(hosting.fittingSize == NSSize(width: 236, height: 236))
    }
    @Test func residentLinkImageReleasedToItsOwnAddressLoadsThroughTheOnDemandPath() async throws {
        let fixture = try CardMediaFixture(blockFirstRead: true)
        defer { fixture.cleanUp() }
        let bytes = try #require(CardMediaFixture.imagePNG(red: false))
        let blobID = fixture.writeBlob(bytes)
        let itemID = UUID()
        let residentItem = fixture.urlItem(id: itemID, inlineLinkImageData: bytes)
        #expect(residentItem.linkImageBlobID == blobID)

        let state = ClipboardCardMediaState()
        let store = fixture.makeStore(items: [residentItem])
        store.panelDidOpen()
        let generation = store.panelAuthorizationGeneration
        let (hosting, window) = fixture.host(
            EquatableCardHost(
                card: fixture.card(
                    item: residentItem,
                    store: store,
                    panelVisible: true,
                    authorizationGeneration: generation,
                    mediaState: state
                )
            )
        )
        defer { fixture.dismiss(window) }
        await fixture.settle()
        #expect(fixture.reader.readCount() == 0)
        #expect(state.linkImage == nil)

        let referenceItem = try #require(
            residentItem.releasingResidentMedia(
                durableImageBlobID: nil,
                durableLinkImageBlobID: blobID
            )
        )
        #expect(referenceItem.linkImageBlobID == residentItem.linkImageBlobID)
        #expect(referenceItem.linkImageData == nil)
        #expect(referenceItem.id == residentItem.id)

        hosting.rootView = EquatableCardHost(
            card: fixture.card(
                item: referenceItem,
                store: store,
                panelVisible: true,
                authorizationGeneration: generation,
                mediaState: state
            )
        )
        await fixture.reader.waitForFirstRead()
        await fixture.waitUntil { fixture.containsProgressIndicator(hosting) }
        // The reserved preview region keeps its place while the payload loads.
        let pending = try #require(fixture.firstProgressIndicator(hosting))
        let pendingCenter = pending.convert(
            NSPoint(x: pending.bounds.midX, y: pending.bounds.midY),
            to: hosting
        )
        #expect(pendingCenter.y > 236 - 157)
        #expect(pendingCenter.y < 236 - 52)
        #expect(hosting.fittingSize == NSSize(width: 236, height: 236))

        fixture.reader.releaseFirstRead()
        await fixture.waitUntil { state.linkImage != nil }
        await fixture.waitUntil { !fixture.containsProgressIndicator(hosting) }
        #expect(fixture.centerIsRed(try #require(state.linkImage)) == false)
        #expect(fixture.reader.readCount() == 1)
        #expect(fixture.reader.readNames() == ["\(blobID).blob"])
        #expect(!state.linkImageLoadFailed)
        #expect(!fixture.containsProgressIndicator(hosting))
        #expect(hosting.fittingSize == NSSize(width: 236, height: 236))
    }
    @Test func sameAddressLinkImageBecomingResidentClearsLoadedLazyMediaWithoutReadingAgain() async throws {
        let fixture = try CardMediaFixture()
        defer { fixture.cleanUp() }
        let bytes = try #require(CardMediaFixture.imagePNG(red: false))
        let blobID = fixture.writeBlob(bytes)
        let itemID = UUID()
        let referenceItem = fixture.urlItem(id: itemID, blobID: blobID)
        let residentItem = fixture.urlItem(id: itemID, inlineLinkImageData: bytes)
        #expect(referenceItem.linkImageBlobID == residentItem.linkImageBlobID)

        let state = ClipboardCardMediaState()
        let store = fixture.makeStore(items: [referenceItem])
        store.panelDidOpen()
        let generation = store.panelAuthorizationGeneration
        let (hosting, window) = fixture.host(
            EquatableCardHost(
                card: fixture.card(
                    item: referenceItem,
                    store: store,
                    panelVisible: true,
                    authorizationGeneration: generation,
                    mediaState: state
                )
            )
        )
        defer { fixture.dismiss(window) }
        await fixture.waitUntil { state.linkImage != nil }
        #expect(fixture.centerIsRed(try #require(state.linkImage)) == false)
        #expect(fixture.reader.readCount() == 1)

        hosting.rootView = EquatableCardHost(
            card: fixture.card(
                item: residentItem,
                store: store,
                panelVisible: true,
                authorizationGeneration: generation,
                mediaState: state
            )
        )
        await fixture.waitUntil { state.linkImage == nil }
        #expect(state.linkImage == nil)
        #expect(!state.linkImageLoadFailed)
        #expect(fixture.reader.readCount() == 1)
        #expect(!fixture.containsProgressIndicator(hosting))
        #expect(hosting.fittingSize == NSSize(width: 236, height: 236))
        let displayedColor = try #require(fixture.renderedPreviewColor(hosting))
        #expect(displayedColor.blueComponent > displayedColor.redComponent)
    }

    @Test func sameAddressBecomingResidentRejectsTheBlockedLinkImageCompletion() async throws {
        let fixture = try CardMediaFixture(blockFirstRead: true)
        defer { fixture.cleanUp() }
        let bytes = try #require(CardMediaFixture.imagePNG(red: false))
        let blobID = fixture.writeBlob(bytes)
        let itemID = UUID()
        let referenceItem = fixture.urlItem(id: itemID, blobID: blobID)
        let residentItem = fixture.urlItem(id: itemID, inlineLinkImageData: bytes)
        #expect(referenceItem.linkImageBlobID == residentItem.linkImageBlobID)

        let state = ClipboardCardMediaState()
        let store = fixture.makeStore(items: [referenceItem])
        store.panelDidOpen()
        let generation = store.panelAuthorizationGeneration
        let (hosting, window) = fixture.host(
            EquatableCardHost(
                card: fixture.card(
                    item: referenceItem,
                    store: store,
                    panelVisible: true,
                    authorizationGeneration: generation,
                    mediaState: state
                )
            )
        )
        defer { fixture.dismiss(window) }
        await fixture.reader.waitForFirstRead()
        #expect(fixture.containsProgressIndicator(hosting))

        hosting.rootView = EquatableCardHost(
            card: fixture.card(
                item: residentItem,
                store: store,
                panelVisible: true,
                authorizationGeneration: generation,
                mediaState: state
            )
        )
        await fixture.settle()
        fixture.reader.releaseFirstRead()
        await fixture.settle()
        #expect(state.linkImage == nil)
        #expect(!state.linkImageLoadFailed)
        #expect(fixture.reader.readCount() == 1)
        #expect(!fixture.containsProgressIndicator(hosting))
        #expect(hosting.fittingSize == NSSize(width: 236, height: 236))
    }

    private func requestPNG(from provider: NSItemProvider) async -> Result<Data, Error> {
        await withCheckedContinuation { continuation in
            let lock = NSLock()
            var didResume = false
            provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, error in
                lock.lock()
                let shouldResume = !didResume
                didResume = true
                lock.unlock()
                guard shouldResume else { return }
                if let data {
                    continuation.resume(returning: .success(data))
                } else {
                    continuation.resume(
                        returning: .failure(error ?? ClipboardImageDragError.undecodableImage)
                    )
                }
            }
        }
    }

    // MARK: - No history mutation
    @Test func loadingMediaDoesNotMutateHistoryOrRequestSaves() async throws {
        let fixture = try CardMediaFixture()
        defer { fixture.cleanUp() }
        let bytes = try #require(CardMediaFixture.imagePNG(red: true))
        let blobID = fixture.writeBlob(bytes)
        let item = fixture.imageItem(blobID: blobID)

        let state = ClipboardCardMediaState()
        let store = fixture.makeStore(items: [item])
        store.panelDidOpen()
        let originalItems = store.items
        let originalSelection = store.selectedID

        let (hosting, window) = fixture.host(
            fixture.card(
                item: store.items[0],
                store: store,
                panelVisible: true,
                authorizationGeneration: store.panelAuthorizationGeneration,
                mediaState: state
            )
        )
        defer { fixture.dismiss(window) }
        await fixture.waitUntil { state.image != nil }
        #expect(store.items == originalItems)
        #expect(store.items.first?.imageData == nil)
        #expect(store.items.first?.imageBlobID == blobID)
        #expect(store.selectedID == originalSelection)
        #expect(store.linkMetadataStates.isEmpty)
        #expect(fixture.saveCount() == 0)
        _ = hosting
    }
}

/// Mirrors the panel's own card wrapping, so updates are observed through real
/// `.equatable()` reconciliation. The host adds no identity of its own: replacing
/// `rootView` re-renders in place, leaving the hosting view, the card's item ID,
/// its metadata, the authorization generation and the injected `@StateObject`
/// untouched. No test here loads, releases or re-identifies media by hand.
@MainActor
private struct EquatableCardHost: View, Equatable {
    let card: ClipboardCardView

    var body: some View {
        card.equatable()
    }
}

/// Shows or removes a real card to model filter-out/in and eviction without
/// tearing down the injected media state the test observes.
@MainActor
private struct ConditionalCardHost: View {
    let showsCard: Bool
    let card: ClipboardCardView

    var body: some View {
        if showsCard {
            card
        } else {
            Color.clear.frame(width: 236, height: 236)
        }
    }
}

/// Horizontal lazy timeline mirroring the panel's own card layout, used to
/// drive real `ClipboardCardView` instances through scrolling.
@MainActor
private final class CardScrollDriver: ObservableObject {
    @Published var target: UUID?
}

@MainActor
private struct CardScrollHarness: View {
    let items: [ClipboardItem]
    let store: ClipboardStore
    let mediaLoader: ClipboardHistoryMediaLoader
    let hidesPreview: Bool
    @ObservedObject var driver: CardScrollDriver

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 28) {
                    ForEach(items) { item in
                        ClipboardCardView(
                            item: item,
                            pinboards: [],
                            isSelected: false,
                            hidesPreview: hidesPreview,
                            panelVisible: true,
                            authorizationGeneration: store.panelAuthorizationGeneration,
                            mediaLoader: mediaLoader,
                            store: store,
                            onSelect: {},
                            onPaste: {},
                            onTogglePin: {},
                            onMoveToPinboard: { _ in },
                            onDelete: {}
                        )
                        .equatable()
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 6)
                .frame(height: 258)
            }
            .scrollClipDisabled()
            .onChange(of: driver.target) { _, id in
                guard let id else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
        .frame(width: 1_120, height: 258)
    }
}

@MainActor
private final class CardMediaFixture {
    let reader: MediaReadRecorder
    let loader: ClipboardHistoryMediaLoader
    private let directory: URL
    private let defaults: UserDefaults
    private let suiteName: String
    private let saves = SaveCounter()

    init(blockFirstRead: Bool = false) throws {
        reader = MediaReadRecorder(blockFirstRead: blockFirstRead)
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CardLazyMedia-\(UUID().uuidString)", isDirectory: true)
        suiteName = "CardLazyMedia.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("history-media", isDirectory: true),
            withIntermediateDirectories: true
        )
        loader = ClipboardHistoryMediaLoader(
            blobStore: ClipboardHistoryBlobStore(
                directoryURL: directory.appendingPathComponent("history-media", isDirectory: true),
                readData: reader.read
            )
        )
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func saveCount() -> Int {
        saves.count
    }

    @discardableResult
    func writeBlob(_ data: Data) -> String {
        let blobID = Self.sha256Hex(data)
        try? data.write(
            to: directory
                .appendingPathComponent("history-media", isDirectory: true)
                .appendingPathComponent("\(blobID).blob")
        )
        return blobID
    }

    func makeStore(items: [ClipboardItem]) -> ClipboardStore {
        ClipboardStore(
            settings: AppSettings(defaults: defaults),
            sourceTracker: CopySourceTracker(),
            initialItems: items,
            pasteboard: NSPasteboard.withUniqueName(),
            mediaLoader: loader,
            persistItems: { [saves] _ in saves.record() }
        )
    }

    func imageItem(id: UUID = UUID(), blobID: String) -> ClipboardItem {
        imageItem(id: id, inlineData: nil, blobID: blobID)
    }


    func imageItem(id: UUID = UUID(), inlineData: Data?) -> ClipboardItem {
        imageItem(id: id, inlineData: inlineData, blobID: nil)
    }

    private func imageItem(id: UUID, inlineData: Data?, blobID: String?) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: .image,
            title: "Image",
            preview: "64 x 64",
            sourceApp: "Preview",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_300),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [],
            imageData: inlineData,
            imageBlobID: blobID
        )
    }

    func textItem(_ text: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .text,
            title: text,
            preview: text,
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_302),
            isPinned: false,
            pinboardName: nil,
            textValue: text,
            fileURLs: [],
            imageData: nil
        )
    }

    func fileItem() -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            kind: .file,
            title: "notes.txt",
            preview: "/tmp/notes.txt",
            sourceApp: "Finder",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_303),
            isPinned: false,
            pinboardName: nil,
            textValue: nil,
            fileURLs: [URL(fileURLWithPath: "/tmp/notes.txt")],
            imageData: nil
        )
    }

    func urlItem(id: UUID = UUID(), blobID: String) -> ClipboardItem {
        urlItem(id: id, linkImageData: nil, linkImageBlobID: blobID)
    }

    func urlItem(id: UUID = UUID(), inlineLinkImageData: Data?) -> ClipboardItem {
        urlItem(id: id, linkImageData: inlineLinkImageData, linkImageBlobID: nil)
    }

    private func urlItem(id: UUID, linkImageData: Data?, linkImageBlobID: String?) -> ClipboardItem {
        ClipboardItem(
            id: id,
            kind: .url,
            title: "Example",
            preview: "https://example.com/",
            sourceApp: "Safari",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_301),
            isPinned: false,
            pinboardName: nil,
            textValue: "https://example.com/",
            fileURLs: [],
            imageData: nil,
            linkTitle: "Example",
            linkImageData: linkImageData,
            linkImageBlobID: linkImageBlobID
        )
    }

    func card(
        item: ClipboardItem,
        store: ClipboardStore,
        panelVisible: Bool,
        hidesPreview: Bool = false,
        authorizationGeneration: Int,
        mediaState: ClipboardCardMediaState
    ) -> ClipboardCardView {
        ClipboardCardView(
            item: item,
            pinboards: [],
            isSelected: false,
            hidesPreview: hidesPreview,
            panelVisible: panelVisible,
            authorizationGeneration: authorizationGeneration,
            mediaLoader: loader,
            store: store,
            mediaState: mediaState,
            onSelect: {},
            onPaste: {},
            onTogglePin: {},
            onMoveToPinboard: { _ in },
            onDelete: {}
        )
    }

    func host<Content: View>(
        _ view: Content,
        size: CGSize = CGSize(width: 236, height: 236)
    ) -> (NSHostingView<Content>, NSWindow) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.orderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        return (hosting, window)
    }

    func dismiss(_ window: NSWindow) {
        window.orderOut(nil)
        window.contentView = nil
    }

    func containsProgressIndicator(_ view: NSView) -> Bool {
        firstProgressIndicator(view) != nil
    }

    func firstProgressIndicator(_ view: NSView) -> NSProgressIndicator? {
        allSubviews(of: view).compactMap { $0 as? NSProgressIndicator }.first
    }

    /// Sample inside both image previews and the URL's reserved image region,
    /// away from the header, captions and rounded corners.
    func renderedPreviewColor(_ hosting: NSView) -> NSColor? {
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?
            .usingColorSpace(.sRGB)
    }

    func centerIsRed(_ image: NSImage) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let color = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?
                  .usingColorSpace(.sRGB) else {
            return false
        }
        return color.redComponent > color.greenComponent
    }

    func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return condition()
    }

    func settle(iterations: Int = 12) async {
        for _ in 0..<iterations {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + allSubviews(of: $0) }
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func imagePNG(red: Bool, seed: UInt8 = 0) -> Data? {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 64,
            pixelsHigh: 64,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let color = red
            ? NSColor(calibratedRed: CGFloat(0.8 + Double(seed) / 2_550), green: 0.1, blue: 0.1, alpha: 1)
            : NSColor(calibratedRed: 0.1, green: 0.2, blue: CGFloat(0.7 + Double(seed) / 2_550), alpha: 1)
        for column in 0..<64 {
            for row in 0..<64 {
                bitmap.setColor(color, atX: column, y: row)
            }
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    static func wideImagePNG() -> Data? {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 640,
            pixelsHigh: 80,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let color = NSColor(calibratedRed: 0.2, green: 0.6, blue: 0.3, alpha: 1)
        for column in 0..<640 {
            for row in 0..<80 {
                bitmap.setColor(color, atX: column, y: row)
            }
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

private final class SaveCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func record() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
