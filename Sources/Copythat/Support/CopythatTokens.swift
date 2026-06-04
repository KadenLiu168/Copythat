import SwiftUI

// Unit tests for these tokens live at `Tests/CopythatTests/CopythatTokensTests.swift`
// and lock the `strokeWidth` / `strokeInset` half-stroke invariant.

/// Centralized visual tokens for Copythat panels and brand chrome.
///
/// All tokens MUST be referenced (not inlined) from views and modifiers that
/// render the panel surface, so a future retune happens in one place.
enum CopythatTokens {
    /// Tokens that describe the bottom panel surface.
    enum Panel {
        /// Corner radius of the panel rounded rectangle and of any surface
        /// that wants to share the panel's silhouette.
        static let cornerRadius: CGFloat = 26

        /// Hairline stroke width used for the panel border and any glass
        /// hairline surfaces (search capsule, etc.).
        static let strokeWidth: CGFloat = 1

        /// Distance the hairline is inset from the shape's edge. MUST equal
        /// `strokeWidth / 2` so the stroke stays inside the `clipShape`.
        static let strokeInset: CGFloat = 0.5

        /// White opacity of the hairline stroke. Tuned to read as a soft
        /// glass edge on the popover material.
        static let strokeOpacity: Double = 0.55

        /// Brand-orange glow shadow. Values mirror the pre-token inline shadow
        /// (`radius: 28, y: 16, color: orange @ 0.44`).
        static let shadowOrange: ShadowSpec = .init(
            color: Color(red: 0.95, green: 0.47, blue: 0.10).opacity(0.44),
            radius: 28,
            y: 16
        )

        /// Black ambient shadow. Values mirror the pre-token inline shadow
        /// (`radius: 12, y: 5, color: black @ 0.10`).
        static let shadowBlack: ShadowSpec = .init(
            color: .black.opacity(0.10),
            radius: 12,
            y: 5
        )
    }

    /// Tokens that describe the Copythat brand palette.
    enum Brand {
        /// Primary brand orange. Mirrors the orange family used in the panel
        /// tint gradient and the brand glow shadow.
        static let accent: Color = Color(red: 0.95, green: 0.47, blue: 0.10)
    }
}

/// A SwiftUI `.shadow(...)` triple, packaged as a value type so it can live
/// inside a `static let` and be destructured at the call site.
struct ShadowSpec {
    let color: Color
    let radius: CGFloat
    let y: CGFloat
}
