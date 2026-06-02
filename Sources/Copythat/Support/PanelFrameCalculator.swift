import CoreGraphics

enum PanelFrameCalculator {
    static let preferredWidthRatio: CGFloat = 0.96
    static let minimumWidth: CGFloat = 560
    static let maximumWidth: CGFloat = 2_200
    static let height: CGFloat = 342
    static let sideMargin: CGFloat = 12
    static let bottomMargin: CGFloat = 24

    static func frame(screenFrame: CGRect, visibleFrame: CGRect, prefersScreenBottomAnchor: Bool = false) -> CGRect {
        let availableWidth = max(1, visibleFrame.width - sideMargin * 2)
        let preferredWidth = visibleFrame.width * preferredWidthRatio
        let width = min(max(minimumWidth, preferredWidth), maximumWidth, availableWidth)
        let x = visibleFrame.midX - width / 2
        let clampedX = min(max(x, visibleFrame.minX + sideMargin), visibleFrame.maxX - sideMargin - width)
        let bottomAnchor = prefersScreenBottomAnchor || visibleFrame.minY <= screenFrame.minY + 1 ? screenFrame.minY : visibleFrame.minY
        let y = bottomAnchor + bottomMargin
        let availableHeight = max(1, visibleFrame.maxY - y)

        return CGRect(x: clampedX, y: y, width: width, height: min(height, availableHeight))
    }
}
