import AppKit
import Combine
import Foundation

/// Short-lived media owned by one displayed card. Holds only the payload that
/// card currently needs and is released whenever the card leaves the eligible
/// display path, so retained cards cannot accumulate browsed images.
@MainActor
final class ClipboardCardMediaState: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var linkImage: NSImage?
    @Published private(set) var imageLoadFailed = false
    @Published private(set) var linkImageLoadFailed = false

    func release() {
        image = nil
        linkImage = nil
        imageLoadFailed = false
        linkImageLoadFailed = false
    }

    /// Loads the persisted payload this item needs, if any. A completion only
    /// applies while its task was not cancelled and the caller's authorization
    /// check still holds; the check reads live state rather than the values
    /// captured when the loading task started.
    func load(
        item: ClipboardItem,
        mediaLoader: ClipboardHistoryMediaLoader,
        isEligible: Bool,
        isAuthorized: @MainActor () -> Bool
    ) async {
        release()
        guard isEligible else { return }

        switch item.kind {
        case .image:
            guard item.imageData == nil, let blobID = item.persistedImageBlobID else { return }
            do {
                let data = try await mediaLoader.load(blobID: blobID)
                guard !Task.isCancelled, isAuthorized() else { return }
                guard let loaded = NSImage(data: data) else {
                    imageLoadFailed = true
                    return
                }
                image = loaded
            } catch {
                guard !Task.isCancelled, isAuthorized() else { return }
                imageLoadFailed = true
            }
        case .url:
            guard item.linkImageData == nil, let blobID = item.persistedLinkImageBlobID else { return }
            do {
                let data = try await mediaLoader.load(blobID: blobID)
                guard !Task.isCancelled, isAuthorized() else { return }
                guard let loaded = NSImage(data: data) else {
                    linkImageLoadFailed = true
                    return
                }
                linkImage = loaded
            } catch {
                guard !Task.isCancelled, isAuthorized() else { return }
                linkImageLoadFailed = true
            }
        case .text, .file:
            return
        }
    }
}
