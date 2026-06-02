import AppKit
import SwiftUI

enum CopythatFont {
    private static let preferredName = "Maple Mono NF CN"

    private static var hasPreferredFont: Bool {
        NSFont(name: preferredName, size: 13) != nil
    }

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if hasPreferredFont {
            return .custom(preferredName, size: size).weight(weight)
        }
        return .system(size: size, weight: weight)
    }
}
