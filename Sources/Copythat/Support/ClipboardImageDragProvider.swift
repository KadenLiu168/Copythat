import AppKit
import Foundation
import UniformTypeIdentifiers

enum ClipboardImageDragError: Error {
    case undecodableImage
}

/// Builds drag representations for history items. Resident bytes use the
/// existing `NSImage` provider; a persisted image registers an asynchronous
/// PNG representation that reads and verifies its blob only when the drag
/// consumer asks for it. Text, URL and file items keep their existing
/// providers, and an image never degrades to a text payload.
enum ClipboardImageDragProvider {
    static func provider(
        for item: ClipboardItem,
        mediaLoader: ClipboardHistoryMediaLoader
    ) -> NSItemProvider {
        if let image = item.image {
            return NSItemProvider(object: image)
        }
        guard item.kind == .image, let blobID = item.imageBlobID else {
            return NSItemProvider(object: (item.textValue ?? item.preview) as NSString)
        }
        return asyncPNGProvider(blobID: blobID, mediaLoader: mediaLoader)
    }

    private static func asyncPNGProvider(
        blobID: String,
        mediaLoader: ClipboardHistoryMediaLoader
    ) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.png.identifier,
            visibility: .all
        ) { completion in
            // Captures only the blob identity and the loader: creating the
            // provider reads nothing, and no Store or view state is retained.
            let progress = Progress(totalUnitCount: 1)
            let task = Task {
                do {
                    let data = try await mediaLoader.load(blobID: blobID)
                    try Task.checkCancellation()
                    guard !progress.isCancelled else { return }
                    guard let png = pngRepresentation(of: data) else {
                        completion(nil, ClipboardImageDragError.undecodableImage)
                        return
                    }
                    try Task.checkCancellation()
                    guard !progress.isCancelled else { return }
                    completion(png, nil)
                } catch {
                    guard !progress.isCancelled else { return }
                    completion(nil, error)
                }
            }
            progress.cancellationHandler = { task.cancel() }
            return progress
        }
        return provider
    }

    /// Verified blob bytes are normally PNG already; legacy-migrated payloads
    /// are converted through native image rendering so the representation
    /// always matches the registered `UTType.png`.
    private static func pngRepresentation(of data: Data) -> Data? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return data
        }
        guard let image = NSImage(data: data),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
