@testable import Copythat
import CoreGraphics
import Testing

struct PanelFrameCalculatorTests {
    @Test func framesStayWithinVisibleBounds() {
        let cases: [(String, CGRect, CGRect, Bool)] = [
            ("compact", CGRect(x: 0, y: 0, width: 640, height: 480), CGRect(x: 0, y: 0, width: 640, height: 480), false),
            ("desktop", CGRect(x: 0, y: 0, width: 1710, height: 1073), CGRect(x: 0, y: 61, width: 1710, height: 1012), false),
            ("desktop-full-height-target", CGRect(x: 0, y: 0, width: 1710, height: 1073), CGRect(x: 0, y: 61, width: 1710, height: 1012), true),
            ("wide", CGRect(x: 0, y: 0, width: 3440, height: 1376), CGRect(x: 0, y: 0, width: 3440, height: 1376), false),
            ("left-display", CGRect(x: -1920, y: 0, width: 1920, height: 1055), CGRect(x: -1920, y: 0, width: 1920, height: 1055), false),
            ("right-display", CGRect(x: 1710, y: 0, width: 1440, height: 900), CGRect(x: 1710, y: 0, width: 1440, height: 900), false)
        ]

        for (name, screenFrame, visibleFrame, prefersScreenBottomAnchor) in cases {
            let frame = PanelFrameCalculator.frame(
                screenFrame: screenFrame,
                visibleFrame: visibleFrame,
                prefersScreenBottomAnchor: prefersScreenBottomAnchor
            )
            let expectedBottomAnchor = prefersScreenBottomAnchor || visibleFrame.minY <= screenFrame.minY + 1 ?
                screenFrame.minY :
                visibleFrame.minY

            #expect(frame.minX >= visibleFrame.minX + PanelFrameCalculator.sideMargin, "\(name): minX out of bounds")
            #expect(frame.maxX <= visibleFrame.maxX - PanelFrameCalculator.sideMargin + 0.001, "\(name): maxX out of bounds")
            #expect(frame.minY == expectedBottomAnchor + PanelFrameCalculator.bottomMargin, "\(name): y is not bottom anchored")
            #expect(frame.maxY <= visibleFrame.maxY + 0.001, "\(name): height out of bounds")
            #expect(frame.width <= visibleFrame.width - PanelFrameCalculator.sideMargin * 2 + 0.001, "\(name): width out of bounds")
            #expect(frame.width <= PanelFrameCalculator.maximumWidth, "\(name): width exceeds maximum")
            if visibleFrame.width >= 1_000 && visibleFrame.width <= 1_860 {
                #expect(abs(frame.width - visibleFrame.width * PanelFrameCalculator.preferredWidthRatio) < 0.001, "\(name): width is not responsive")
            }
        }
    }
}
