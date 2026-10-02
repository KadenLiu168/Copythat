import AppKit
import Foundation

// Paste-time media materialization. It reads the shared on-demand loader and
// hands the model a temporary copy, so it touches no history state and needs no
// access beyond the Store's own internal media loader.
extension ClipboardStore {
    /// Returns an item ready for the existing pasteboard write path. Items
    /// without persisted heavy media — text, URL, file, and items whose bytes
    /// are already resident — return unchanged, so their path stays
    /// synchronous. A persisted image is materialized into a temporary copy
    /// that carries verified bytes and never mutates history.
    func materializedItemForPaste(_ item: ClipboardItem) async throws -> ClipboardItem {
        guard item.kind == .image,
              item.imageData == nil,
              let blobID = item.imageBlobID else {
            return item
        }
        let data = try await mediaLoader.load(blobID: blobID)
        guard NSImage(data: data) != nil else {
            throw ClipboardPasteMaterializationError.undecodableImage
        }
        // The verified bytes and the address they were loaded by are handed to
        // the model together, so the temporary copy keeps the item's identity
        // and the Store never writes media fields itself.
        return item.materializedForPaste(PreparedMedia(data: data, id: blobID))
    }
}
