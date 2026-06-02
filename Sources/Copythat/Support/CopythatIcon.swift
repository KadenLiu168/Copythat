import AppKit

enum CopythatIcon {
    static func statusBarImage() -> NSImage {
        if let image = image(named: "MenuBarIconTemplate") {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }

        let image = NSImage(systemSymbolName: "c.circle", accessibilityDescription: "Copythat") ?? NSImage()
        image.isTemplate = true
        return image
    }

    static func transparentMark() -> NSImage? {
        image(named: "AppIcon-transparent")
    }

    private static func image(named name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
