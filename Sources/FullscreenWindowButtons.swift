import AppKit
import SwiftUI

struct FullscreenWindowButtons: NSViewRepresentable {
    func makeNSView(context: Context) -> Target { Target() }
    func updateNSView(_ view: Target, context: Context) {}
    static func dismantleNSView(_ view: Target, coordinator: ()) { view.detach() }

    final class Target: NSView {
        private var observations: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            subviews.forEach { $0.removeFromSuperview() }
            guard let window else { return }
            let controls: [(NSWindow.ButtonType, Selector)] = [
                (.closeButton, #selector(NSWindow.performClose(_:))),
                (.miniaturizeButton, #selector(NSWindow.performMiniaturize(_:))),
                (.zoomButton, #selector(NSWindow.toggleFullScreen(_:)))
            ]
            for (index, control) in controls.enumerated() {
                guard let button = NSWindow.standardWindowButton(control.0, for: window.styleMask) else { continue }
                button.target = window
                button.action = control.1
                button.frame.origin.x = 9 + CGFloat(index) * 20
                if control.0 == .miniaturizeButton { button.isEnabled = false }
                addSubview(button)
            }
            for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                observations.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updateVisibility() }
                })
            }
            updateVisibility()
        }

        override func layout() {
            super.layout()
            for button in subviews { button.frame.origin.y = (bounds.height - button.frame.height) / 2 }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard !isHidden, let hit = super.hitTest(point), hit !== self else { return nil }
            return hit
        }

        private func updateVisibility() {
            isHidden = window?.styleMask.contains(.fullScreen) != true
        }

        func detach() {
            observations.forEach(NotificationCenter.default.removeObserver)
            observations.removeAll()
        }
    }
}
