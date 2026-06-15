@testable import Copythat
import AppKit
import Testing

@MainActor
struct CopythatPanelTests {
    @Test func panelCannotBeRepositionedByMouseDragging() {
        let panel = CopythatPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 342),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        #expect(panel.isMovable == false)
        #expect(panel.isMovableByWindowBackground == false)
    }
}
