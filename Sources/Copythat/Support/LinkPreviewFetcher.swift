import AppKit
import LinkPresentation
import UniformTypeIdentifiers
import WebKit

struct LinkPreviewMetadata {
    let title: String?
    let imageData: Data?
}

enum LinkPreviewFetcher {
    static func fetch(url: URL) async -> LinkPreviewMetadata? {
        let provider = LPMetadataProvider()
        provider.timeout = 8

        let metadata: LPLinkMetadata
        do {
            metadata = try await withCheckedThrowingContinuation { continuation in
                provider.startFetchingMetadata(for: url) { metadata, error in
                    if let metadata {
                        continuation.resume(returning: metadata)
                    } else {
                        continuation.resume(throwing: error ?? URLError(.badServerResponse))
                    }
                }
            }
        } catch {
            return nil
        }

        let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        var fetchedImageData = await imageData(from: metadata.imageProvider)
        if fetchedImageData == nil {
            fetchedImageData = await imageData(from: metadata.iconProvider)
        }
        if fetchedImageData == nil {
            fetchedImageData = await webSnapshotImageData(for: url)
        }
        guard title != nil || fetchedImageData != nil else { return nil }
        return LinkPreviewMetadata(title: title, imageData: fetchedImageData)
    }

    private static func imageData(from provider: NSItemProvider?) async -> Data? {
        guard let provider else { return nil }

        if provider.canLoadObject(ofClass: NSImage.self) {
            let image = await withCheckedContinuation { continuation in
                provider.loadObject(ofClass: NSImage.self) { object, _ in
                    continuation.resume(returning: object as? NSImage)
                }
            }
            return image?.pngData(maxPixel: 640)
        }

        guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            return nil
        }

        let data = await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
        guard let data, let image = NSImage(data: data) else { return nil }
        return image.pngData(maxPixel: 640)
    }

    @MainActor
    private static func webSnapshotImageData(for url: URL) async -> Data? {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 360),
            configuration: configuration
        )
        webView.load(URLRequest(url: url, timeoutInterval: 8))

        try? await Task.sleep(nanoseconds: 3_000_000_000)

        let snapshot = await withCheckedContinuation { continuation in
            let config = WKSnapshotConfiguration()
            config.rect = NSRect(x: 0, y: 0, width: 640, height: 360)
            webView.takeSnapshot(with: config) { image, _ in
                continuation.resume(returning: image)
            }
        }

        return snapshot?.pngData(maxPixel: 640)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
