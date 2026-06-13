import SwiftUI

struct EmptyTimelineView: View {
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 7) {
            Text(title)
                .font(CopythatFont.font(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.16, blue: 0.13).opacity(0.92))
            Text(description)
                .font(CopythatFont.font(size: 12, weight: .medium))
                .foregroundStyle(Color(red: 0.25, green: 0.20, blue: 0.16).opacity(0.56))
        }
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .frame(maxWidth: 360)
    }
}
