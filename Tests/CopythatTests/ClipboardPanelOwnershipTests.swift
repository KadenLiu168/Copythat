@testable import Copythat
import AppKit
import Foundation
import SwiftUI
import Testing

/// Hosted-card coverage for the real panel close/reopen ownership path: a
/// commit while visible keeps inline ownership and never swaps to a
/// placeholder, closing releases history ownership, and reopening renders
/// through the existing lazy media identity and visibility gating.
@MainActor
@Suite(.serialized)
struct ClipboardPanelOwnershipTests {
    @Test(arguments: [ClipboardKind.image, .url])
    func commitWhileVisibleKeepsInlineOwnershipAndCloseEnablesLazyReopen(kind: ClipboardKind) async throws {
        let harness = DurableReleaseHarness()
        defer { harness.cleanup() }
        let png = DurableReleaseHarness.pngBytes(size: 32)
        let media = PreparedMedia(hashing: png)
        let itemID = UUID()
        let item = kind == .image
            ? DurableReleaseHarness.imageItem(id: itemID, media: media)
            : DurableReleaseHarness.urlItem(id: itemID, linkTitle: "Example", linkImage: media)
        let store = harness.makeStore(initialItems: [item])
        store.panelDidOpen()

        let visibleState = ClipboardCardMediaState()
        let (hosting, window) = host(
            card(
                item: store.items[0],
                store: store,
                panelVisible: true,
                generation: store.panelAuthorizationGeneration,
                mediaState: visibleState
            )
        )
        defer { dismiss(window) }

        // Committing while the panel is visible owns nothing new on screen: the
        // card keeps rendering inline bytes and never shows a placeholder.
        harness.counters.reset()
        #expect(await harness.saveAndFlush(store))
        #expect(kind == .image ? store.items.first?.imageData == png : store.items.first?.linkImageData == png,
                "inline bytes stay owned while visible")
        let pending = store.pendingDurableMediaRelease[itemID]
        #expect(kind == .image ? pending?.imageBlobID == media.id : pending?.linkImageBlobID == media.id)
        #expect(!containsProgressIndicator(hosting), "no placeholder while inline bytes are owned")
        #expect(harness.counters.manifestWriteCount == 1, "committed-media handling must not save")

        // Closing the panel is the ownership boundary that releases history.
        store.panelDidClose()
        let released = try #require(store.items.first)
        #expect(released.imageData == nil && released.linkImageData == nil)
        #expect(kind == .image ? released.imageBlobID == media.id : released.linkImageBlobID == media.id)
        #expect(kind == .image ? released.hasImagePayload : released.hasLinkImagePayload,
                "the reference keeps the payload eligible")

        // Reopening renders through the existing lazy identity/visibility gating.
        store.panelDidOpen()
        let reopenedState = ClipboardCardMediaState()
        let (reopened, reopenedWindow) = host(
            card(
                item: released,
                store: store,
                panelVisible: true,
                generation: store.panelAuthorizationGeneration,
                mediaState: reopenedState
            )
        )
        defer { dismiss(reopenedWindow) }
        #expect(await waitUntil { kind == .image ? reopenedState.image != nil : reopenedState.linkImage != nil })

        let renderedImage = kind == .image ? reopenedState.image : reopenedState.linkImage
        #expect(renderedImage?.size == NSSize(width: 32, height: 32))
        #expect(!reopenedState.imageLoadFailed && !reopenedState.linkImageLoadFailed)
        #expect(store.items.first?.imageData == nil && store.items.first?.linkImageData == nil,
                "lazy rendering must not repopulate history")
        #expect(harness.counters.manifestWriteCount == 1, "lazy rendering must not save")
        _ = reopened
    }

    @Test(arguments: [ClipboardKind.image, .url])
    func realPanelCloseReleasesCommittedMediaAndRetainedPanelReopensLazily(kind: ClipboardKind) async throws {
        // Skip cache admission so only the actual panel's lazy task can cause
        // the observed disk read after close/reopen, not a test-side load.
        let harness = DurableReleaseHarness(byteBudget: 1)
        defer { harness.cleanup() }
        let media = PreparedMedia(hashing: DurableReleaseHarness.pngBytes(size: 32))
        let item = kind == .image
            ? DurableReleaseHarness.imageItem(id: UUID(), media: media)
            : DurableReleaseHarness.urlItem(id: UUID(), linkTitle: "Example", linkImage: media)
        let model = AppModel(
            historySaveCoordinator: harness.coordinator,
            pasteboard: harness.pasteboard,
            settings: harness.settings,
            initialItems: [item],
            mediaLoader: harness.loader
        )
        _ = NSApplication.shared
        let controller = PanelWindowController(model: model)
        defer { controller.close() }
        controller.show()
        let panel = try #require(controller.panel)

        harness.coordinator.requestSave(model.store.items)
        #expect(await harness.flush())
        #expect(model.store.items.first?.imageData == item.imageData)
        #expect(model.store.items.first?.linkImageData == item.linkImageData)
        #expect(harness.counters.blobReadCount == 0, "visible inline media must not be loaded")

        controller.close()
        #expect(!panel.isVisible && !model.store.panelVisible)
        #expect(model.store.items.first?.imageData == nil && model.store.items.first?.linkImageData == nil)
        #expect(model.store.filteredItems.first?.imageData == nil && model.store.filteredItems.first?.linkImageData == nil)
        #expect(model.store.pendingDurableReleaseReferences.isEmpty)

        controller.show()
        #expect(controller.panel === panel, "reopen must reuse the real retained hosting view")
        #expect(panel.isVisible && model.store.panelVisible)
        #expect(await waitUntil { harness.counters.blobReadCount >= 1 })
        #expect(harness.counters.manifestWriteCount == 1, "close/reopen must not request another save")
        #expect(model.store.items.first?.imageData == nil && model.store.items.first?.linkImageData == nil)
        #expect(model.store.activeFallback == nil, "released link media must not trigger preview refetch")
    }

    // MARK: - Hosting helpers

    private func card(
        item: ClipboardItem,
        store: ClipboardStore,
        panelVisible: Bool,
        generation: Int,
        mediaState: ClipboardCardMediaState
    ) -> ClipboardCardView {
        ClipboardCardView(
            item: item,
            pinboards: [],
            isSelected: false,
            hidesPreview: false,
            panelVisible: panelVisible,
            authorizationGeneration: generation,
            mediaLoader: store.mediaLoader,
            store: store,
            mediaState: mediaState,
            onSelect: {},
            onPaste: {},
            onTogglePin: {},
            onMoveToPinboard: { _ in },
            onDelete: {}
        )
    }

    private func host(_ view: ClipboardCardView) -> (NSHostingView<ClipboardCardView>, NSWindow) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: CGSize(width: 236, height: 236))
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

    private func dismiss(_ window: NSWindow) {
        window.orderOut(nil)
        window.contentView = nil
    }

    private func containsProgressIndicator(_ view: NSView) -> Bool {
        if view is NSProgressIndicator { return true }
        return view.subviews.contains(where: containsProgressIndicator)
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return condition()
    }
}
