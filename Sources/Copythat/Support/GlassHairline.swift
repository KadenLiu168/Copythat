import SwiftUI

/// Applies the panel's glass hairline stroke on top of the receiver.
///
/// The stroke is a 1pt white line, inset by `CopythatTokens.Panel.strokeInset`
/// so that the full stroke stays inside the underlying `clipShape` (the inset
/// MUST equal `strokeWidth / 2`; both are locked together in
/// `CopythatTokens.Panel`).
extension View {
    func glassHairline() -> some View {
        overlay(
            RoundedRectangle(cornerRadius: CopythatTokens.Panel.cornerRadius, style: .continuous)
                .inset(by: CopythatTokens.Panel.strokeInset)
                .stroke(
                    .white.opacity(CopythatTokens.Panel.strokeOpacity),
                    lineWidth: CopythatTokens.Panel.strokeWidth
                )
        )
    }
}
