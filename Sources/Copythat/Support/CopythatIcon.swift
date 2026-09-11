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

    private static func image(named name: String) -> NSImage? {
        guard let url = resourceBundle.url(forResource: name, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private static var resourceBundle: Bundle {
        if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent("Copythat_Copythat.bundle"),
           let appBundle = Bundle(url: resourceURL) {
            return appBundle
        }

        return Bundle.module
    }
}
