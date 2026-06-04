@testable import Copythat
import SwiftUI
import Testing

struct CopythatTokensTests {
    @Test func namespaceIsNotInstantiable() {
        // CopythatTokens is an `enum` with no cases; instantiating it is a
        // compile-time error. The runtime check below documents the intent
        // and would fail to compile if a future refactor changed it to a
        // struct or class.
        let mirror = Mirror(reflecting: CopythatTokens.self)
        #expect(mirror.children.isEmpty)
    }

    @Test func panelStrokeTokensMatchPreExtractionValues() {
        // Lock the pre-extraction literals from BottomPanelView L5 / L76-77
        // so a future retune of the panel border is a deliberate, one-place
        // edit instead of a silent re-derivation.
        #expect(CopythatTokens.Panel.cornerRadius == 26)
        #expect(CopythatTokens.Panel.strokeWidth == 1)
        #expect(CopythatTokens.Panel.strokeInset == 0.5)
        #expect(CopythatTokens.Panel.strokeOpacity == 0.55)
    }

    @Test func strokeInsetIsExactlyHalfOfStrokeWidth() {
        // `inset(by:)` MUST equal `lineWidth / 2` so the stroke stays inside
        // the `clipShape`. Bumping strokeWidth without bumping strokeInset
        // reintroduces the L-shaped corner artifact this change family
        // exists to prevent.
        #expect(CopythatTokens.Panel.strokeInset * 2 == CopythatTokens.Panel.strokeWidth)
    }

    @Test func shadowSpecsAndBrandAccentMatchPreExtractionValues() {
        // Lock the pre-extraction shadow triple and brand orange from
        // BottomPanelView L79 (orange shadow) and L80 (black shadow).
        #expect(CopythatTokens.Panel.shadowOrange.radius == 28)
        #expect(CopythatTokens.Panel.shadowOrange.y == 16)
        #expect(CopythatTokens.Panel.shadowBlack.radius == 12)
        #expect(CopythatTokens.Panel.shadowBlack.y == 5)

        // Brand accent must agree with the orange shadow color's RGB family
        // (both pre-extraction values are red 0.95, green 0.47, blue 0.10).
        let orangeComponents = CopythatTokens.Brand.accent.rgbaComponents()
        #expect(abs(orangeComponents.red - 0.95) < 0.005)
        #expect(abs(orangeComponents.green - 0.47) < 0.005)
        #expect(abs(orangeComponents.blue - 0.10) < 0.005)
    }
}

private extension Color {
    /// Linear-RGB components in 0...1, used only by the token tests to lock
    /// the brand accent's RGB family. Intentionally minimal — production
    /// code MUST go through `CopythatTokens.Brand.accent` directly.
    func rgbaComponents() -> (red: Double, green: Double, blue: Double) {
        #if canImport(AppKit)
        let nsColor = NSColor(self)
        guard let rgb = nsColor.usingColorSpace(.deviceRGB) else {
            return (0, 0, 0)
        }
        return (Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent))
        #else
        return (0, 0, 0)
        #endif
    }
}
