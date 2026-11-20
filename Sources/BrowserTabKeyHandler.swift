import AppKit
import Carbon.HIToolbox
import SwiftUI

struct BrowserTabKeyHandler: NSViewRepresentable {
    let step: (Int) -> Void
    let zoom: (PageZoomAction) -> Bool

    func makeNSView(context: Context) -> Target { Target() }

    func updateNSView(_ view: Target, context: Context) {
        view.step = step
        view.zoom = zoom
    }

    final class Target: NSView {
        var step: ((Int) -> Void)?
        var zoom: ((PageZoomAction) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                return self.handle(event) ? nil : event
            }
        }

        private func handle(_ event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags.intersection([.control, .shift, .option, .command])
            if event.keyCode == UInt16(kVK_Tab), let step {
                switch modifiers {
                case .control:
                    step(1)
                    return true
                case [.control, .shift]:
                    step(-1)
                    return true
                default: return false
                }
            }
            guard let zoom, modifiers == .command || modifiers == [.command, .shift] else { return false }
            switch event.charactersIgnoringModifiers {
            case "+", "=": return zoom(.increase)
            case "-", "−": return zoom(.decrease)
            case "0" where modifiers == .command: return zoom(.reset)
            default: return false
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
