import AppKit
import SwiftUI

struct TabStripWindowInteraction: NSViewRepresentable {
    let blocked: Bool

    func makeNSView(context: Context) -> Target { Target() }

    func updateNSView(_ view: Target, context: Context) {
        view.blocked = blocked
        view.apply()
    }

    static func dismantleNSView(_ view: Target, coordinator: ()) { view.restore() }

    final class Target: NSView {
        var blocked = false
        private weak var attachedWindow: NSWindow?
        private var wasMovable = true

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            restore()
            attachedWindow = window
            wasMovable = window?.isMovable ?? true
            apply()
        }

        func apply() {
            // Controls occupy the native title bar, whose drag region takes priority over SwiftUI.
            attachedWindow?.isMovable = wasMovable && !blocked
        }

        func restore() { attachedWindow?.isMovable = wasMovable }
    }
}
