import AppKit
import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var filteredItems: [ClipboardItem] = []
    @Published var selectedID: UUID?
    @Published var searchText = "" {
        didSet { refreshFilteredItems() }
    }
    @Published var selectedBoardID = Pinboard.all.id {
        didSet { refreshFilteredItems() }
    }
    @Published var permissionMessage: String?

    private let pasteboard = NSPasteboard.general
    private let settings: AppSettings
    private let sourceTracker: CopySourceTracker
    private var timer: Timer?
    private var pollTask: Task<Void, Never>?
    private var imageEncodingTask: Task<Void, Never>?
    private var lastChangeCount: Int

    init(settings: AppSettings, sourceTracker: CopySourceTracker, initialItems: [ClipboardItem]? = nil) {
        self.settings = settings
        self.sourceTracker = sourceTracker
        lastChangeCount = pasteboard.changeCount
        items = initialItems ?? ClipboardHistoryPersistence.loadItems()
        refreshFilteredItems()
    }

    var selectedItem: ClipboardItem? {
        filteredItems.first { $0.id == selectedID } ?? filteredItems.first
    }

    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pollTask?.cancel()
                self.pollTask = Task { @MainActor [weak self] in
                    guard !Task.isCancelled else { return }
                    self?.pollPasteboard()
                }
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        pollTask?.cancel()
        pollTask = nil
        imageEncodingTask?.cancel()
        imageEncodingTask = nil
    }

    func pollPasteboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        let currentChangeCount = pasteboard.changeCount
        let changeCountDelta = max(1, currentChangeCount - lastChangeCount)
        lastChangeCount = currentChangeCount
        guard let newItem = readCurrentPasteboard(
            changeCountDelta: changeCountDelta,
            currentChangeCount: currentChangeCount
        ) else { return }
        guard !ignoredApplications.contains(newItem.sourceApp) else { return }
        add(newItem)
    }

    func selectFirstVisibleItem() {
        selectID(filteredItems.first?.id)
    }

    func clearPermissionMessage() {
        permissionMessage = nil
    }

    func select(_ item: ClipboardItem) {
        selectID(item.id)
    }

    func moveSelection(_ delta: Int) {
        let visible = filteredItems
        guard !visible.isEmpty else {
            selectID(nil)
            return
        }
        let currentIndex = visible.firstIndex { $0.id == selectedID } ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), visible.count - 1)
        selectID(visible[nextIndex].id)
    }

    func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        refreshFilteredItems()
        saveItems()
    }

    func move(_ item: ClipboardItem, toPinboard name: String?) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].pinboardName = name
        refreshFilteredItems()
        saveItems()
    }

    func pinboardAssignmentCount(named name: String) -> Int {
        items.filter { $0.pinboardName == name }.count
    }

    func clearPinboardAssignments(named name: String) {
        var didChange = false
        for index in items.indices where items[index].pinboardName == name {
            items[index].pinboardName = nil
            didChange = true
        }

        guard didChange else { return }
        refreshFilteredItems()
        saveItems()
    }

    func selectClipboardIfViewingPinboard(named name: String) {
        guard selectedBoardID == Pinboard.custom(name).id else { return }
        selectedBoardID = Pinboard.all.id
    }

    func remove(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        refreshFilteredItems()
        saveItems()
    }

    @discardableResult
    func clearHistory(includePinnedAndPinboardItems: Bool) -> Int {
        let originalCount = items.count
        if includePinnedAndPinboardItems {
            items.removeAll()
        } else {
            items.removeAll { !$0.isPinned && $0.pinboardName == nil }
        }

        let removedCount = originalCount - items.count
        guard removedCount > 0 else { return 0 }
        refreshFilteredItems()
        saveItems()
        return removedCount
    }

    func writeToPasteboard(_ item: ClipboardItem) -> Bool {
        switch item.kind {
        case .text, .url:
            let string = item.textValue ?? item.preview
            guard !string.isEmpty else { return false }
            pasteboard.clearContents()
            let didWrite = pasteboard.setString(string, forType: .string)
            lastChangeCount = pasteboard.changeCount
            return didWrite
        case .file:
            let existingFileURLs = item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !existingFileURLs.isEmpty else { return false }
            pasteboard.clearContents()
            let didWrite = pasteboard.writeObjects(existingFileURLs as [NSURL])
            lastChangeCount = pasteboard.changeCount
            return didWrite
        case .image:
            guard let image = item.image else { return false }
            pasteboard.clearContents()
            let didWrite = pasteboard.writeObjects([image])
            lastChangeCount = pasteboard.changeCount
            return didWrite
        }
    }

    private var ignoredApplications: [String] {
        settings.ignoredApplications
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func add(_ item: ClipboardItem) {
        items = ClipboardHistoryPolicy.adding(item, to: items, limit: settings.historyLimit)
        refreshFilteredItems()
        selectedID = item.id
        saveItems()
        enrichLinkPreviewIfNeeded(for: item)
    }

    private func readCurrentPasteboard(changeCountDelta: Int, currentChangeCount: Int) -> ClipboardItem? {
        guard settings.recordSensitiveContent || !pasteboardContainsSensitiveContent() else {
            return nil
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            let fileURLs = urls.filter(\.isFileURL)
            if !fileURLs.isEmpty {
                let source = sourceMetadata(
                    changeCountDelta: changeCountDelta,
                    currentChangeCount: currentChangeCount
                )
                return ClipboardItem(
                    id: UUID(),
                    kind: .file,
                    title: fileURLs.count == 1 ? fileURLs[0].lastPathComponent : "\(fileURLs.count) files",
                    preview: fileURLs.map(\.path).joined(separator: "\n"),
                    sourceApp: source.appName,
                    sourceAppIconData: source.iconData,
                    createdAt: Date(),
                    isPinned: false,
                    pinboardName: nil,
                    textValue: nil,
                    fileURLs: fileURLs,
                    imageData: nil
                )
            }
        }

        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first {
            enqueueImageItem(
                image: image,
                changeCountDelta: changeCountDelta,
                currentChangeCount: currentChangeCount
            )
            return nil
        }

        guard let string = pasteboard.string(forType: .string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        if let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme) {
            let source = sourceMetadata(
                changeCountDelta: changeCountDelta,
                currentChangeCount: currentChangeCount
            )
            return ClipboardItem(
                id: UUID(),
                kind: .url,
                title: url.host(percentEncoded: false) ?? string,
                preview: string,
                sourceApp: source.appName,
                sourceAppIconData: source.iconData,
                createdAt: Date(),
                isPinned: false,
                pinboardName: nil,
                textValue: string,
                fileURLs: [],
                imageData: nil
            )
        }

        let possibleFile = URL(fileURLWithPath: string)
        if FileManager.default.fileExists(atPath: possibleFile.path) {
            let source = sourceMetadata(
                changeCountDelta: changeCountDelta,
                currentChangeCount: currentChangeCount
            )
            return ClipboardItem(
                id: UUID(),
                kind: .file,
                title: possibleFile.lastPathComponent,
                preview: possibleFile.path,
                sourceApp: source.appName,
                sourceAppIconData: source.iconData,
                createdAt: Date(),
                isPinned: false,
                pinboardName: nil,
                textValue: nil,
                fileURLs: [possibleFile],
                imageData: nil
            )
        }

        let firstLine = string.components(separatedBy: .newlines).first ?? string
        let source = sourceMetadata(
            changeCountDelta: changeCountDelta,
            currentChangeCount: currentChangeCount
        )
        return ClipboardItem(
            id: UUID(),
            kind: .text,
            title: firstLine.truncated(to: 42),
            preview: string.truncated(to: 240),
            sourceApp: source.appName,
            sourceAppIconData: source.iconData,
            createdAt: Date(),
            isPinned: false,
            pinboardName: nil,
            textValue: string,
            fileURLs: [],
            imageData: nil
        )
    }

    private func enrichLinkPreviewIfNeeded(for item: ClipboardItem) {
        let rawURL = (item.textValue ?? item.preview).trimmingCharacters(in: .whitespacesAndNewlines)
        guard item.kind == .url,
              item.linkTitle == nil,
              item.linkImageData == nil,
              let url = URL(string: rawURL) else {
            return
        }

        Task { [weak self, itemID = item.id] in
            guard let metadata = await LinkPreviewFetcher.fetch(url: url) else { return }
            self?.applyLinkPreview(
                itemID: itemID,
                title: metadata.title,
                imageData: metadata.imageData
            )
        }
    }

    private func applyLinkPreview(itemID: UUID, title: String?, imageData: Data?) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index] = items[index].withLinkPreview(title: title, linkImageData: imageData).storageOptimized
        refreshFilteredItems()
        saveItems()
    }

    private func enqueueImageItem(image: NSImage, changeCountDelta: Int, currentChangeCount: Int) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let size = image.size
        let source = sourceMetadata(
            isSystemGeneratedContent: pasteboardContainsSystemScreenshot(),
            changeCountDelta: changeCountDelta,
            currentChangeCount: currentChangeCount
        )

        imageEncodingTask?.cancel()
        let encodingTask = Task.detached(priority: .utility) {
            Self.pngData(cgImage: cgImage, maxPixel: 1_200)
        }
        imageEncodingTask = Task { @MainActor [weak self] in
            let data = await encodingTask.value
            guard !Task.isCancelled, let data else { return }
            let item = ClipboardItem(
                id: UUID(),
                kind: .image,
                title: "Image",
                preview: "\(Int(size.width)) x \(Int(size.height))",
                sourceApp: source.appName,
                sourceAppIconData: source.iconData,
                createdAt: Date(),
                isPinned: false,
                pinboardName: nil,
                textValue: nil,
                fileURLs: [],
                imageData: data
            )
            self?.add(item)
        }
    }

    private nonisolated static func pngData(cgImage: CGImage, maxPixel: CGFloat) -> Data? {
        let largestSide = max(cgImage.width, cgImage.height)
        guard largestSide > 0 else { return nil }
        let scale = min(1, maxPixel / CGFloat(largestSide))
        let width = max(1, Int((CGFloat(cgImage.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(cgImage.height) * scale).rounded()))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let resized = context.makeImage() else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, resized, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private func sourceMetadata(
        isSystemGeneratedContent: Bool = false,
        changeCountDelta: Int,
        currentChangeCount: Int
    ) -> ClipboardSource {
        sourceTracker.resolveSource(
            isSystemGeneratedContent: isSystemGeneratedContent,
            pasteboardChangeCountDelta: changeCountDelta,
            currentPasteboardChangeCount: currentChangeCount
        )
    }

    private func pasteboardContainsSystemScreenshot() -> Bool {
        pasteboard.types?.contains { type in
            type.rawValue.localizedCaseInsensitiveContains("screenshot")
        } ?? false
    }

    private func pasteboardContainsSensitiveContent() -> Bool {
        pasteboard.types?.contains { type in
            let rawValue = type.rawValue.localizedLowercase
            return rawValue.contains("concealed") ||
                rawValue.contains("1password") ||
                rawValue.contains("bitwarden") ||
                rawValue.contains("keychain") ||
                rawValue.contains("keepass") ||
                rawValue.contains("lastpass") ||
                rawValue.contains("dashlane")
        } ?? false
    }

    private func refreshFilteredItems() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        let board = Pinboard(id: selectedBoardID)
        filteredItems = items.filter { item in
            let boardMatches: Bool
            switch board.kind {
            case .all, .unknown:
                boardMatches = true
            case .pinned:
                boardMatches = item.isPinned
            case .custom:
                boardMatches = item.pinboardName == board.customName
            }
            let searchMatches = query.isEmpty || item.searchText.contains(query)
            return boardMatches && searchMatches
        }
        if let selectedID, filteredItems.contains(where: { $0.id == selectedID }) {
            return
        }
        selectID(filteredItems.first?.id)
    }

    private func saveItems() {
        ClipboardHistoryPersistence.save(items)
    }

    private func selectID(_ id: UUID?) {
        guard selectedID != id else { return }
        selectedID = id
    }
}

struct Pinboard: Hashable, Identifiable {
    enum Kind: Hashable {
        case all
        case pinned
        case custom
        case unknown
    }

    let kind: Kind
    let title: String
    let customName: String?

    var id: String {
        switch kind {
        case .all: "all"
        case .pinned: "pinned"
        case .custom: "custom:\(customName ?? "")"
        case .unknown: "unknown"
        }
    }

    static let all = Pinboard(kind: .all, title: "All", customName: nil)
    static let pinned = Pinboard(kind: .pinned, title: "Pinned", customName: nil)

    static func custom(_ name: String) -> Pinboard {
        Pinboard(kind: .custom, title: name, customName: name)
    }

    init(id: String) {
        switch id {
        case Self.all.id:
            self = .all
        case Self.pinned.id:
            self = .pinned
        default:
            if id.hasPrefix("custom:") {
                let name = String(id.dropFirst("custom:".count))
                self = .custom(name)
            } else {
                self = Pinboard(kind: .unknown, title: "All", customName: nil)
            }
        }
    }

    init(kind: Kind, title: String, customName: String?) {
        self.kind = kind
        self.title = title
        self.customName = customName
    }
}
