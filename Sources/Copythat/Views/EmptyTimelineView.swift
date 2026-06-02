import SwiftUI

struct EmptyTimelineView: View {
    var body: some View {
        VStack(spacing: 10) {
            appMark
            Text("Copy something to start")
                .font(CopythatFont.font(size: 13, weight: .semibold))
            Text("Text, links, images, and file paths will appear here.")
                .font(CopythatFont.font(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(width: 320, height: 180)
    }

    @ViewBuilder
    private var appMark: some View {
        if let image = CopythatIcon.transparentMark() {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .opacity(0.72)
        } else {
            Image(systemName: "c.circle")
                .font(CopythatFont.font(size: 38))
                .foregroundStyle(.secondary)
        }
    }
}
